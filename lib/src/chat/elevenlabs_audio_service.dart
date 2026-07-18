import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:dio/dio.dart';

class ElevenLabsVoice {
  const ElevenLabsVoice({
    required this.id,
    required this.name,
    required this.category,
    this.gender,
    this.accent,
    this.description,
    this.previewUrl,
  });

  final String id;
  final String name;
  final String category;
  final String? gender;
  final String? accent;
  final String? description;
  final String? previewUrl;

  String get detail {
    final parts = <String>[
      if (gender?.isNotEmpty == true) gender!,
      if (accent?.isNotEmpty == true) accent!,
      if (category.isNotEmpty) category,
    ];
    return parts.join(' · ');
  }
}

class ElevenLabsException implements Exception {
  const ElevenLabsException({
    required this.message,
    this.statusCode,
    this.code,
  });

  final String message;
  final int? statusCode;
  final String? code;

  bool get isPaymentRequired =>
      statusCode == 402 || code == 'insufficient_credits';

  @override
  String toString() => message;
}

class ElevenLabsAudioService {
  ElevenLabsAudioService({Dio? dio}) : _dio = dio ?? Dio();

  static const String _baseUrl = 'https://api.elevenlabs.io';
  static const String speechModel = 'eleven_flash_v2_5';
  static const String outputFormat = 'mp3_44100_128';

  final Dio _dio;

  Options _options({ResponseType? responseType}) {
    final key = AppConstants.elevenLabsApiKey;
    if (key.isEmpty) {
      throw StateError('ELEVENLABS_API_KEY is not configured for this build.');
    }
    return Options(
      responseType: responseType,
      headers: {'xi-api-key': key, 'Accept': 'application/json'},
    );
  }

  Future<List<ElevenLabsVoice>> listVoices() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl/v2/voices',
      queryParameters: {
        'page_size': 100,
        'sort': 'name',
        'sort_direction': 'asc',
        'include_total_count': false,
      },
      options: _options(),
    );
    final items = response.data?['voices'];
    if (items is! List) return const [];

    final voices = <ElevenLabsVoice>[];
    for (final item in items) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final id = json['voice_id']?.toString().trim() ?? '';
      final name = json['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final labels = json['labels'] is Map
          ? Map<String, dynamic>.from(json['labels'] as Map)
          : const <String, dynamic>{};
      voices.add(
        ElevenLabsVoice(
          id: id,
          name: name,
          category: json['category']?.toString().trim() ?? '',
          gender: labels['gender']?.toString().trim(),
          accent: labels['accent']?.toString().trim(),
          description: json['description']?.toString().trim(),
          previewUrl: json['preview_url']?.toString().trim(),
        ),
      );
    }
    voices.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return voices;
  }

  Future<Uint8List> synthesize(String text, {required String voiceId}) async {
    try {
      final response = await _dio.post<List<int>>(
        '$_baseUrl/v1/text-to-speech/$voiceId',
        queryParameters: {'output_format': outputFormat},
        data: {'text': text, 'model_id': speechModel},
        options: _options(responseType: ResponseType.bytes).copyWith(
          headers: {
            'xi-api-key': AppConstants.elevenLabsApiKey,
            'Accept': 'audio/mpeg',
            'Content-Type': 'application/json',
          },
        ),
      );
      final audio = Uint8List.fromList(response.data ?? const <int>[]);
      if (audio.length < 100) {
        throw const ElevenLabsException(
          message: 'ElevenLabs returned an invalid audio response.',
        );
      }
      return audio;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  ElevenLabsException _mapDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final detail = _decodeErrorDetail(error.response?.data);
    final code = detail?['code']?.toString();
    final apiMessage = detail?['message']?.toString().trim();
    if (statusCode == 402 || code == 'insufficient_credits') {
      return ElevenLabsException(
        statusCode: statusCode,
        code: code,
        message: apiMessage?.isNotEmpty == true
            ? apiMessage!
            : 'ElevenLabs has insufficient credits, or this API key has reached its credit limit.',
      );
    }
    return ElevenLabsException(
      statusCode: statusCode,
      code: code,
      message: apiMessage?.isNotEmpty == true
          ? apiMessage!
          : 'ElevenLabs request failed${statusCode == null ? '' : ' (HTTP $statusCode)'}.',
    );
  }

  Map<String, dynamic>? _decodeErrorDetail(dynamic data) {
    dynamic decoded = data;
    try {
      if (data is List<int>) decoded = jsonDecode(utf8.decode(data));
      if (data is String) decoded = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final root = Map<String, dynamic>.from(decoded);
    final detail = root['detail'];
    if (detail is Map) return Map<String, dynamic>.from(detail);
    if (detail is String) return {'message': detail};
    return root;
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
