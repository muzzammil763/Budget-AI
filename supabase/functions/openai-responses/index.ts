import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

import {
  maxRequestBytes,
  validateAndSanitizeBody,
} from "./request_validation.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

const openAIResponsesUrl = "https://api.openai.com/v1/responses";
const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info, x-region, x-client-platform",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-expose-headers":
    "server-timing, x-budget-ai-request-id, x-budget-ai-edge-region, x-budget-ai-quota-ms, x-budget-ai-openai-headers-ms, x-sb-edge-region, x-budget-ai-plan, x-budget-ai-remaining-messages",
};

type Usage = {
  inputTokens: number;
  outputTokens: number;
  cachedInputTokens: number;
};

type Reservation = {
  allowed: boolean;
  code: string;
  plan_tier: string | null;
  model: string | null;
  effective_service_tier: "default" | "fast";
  monthly_message_limit: number;
  remaining_messages: number;
  remaining_tokens: number;
  remaining_deep: number;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function uuidOrNull(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

/** `android` or `ios` from the app; anything else counts as unknown. */
function clientPlatform(req: Request) {
  const value = req.headers.get("x-client-platform")?.toLowerCase();
  return value === "android" || value === "ios" ? value : "unknown";
}

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

function quotaStatus(code: string) {
  if (code === "duplicate_request") return 409;
  if (code === "account_disabled") return 403;
  // The app opens the paywall (or the upgrade sheet) on 402.
  if (code === "premium_required" || code === "plan_limit_reached") return 402;
  return 429;
}

function quotaMessage(code: string) {
  switch (code) {
    case "concurrent_request_limit":
      return "Another response is already running. Please wait.";
    case "duplicate_request":
      return "This request was already submitted.";
    case "account_disabled":
      return "Your AI access has been blocked by an administrator.";
    case "premium_required":
      return "You've used this month's free AI messages. Upgrade to keep going.";
    case "plan_limit_reached":
      return "You've reached your plan's AI message limit.";
    case "message_round_limit":
      return "This reply needed too many steps. Try a simpler request.";
    default:
      return "Your AI usage limit has been reached.";
  }
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

    const rawRecord = rawBody as Record<string, unknown>;
    const clientTurnId = uuidOrNull(rawRecord.client_turn_id) ??
      crypto.randomUUID();
    // Every request answering one user message shares this id, so the
    // message counts once toward the plan.
    const userTurnId = uuidOrNull(rawRecord.user_turn_id);
    const deepAnalysis = rawRecord.deep_analysis === true;
    const requestId = crypto.randomUUID();
    const adminClient = ctx.supabaseAdmin as unknown as AdminClientWithRpc;

    const quotaStartedAt = performance.now();
    const { data: reservationData, error: reservationError } = await adminClient
      .rpc("reserve_ai_message_request", {
        p_user_id: userId,
        p_request_id: requestId,
        p_client_turn_id: clientTurnId,
        p_user_turn_id: userTurnId,
        p_platform: clientPlatform(req),
        p_requested_model: model,
        p_estimated_tokens: estimatedTokens,
        p_requested_service_tier: requestBody.service_tier === "fast"
          ? "fast"
          : "default",
        p_deep: deepAnalysis,
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
        message: quotaMessage(code),
        plan_tier: reservation?.plan_tier ?? null,
        limits: reservation
          ? {
            monthly_message_limit: reservation.monthly_message_limit,
            remaining_messages: reservation.remaining_messages,
            remaining_tokens: reservation.remaining_tokens,
            remaining_deep: reservation.remaining_deep,
          }
          : undefined,
      });
    }

    // The plan decides the model, not the client.
    if (reservation.model) requestBody.model = reservation.model;
    const planHeaders = {
      "x-budget-ai-plan": reservation.plan_tier ?? "unknown",
      "x-budget-ai-remaining-messages": String(reservation.remaining_messages),
    };

    if (reservation.effective_service_tier !== "fast") {
      delete requestBody.service_tier;
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
      // OpenAI's error names the failing parameter; log it (never the
      // request body) so 4xx causes are visible in the function logs.
      const upstreamError = await upstream.text().catch(() => "");
      let detail = upstreamError.slice(0, 300);
      try {
        const parsed = JSON.parse(upstreamError) as {
          error?: {
            code?: string;
            type?: string;
            param?: string;
            message?: string;
          };
        };
        const e = parsed.error ?? {};
        detail = [e.code, e.type, e.param, e.message?.slice(0, 240)]
          .filter(Boolean).join(" | ");
      } catch {
        // Not JSON; keep the truncated text.
      }
      console.error(
        "OpenAI request failed",
        upstream.status,
        requestBody.model,
        detail,
      );
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
          ...planHeaders,
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
        ...planHeaders,
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
