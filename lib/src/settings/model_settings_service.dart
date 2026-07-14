import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelSettingsService {
  ModelSettingsService._();

  static final ModelSettingsService instance = ModelSettingsService._();
  static const String _modelKey = 'budget_selected_model_id';

  final ValueNotifier<String> modelId = ValueNotifier<String>(
    AIModels.defaultModelId,
  );
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    final saved = (await _preferences.getString(_modelKey))?.trim();
    if (saved != null && AIModels.getModelById(saved) != null) {
      modelId.value = saved;
    }
  }

  Future<void> setModel(String value) async {
    final normalized = value.trim();
    if (AIModels.getModelById(normalized) == null) return;
    await _preferences.setString(_modelKey, normalized);
    modelId.value = normalized;
  }

  String get current => modelId.value;
}
