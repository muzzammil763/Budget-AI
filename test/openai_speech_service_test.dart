import 'dart:async';
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
      expect(request?['audioContent'], base64Encode([1, 2, 3, 4]));
      expect(request?['fileName'], 'voice.wav');
      expect(request?['action'], 'transcribe');
      expect(request?['languageCode'], 'ur-PK');
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test(
    'cancelled transcription finishes immediately and cannot replace a new result',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'budget_voice_cancel_',
      );
      final audio = File('${directory.path}/voice.wav');
      final started = Completer<void>();
      final oldResponse = Completer<Map<String, dynamic>>();
      var calls = 0;
      final service = OpenAiSpeechService(
        invoke: (_) {
          if (calls++ == 0) {
            started.complete();
            return oldResponse.future;
          }
          return Future.value({'transcript': 'new recording'});
        },
      );
      try {
        await audio.writeAsBytes([1, 2, 3, 4]);
        final old = service.transcribe(audio.path, locale: const Locale('en'));
        final cancelled = expectLater(
          old,
          throwsA(isA<SpeechTranscriptionCancelled>()),
        );
        await started.future;
        service.cancelTranscription();
        await cancelled;
        final current = await service.transcribe(
          audio.path,
          locale: const Locale('en'),
        );
        expect(current.text, 'new recording');
        oldResponse.completeError(StateError('late failure must be ignored'));
        await Future<void>.delayed(Duration.zero);
      } finally {
        service.cancelTranscription();
        await directory.delete(recursive: true);
      }
    },
  );
}
