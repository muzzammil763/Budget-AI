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
      configureTextToSpeech: false,
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
      expect(request?['languageCode'], 'ur-PK');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('device TTS selects Urdu script and English for Roman Urdu', () {
    const languages = {'ur-PK', 'en-US'};
    expect(
      selectDeviceTtsLanguage(
        text: 'آج کا خرچہ',
        requestedLanguageCode: 'ur-PK',
        availableLanguages: languages,
      ),
      'ur-PK',
    );
    expect(
      selectDeviceTtsLanguage(
        text: 'Aaj ka kharcha',
        requestedLanguageCode: 'ur-PK',
        availableLanguages: languages,
      ),
      'en-US',
    );
  });

  test('device TTS falls back to an installed matching locale', () {
    expect(
      selectDeviceTtsLanguage(
        text: 'Hello',
        requestedLanguageCode: 'en-GB',
        availableLanguages: const {'en-AU', 'ur-PK'},
      ),
      'en-AU',
    );
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
