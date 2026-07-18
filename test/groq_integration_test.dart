import 'dart:convert';

import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/elevenlabs_audio_service.dart';
import 'package:budget_ai/src/chat/groq_audio_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await ModelSettingsService.instance.initialize();
    dotenv.testLoad(
      fileInput:
          'DEEPSEEK_API_KEY=test-deepseek\nGROQ_API_KEY=test-groq\nELEVENLABS_API_KEY=test-elevenlabs',
    );
  });

  test('DeepSeek remains the only chat model family', () {
    expect(ModelSettingsService.instance.current, AIModels.defaultModelId);
    expect(AIModels.getModelById('llama-3.3-70b-versatile'), isNull);
  });

  test('speech provider defaults to Groq and persists ElevenLabs', () async {
    final settings = ModelSettingsService.instance;
    expect(
      settings.currentSpeechProvider,
      ModelSettingsService.groqSpeechProviderId,
    );

    await settings.setSpeechProvider(
      ModelSettingsService.elevenLabsSpeechProviderId,
    );
    await settings.initialize();

    expect(
      settings.currentSpeechProvider,
      ModelSettingsService.elevenLabsSpeechProviderId,
    );
  });

  test('Orpheus speech chunks respect its 200 character limit', () {
    final chunks = GroqAudioService.speechChunks(
      List.filled(80, 'Budget AI gives a clear answer.').join(' '),
    );

    expect(chunks, isNotEmpty);
    expect(chunks.every((chunk) => chunk.length <= 200), isTrue);
    expect(chunks.join(' '), contains('Budget AI gives a clear answer.'));
  });

  test('Groq response voice defaults to Troy and persists selection', () async {
    final settings = ModelSettingsService.instance;
    expect(settings.currentGroqVoice.id, 'troy');

    await settings.setGroqVoice('hannah');
    await settings.initialize();

    expect(settings.currentGroqVoice.id, 'hannah');
    expect(settings.currentGroqVoice.gender, 'Female');
  });

  test('ElevenLabs voice and response chunks persist safely', () async {
    final settings = ModelSettingsService.instance;
    await settings.setElevenLabsVoice(id: 'voice-123', name: 'Test Voice');
    await settings.initialize();

    expect(settings.elevenLabsVoiceId.value, 'voice-123');
    expect(settings.elevenLabsVoiceName.value, 'Test Voice');
    expect(
      ElevenLabsAudioService.speechChunks(
        List.filled(2600, 'A').join(),
      ).every((chunk) => chunk.length <= 2500),
      isTrue,
    );
  });

  test('ElevenLabs 402 exposes the API credit message', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<List<int>>(
                requestOptions: options,
                statusCode: 402,
                data: utf8.encode(
                  jsonEncode({
                    'detail': {
                      'type': 'payment_required',
                      'code': 'insufficient_credits',
                      'message': 'This API key has insufficient credits.',
                    },
                  }),
                ),
              ),
            ),
          );
        },
      ),
    );
    final service = ElevenLabsAudioService(dio: dio);

    await expectLater(
      service.synthesize('Hello', voiceId: 'voice-123'),
      throwsA(
        isA<ElevenLabsException>()
            .having((error) => error.statusCode, 'statusCode', 402)
            .having(
              (error) => error.message,
              'message',
              contains('insufficient credits'),
            ),
      ),
    );
  });
}
