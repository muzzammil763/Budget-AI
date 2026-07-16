import 'dart:convert';

import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    dotenv.testLoad(fileInput: 'DEEPSEEK_API_KEY=test-key');
  });

  test('Flash disables thinking and requests streamed usage', () async {
    final requestBodies = <Map<String, dynamic>>[];
    final provider = ChatCompletionsProvider(
      ChatModelConfig.deepseek,
      dio: _streamingDio(requestBodies),
    );
    await provider.initialize();
    provider.updateModel('deepseek-v4-flash');

    await provider
        .sendMessageStreamWithThinking('Add 500 fuel', enableToolCalls: false)
        .toList();

    expect(requestBodies, hasLength(1));
    expect(requestBodies.single['thinking'], {'type': 'disabled'});
    expect(requestBodies.single.containsKey('reasoning_effort'), isFalse);
    expect(requestBodies.single['stream_options'], {'include_usage': true});
  });

  test(
    'Pro enables high-effort thinking and aggregates DeepSeek cache usage',
    () async {
      final requestBodies = <Map<String, dynamic>>[];
      final provider = ChatCompletionsProvider(
        ChatModelConfig.deepseek,
        dio: _streamingDio(requestBodies),
      );
      await provider.initialize();
      provider.updateModel('deepseek-v4-pro');

      await provider
          .sendMessageStreamWithThinking(
            'Analyze my spending',
            enableToolCalls: false,
          )
          .toList();

      expect(requestBodies, hasLength(1));
      expect(requestBodies.single['thinking'], {'type': 'enabled'});
      expect(requestBodies.single['reasoning_effort'], 'high');
      expect(requestBodies.single['stream_options'], {'include_usage': true});

      final metadata = provider.lastResponseMetadata;
      expect(metadata?['cacheReadTokens'], 120);
      expect(metadata?['cacheMissTokens'], 30);
      expect(metadata?['workflowCacheReadTokens'], 120);
      expect(metadata?['workflowCacheMissTokens'], 30);
      expect(metadata?['workflowTotalTokens'], 160);
    },
  );
}

Dio _streamingDio(List<Map<String, dynamic>> requestBodies) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requestBodies.add(Map<String, dynamic>.from(options.data as Map));
        final usageChunk = jsonEncode({
          'id': 'response-1',
          'model': requestBodies.last['model'],
          'choices': <dynamic>[],
          'usage': {
            'prompt_tokens': 150,
            'completion_tokens': 10,
            'total_tokens': 160,
            'prompt_cache_hit_tokens': 120,
            'prompt_cache_miss_tokens': 30,
          },
        });
        handler.resolve(
          Response<ResponseBody>(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody.fromString(
              'data: $usageChunk\n\ndata: [DONE]\n\n',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/event-stream'],
              },
            ),
          ),
        );
      },
    ),
  );
  return dio;
}
