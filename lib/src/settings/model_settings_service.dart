import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelSettingsService {
  ModelSettingsService._();

  static final ModelSettingsService instance = ModelSettingsService._();
  static const String _modelKey = 'budget_selected_model_id';
  static const String _groqVoiceKey = 'budget_selected_groq_voice_id';
  static const String _speechProviderKey = 'budget_speech_provider_id';
  static const String _elevenLabsVoiceIdKey = 'budget_elevenlabs_voice_id';
  static const String _elevenLabsVoiceNameKey = 'budget_elevenlabs_voice_name';
  static const String _voiceInputProviderKey = 'budget_voice_input_provider_id';
  static const String _geminiVoiceKey = 'budget_selected_gemini_voice_id';
  static const String groqSpeechProviderId = 'groq';
  static const String elevenLabsSpeechProviderId = 'elevenlabs';
  static const String geminiSpeechProviderId = 'gemini';
  static const String groqVoiceInputProviderId = 'groq';
  static const String geminiVoiceInputProviderId = 'gemini';
  static const String defaultGroqVoiceId = 'troy';
  static const List<GroqVoiceOption> groqVoices = [
    GroqVoiceOption(id: 'autumn', name: 'Autumn', gender: 'Female'),
    GroqVoiceOption(id: 'diana', name: 'Diana', gender: 'Female'),
    GroqVoiceOption(id: 'hannah', name: 'Hannah', gender: 'Female'),
    GroqVoiceOption(id: 'austin', name: 'Austin', gender: 'Male'),
    GroqVoiceOption(id: 'daniel', name: 'Daniel', gender: 'Male'),
    GroqVoiceOption(id: 'troy', name: 'Troy', gender: 'Male'),
  ];
  static const String defaultGeminiVoiceId = 'Kore';
  static const List<GeminiVoiceOption> geminiVoices = [
    GeminiVoiceOption(id: 'Zephyr', style: 'Bright'),
    GeminiVoiceOption(id: 'Puck', style: 'Upbeat'),
    GeminiVoiceOption(id: 'Charon', style: 'Informative'),
    GeminiVoiceOption(id: 'Kore', style: 'Firm'),
    GeminiVoiceOption(id: 'Fenrir', style: 'Excitable'),
    GeminiVoiceOption(id: 'Leda', style: 'Youthful'),
    GeminiVoiceOption(id: 'Orus', style: 'Firm'),
    GeminiVoiceOption(id: 'Aoede', style: 'Breezy'),
    GeminiVoiceOption(id: 'Callirrhoe', style: 'Easy-going'),
    GeminiVoiceOption(id: 'Autonoe', style: 'Bright'),
    GeminiVoiceOption(id: 'Enceladus', style: 'Breathy'),
    GeminiVoiceOption(id: 'Iapetus', style: 'Clear'),
    GeminiVoiceOption(id: 'Umbriel', style: 'Easy-going'),
    GeminiVoiceOption(id: 'Algieba', style: 'Smooth'),
    GeminiVoiceOption(id: 'Despina', style: 'Smooth'),
    GeminiVoiceOption(id: 'Erinome', style: 'Clear'),
    GeminiVoiceOption(id: 'Algenib', style: 'Gravelly'),
    GeminiVoiceOption(id: 'Rasalgethi', style: 'Informative'),
    GeminiVoiceOption(id: 'Laomedeia', style: 'Upbeat'),
    GeminiVoiceOption(id: 'Achernar', style: 'Soft'),
    GeminiVoiceOption(id: 'Alnilam', style: 'Firm'),
    GeminiVoiceOption(id: 'Schedar', style: 'Even'),
    GeminiVoiceOption(id: 'Gacrux', style: 'Mature'),
    GeminiVoiceOption(id: 'Pulcherrima', style: 'Forward'),
    GeminiVoiceOption(id: 'Achird', style: 'Friendly'),
    GeminiVoiceOption(id: 'Zubenelgenubi', style: 'Casual'),
    GeminiVoiceOption(id: 'Vindemiatrix', style: 'Gentle'),
    GeminiVoiceOption(id: 'Sadachbia', style: 'Lively'),
    GeminiVoiceOption(id: 'Sadaltager', style: 'Knowledgeable'),
    GeminiVoiceOption(id: 'Sulafat', style: 'Warm'),
  ];

  final ValueNotifier<String> modelId = ValueNotifier<String>(
    AIModels.defaultModelId,
  );
  final ValueNotifier<String> speechProviderId = ValueNotifier<String>(
    groqSpeechProviderId,
  );
  final ValueNotifier<String> voiceInputProviderId = ValueNotifier<String>(
    groqVoiceInputProviderId,
  );
  final ValueNotifier<String> groqVoiceId = ValueNotifier<String>(
    defaultGroqVoiceId,
  );
  final ValueNotifier<String?> elevenLabsVoiceId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> elevenLabsVoiceName = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<String> geminiVoiceId = ValueNotifier<String>(
    defaultGeminiVoiceId,
  );
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    final savedSpeechProvider = (await _preferences.getString(
      _speechProviderKey,
    ))?.trim();
    speechProviderId.value = switch (savedSpeechProvider) {
      elevenLabsSpeechProviderId => elevenLabsSpeechProviderId,
      geminiSpeechProviderId => geminiSpeechProviderId,
      _ => groqSpeechProviderId,
    };

    final savedVoiceInputProvider = (await _preferences.getString(
      _voiceInputProviderKey,
    ))?.trim();
    voiceInputProviderId.value =
        savedVoiceInputProvider == geminiVoiceInputProviderId
        ? geminiVoiceInputProviderId
        : groqVoiceInputProviderId;

    final savedVoice = (await _preferences.getString(_groqVoiceKey))?.trim();
    groqVoiceId.value = groqVoices.any((voice) => voice.id == savedVoice)
        ? savedVoice!
        : defaultGroqVoiceId;

    final savedGeminiVoice = (await _preferences.getString(
      _geminiVoiceKey,
    ))?.trim();
    geminiVoiceId.value =
        geminiVoices.any((voice) => voice.id == savedGeminiVoice)
        ? savedGeminiVoice!
        : defaultGeminiVoiceId;

    final savedElevenVoiceId = (await _preferences.getString(
      _elevenLabsVoiceIdKey,
    ))?.trim();
    final savedElevenVoiceName = (await _preferences.getString(
      _elevenLabsVoiceNameKey,
    ))?.trim();
    elevenLabsVoiceId.value = savedElevenVoiceId?.isNotEmpty == true
        ? savedElevenVoiceId
        : null;
    elevenLabsVoiceName.value = savedElevenVoiceName?.isNotEmpty == true
        ? savedElevenVoiceName
        : null;

    final savedModel = (await _preferences.getString(_modelKey))?.trim();
    modelId.value =
        AIModels.deepseekModels.any((model) => model.id == savedModel)
        ? savedModel!
        : AIModels.defaultModelId;
  }

  Future<void> setModel(String value) async {
    final normalized = value.trim();
    if (!AIModels.deepseekModels.any((model) => model.id == normalized)) {
      return;
    }
    await _preferences.setString(_modelKey, normalized);
    modelId.value = normalized;
  }

  Future<void> setSpeechProvider(String value) async {
    if (value != groqSpeechProviderId &&
        value != elevenLabsSpeechProviderId &&
        value != geminiSpeechProviderId) {
      return;
    }
    await _preferences.setString(_speechProviderKey, value);
    speechProviderId.value = value;
  }

  Future<void> setVoiceInputProvider(String value) async {
    if (value != groqVoiceInputProviderId &&
        value != geminiVoiceInputProviderId) {
      return;
    }
    await _preferences.setString(_voiceInputProviderKey, value);
    voiceInputProviderId.value = value;
  }

  Future<void> setGroqVoice(String value) async {
    final normalized = value.trim().toLowerCase();
    if (!groqVoices.any((voice) => voice.id == normalized)) return;
    await _preferences.setString(_groqVoiceKey, normalized);
    groqVoiceId.value = normalized;
  }

  GroqVoiceOption get currentGroqVoice => groqVoices.firstWhere(
    (voice) => voice.id == groqVoiceId.value,
    orElse: () => groqVoices.last,
  );

  Future<void> setGeminiVoice(String value) async {
    final normalized = value.trim();
    if (!geminiVoices.any((voice) => voice.id == normalized)) return;
    await _preferences.setString(_geminiVoiceKey, normalized);
    geminiVoiceId.value = normalized;
  }

  GeminiVoiceOption get currentGeminiVoice => geminiVoices.firstWhere(
    (voice) => voice.id == geminiVoiceId.value,
    orElse: () => geminiVoices[3],
  );

  Future<void> setElevenLabsVoice({
    required String id,
    required String name,
  }) async {
    final normalizedId = id.trim();
    final normalizedName = name.trim();
    if (normalizedId.isEmpty || normalizedName.isEmpty) return;
    await _preferences.setString(_elevenLabsVoiceIdKey, normalizedId);
    await _preferences.setString(_elevenLabsVoiceNameKey, normalizedName);
    elevenLabsVoiceId.value = normalizedId;
    elevenLabsVoiceName.value = normalizedName;
  }

  String get current => modelId.value;
  String get currentSpeechProvider => speechProviderId.value;
  String get currentVoiceInputProvider => voiceInputProviderId.value;
}

class GroqVoiceOption {
  const GroqVoiceOption({
    required this.id,
    required this.name,
    required this.gender,
  });

  final String id;
  final String name;
  final String gender;
}

class GeminiVoiceOption {
  const GeminiVoiceOption({required this.id, required this.style});

  final String id;
  final String style;
}
