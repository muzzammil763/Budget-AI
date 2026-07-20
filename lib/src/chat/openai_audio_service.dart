import 'dart:typed_data';

import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:dio/dio.dart';

/// OpenAI-only speech input and output for the record-then-send chat flow.
class OpenAIAudioService {
  OpenAIAudioService({Dio? dio}) : _dio = dio ?? Dio();

  static const String _baseUrl = 'https://api.openai.com/v1';
  static const String transcriptionModel = 'gpt-4o-transcribe';
  static const String speechModel = 'gpt-4o-mini-tts';

  final Dio _dio;

  Options _options({ResponseType? responseType}) {
    final key = AppConstants.openAIApiKey;
    if (key.isEmpty) {
      throw StateError('OPENAI_API_KEY is not configured for this build.');
    }
    return Options(
      responseType: responseType,
      headers: {'Authorization': 'Bearer $key'},
    );
  }

  Future<String> transcribe(String audioPath) async {
    final fileName = audioPath.split('/').last;
    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/audio/transcriptions',
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(audioPath, filename: fileName),
        'model': transcriptionModel,
        'response_format': 'json',
      }),
      options: _options(),
    );
    return response.data?['text']?.toString().trim() ?? '';
  }

  Future<Uint8List> synthesize(String text, {String? voice}) async {
    final selectedVoice = voice ?? ModelSettingsService.instance.currentVoice;
    final response = await _dio.post<List<int>>(
      '$_baseUrl/audio/speech',
      data: {
        'model': speechModel,
        'voice': selectedVoice,
        'input': text,
        'instructions':
            'Speak naturally and efficiently. Preserve numbers, dates, and monetary amounts exactly.',
        'response_format': 'mp3',
      },
      options: _options(responseType: ResponseType.bytes),
    );
    final audio = Uint8List.fromList(response.data ?? const <int>[]);
    if (audio.isEmpty) {
      throw const FormatException('OpenAI returned an empty speech response.');
    }
    return audio;
  }

  static List<String> speechChunks(String input, {int maxLength = 2000}) {
    final normalized = input
        .replaceAll(RegExp(r'[`#*_>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];

    final chunks = <String>[];
    var remaining = normalized;
    while (remaining.length > maxLength) {
      var splitAt = remaining.lastIndexOf(RegExp(r'[.!?]'), maxLength - 1);
      var includeBoundary = splitAt >= maxLength ~/ 2;
      if (splitAt < maxLength ~/ 2) {
        splitAt = remaining.lastIndexOf(' ', maxLength - 1);
        includeBoundary = false;
      }
      if (splitAt <= 0) {
        splitAt = maxLength;
        includeBoundary = false;
      }
      final end = includeBoundary ? splitAt + 1 : splitAt;
      chunks.add(remaining.substring(0, end).trim());
      remaining = remaining.substring(end).trim();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  void dispose() => _dio.close(force: true);
}
