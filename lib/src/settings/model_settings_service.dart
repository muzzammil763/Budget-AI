import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/openai_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelSettingsService {
  ModelSettingsService._();

  static final ModelSettingsService instance = ModelSettingsService._();

  static const String _modelKey = 'budget_selected_model_id';
  static const String _microphoneEnabledKey = 'budget_microphone_enabled';
  static const String _voiceKey = 'budget_openai_voice_id';

  final ValueNotifier<String> modelId = ValueNotifier<String>(
    AIModels.defaultModelId,
  );
  final ValueNotifier<bool> microphoneEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<String> voiceId = ValueNotifier<String>(
    OpenAIVoices.defaultVoiceId,
  );
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    final savedModel = (await _preferences.getString(_modelKey))?.trim();
    modelId.value = AIModels.openAIModels.any((model) => model.id == savedModel)
        ? savedModel!
        : AIModels.defaultModelId;
    microphoneEnabled.value =
        await _preferences.getBool(_microphoneEnabledKey) ?? true;
    final savedVoice = (await _preferences.getString(_voiceKey))?.trim();
    voiceId.value = OpenAIVoices.byId(savedVoice ?? '') != null
        ? savedVoice!
        : OpenAIVoices.defaultVoiceId;
  }

  Future<void> setModel(String value) async {
    final normalized = value.trim();
    if (!AIModels.openAIModels.any((model) => model.id == normalized)) return;
    await _preferences.setString(_modelKey, normalized);
    modelId.value = normalized;
  }

  Future<void> setMicrophoneEnabled(bool value) async {
    await _preferences.setBool(_microphoneEnabledKey, value);
    microphoneEnabled.value = value;
  }

  Future<void> setVoice(String value) async {
    final normalized = value.trim().toLowerCase();
    if (OpenAIVoices.byId(normalized) == null) return;
    await _preferences.setString(_voiceKey, normalized);
    voiceId.value = normalized;
  }

  String get current => modelId.value;
  String get currentVoice => voiceId.value;
}
