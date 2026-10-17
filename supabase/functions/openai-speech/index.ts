import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info, x-client-platform",
  "access-control-allow-methods": "POST, OPTIONS",
};
const openAiApiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
const transcriptionModel = "gpt-transcribe";
const maxEncodedAudioLength = 12_000_000;

function jsonResponse(status: number, body: Record<string, unknown>) {
  return Response.json(body, { status, headers: corsHeaders });
}

function decodeBase64(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function transcribe(body: Record<string, unknown>) {
  const audioContent = typeof body.audioContent === "string"
    ? body.audioContent
    : "";
  if (!audioContent || audioContent.length > maxEncodedAudioLength) {
    return jsonResponse(400, {
      code: "invalid_audio",
      message: "The recording is empty or too large.",
    });
  }

  let audio: Uint8Array;
  try {
    audio = decodeBase64(audioContent);
  } catch (_) {
    return jsonResponse(400, {
      code: "invalid_audio",
      message: "The recording is not valid base64 audio.",
    });
  }
  const suppliedName = typeof body.fileName === "string"
    ? body.fileName.trim()
    : "";
  const fileName = suppliedName.toLowerCase().endsWith(".wav")
    ? suppliedName
    : "recording.wav";
  const form = new FormData();
  form.append("model", transcriptionModel);
  form.append("response_format", "json");
  form.append(
    "prompt",
    "Personal finance commands in English, Urdu, or Roman Urdu. Preserve amounts, names, and dates.",
  );
  const audioBuffer = new ArrayBuffer(audio.byteLength);
  new Uint8Array(audioBuffer).set(audio);
  form.append("file", new File([audioBuffer], fileName, { type: "audio/wav" }));

  const response = await fetch(
    "https://api.openai.com/v1/audio/transcriptions",
    {
      method: "POST",
      headers: { authorization: `Bearer ${openAiApiKey}` },
      body: form,
    },
  );
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = typeof data?.error?.message === "string"
      ? data.error.message
      : "OpenAI transcription failed.";
    throw new Error(message);
  }
  const transcript = typeof data.text === "string" ? data.text.trim() : "";
  return jsonResponse(200, {
    transcript,
    languageCode: typeof body.languageCode === "string"
      ? body.languageCode
      : "en-US",
    model: transcriptionModel,
  });
}

type AdminClientWithRpc = {
  rpc: (
    functionName: string,
    arguments_: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: { code?: string } | null }>;
};

function clientPlatform(req: Request) {
  const value = req.headers.get("x-client-platform")?.toLowerCase();
  return value === "android" || value === "ios" ? value : "unknown";
}

/** A voice note becomes an AI message, so it needs room in the plan. */
async function messageAccessCode(
  req: Request,
  ctx: {
    userClaims?: { id?: string } | null;
    jwtClaims?: { sub?: string } | null;
    supabaseAdmin: unknown;
  },
) {
  const userId = ctx.userClaims?.id ?? ctx.jwtClaims?.sub;
  if (!userId) return "unauthorized";
  const admin = ctx.supabaseAdmin as AdminClientWithRpc;
  const { data, error } = await admin.rpc("can_start_ai_message", {
    p_user_id: userId,
    p_platform: clientPlatform(req),
  });
  if (error) {
    console.error("Speech access check failed", error.code);
    return "quota_unavailable";
  }
  return typeof data === "string" ? data : "quota_unavailable";
}

const authenticatedHandler = withSupabase(
  { auth: "user" },
  async (req, ctx) => {
    if (req.method !== "POST") {
      return jsonResponse(405, {
        code: "method_not_allowed",
        message: "Use POST.",
      });
    }
    if (!openAiApiKey) {
      return jsonResponse(503, {
        code: "speech_not_configured",
        message: "OpenAI transcription is not configured.",
      });
    }
    const access = await messageAccessCode(req, ctx);
    if (access !== "allowed") {
      const status = access === "premium_required" ||
          access === "plan_limit_reached"
        ? 402
        : access === "account_disabled"
        ? 403
        : access === "unauthorized"
        ? 401
        : 503;
      return jsonResponse(status, {
        code: access,
        message: access === "premium_required"
          ? "You've used this month's free AI messages. Upgrade to keep going."
          : access === "plan_limit_reached"
          ? "You've reached this month's AI limit for your plan."
          : "Voice messages are unavailable right now.",
      });
    }
    try {
      return await transcribe(await req.json() as Record<string, unknown>);
    } catch (error) {
      console.error("OpenAI transcription failed", error);
      return jsonResponse(502, {
        code: "openai_transcription_failed",
        message: error instanceof Error
          ? error.message
          : "OpenAI transcription failed.",
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
