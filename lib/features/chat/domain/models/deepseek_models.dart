part of 'ai_models.dart';

const List<AIModel> _deepseekModels = [
  AIModel(
    id: 'deepseek-v4-flash',
    name: 'DeepSeek V4 Flash',
    description:
        'Fast and efficient. 1M context, tool calls, thinking mode, and JSON output.',
    supportsToolCall: true,
    supportsThinking: true,
    supportsTemperature: true,
    inputModalities: ['text'],
    outputModalities: ['text'],
    contextLength: 1000000,
    maxOutput: 384000,
  ),
  AIModel(
    id: 'deepseek-v4-pro',
    name: 'DeepSeek V4 Pro',
    description:
        'Highest capability tier. 1M context, tool calls, thinking mode, and JSON output. Best for complex coding, math, and multi-step reasoning.',
    supportsToolCall: true,
    supportsThinking: true,
    supportsTemperature: true,
    inputModalities: ['text'],
    outputModalities: ['text'],
    contextLength: 1000000,
    maxOutput: 384000,
  ),
];
