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

class AIModels {
  static const List<AIModel> deepseekModels = _deepseekModels;

  static const String defaultModelId = 'deepseek-v4-flash';

  static AIModel? getModelById(String modelId) {
    try {
      return deepseekModels.firstWhere((model) => model.id == modelId);
    } catch (e) {
      return null;
    }
  }
}
