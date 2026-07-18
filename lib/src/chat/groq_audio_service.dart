import 'dart:typed_data';

import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:dio/dio.dart';

class GroqAudioService {
  GroqAudioService({Dio? dio}) : _dio = dio ?? Dio();

  static const String _baseUrl = 'https://api.groq.com/openai/v1';
  static const String transcriptionModel = 'whisper-large-v3-turbo';
  static const String speechModel = 'canopylabs/orpheus-v1-english';
  static const String speechVoice = 'troy';

  final Dio _dio;

  Options get _authorizedOptions {
    final key = AppConstants.groqApiKey;
    if (key.isEmpty) {
      throw StateError('GROQ_API_KEY is not configured for this build.');
    }
    return Options(headers: {'Authorization': 'Bearer $key'});
  }

  Future<String> transcribe(String audioPath) async {
    final fileName = audioPath.split('/').last;
    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/audio/transcriptions',
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(audioPath, filename: fileName),
        'model': transcriptionModel,
        'response_format': 'json',
        'temperature': 0,
      }),
      options: _authorizedOptions,
    );
    return response.data?['text']?.toString().trim() ?? '';
  }

  Future<Uint8List> synthesize(String text) async {
    final response = await _dio.post<List<int>>(
      '$_baseUrl/audio/speech',
      data: {
        'model': speechModel,
        'voice': speechVoice,
        'input': text,
        'response_format': 'wav',
      },
      options: _authorizedOptions.copyWith(responseType: ResponseType.bytes),
    );
    final audio = Uint8List.fromList(response.data ?? const <int>[]);
    if (!_isWaveFile(audio)) {
      throw const FormatException(
        'Groq returned an invalid WAV response. Please try again.',
      );
    }
    return audio;
  }

  static bool _isWaveFile(Uint8List bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;

  static List<String> speechChunks(String input, {int maxLength = 200}) {
    final normalized = input
        .replaceAll(RegExp(r'[`#*_>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];

    final chunks = <String>[];
    var remaining = normalized;
    while (remaining.length > maxLength) {
      var splitAt = remaining.lastIndexOf(RegExp(r'[.!?]'), maxLength - 1);
      if (splitAt < maxLength ~/ 2) {
        splitAt = remaining.lastIndexOf(' ', maxLength - 1);
      }
      if (splitAt <= 0) splitAt = maxLength;
      final end = splitAt < remaining.length && remaining[splitAt] != ' '
          ? splitAt + 1
          : splitAt;
      chunks.add(remaining.substring(0, end).trim());
      remaining = remaining.substring(end).trim();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  void dispose() => _dio.close(force: true);
}
