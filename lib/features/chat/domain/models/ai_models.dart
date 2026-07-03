part 'deepseek_models.dart';

class AIModel {
  final String id;
  final String name;
  final String description;
  final bool supportsToolCall;
  final bool supportsThinking;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final bool supportsAttachments;
  final int? contextLength;
  final int? maxOutput;
  final String? providerId;
  final bool? supportsTemperature;

  const AIModel({
    required this.id,
    required this.name,
    required this.description,
    this.supportsToolCall = false,
    this.supportsThinking = false,
    this.inputModalities = const ['text'],
    this.outputModalities = const ['text'],
    this.supportsAttachments = false,
    this.contextLength,
    this.maxOutput,
    this.providerId,
    this.supportsTemperature,
  });

  bool supportsInput(String modality) =>
      inputModalities.contains(modality.toLowerCase());

  bool supportsOutput(String modality) =>
      outputModalities.contains(modality.toLowerCase());

  String get formattedContextLength {
    if (contextLength == null) return 'Unknown';
    if (contextLength! >= 1000000) {
      return '${(contextLength! / 1000000).toStringAsFixed(1)}M';
    } else if (contextLength! >= 1000) {
      return '${(contextLength! / 1000).round()}K';
    }
    return contextLength.toString();
  }
}

class AIModels {
  static const List<AIModel> deepseekModels = _deepseekModels;

  static String getDefaultModel(String modelType) {
    switch (modelType) {
      case 'deepseek':
        return 'deepseek-v4-flash';
      default:
        return '';
    }
  }

  static List<AIModel> getModelsForType(String modelType) {
    switch (modelType) {
      case 'deepseek':
        return deepseekModels;
      default:
        return [];
    }
  }

  static AIModel? getModelById(String modelType, String modelId) {
    final models = getModelsForType(modelType);
    try {
      return models.firstWhere((model) => model.id == modelId);
    } catch (e) {
      return null;
    }
  }

  static List<AIModel> searchModels(List<AIModel> models, String query) {
    if (query.isEmpty) return models;

    final lowerQuery = query.toLowerCase();
    return models.where((model) {
      return model.name.toLowerCase().contains(lowerQuery) ||
          model.description.toLowerCase().contains(lowerQuery) ||
          model.id.toLowerCase().contains(lowerQuery);
    }).toList();
  }
}
