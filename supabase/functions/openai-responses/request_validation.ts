export const maxRequestBytes = 24 * 1024 * 1024;
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

function safeInteger(value: unknown, fallback: number, maximum: number) {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(1, Math.min(Math.trunc(value), maximum));
}

export function validateAndSanitizeBody(raw: unknown) {
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

  let imageCount = 0;
  let generatedCount = 0;
  const inputJson = JSON.stringify(body.input ?? "", (_key, value) => {
    if (value && typeof value === "object" && value.type === "input_image") {
      imageCount++;
      if (
        imageCount > 3 || typeof value.image_url !== "string" ||
        !/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(
          value.image_url,
        ) ||
        value.image_url.length > 5_600_000
      ) throw new Error("invalid_image");
      return { type: "input_text", text: "[Image]" };
    }
    if (
      value && typeof value === "object" &&
      value.type === "image_generation_call"
    ) {
      generatedCount++;
      if (
        generatedCount > 3 || typeof value.result !== "string" ||
        value.result.length > 12_000_000
      ) throw new Error("invalid_generated_image");
      return { type: "input_text", text: "[Generated image]" };
    }
    return value;
  });
  if (inputJson.length > maxInputLength) throw new Error("input_too_large");

  const tools = body.tools;
  if (tools !== undefined) {
    if (!Array.isArray(tools) || tools.length > allowedTools.size + 1) {
      throw new Error("invalid_tools");
    }
    let imageTools = 0;
    for (const tool of tools) {
      if (!tool || typeof tool !== "object") throw new Error("invalid_tools");
      const name = (tool as Record<string, unknown>).name;
      const type = (tool as Record<string, unknown>).type;
      if (type === "image_generation") {
        if (++imageTools > 1) throw new Error("invalid_tools");
        continue;
      }
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
    sanitized.tools = (tools as Record<string, unknown>[]).map((tool) =>
      tool.type === "image_generation"
        ? {
          type: "image_generation",
          model: "gpt-image-2",
          size: "1024x1024",
          quality: "medium",
        }
        : tool
    );
    sanitized.max_tool_calls = 1;
    sanitized.tool_choice = "auto";
    sanitized.parallel_tool_calls = false;
  }

  return {
    sanitized,
    model,
    estimatedTokens: Math.ceil(inputJson.length / 4) + imageCount * 2500 +
      generatedCount * 2500 + requestedOutputTokens,
  };
}
