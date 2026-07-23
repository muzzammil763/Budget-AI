import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';

class ModelSettingsService {
  ModelSettingsService._();

  static final ModelSettingsService instance = ModelSettingsService._();

  static const String _modelKey = 'budget_selected_model_id';

  final ValueNotifier<String> modelId = ValueNotifier<String>(
    AIModels.defaultModelId,
  );
  final LocalSettingsStore _settings = LocalSettingsStore.instance;

  Future<void> initialize() async {
    final savedModel = (await _settings.getString(_modelKey))?.trim();
    modelId.value = AIModels.openAIModels.any((model) => model.id == savedModel)
        ? savedModel!
        : AIModels.defaultModelId;
  }

  Future<void> setModel(String value) async {
    final normalized = value.trim();
    if (!AIModels.openAIModels.any((model) => model.id == normalized)) return;
    modelId.value = normalized;
    await _settings.setString(
      _modelKey,
      normalized,
      scope: SettingSyncScope.account,
    );
  }

  Future<void> applySyncedModel(String value) async {
    final normalized = value.trim();
    if (!AIModels.openAIModels.any((model) => model.id == normalized)) return;
    modelId.value = normalized;
    await _settings.setValue(
      _modelKey,
      normalized,
      scope: SettingSyncScope.account,
      pendingSync: false,
    );
  }

  String get current => modelId.value;
}
