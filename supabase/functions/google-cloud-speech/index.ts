import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};

const googleApiKey = Deno.env.get("GOOGLE_CLOUD_API_KEY")?.trim() ?? "";
const languageCodePattern = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$/;

function jsonResponse(status: number, body: Record<string, unknown>) {
  return Response.json(body, { status, headers: corsHeaders });
}

function cleanLanguageCode(value: unknown, fallback = "en-US") {
  const code = typeof value === "string" ? value.trim() : "";
  return languageCodePattern.test(code) ? code : fallback;
}

async function googleRequest(url: string, body: Record<string, unknown>) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": googleApiKey,
    },
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = typeof data?.error?.message === "string"
      ? data.error.message
      : "Google Cloud speech request failed.";
    throw new Error(message);
  }
  return data as Record<string, unknown>;
}

async function transcribe(body: Record<string, unknown>) {
  const audioContent = typeof body.audioContent === "string"
    ? body.audioContent
    : "";
  if (audioContent.length === 0 || audioContent.length > 12_000_000) {
    return jsonResponse(400, {
      code: "invalid_audio",
      message: "The recording is empty or too large.",
    });
  }
  const languageCode = cleanLanguageCode(body.languageCode);
  const alternatives = Array.isArray(body.alternativeLanguageCodes)
    ? body.alternativeLanguageCodes
      .map((value) => cleanLanguageCode(value, ""))
      .filter((value) => value && value !== languageCode)
      .slice(0, 3)
    : [];
  const data = await googleRequest(
    "https://speech.googleapis.com/v1/speech:recognize",
    {
      config: {
        encoding: body.audioEncoding === "LINEAR16"
          ? "LINEAR16"
          : "ENCODING_UNSPECIFIED",
        sampleRateHertz: body.sampleRateHertz === 16000 ? 16000 : undefined,
        audioChannelCount: body.audioChannelCount === 1 ? 1 : undefined,
        languageCode,
        alternativeLanguageCodes: alternatives,
        enableAutomaticPunctuation: true,
      },
      audio: { content: audioContent },
    },
  );
  const results = Array.isArray(data.results) ? data.results : [];
  const transcript = results.map((result) => {
    const alternatives = Array.isArray(result?.alternatives)
      ? result.alternatives
      : [];
    return typeof alternatives[0]?.transcript === "string"
      ? alternatives[0].transcript.trim()
      : "";
  }).filter(Boolean).join(" ").trim();
  const detectedLanguage = results.find((result) =>
    typeof result?.languageCode === "string"
  )?.languageCode;
  return jsonResponse(200, {
    transcript,
    languageCode: detectedLanguage ?? languageCode,
  });
}

async function synthesize(body: Record<string, unknown>) {
  const text = typeof body.text === "string" ? body.text.trim() : "";
  if (text.length === 0 || new TextEncoder().encode(text).length > 4500) {
    return jsonResponse(400, {
      code: "invalid_text",
      message: "Speech text is empty or too long.",
    });
  }
  const requestedLanguage = cleanLanguageCode(body.languageCode);
  let usedLanguage = requestedLanguage;
  let data: Record<string, unknown>;
  try {
    data = await googleRequest(
      "https://texttospeech.googleapis.com/v1/text:synthesize",
      {
        input: { text },
        voice: { languageCode: requestedLanguage },
        audioConfig: { audioEncoding: "MP3" },
      },
    );
  } catch (error) {
    if (requestedLanguage === "en-US") throw error;
    usedLanguage = "en-US";
    data = await googleRequest(
      "https://texttospeech.googleapis.com/v1/text:synthesize",
      {
        input: { text },
        voice: { languageCode: usedLanguage },
        audioConfig: { audioEncoding: "MP3" },
      },
    );
  }
  if (typeof data.audioContent !== "string" || !data.audioContent) {
    throw new Error("Google Cloud returned no speech audio.");
  }
  return jsonResponse(200, {
    audioContent: data.audioContent,
    languageCode: usedLanguage,
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
    if (!googleApiKey) {
      return jsonResponse(503, {
        code: "speech_not_configured",
        message: "Google Cloud speech is not configured.",
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
      console.error("Google Cloud speech failed", error);
      return jsonResponse(502, {
        code: "google_speech_failed",
        message: error instanceof Error
          ? error.message
          : "Google Cloud speech request failed.",
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
