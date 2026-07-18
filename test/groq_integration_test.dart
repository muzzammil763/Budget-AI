import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/elevenlabs_audio_service.dart';
import 'package:budget_ai/src/chat/gemini_audio_service.dart';
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
          'DEEPSEEK_API_KEY=test-deepseek\nGROQ_API_KEY=test-groq\nELEVENLABS_API_KEY=test-elevenlabs\nGEMINI_API_KEY=test-gemini',
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

  test('Gemini audio settings persist independently', () async {
    final settings = ModelSettingsService.instance;
    await settings.setVoiceInputProvider(
      ModelSettingsService.geminiVoiceInputProviderId,
    );
    await settings.setSpeechProvider(
      ModelSettingsService.geminiSpeechProviderId,
    );
    await settings.setGeminiVoice('Aoede');
    await settings.initialize();

    expect(
      settings.currentVoiceInputProvider,
      ModelSettingsService.geminiVoiceInputProviderId,
    );
    expect(
      settings.currentSpeechProvider,
      ModelSettingsService.geminiSpeechProviderId,
    );
    expect(settings.currentGeminiVoice.id, 'Aoede');
    expect(ModelSettingsService.geminiVoices, hasLength(30));
  });

  test('Gemini TTS converts returned PCM into a WAV file', () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'inlineData': {
                            'mimeType': 'audio/L16;codec=pcm;rate=24000',
                            'data': base64Encode(List<int>.filled(96, 0)),
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final service = GeminiAudioService(dio: dio);
    final wave = await service.synthesize('Hello', voiceName: 'Kore');

    expect(utf8.decode(wave.sublist(0, 4)), 'RIFF');
    expect(utf8.decode(wave.sublist(8, 12)), 'WAVE');
    expect(requests.single.path, contains('gemini-3.1-flash-tts-preview'));
    expect(
      (requests.single.data
          as Map)['generationConfig']['speechConfig']['voiceConfig']['prebuiltVoiceConfig']['voiceName'],
      'Kore',
    );
  });

  test(
    'Gemini transcription sends inline WAV audio and extracts text',
    () async {
      RequestOptions? capturedRequest;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'Add five hundred for groceries'},
                        ],
                      },
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      final audioFile = File(
        '${Directory.systemTemp.path}/gemini_transcription_test.wav',
      );
      await audioFile.writeAsBytes(List<int>.filled(64, 0));
      final service = GeminiAudioService(dio: dio);

      try {
        expect(
          await service.transcribe(audioFile.path),
          'Add five hundred for groceries',
        );
        expect(capturedRequest?.path, contains('gemini-3.5-flash'));
        final parts =
            ((capturedRequest?.data as Map)['contents'] as List).first['parts']
                as List;
        expect(parts.first['inlineData']['mimeType'], 'audio/wav');
        expect(parts.first['inlineData']['data'], isNotEmpty);
      } finally {
        if (await audioFile.exists()) await audioFile.delete();
      }
    },
  );
}
