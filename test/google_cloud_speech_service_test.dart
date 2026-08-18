import 'dart:convert';
import 'dart:io';
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
        await audio.writeAsBytes([1, 2, 3, 4]);
        final result = await service.transcribe(
          audio.path,
          locale: const Locale('ur', 'PK'),
        );

        expect(result.text, 'mera kharcha');
        expect(result.languageCode, 'ur-PK');
        expect(request?['action'], 'transcribe');
        expect(request?['languageCode'], 'ur-PK');
        expect(request?['alternativeLanguageCodes'], contains('en-US'));
        expect(request?['audioContent'], 'AQIDBA==');
        expect(request?['audioEncoding'], 'LINEAR16');
        expect(request?['sampleRateHertz'], 16000);
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
