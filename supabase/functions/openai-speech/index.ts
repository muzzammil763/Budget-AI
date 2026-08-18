import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};
const openAiApiKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? "";
const elevenLabsApiKey = Deno.env.get("ELEVENLABS_API_KEY")?.trim() ?? "";
const transcriptionModel = "gpt-4o-mini-transcribe";
const elevenLabsModel = "eleven_multilingual_v2";
const elevenLabsVoiceId = "JBFqnCBsd6RMkjVDRZzb";
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
    "A short personal-finance command, possibly in English, Urdu, or Roman Urdu.",
  );
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

function encodeBase64(bytes: Uint8Array) {
  const parts: string[] = [];
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    parts.push(String.fromCharCode(...bytes.subarray(offset, offset + chunkSize)));
  }
  return btoa(parts.join(""));
}

async function synthesize(body: Record<string, unknown>) {
  const text = typeof body.text === "string" ? body.text.trim() : "";
  if (!text || text.length > 1500) {
    return jsonResponse(400, {
      code: "invalid_text",
      message: "Speech text is empty or too long.",
    });
  }
  if (!elevenLabsApiKey) {
    return jsonResponse(503, {
      code: "speech_not_configured",
      message: "ElevenLabs speech synthesis is not configured.",
    });
  }
  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${elevenLabsVoiceId}?output_format=mp3_44100_128`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "xi-api-key": elevenLabsApiKey,
      },
      body: JSON.stringify({ text, model_id: elevenLabsModel }),
    },
  );
  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    const message = typeof data?.detail?.message === "string"
      ? data.detail.message
      : typeof data?.detail === "string"
      ? data.detail
      : "ElevenLabs speech synthesis failed.";
    throw new Error(message);
  }
  const audio = new Uint8Array(await response.arrayBuffer());
  if (!audio.length) throw new Error("ElevenLabs returned no speech audio.");
  return jsonResponse(200, {
    audioContent: encodeBase64(audio),
    model: elevenLabsModel,
    voiceId: elevenLabsVoiceId,
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
      const body = await req.json() as Record<string, unknown>;
      if (body.action === "transcribe") return await transcribe(body);
      if (body.action === "synthesize") return await synthesize(body);
      return jsonResponse(400, {
        code: "invalid_action",
        message: "Choose transcribe or synthesize.",
      });
    } catch (error) {
      console.error("Cloud speech request failed", error);
      return jsonResponse(502, {
        code: "cloud_speech_failed",
        message: error instanceof Error
          ? error.message
          : "Cloud speech request failed.",
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
