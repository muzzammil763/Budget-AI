import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:budget_ai/src/speech/google_cloud_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'transcription sends locale candidates and returns detected language',
    () async {
      Map<String, dynamic>? request;
      final service = GoogleCloudSpeechService(
        invoke: (body) async {
          request = body;
          return {'transcript': 'mera kharcha', 'languageCode': 'ur-PK'};
        },
      );
      final directory = await Directory.systemTemp.createTemp(
        'budget_ai_google_speech_',
      );
      final audio = File('${directory.path}/voice.wav');
      try {
        final wav = _wavHeader(sampleRate: 48000, channels: 1);
        await audio.writeAsBytes(wav);
        final result = await service.transcribe(
          audio.path,
          locale: const Locale('ur', 'PK'),
        );

        expect(result.text, 'mera kharcha');
        expect(result.languageCode, 'ur-PK');
        expect(request?['action'], 'transcribe');
        expect(request?['languageCode'], 'ur-PK');
        expect(request?['alternativeLanguageCodes'], contains('en-US'));
        expect(request?['audioContent'], base64Encode(wav));
        expect(request?['audioEncoding'], 'LINEAR16');
        expect(request?['sampleRateHertz'], 48000);
        expect(request?['audioChannelCount'], 1);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('speech text chunks stay inside Google UTF-8 request limits', () {
    final chunks = splitTextForGoogleSpeech(
      List.filled(3000, 'سلام').join(' '),
      maxUtf8Bytes: 4200,
    );

    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => utf8.encode(chunk).length <= 4200), isTrue);
  });

  test('WAV metadata reads the recorder output format from its header', () {
    final metadata = googleWavMetadata(
      _wavHeader(sampleRate: 44100, channels: 2),
    );

    expect(metadata?.sampleRateHertz, 44100);
    expect(metadata?.audioChannelCount, 2);
    expect(googleWavMetadata(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('assistant tap is disabled until the final response is complete', () {
    expect(
      assistantSpeechTapEnabled(
        isUser: false,
        hasText: true,
        responseInProgress: true,
        isStreamingMessage: true,
        isFinalInTurn: true,
      ),
      isFalse,
    );
    expect(
      assistantSpeechTapEnabled(
        isUser: false,
        hasText: true,
        responseInProgress: false,
        isStreamingMessage: false,
        isFinalInTurn: true,
      ),
      isTrue,
    );
  });
}

Uint8List _wavHeader({required int sampleRate, required int channels}) {
  final bytes = Uint8List(44);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, 36, Endian.little);
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  bytes.setRange(12, 16, ascii.encode('fmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, 0, Endian.little);
  return bytes;
}
