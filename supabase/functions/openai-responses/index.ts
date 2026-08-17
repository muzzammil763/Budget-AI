import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const openAIResponsesUrl = "https://api.openai.com/v1/responses";
const maxRequestBytes = 512 * 1024;
const maxInstructionsLength = 30000;
const maxInputLength = 400000;
const defaultMaxOutputTokens = 4096;
const maxOutputTokens = 8192;

const allowedModels = new Set([
  "gpt-5.6-luna",
  "gpt-5.6-terra",
  "gpt-5.6-sol",
  "gpt-5.5",
  "gpt-5.4",
  "gpt-5.4-mini",
  "gpt-5.4-nano",
  "gpt-4.1",
  "o3",
]);

const allowedTools = new Set([
  "finance_add",
  "finance_income_add",
  "finance_list",
  "finance_summary",
  "finance_update",
  "finance_delete",
]);

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info, x-region",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-expose-headers":
    "server-timing, x-budget-ai-request-id, x-budget-ai-edge-region, x-budget-ai-quota-ms, x-budget-ai-openai-headers-ms, x-sb-edge-region",
};

type Usage = {
  inputTokens: number;
  outputTokens: number;
  cachedInputTokens: number;
};

type Reservation = {
  allowed: boolean;
  code: string;
  request_id: string;
  monthly_request_limit: number;
  monthly_token_limit: number;
  remaining_requests: number;
  remaining_tokens: number;
};

type AdminRpc = (
  functionName: string,
  arguments_: Record<string, unknown>,
) => Promise<{
  data: unknown;
  error: { code?: string } | null;
}>;

type AdminClientWithRpc = {
  rpc: AdminRpc;
};

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  extraHeaders: HeadersInit = {},
) {
  return Response.json(body, {
    status,
    headers: { ...corsHeaders, ...extraHeaders },
  });
}

function safeInteger(value: unknown, fallback: number, maximum: number) {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(1, Math.min(Math.trunc(value), maximum));
}

function nonnegativeInteger(value: unknown) {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(Math.trunc(value), Number.MAX_SAFE_INTEGER));
}

function extractUsage(payload: unknown): Usage {
  if (!payload || typeof payload !== "object") {
    return { inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 };
  }

  const record = payload as Record<string, unknown>;
  const response = record.response && typeof record.response === "object"
    ? record.response as Record<string, unknown>
    : record;
  const usage = response.usage && typeof response.usage === "object"
    ? response.usage as Record<string, unknown>
    : {};
  const details = usage.input_tokens_details &&
      typeof usage.input_tokens_details === "object"
    ? usage.input_tokens_details as Record<string, unknown>
    : {};

  return {
    inputTokens: nonnegativeInteger(usage.input_tokens),
    outputTokens: nonnegativeInteger(usage.output_tokens),
    cachedInputTokens: nonnegativeInteger(details.cached_tokens),
  };
}

function validateAndSanitizeBody(raw: unknown) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("invalid_body");
  }

  const body = raw as Record<string, unknown>;
  const model = typeof body.model === "string" ? body.model.trim() : "";
  if (!allowedModels.has(model)) throw new Error("unsupported_model");

  const instructions = body.instructions;
  if (
    instructions !== undefined &&
    (typeof instructions !== "string" ||
      instructions.length > maxInstructionsLength)
  ) {
    throw new Error("invalid_instructions");
  }

  const inputJson = JSON.stringify(body.input ?? "");
  if (inputJson.length > maxInputLength) throw new Error("input_too_large");

  const tools = body.tools;
  if (tools !== undefined) {
    if (!Array.isArray(tools) || tools.length > allowedTools.size) {
      throw new Error("invalid_tools");
    }
    for (const tool of tools) {
      if (!tool || typeof tool !== "object") throw new Error("invalid_tools");
      const name = (tool as Record<string, unknown>).name;
      const type = (tool as Record<string, unknown>).type;
      if (
        type !== "function" || typeof name !== "string" ||
        !allowedTools.has(name)
      ) {
        throw new Error("unsupported_tool");
      }
    }
  }

  const requestedOutputTokens = safeInteger(
    body.max_output_tokens,
    defaultMaxOutputTokens,
    maxOutputTokens,
  );
  const serviceTier = body.service_tier;
  if (serviceTier !== undefined && serviceTier !== "fast") {
    throw new Error("unsupported_service_tier");
  }

  const sanitized: Record<string, unknown> = {
    model,
    input: body.input,
    stream: body.stream === true,
    max_output_tokens: requestedOutputTokens,
  };
  if (instructions !== undefined) sanitized.instructions = instructions;
  if (body.reasoning !== undefined) sanitized.reasoning = body.reasoning;
  if (body.text !== undefined) sanitized.text = body.text;
  if (serviceTier === "fast") sanitized.service_tier = "fast";
  if (tools !== undefined) {
    sanitized.tools = tools;
    sanitized.tool_choice = "auto";
    sanitized.parallel_tool_calls = false;
  }

  return {
    sanitized,
    model,
    estimatedTokens: Math.ceil(inputJson.length / 4) + requestedOutputTokens,
  };
}

function quotaStatus(code: string) {
  return code === "duplicate_request" ? 409 : 429;
}

function elapsedMilliseconds(startedAt: number) {
  return Math.max(0, Math.round(performance.now() - startedAt));
}

function proxyTimingHeaders({
  handlerMilliseconds,
  quotaMilliseconds,
  openAIHeadersMilliseconds,
}: {
  handlerMilliseconds: number;
  quotaMilliseconds: number;
  openAIHeadersMilliseconds: number;
}) {
  return {
    "server-timing":
      `handler;dur=${handlerMilliseconds}, quota;dur=${quotaMilliseconds}, openai_headers;dur=${openAIHeadersMilliseconds}`,
    "x-budget-ai-edge-region": Deno.env.get("SB_REGION") ?? "unknown",
    "x-budget-ai-quota-ms": quotaMilliseconds.toString(),
    "x-budget-ai-openai-headers-ms": openAIHeadersMilliseconds.toString(),
  };
}

const authenticatedHandler = withSupabase(
  { auth: "user" },
  async (req, ctx) => {
    const handlerStartedAt = performance.now();

    if (req.method !== "POST") {
      return jsonResponse(405, {
        code: "method_not_allowed",
        message: "Use POST.",
      });
    }

    const contentLength = Number(req.headers.get("content-length") ?? "0");
    if (contentLength > maxRequestBytes) {
      return jsonResponse(413, {
        code: "request_too_large",
        message: "The request is too large.",
      });
    }

    const openAIKey = Deno.env.get("OPENAI_API_KEY");
    if (!openAIKey) {
      return jsonResponse(503, {
        code: "backend_not_configured",
        message: "AI service is not configured yet.",
      });
    }

    let rawBody: unknown;
    try {
      const text = await req.text();
      if (text.length > maxRequestBytes) {
        return jsonResponse(413, {
          code: "request_too_large",
          message: "The request is too large.",
        });
      }
      rawBody = JSON.parse(text);
    } catch {
      return jsonResponse(400, {
        code: "invalid_json",
        message: "The request body is invalid.",
      });
    }

    let requestBody: Record<string, unknown>;
    let model: string;
    let estimatedTokens: number;
    try {
      const validated = validateAndSanitizeBody(rawBody);
      requestBody = validated.sanitized;
      model = validated.model;
      estimatedTokens = validated.estimatedTokens;
    } catch (error) {
      return jsonResponse(400, {
        code: error instanceof Error ? error.message : "invalid_request",
        message: "The AI request is not supported.",
      });
    }

    const userId = ctx.userClaims?.id ?? ctx.jwtClaims?.sub;
    if (!userId) {
      return jsonResponse(401, {
        code: "unauthorized",
        message: "Sign in again to continue.",
      });
    }

    const rawClientTurnId = (rawBody as Record<string, unknown>).client_turn_id;
    const clientTurnId =
      typeof rawClientTurnId === "string" && rawClientTurnId.length <= 64
        ? rawClientTurnId
        : crypto.randomUUID();
    const requestId = crypto.randomUUID();
    const adminClient = ctx.supabaseAdmin as unknown as AdminClientWithRpc;

    const quotaStartedAt = performance.now();
    const { data: reservationData, error: reservationError } = await adminClient
      .rpc("reserve_ai_request", {
        p_user_id: userId,
        p_request_id: requestId,
        p_client_turn_id: clientTurnId,
        p_model: model,
        p_estimated_tokens: estimatedTokens,
      });
    const quotaMilliseconds = elapsedMilliseconds(quotaStartedAt);

    if (reservationError) {
      console.error("AI quota reservation failed", reservationError.code);
      return jsonResponse(503, {
        code: "quota_unavailable",
        message: "Usage limits could not be checked.",
      });
    }

    const reservation = Array.isArray(reservationData)
      ? reservationData[0] as Reservation | undefined
      : reservationData as Reservation | null;
    if (!reservation?.allowed) {
      const code = reservation?.code ?? "quota_rejected";
      return jsonResponse(quotaStatus(code), {
        code,
        message: code === "concurrent_request_limit"
          ? "Another response is already running. Please wait."
          : code === "duplicate_request"
          ? "This request was already submitted."
          : "Your AI usage limit has been reached.",
        limits: reservation
          ? {
            remaining_requests: reservation.remaining_requests,
            remaining_tokens: reservation.remaining_tokens,
          }
          : undefined,
      });
    }

    let finalized = false;
    const finalize = async (
      status: "completed" | "failed" | "cancelled",
      usage: Usage,
      errorCode?: string,
    ) => {
      if (finalized) return;
      finalized = true;
      const { error } = await adminClient.rpc("finalize_ai_request", {
        p_request_id: requestId,
        p_status: status,
        p_input_tokens: usage.inputTokens,
        p_output_tokens: usage.outputTokens,
        p_cached_input_tokens: usage.cachedInputTokens,
        p_error_code: errorCode ?? null,
      });
      if (error) console.error("AI request finalization failed", error.code);
    };

    const scheduleFinalize = (
      status: "completed" | "failed" | "cancelled",
      usage: Usage,
      errorCode?: string,
    ) => {
      EdgeRuntime.waitUntil(
        finalize(status, usage, errorCode).catch((error: unknown) => {
          console.error(
            "AI request finalization crashed",
            error instanceof Error ? error.message : "unknown",
          );
        }),
      );
    };

    let upstream: Response;
    const openAIStartedAt = performance.now();
    try {
      upstream = await fetch(openAIResponsesUrl, {
        method: "POST",
        headers: {
          "authorization": `Bearer ${openAIKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(requestBody),
        signal: req.signal,
      });
    } catch (error) {
      await finalize(
        req.signal.aborted ? "cancelled" : "failed",
        { inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 },
        req.signal.aborted ? "client_cancelled" : "upstream_unreachable",
      );
      return jsonResponse(req.signal.aborted ? 499 : 502, {
        code: req.signal.aborted ? "cancelled" : "upstream_unreachable",
        message: req.signal.aborted
          ? "The request was cancelled."
          : "The AI service could not be reached.",
      });
    }
    const openAIHeadersMilliseconds = elapsedMilliseconds(openAIStartedAt);
    const timingHeaders = proxyTimingHeaders({
      handlerMilliseconds: elapsedMilliseconds(handlerStartedAt),
      quotaMilliseconds,
      openAIHeadersMilliseconds,
    });

    if (!upstream.ok) {
      await finalize(
        "failed",
        { inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 },
        `upstream_${upstream.status}`,
      );
      return jsonResponse(upstream.status === 429 ? 429 : 502, {
        code: upstream.status === 429
          ? "upstream_rate_limit"
          : "upstream_error",
        message: upstream.status === 429
          ? "The AI service is busy. Please try again shortly."
          : "The AI service returned an error.",
      });
    }

    if (requestBody.stream !== true) {
      try {
        const payload = await upstream.json();
        await finalize("completed", extractUsage(payload));
        return jsonResponse(200, payload as Record<string, unknown>, {
          "x-budget-ai-request-id": requestId,
          ...timingHeaders,
        });
      } catch {
        await finalize(
          "failed",
          { inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 },
          "invalid_upstream_json",
        );
        return jsonResponse(502, {
          code: "invalid_upstream_response",
          message: "The AI service returned an invalid response.",
        });
      }
    }

    if (!upstream.body) {
      await finalize(
        "failed",
        { inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 },
        "missing_upstream_stream",
      );
      return jsonResponse(502, {
        code: "missing_upstream_stream",
        message: "The AI service returned an invalid stream.",
      });
    }

    const stream = new ReadableStream<Uint8Array>({
      async start(controller) {
        const reader = upstream.body!.getReader();
        const decoder = new TextDecoder();
        let lineBuffer = "";
        let usage: Usage = {
          inputTokens: 0,
          outputTokens: 0,
          cachedInputTokens: 0,
        };
        let completed = false;
        let firstChunkLogged = false;

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            if (!firstChunkLogged) {
              firstChunkLogged = true;
              console.log(JSON.stringify({
                event: "openai_proxy_timing",
                request_id: requestId,
                region: Deno.env.get("SB_REGION") ?? "unknown",
                quota_ms: quotaMilliseconds,
                openai_headers_ms: openAIHeadersMilliseconds,
                first_chunk_ms: elapsedMilliseconds(handlerStartedAt),
              }));
            }
            controller.enqueue(value);
            lineBuffer += decoder.decode(value, { stream: true });
            const lines = lineBuffer.split("\n");
            lineBuffer = lines.pop() ?? "";

            for (const rawLine of lines) {
              const line = rawLine.trim();
              if (!line.startsWith("data: ")) continue;
              const data = line.slice(6).trim();
              if (!data || data === "[DONE]") continue;
              try {
                const event = JSON.parse(data);
                if (event.type === "response.completed") {
                  usage = extractUsage(event);
                  completed = true;
                } else if (event.type === "response.failed") {
                  completed = false;
                }
              } catch {
                // A malformed upstream event is forwarded but not logged.
              }
            }
          }

          scheduleFinalize(
            completed ? "completed" : "failed",
            usage,
            completed ? undefined : "stream_incomplete",
          );
          controller.close();
        } catch {
          scheduleFinalize(
            req.signal.aborted ? "cancelled" : "failed",
            usage,
            req.signal.aborted ? "client_cancelled" : "stream_error",
          );
          controller.error(new Error("AI stream interrupted"));
        } finally {
          reader.releaseLock();
        }
      },
      cancel() {
        scheduleFinalize(
          "cancelled",
          { inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 },
          "client_cancelled",
        );
      },
    });

    return new Response(stream, {
      status: 200,
      headers: {
        ...corsHeaders,
        "content-type": "text/event-stream",
        "cache-control": "no-cache, no-transform",
        "x-accel-buffering": "no",
        "x-budget-ai-request-id": requestId,
        ...timingHeaders,
      },
    });
  },
);

export default {
  fetch(req: Request) {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    return authenticatedHandler(req).catch((error: unknown) => {
      console.error(
        "Unhandled AI proxy error",
        error instanceof Error ? `${error.name}: ${error.message}` : "unknown",
      );
      return jsonResponse(500, {
        code: "internal_error",
        message: "The AI request could not be processed.",
      });
    });
  },
};
