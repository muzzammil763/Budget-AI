import 'dart:io';

import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/openai_audio_service.dart';
import 'package:budget_ai/src/chat/openai_voice.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
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
    dotenv.testLoad(fileInput: 'OPENAI_API_KEY=test-key');
    await ModelSettingsService.instance.initialize();
  });

  test('OpenAI model picker defaults to GPT-5.6 Luna', () {
    expect(ModelSettingsService.instance.current, 'gpt-5.6-luna');
    expect(AIModels.openAIModels, hasLength(9));
  });

  test('all OpenAI voices are available and selection persists', () async {
    final settings = ModelSettingsService.instance;
    expect(OpenAIVoices.all, hasLength(13));
    expect(settings.currentVoice, 'marin');
    await settings.setVoice('cedar');
    await settings.initialize();
    expect(settings.currentVoice, 'cedar');
    expect(OpenAIVoices.byId('cedar')?.recommended, isTrue);
  });

  test('every OpenAI voice has a bundled preview asset', () async {
    for (final voice in OpenAIVoices.all) {
      final data = await rootBundle.load('assets/${voice.previewAsset}');
      expect(
        data.lengthInBytes,
        greaterThan(1000),
        reason: '${voice.name} preview should contain MP3 audio',
      );
    }
  });

  test('transcription and speech use OpenAI audio endpoints', () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.path.endsWith('/audio/transcriptions')) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {'text': 'Add five hundred for groceries'},
              ),
            );
          } else {
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                statusCode: 200,
                data: List<int>.filled(128, 1),
              ),
            );
          }
        },
      ),
    );
    final file = File('${Directory.systemTemp.path}/openai_audio_test.wav');
    await file.writeAsBytes(List<int>.filled(64, 0));
    final service = OpenAIAudioService(dio: dio);

    try {
      expect(
        await service.transcribe(file.path),
        'Add five hundred for groceries',
      );
      await ModelSettingsService.instance.setVoice('cedar');
      expect(await service.synthesize('Recorded.'), hasLength(128));
      expect(requests[0].path, endsWith('/audio/transcriptions'));
      final transcription = requests[0].data as FormData;
      expect(
        Map<String, String>.fromEntries(transcription.fields)['model'],
        'gpt-4o-transcribe',
      );
      expect(requests[1].path, endsWith('/audio/speech'));
      expect((requests[1].data as Map)['model'], 'gpt-4o-mini-tts');
      expect((requests[1].data as Map)['voice'], 'cedar');
    } finally {
      service.dispose();
      if (await file.exists()) await file.delete();
    }
  });

  test('speech chunks stay within the API-safe input size', () {
    final chunks = OpenAIAudioService.speechChunks(
      List<String>.filled(500, 'Budget AI gives a clear answer.').join(' '),
    );
    expect(chunks, isNotEmpty);
    expect(chunks.every((chunk) => chunk.length <= 2000), isTrue);
  });
}
