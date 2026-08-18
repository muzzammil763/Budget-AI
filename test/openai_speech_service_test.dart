import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:budget_ai/src/speech/openai_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('transcription sends WAV audio to the OpenAI proxy', () async {
    Map<String, dynamic>? request;
    final service = OpenAiSpeechService(
      invoke: (body) async {
        request = body;
        return {'transcript': 'mera kharcha', 'languageCode': 'ur-PK'};
      },
    );
    final directory = await Directory.systemTemp.createTemp(
      'budget_ai_openai_speech_',
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
      expect(request?['audioContent'], base64Encode([1, 2, 3, 4]));
      expect(request?['fileName'], 'voice.wav');
      expect(request?['languageCode'], 'ur-PK');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('ElevenLabs speech chunks stay within the proxy limit', () {
    final chunks = splitTextForSpeech(
      List.filled(1000, 'Roman Urdu response').join(' '),
    );
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => chunk.length <= 1200), isTrue);
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
