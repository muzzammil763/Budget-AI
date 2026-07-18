import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelSettingsService {
  ModelSettingsService._();

  static final ModelSettingsService instance = ModelSettingsService._();
  static const String _modelKey = 'budget_selected_model_id';
  static const String _providerKey = 'budget_selected_provider_id';
  static const String _groqModelKey = 'budget_selected_groq_model_id';

  final ValueNotifier<String> providerId = ValueNotifier<String>(
    ChatModelConfig.deepseek.id,
  );

  final ValueNotifier<String> modelId = ValueNotifier<String>(
    AIModels.defaultModelId,
  );
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    final savedProvider = (await _preferences.getString(_providerKey))?.trim();
    providerId.value =
        ChatModelConfig.fromId(savedProvider ?? '')?.id ??
        ChatModelConfig.deepseek.id;

    final key = providerId.value == ChatModelConfig.groq.id
        ? _groqModelKey
        : _modelKey;
    final savedModel = (await _preferences.getString(key))?.trim();
    final allowed = AIModels.modelsForProvider(providerId.value);
    modelId.value = allowed.any((model) => model.id == savedModel)
        ? savedModel!
        : AIModels.defaultModelForProvider(providerId.value);
  }

  Future<void> setProvider(String value) async {
    final normalized = value.trim();
    if (ChatModelConfig.fromId(normalized) == null) return;
    await _preferences.setString(_providerKey, normalized);
    providerId.value = normalized;
    final key = normalized == ChatModelConfig.groq.id
        ? _groqModelKey
        : _modelKey;
    final savedModel = (await _preferences.getString(key))?.trim();
    final allowed = AIModels.modelsForProvider(normalized);
    modelId.value = allowed.any((model) => model.id == savedModel)
        ? savedModel!
        : AIModels.defaultModelForProvider(normalized);
  }

  Future<void> setModel(String value) async {
    final normalized = value.trim();
    if (!AIModels.modelsForProvider(
      providerId.value,
    ).any((model) => model.id == normalized)) {
      return;
    }
    final key = providerId.value == ChatModelConfig.groq.id
        ? _groqModelKey
        : _modelKey;
    await _preferences.setString(key, normalized);
    modelId.value = normalized;
  }

  String get current => modelId.value;
  String get currentProvider => providerId.value;
  ChatModelConfig get currentConfig =>
      ChatModelConfig.fromId(currentProvider) ?? ChatModelConfig.deepseek;
}
