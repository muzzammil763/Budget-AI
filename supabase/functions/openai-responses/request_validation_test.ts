import { validateAndSanitizeBody } from "./request_validation.ts";

function assert(value: boolean, message: string) {
  if (!value) throw new Error(message);
}
function rejected(input: unknown, code: string) {
  try {
    validateAndSanitizeBody(input);
  } catch (error) {
    assert(
      error instanceof Error && error.message === code,
      `Expected ${code}: ${error}`,
    );
    return;
  }
  throw new Error(`Expected rejection: ${code}`);
}
const image = {
  type: "input_image",
  image_url: "data:image/png;base64,aGVsbG8=",
};
const request = (images: unknown[]) => ({
  model: "gpt-5.6-luna",
  input: [{ role: "user", content: images }],
});

Deno.test("accept three inline images; estimate image tokens instead of base64 characters", () => {
  const large = {
    ...image,
    image_url: "data:image/png;base64," + "A".repeat(1_000_000),
  };
  const result = validateAndSanitizeBody(request([large, large, large]));
  assert(result.estimatedTokens < 15_000, "Base64 must not be billed as text");
  assert(
    (result.sanitized.input as unknown[]).length === 1,
    "Preserve multimodal input",
  );
});
Deno.test("reject too many, oversized and remote image inputs", () => {
  rejected(request([image, image, image, image]), "invalid_image");
  rejected(
    request([{ ...image, image_url: "https://example.com/image.png" }]),
    "invalid_image",
  );
  rejected(
    request([{
      ...image,
      image_url: "data:image/png;base64," + "A".repeat(5_600_000),
    }]),
    "invalid_image",
  );
  rejected(
    request([{ ...image, image_url: "data:image/svg+xml;base64,aA==" }]),
    "invalid_image",
  );
});
Deno.test("reject image generation while retaining finance tools", () => {
  rejected({ ...request([]), tools: [{ type: "image_generation" }] }, "unsupported_tool");
  rejected({ ...request([]), tools: [{ type: "web_search" }] }, "unsupported_tool");
  const result = validateAndSanitizeBody({ ...request([]), tools: [{ type: "function", name: "finance_summary" }] });
  assert((result.sanitized.tools as unknown[]).length === 1, "Finance tool allowed");
});
Deno.test("text limit still applies alongside images and invalid models fail", () => {
  rejected(
    request([image, { type: "input_text", text: "A".repeat(400_001) }]),
    "input_too_large",
  );
  rejected({ ...request([image]), model: "unknown" }, "unsupported_model");
});
