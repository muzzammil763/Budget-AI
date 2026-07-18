class AIModel {
  final String id;
  final String name;
  final String description;
  final bool supportsToolCall;
  final bool supportsThinking;
  final int? contextLength;

  const AIModel({
    required this.id,
    required this.name,
    required this.description,
    this.supportsToolCall = false,
    this.supportsThinking = false,
    this.contextLength,
  });
}

const List<AIModel> _deepseekModels = [
  AIModel(
    id: 'deepseek-v4-flash',
    name: 'DeepSeek V4 Flash',
    description:
        'Fast and efficient. 1M context, tool calls, thinking mode, and JSON output.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 1000000,
  ),
  AIModel(
    id: 'deepseek-v4-pro',
    name: 'DeepSeek V4 Pro',
    description:
        'Highest capability tier. 1M context, tool calls, thinking mode, and JSON output. Best for complex coding, math, and multi-step reasoning.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 1000000,
  ),
];

const List<AIModel> _groqModels = [
  AIModel(
    id: 'llama-3.1-8b-instant',
    name: 'Llama 3.1 8B Instant',
    description: 'Fast, lightweight model for everyday conversations.',
    supportsToolCall: true,
    contextLength: 131072,
  ),
  AIModel(
    id: 'llama-3.3-70b-versatile',
    name: 'Llama 3.3 70B',
    description: 'High-quality multilingual model with reliable tool use.',
    supportsToolCall: true,
    contextLength: 131072,
  ),
  AIModel(
    id: 'qwen/qwen3-32b',
    name: 'Qwen 3 32B',
    description: 'Strong general-purpose model with parallel tool use.',
    supportsToolCall: true,
    contextLength: 131072,
  ),
  AIModel(
    id: 'openai/gpt-oss-120b',
    name: 'GPT-OSS 120B',
    description: 'Groq\'s highest-capability open-weight reasoning model.',
    supportsToolCall: true,
    contextLength: 131072,
  ),
];

class AIModels {
  static const List<AIModel> deepseekModels = _deepseekModels;
  static const List<AIModel> groqModels = _groqModels;

  static const String defaultModelId = 'deepseek-v4-flash';
  static const String defaultGroqModelId = 'llama-3.1-8b-instant';

  static List<AIModel> modelsForProvider(String providerId) =>
      providerId == 'groq' ? groqModels : deepseekModels;

  static String defaultModelForProvider(String providerId) =>
      providerId == 'groq' ? defaultGroqModelId : defaultModelId;

  static AIModel? getModelById(String modelId) {
    try {
      return [
        ...deepseekModels,
        ...groqModels,
      ].firstWhere((model) => model.id == modelId);
    } catch (e) {
      return null;
    }
  }
}
