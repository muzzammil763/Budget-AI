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

const List<AIModel> _openAIModels = [
  AIModel(
    id: 'gpt-5.6-luna',
    name: 'GPT-5.6 Luna',
    description:
        'Cost-sensitive, high-volume GPT-5.6 model. \$1 / \$6 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 1050000,
  ),
  AIModel(
    id: 'gpt-5.6-terra',
    name: 'GPT-5.6 Terra',
    description: 'Balanced intelligence and cost. \$2.50 / \$15 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 1050000,
  ),
  AIModel(
    id: 'gpt-5.6-sol',
    name: 'GPT-5.6 Sol',
    description:
        'Frontier model for complex professional work. \$5 / \$30 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 1050000,
  ),
  AIModel(
    id: 'gpt-5.5',
    name: 'GPT-5.5',
    description:
        'Previous flagship for professional and agentic work. \$5 / \$30 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 1050000,
  ),
  AIModel(
    id: 'gpt-5.4',
    name: 'GPT-5.4',
    description:
        'Affordable professional workhorse. \$2.50 / \$15 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 1050000,
  ),
  AIModel(
    id: 'gpt-5.4-mini',
    name: 'GPT-5.4 mini',
    description:
        'Efficient model for well-defined tasks. \$0.75 / \$4.50 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 400000,
  ),
  AIModel(
    id: 'gpt-5.4-nano',
    name: 'GPT-5.4 nano',
    description:
        'Fast, inexpensive routing and extraction. \$0.20 / \$1.25 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 400000,
  ),
  AIModel(
    id: 'gpt-4.1',
    name: 'GPT-4.1',
    description:
        'Long-context non-reasoning model with vision. \$2 / \$8 per 1M tokens.',
    supportsToolCall: true,
    contextLength: 1047576,
  ),
  AIModel(
    id: 'o3',
    name: 'o3',
    description:
        'Previous reasoning model for difficult multi-step work. \$2 / \$8 per 1M tokens.',
    supportsToolCall: true,
    supportsThinking: true,
    contextLength: 200000,
  ),
];

class AIModels {
  static const List<AIModel> openAIModels = _openAIModels;

  static const String defaultModelId = 'gpt-5.4-nano';

  static AIModel? getModelById(String modelId) {
    try {
      return openAIModels.firstWhere((model) => model.id == modelId);
    } catch (e) {
      return null;
    }
  }
}
