import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
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
  OpenAiSpeechService({OpenAiSpeechFunctionInvoker? invoke})
    : _invoke = invoke ?? _invokeFunction;

  final OpenAiSpeechFunctionInvoker _invoke;

  bool get isReadyForVoiceTurn =>
      Supabase.instance.client.auth.currentSession != null;

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
