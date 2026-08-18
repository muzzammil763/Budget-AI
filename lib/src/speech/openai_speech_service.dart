import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budget_ai/src/storage/local_settings_store.dart';

typedef OpenAiSpeechFunctionInvoker =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

class OpenAiTranscription {
  const OpenAiTranscription({required this.text, required this.languageCode});

  final String text;
  final String languageCode;
}

class OpenAiSpeechService {
  OpenAiSpeechService({
    OpenAiSpeechFunctionInvoker? invoke,
    FlutterTts? textToSpeech,
    bool configureTextToSpeech = true,
  }) : _invoke = invoke ?? _invokeFunction,
       _tts = textToSpeech ?? FlutterTts() {
    _ttsReady = configureTextToSpeech
        ? _configureTextToSpeech()
        : Future<void>.value();
  }

  final OpenAiSpeechFunctionInvoker _invoke;
  final FlutterTts _tts;
  late final Future<void> _ttsReady;
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  int _playbackGeneration = 0;

  bool get isReadyForVoiceTurn =>
      Supabase.instance.client.auth.currentSession != null;

  Future<void> _configureTextToSpeech() async {
    await _tts.awaitSpeakCompletion(true);
    _tts.setStartHandler(() => isPlaying.value = true);
    _tts.setCompletionHandler(() => isPlaying.value = false);
    _tts.setCancelHandler(() => isPlaying.value = false);
    _tts.setErrorHandler((_) => isPlaying.value = false);
  }

  static Future<void> removeLegacyOfflineSpeechArtifacts() async {
    try {
      await LocalSettingsStore.instance.remove('budget_local_stt_model_id');
      final supportDirectory = await getApplicationSupportDirectory();
      final legacyModels = Directory(
        p.join(supportDirectory.path, 'speech_models'),
      );
      if (await legacyModels.exists()) {
        await legacyModels.delete(recursive: true);
      }
    } catch (error) {
      debugPrint('[OpenAiSpeech] Could not remove legacy models: $error');
    }
  }

  Future<OpenAiTranscription> transcribe(
    String audioPath, {
    required Locale locale,
  }) async {
    final bytes = await File(audioPath).readAsBytes();
    final requestedLanguageCode = speechLanguageCodeForLocale(locale);
    final data = await _invoke({
      'audioContent': base64Encode(bytes),
      'fileName': p.basename(audioPath),
      'languageCode': requestedLanguageCode,
    });
    final text = data['transcript']?.toString().trim() ?? '';
    final languageCode =
        data['languageCode']?.toString().trim() ?? requestedLanguageCode;
    return OpenAiTranscription(
      text: text,
      languageCode: languageCode.isEmpty ? requestedLanguageCode : languageCode,
    );
  }

  Future<void> speak(String text, {required String languageCode}) async {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return;

    await _ttsReady;
    final generation = ++_playbackGeneration;
    await _tts.stop();
    final availableLanguages = await _availableLanguages();
    final selectedLanguage = selectDeviceTtsLanguage(
      text: normalized,
      requestedLanguageCode: languageCode,
      availableLanguages: availableLanguages,
    );
    await _tts.setLanguage(selectedLanguage);
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    if (generation != _playbackGeneration) return;
    isPlaying.value = true;
    try {
      await _tts.speak(normalized);
    } finally {
      if (generation == _playbackGeneration) isPlaying.value = false;
    }
  }

  Future<Set<String>> _availableLanguages() async {
    try {
      final values = await _tts.getLanguages;
      if (values is List) {
        return values.map((value) => value.toString()).toSet();
      }
    } catch (_) {
      // The platform default remains usable when enumeration is unavailable.
    }
    return const {};
  }

  Future<void> stop() async {
    _playbackGeneration++;
    isPlaying.value = false;
    await _tts.stop();
  }

  Future<void> dispose() async {
    await stop();
    isPlaying.dispose();
  }

  static Future<Map<String, dynamic>> _invokeFunction(
    Map<String, dynamic> body,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'openai-speech',
      body: body,
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('OpenAI transcription returned an invalid response.');
    }
    return Map<String, dynamic>.from(data);
  }
}

String speechLanguageCodeForLocale(Locale locale) {
  const defaults = <String, String>{
    'ar': 'ar-SA',
    'de': 'de-DE',
    'en': 'en-US',
    'es': 'es-ES',
    'fa': 'fa-IR',
    'fr': 'fr-FR',
    'hi': 'hi-IN',
    'it': 'it-IT',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'pa': 'pa-IN',
    'pt': 'pt-BR',
    'ru': 'ru-RU',
    'tr': 'tr-TR',
    'ur': 'ur-PK',
    'zh': 'zh-CN',
  };
  final language = locale.languageCode.toLowerCase();
  final country = locale.countryCode?.toUpperCase();
  return country != null && country.isNotEmpty
      ? '$language-$country'
      : defaults[language] ?? 'en-US';
}

String selectDeviceTtsLanguage({
  required String text,
  required String requestedLanguageCode,
  required Set<String> availableLanguages,
}) {
  final hasUrduScript = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  final requested = requestedLanguageCode.trim().isEmpty
      ? 'en-US'
      : requestedLanguageCode;
  final preferred = hasUrduScript
      ? 'ur-PK'
      : requested.toLowerCase().startsWith('ur')
      ? 'en-US'
      : requested;
  if (availableLanguages.isEmpty || availableLanguages.contains(preferred)) {
    return preferred;
  }
  final sameLanguage = availableLanguages.where(
    (value) => value.toLowerCase().startsWith(
      '${preferred.split('-').first.toLowerCase()}-',
    ),
  );
  if (sameLanguage.isNotEmpty) return sameLanguage.first;
  if (availableLanguages.contains('en-US')) return 'en-US';
  return availableLanguages.first;
}

bool assistantSpeechTapEnabled({
  required bool isUser,
  required bool hasText,
  required bool responseInProgress,
  required bool isStreamingMessage,
  required bool isFinalInTurn,
}) {
  return !isUser &&
      hasText &&
      !responseInProgress &&
      !isStreamingMessage &&
      isFinalInTurn;
}
