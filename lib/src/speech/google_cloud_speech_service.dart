import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budget_ai/src/storage/local_settings_store.dart';

typedef GoogleSpeechFunctionInvoker =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

class GoogleCloudTranscription {
  const GoogleCloudTranscription({
    required this.text,
    required this.languageCode,
  });

  final String text;
  final String languageCode;
}

class GoogleCloudSpeechService {
  GoogleCloudSpeechService({
    GoogleSpeechFunctionInvoker? invoke,
    AudioPlayer? audioPlayer,
  }) : _invoke = invoke ?? _invokeFunction,
       _audioPlayer = audioPlayer;

  final GoogleSpeechFunctionInvoker _invoke;
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
      debugPrint('[GoogleCloudSpeech] Could not remove legacy models: $error');
    }
  }

  Future<GoogleCloudTranscription> transcribe(
    String audioPath, {
    required Locale locale,
  }) async {
    final bytes = await File(audioPath).readAsBytes();
    final candidates = googleSpeechLanguageCandidates(locale);
    final data = await _invoke({
      'action': 'transcribe',
      'audioContent': base64Encode(bytes),
      'languageCode': candidates.first,
      'alternativeLanguageCodes': candidates.skip(1).toList(),
    });
    final text = data['transcript']?.toString().trim() ?? '';
    final languageCode =
        data['languageCode']?.toString().trim() ?? candidates.first;
    return GoogleCloudTranscription(
      text: text,
      languageCode: languageCode.isEmpty ? candidates.first : languageCode,
    );
  }

  Future<void> speak(String text, {required String languageCode}) async {
    final chunks = splitTextForGoogleSpeech(text);
    if (chunks.isEmpty) return;

    final generation = ++_playbackGeneration;
    await _player.stop();
    isPlaying.value = true;
    try {
      for (final chunk in chunks) {
        if (generation != _playbackGeneration) return;
        final data = await _invoke({
          'action': 'synthesize',
          'text': chunk,
          'languageCode': languageCode,
        });
        final encoded = data['audioContent']?.toString() ?? '';
        if (encoded.isEmpty) {
          throw StateError('Google Cloud returned no speech audio.');
        }
        final audio = base64Decode(encoded);
        await _playAudioChunk(audio, generation);
      }
    } finally {
      if (generation == _playbackGeneration) {
        isPlaying.value = false;
      }
    }
  }

  Future<void> _playAudioChunk(Uint8List audio, int generation) async {
    final completed = _player.onPlayerComplete.first;
    await _player.play(BytesSource(audio));
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
      'google-cloud-speech',
      body: body,
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('Google Cloud speech returned an invalid response.');
    }
    return Map<String, dynamic>.from(data);
  }
}

List<String> googleSpeechLanguageCandidates(Locale locale) {
  const regionalDefaults = <String, String>{
    'ar': 'ar-XA',
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
    'zh': 'cmn-Hans-CN',
  };
  final language = locale.languageCode.toLowerCase();
  final country = locale.countryCode?.toUpperCase();
  final primary = country != null && country.isNotEmpty
      ? '$language-$country'
      : regionalDefaults[language] ?? 'en-US';
  return <String>{primary, 'en-US', 'ur-PK'}.take(4).toList();
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

List<String> splitTextForGoogleSpeech(String text, {int maxUtf8Bytes = 4200}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];

  final chunks = <String>[];
  final current = StringBuffer();

  void flush() {
    final value = current.toString().trim();
    if (value.isNotEmpty) chunks.add(value);
    current.clear();
  }

  void appendOversizedWord(String word) {
    for (final rune in word.runes) {
      final character = String.fromCharCode(rune);
      final candidate = '${current.toString()}$character';
      if (utf8.encode(candidate).length > maxUtf8Bytes) flush();
      current.write(character);
    }
  }

  for (final word in normalized.split(' ')) {
    final separator = current.isEmpty ? '' : ' ';
    final candidate = '${current.toString()}$separator$word';
    if (utf8.encode(candidate).length <= maxUtf8Bytes) {
      current
        ..write(separator)
        ..write(word);
      continue;
    }
    flush();
    if (utf8.encode(word).length <= maxUtf8Bytes) {
      current.write(word);
    } else {
      appendOversizedWord(word);
    }
  }
  flush();
  return chunks;
}
