import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { decodeProtectedHeader, importJWK, jwtVerify } from "jose";

function base64Url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function constantTimeEqual(left: string, right: string) {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  let difference = leftBytes.length ^ rightBytes.length;
  const length = Math.max(leftBytes.length, rightBytes.length);
  for (let index = 0; index < length; index++) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
}

async function verifyWebhook(rawBody: string, signedJwt: string) {
  const header = decodeProtectedHeader(signedJwt);
  if (header.alg !== "ES256" || !header.kid) return false;
  const keyResponse = await fetch(
    `https://${
      Deno.env.get("PLAID_ENV") ?? "sandbox"
    }.plaid.com/webhook_verification_key/get`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "PLAID-CLIENT-ID": Deno.env.get("PLAID_CLIENT_ID")!,
        "PLAID-SECRET": Deno.env.get("PLAID_SECRET")!,
        "Plaid-Version": "2020-09-14",
      },
      body: JSON.stringify({ key_id: header.kid }),
    },
  );
  if (!keyResponse.ok) return false;
  const { key } = await keyResponse.json();
  if (key.alg !== "ES256" || key.expired_at != null) return false;
  const verified = await jwtVerify(signedJwt, await importJWK(key, "ES256"), {
    algorithms: ["ES256"],
    maxTokenAge: "5 minutes",
  });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(rawBody),
  );
  return constantTimeEqual(
    base64Url(new Uint8Array(digest)),
    String(verified.payload.request_body_sha256 ?? ""),
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  const rawBody = await req.text();
  const signature = req.headers.get("plaid-verification");
  if (!signature || !await verifyWebhook(rawBody, signature)) {
    return new Response("Invalid signature", { status: 401 });
  }
  const payload = JSON.parse(rawBody);
  if (!payload.item_id) return new Response("ok");
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const status = payload.webhook_type === "ITEM" && payload.error
    ? "attention"
    : "healthy";
  const { error } = await admin.schema("public").from("bank_connections")
    .update({ sync_required: true, status })
    .eq("item_id", payload.item_id);
  if (error) {
    console.error("Could not mark Plaid connection for sync", error.code);
    return new Response("Failed", { status: 500 });
  }
  return new Response("ok");
});
