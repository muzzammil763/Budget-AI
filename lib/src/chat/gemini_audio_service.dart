import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:dio/dio.dart';

class GeminiAudioException implements Exception {
  const GeminiAudioException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class GeminiAudioService {
  GeminiAudioService({Dio? dio}) : _dio = dio ?? Dio();

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const String transcriptionModel = 'gemini-3.5-flash';
  static const String speechModel = 'gemini-3.1-flash-tts-preview';
  static const int speechSampleRate = 24000;

  final Dio _dio;

  Options get _options {
    final key = AppConstants.geminiApiKey;
    if (key.isEmpty) {
      throw StateError('GEMINI_API_KEY is not configured for this build.');
    }
    return Options(
      headers: {
        'x-goog-api-key': key,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
  }

  Future<String> transcribe(String audioPath) async {
    final audio = await File(audioPath).readAsBytes();
    if (audio.length > 19 * 1024 * 1024) {
      throw const GeminiAudioException(
        'The recording is too large for inline Gemini transcription.',
      );
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/$transcriptionModel:generateContent',
        data: {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'inlineData': {
                    'mimeType': 'audio/wav',
                    'data': base64Encode(audio),
                  },
                },
                {
                  'text':
                      'Transcribe the spoken words exactly. Return only the transcript, without quotes, timestamps, explanations, or Markdown.',
                },
              ],
            },
          ],
          'generationConfig': {'temperature': 0},
        },
        options: _options,
      );
      return _extractText(response.data).trim();
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Uint8List> synthesize(String text, {required String voiceName}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '$_baseUrl/$speechModel:generateContent',
          data: {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': 'Read this response naturally:\n\n$text'},
                ],
              },
            ],
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'speechConfig': {
                'voiceConfig': {
                  'prebuiltVoiceConfig': {'voiceName': voiceName},
                },
              },
            },
          },
          options: _options,
        );
        final pcm = _extractAudio(response.data);
        if (pcm.isEmpty) {
          throw const GeminiAudioException(
            'Gemini returned no speech audio. Please try again.',
          );
        }
        return _pcmToWave(pcm, sampleRate: speechSampleRate);
      } on DioException catch (error) {
        if (attempt == 0 && (error.response?.statusCode ?? 0) >= 500) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        throw _mapDioException(error);
      }
    }
    throw const GeminiAudioException('Gemini speech generation failed.');
  }

  String _extractText(Map<String, dynamic>? response) {
    final candidates = response?['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final candidate = candidates.first;
    if (candidate is! Map) return '';
    final content = candidate['content'];
    if (content is! Map || content['parts'] is! List) return '';
    return (content['parts'] as List)
        .whereType<Map>()
        .map((part) => part['text']?.toString() ?? '')
        .join();
  }

  Uint8List _extractAudio(Map<String, dynamic>? response) {
    final bytes = BytesBuilder(copy: false);
    final candidates = response?['candidates'];
    if (candidates is! List || candidates.isEmpty) return Uint8List(0);
    final candidate = candidates.first;
    if (candidate is! Map) return Uint8List(0);
    final content = candidate['content'];
    if (content is! Map || content['parts'] is! List) return Uint8List(0);
    for (final part in content['parts'] as List) {
      if (part is! Map) continue;
      final inlineData = part['inlineData'] ?? part['inline_data'];
      if (inlineData is! Map) continue;
      final data = inlineData['data']?.toString();
      if (data == null || data.isEmpty) continue;
      bytes.add(base64Decode(data));
    }
    return bytes.takeBytes();
  }

  GeminiAudioException _mapDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;
    String? apiMessage;
    if (data is Map) {
      final errorData = data['error'];
      if (errorData is Map) apiMessage = errorData['message']?.toString();
    }
    return GeminiAudioException(
      apiMessage?.trim().isNotEmpty == true
          ? apiMessage!.trim()
          : 'Gemini audio request failed${statusCode == null ? '' : ' (HTTP $statusCode)'}.',
      statusCode: statusCode,
    );
  }

  static Uint8List _pcmToWave(
    Uint8List pcm, {
    required int sampleRate,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final header = ByteData(44);
    final bytesPerSample = bitsPerSample ~/ 8;
    final byteRate = sampleRate * channels * bytesPerSample;
    final blockAlign = channels * bytesPerSample;

    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);

    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
  }

  static List<String> speechChunks(String input, {int maxLength = 2500}) {
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
