import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
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
  OpenAiSpeechService({
    OpenAiSpeechFunctionInvoker? invoke,
    AudioPlayer? audioPlayer,
  }) : _invoke = invoke ?? _invokeFunction,
       _audioPlayer = audioPlayer;

  final OpenAiSpeechFunctionInvoker _invoke;
  AudioPlayer? _audioPlayer;
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  int _playbackGeneration = 0;

  AudioPlayer get _player => _audioPlayer ??= AudioPlayer();

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
      'action': 'transcribe',
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
    final chunks = splitTextForSpeech(text);
    if (chunks.isEmpty) return;

    final generation = ++_playbackGeneration;
    await _player.stop();
    isPlaying.value = true;
    try {
      for (final chunk in chunks) {
        if (generation != _playbackGeneration) return;
        final audioFile = await _cachedOrSynthesizedAudio(
          chunk,
          languageCode: languageCode,
        );
        await _playAudioFile(audioFile, generation);
      }
    } finally {
      if (generation == _playbackGeneration) isPlaying.value = false;
    }
  }

  Future<File> _cachedOrSynthesizedAudio(
    String text, {
    required String languageCode,
  }) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final cacheKey = sha256
        .convert(utf8.encode('elevenlabs-v2\n$languageCode\n$text'))
        .toString();
    final audioFile = File(
      p.join(temporaryDirectory.path, 'budget_ai_tts_$cacheKey.mp3'),
    );
    if (await audioFile.exists() && await audioFile.length() > 0) {
      return audioFile;
    }

    final data = await _invoke({
      'action': 'synthesize',
      'text': text,
      'languageCode': languageCode,
    });
    final encoded = data['audioContent']?.toString() ?? '';
    if (encoded.isEmpty) {
      throw StateError('ElevenLabs returned no speech audio.');
    }
    await audioFile.writeAsBytes(base64Decode(encoded), flush: true);
    return audioFile;
  }

  Future<void> _playAudioFile(File audioFile, int generation) async {
    final completed = _player.onPlayerComplete.first;
    await _player.play(
      DeviceFileSource(audioFile.path, mimeType: 'audio/mpeg'),
    );
    await completed;
    if (generation != _playbackGeneration) return;
  }

  Future<void> stop() async {
    _playbackGeneration++;
    isPlaying.value = false;
    await _audioPlayer?.stop();
  }

  Future<void> dispose() async {
    await stop();
    isPlaying.dispose();
    await _audioPlayer?.dispose();
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
      throw StateError('Cloud speech returned an invalid response.');
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

List<String> splitTextForSpeech(String text, {int maxCharacters = 1200}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  final chunks = <String>[];
  final current = StringBuffer();
  for (final word in normalized.split(' ')) {
    if (current.isNotEmpty &&
        current.length + word.length + 1 > maxCharacters) {
      chunks.add(current.toString());
      current.clear();
    }
    if (word.length > maxCharacters) {
      if (current.isNotEmpty) {
        chunks.add(current.toString());
        current.clear();
      }
      for (var offset = 0; offset < word.length; offset += maxCharacters) {
        chunks.add(
          word.substring(
            offset,
            (offset + maxCharacters).clamp(0, word.length),
          ),
        );
      }
      continue;
    }
    if (current.isNotEmpty) current.write(' ');
    current.write(word);
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
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
