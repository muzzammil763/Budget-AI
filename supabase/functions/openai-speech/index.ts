import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};
const openAiApiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
const transcriptionModel = "gpt-4o-mini-transcribe";
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
  const audioBuffer = new ArrayBuffer(audio.byteLength);
  new Uint8Array(audioBuffer).set(audio);
  form.append("file", new File([audioBuffer], fileName, { type: "audio/wav" }));

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { authorization: `Bearer ${openAiApiKey}` },
    body: form,
  });
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

const authenticatedHandler = withSupabase(
  { auth: "user" },
  async (req) => {
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
