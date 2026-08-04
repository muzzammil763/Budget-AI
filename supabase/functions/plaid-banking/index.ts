import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};

const allowedCountries = new Set([
  "US",
  "CA",
  "GB",
  "IE",
  "FR",
  "DE",
  "ES",
  "NL",
  "IT",
  "PL",
  "DK",
  "NO",
  "SE",
  "EE",
  "LT",
  "LV",
  "PT",
  "BE",
  "AT",
  "FI",
]);

function jsonResponse(status: number, body: Record<string, unknown>) {
  return Response.json(body, { status, headers: corsHeaders });
}

function requiredSecret(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name} secret.`);
  return value;
}

async function plaid(path: string, body: Record<string, unknown>) {
  const environment = Deno.env.get("PLAID_ENV") ?? "sandbox";
  if (!["sandbox", "development", "production"].includes(environment)) {
    throw new Error("PLAID_ENV is invalid.");
  }
  const response = await fetch(`https://${environment}.plaid.com${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "PLAID-CLIENT-ID": requiredSecret("PLAID_CLIENT_ID"),
      "PLAID-SECRET": requiredSecret("PLAID_SECRET"),
      "Plaid-Version": "2020-09-14",
    },
    body: JSON.stringify(body),
  });
  const result = await response.json();
  if (!response.ok || result.error_code) {
    const error = new Error(result.error_message ?? "Plaid request failed.");
    Object.assign(error, {
      code: result.error_code ?? `http_${response.status}`,
    });
    throw error;
  }
  return result;
}

function base64(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes));
}

function fromBase64(value: string) {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

async function tokenKey() {
  const raw = fromBase64(requiredSecret("PLAID_TOKEN_ENCRYPTION_KEY"));
  if (raw.byteLength !== 32) {
    throw new Error("PLAID_TOKEN_ENCRYPTION_KEY must contain 32 base64 bytes.");
  }
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

async function encryptToken(value: string) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    await tokenKey(),
    new TextEncoder().encode(value),
  );
  return {
    ciphertext: base64(new Uint8Array(encrypted)),
    nonce: base64(nonce),
  };
}

async function decryptToken(ciphertext: string, nonce: string) {
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: fromBase64(nonce) },
    await tokenKey(),
    fromBase64(ciphertext),
  );
  return new TextDecoder().decode(decrypted);
}

type AdminClient = {
  schema: (schema: string) => {
    from: (table: string) => any;
  };
};

const authenticatedHandler = withSupabase(
  { auth: "user" },
  async (req, ctx) => {
    if (req.method !== "POST") {
      return jsonResponse(405, { error: "Use POST." });
    }
    const userId = ctx.userClaims?.id ?? ctx.jwtClaims?.sub;
    if (!userId) return jsonResponse(401, { error: "Sign in again." });

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { error: "A JSON body is required." });
    }

    const action = body.action;
    const admin = ctx.supabaseAdmin as unknown as AdminClient;
    const protectedSchema = admin.schema("public");

    try {
      if (action === "create_link_token") {
        const country = String(body.country_code ?? "").toUpperCase();
        if (!allowedCountries.has(country)) {
          return jsonResponse(400, {
            error: "That bank country is not supported.",
          });
        }
        const result = await plaid("/link/token/create", {
          user: { client_user_id: userId },
          client_name: "Budget AI",
          products: ["transactions"],
          country_codes: [country],
          language: "en",
          transactions: {
            days_requested: Math.max(
              30,
              Math.min(730, Number(body.days_requested ?? 90)),
            ),
          },
          webhook: `${
            requiredSecret("SUPABASE_URL")
          }/functions/v1/plaid-webhook`,
        });
        return jsonResponse(200, { link_token: result.link_token });
      }

      if (action === "exchange_public_token") {
        const publicToken = String(body.public_token ?? "");
        if (!publicToken) {
          return jsonResponse(400, { error: "Missing public token." });
        }
        const exchange = await plaid("/item/public_token/exchange", {
          public_token: publicToken,
        });
        const protectedToken = await encryptToken(exchange.access_token);
        const institutionName = String(
          body.institution_name ?? "Connected bank",
        );
        const { data: connection, error } = await protectedSchema
          .from("bank_connections")
          .insert({
            user_id: userId,
            item_id: exchange.item_id,
            encrypted_access_token: protectedToken.ciphertext,
            token_nonce: protectedToken.nonce,
            institution_id: body.institution_id ?? null,
            institution_name: institutionName,
            country_code: String(body.country_code ?? "GB"),
            import_start_date: body.import_start_date ?? null,
            import_end_date: body.import_end_date ?? null,
          })
          .select("id")
          .single();
        if (error) throw error;
        const accounts = Array.isArray(body.accounts) ? body.accounts : [];
        if (accounts.length > 0) {
          const { error: accountError } = await protectedSchema
            .from("bank_accounts")
            .insert(accounts.map((raw: Record<string, unknown>) => ({
              connection_id: connection.id,
              provider_account_id: raw.id,
              name: raw.name ?? "Bank account",
              mask: raw.mask ?? null,
              account_type: raw.type ?? "account",
              account_subtype: raw.subtype ?? null,
            })));
          if (accountError) throw accountError;
        }
        return jsonResponse(200, { connection_id: connection.id });
      }

      if (action === "dashboard") {
        const { data: connections, error } = await protectedSchema
          .from("bank_connections")
          .select(
            "id,institution_name,country_code,status,last_synced_at,sync_required,bank_accounts(id:provider_account_id,name,mask,type:account_type,currency_code,selected)",
          )
          .eq("user_id", userId)
          .neq("status", "disconnected")
          .order("created_at");
        if (error) throw error;
        const { data: history, error: historyError } = await protectedSchema
          .from("bank_sync_history")
          .select(
            "id,connection_id,institution_name,status,added_count,modified_count,removed_count,started_at",
          )
          .eq("user_id", userId)
          .order("started_at", { ascending: false })
          .limit(30);
        if (historyError) throw historyError;
        return jsonResponse(200, {
          connections: (connections ?? []).map((connection: any) => ({
            ...connection,
            accounts: connection.bank_accounts ?? [],
            bank_accounts: undefined,
          })),
          history: history ?? [],
        });
      }

      if (action === "sync_transactions") {
        const connectionId = String(body.connection_id ?? "");
        const { data: connection, error } = await protectedSchema
          .from("bank_connections")
          .select("*")
          .eq("id", connectionId)
          .eq("user_id", userId)
          .single();
        if (error || !connection) {
          return jsonResponse(404, { error: "Bank connection not found." });
        }

        await protectedSchema.from("bank_connections").update({
          status: "syncing",
        }).eq("id", connectionId);
        const accessToken = await decryptToken(
          connection.encrypted_access_token,
          connection.token_nonce,
        );
        let cursor = connection.sync_cursor ?? null;
        const initialImport = !connection.initial_import_complete;
        let transactionUpdateStatus = "NOT_READY";
        let hasMore = true;
        const added: unknown[] = [];
        const modified: unknown[] = [];
        const removed: unknown[] = [];
        while (hasMore) {
          const page = await plaid("/transactions/sync", {
            access_token: accessToken,
            cursor,
            count: 500,
          });
          added.push(...page.added);
          modified.push(...page.modified);
          removed.push(...page.removed);
          cursor = page.next_cursor;
          hasMore = page.has_more;
          transactionUpdateStatus = page.transactions_update_status ??
            transactionUpdateStatus;
        }
        const withinInitialRange = (transaction: any) => {
          const date = transaction.authorized_date ?? transaction.date;
          return (!connection.import_start_date ||
            date >= connection.import_start_date) &&
            (!initialImport || !connection.import_end_date ||
              date <= connection.import_end_date);
        };
        const returnedAdded = added.filter(withinInitialRange);
        const returnedModified = modified.filter(withinInitialRange);
        await protectedSchema.from("bank_connections").update({
          sync_cursor: cursor,
          sync_required: false,
          status: "healthy",
          last_synced_at: new Date().toISOString(),
          initial_import_complete: connection.initial_import_complete ||
            transactionUpdateStatus === "HISTORICAL_UPDATE_COMPLETE",
        }).eq("id", connectionId).eq("user_id", userId);
        await protectedSchema.from("bank_sync_history").insert({
          connection_id: connectionId,
          user_id: userId,
          institution_name: connection.institution_name,
          status: "completed",
          added_count: returnedAdded.length,
          modified_count: returnedModified.length,
          removed_count: removed.length,
          finished_at: new Date().toISOString(),
        });
        return jsonResponse(200, {
          added: returnedAdded,
          modified: returnedModified,
          removed,
        });
      }

      if (action === "disconnect") {
        const connectionId = String(body.connection_id ?? "");
        const { data: connection, error } = await protectedSchema
          .from("bank_connections")
          .select("encrypted_access_token,token_nonce")
          .eq("id", connectionId)
          .eq("user_id", userId)
          .single();
        if (error || !connection) {
          return jsonResponse(404, { error: "Bank connection not found." });
        }
        const accessToken = await decryptToken(
          connection.encrypted_access_token,
          connection.token_nonce,
        );
        await plaid("/item/remove", { access_token: accessToken });
        await protectedSchema.from("bank_connections").delete().eq(
          "id",
          connectionId,
        ).eq("user_id", userId);
        return jsonResponse(200, { disconnected: true });
      }

      return jsonResponse(400, { error: "Unknown banking action." });
    } catch (error) {
      const code = typeof error === "object" && error && "code" in error
        ? String(error.code)
        : "banking_request_failed";
      if (action === "sync_transactions" && body.connection_id) {
        const connectionId = String(body.connection_id);
        const { data: failedConnection } = await protectedSchema
          .from("bank_connections")
          .select("institution_name")
          .eq("id", connectionId)
          .eq("user_id", userId)
          .maybeSingle();
        await protectedSchema.from("bank_connections").update({
          status: "attention",
        }).eq("id", connectionId).eq("user_id", userId);
        if (failedConnection) {
          await protectedSchema.from("bank_sync_history").insert({
            connection_id: connectionId,
            user_id: userId,
            institution_name: failedConnection.institution_name,
            status: "failed",
            error_code: code.slice(0, 120),
            finished_at: new Date().toISOString(),
          });
        }
      }
      console.error("Plaid banking action failed", { action, code });
      return jsonResponse(502, {
        error: "The bank request could not be completed.",
        code,
      });
    }
  },
);

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return authenticatedHandler(req);
});
