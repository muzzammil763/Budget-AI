import 'dart:convert';

import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/tools/tools.dart';
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
    dotenv.testLoad(fileInput: 'OPENAI_API_KEY=test-key');
  });

  test(
    'OpenAI Responses API streams Luna with concise low reasoning',
    () async {
      final requests = <RequestOptions>[];
      final provider = ResponsesProvider(
        ChatModelConfig.openAI,
        dio: _streamingDio(requests),
      );
      await provider.initialize();
      provider.updateModel(AIModels.defaultModelId);

      final chunks = await provider
          .sendMessageStreamWithThinking(
            'Summarize my spending',
            enableToolCalls: false,
          )
          .toList();

      expect(requests, hasLength(1));
      expect(requests.single.path, 'https://api.openai.com/v1/responses');
      final body = Map<String, dynamic>.from(requests.single.data as Map);
      expect(body['model'], 'gpt-5.6-luna');
      expect(body['reasoning'], {'effort': 'low'});
      expect(body['text'], {'verbosity': 'low'});
      expect(body['stream'], isTrue);
      expect(chunks.map((chunk) => chunk.content).join(), 'Done.');
      expect(provider.lastResponseMetadata?['promptTokens'], 20);
      expect(provider.lastResponseMetadata?['completionTokens'], 4);
    },
  );

  test('GPT-4.1 request omits GPT-5-only controls', () async {
    final requests = <RequestOptions>[];
    final provider = ResponsesProvider(
      ChatModelConfig.openAI,
      dio: _streamingDio(requests),
    );
    await provider.initialize();
    provider.updateModel('gpt-4.1');

    await provider
        .sendMessageStreamWithThinking('Hello', enableToolCalls: false)
        .drain<void>();

    final body = Map<String, dynamic>.from(requests.single.data as Map);
    expect(body.containsKey('reasoning'), isFalse);
    expect(body.containsKey('text'), isFalse);
  });

  test('Responses tool output is replayed before the final answer', () async {
    final requests = <RequestOptions>[];
    final provider = ResponsesProvider(
      ChatModelConfig.openAI,
      dio: _toolStreamingDio(requests),
      toolRegistry: _TestToolRegistry(),
    );
    await provider.initialize();

    final chunks = await provider
        .sendMessageStreamWithThinking('Save this', enableToolCalls: true)
        .toList();

    expect(requests, hasLength(2));
    final secondInput = (requests[1].data as Map)['input'] as List;
    expect(
      secondInput.whereType<Map>().any(
        (item) =>
            item['type'] == 'function_call_output' &&
            item['call_id'] == 'call_1',
      ),
      isTrue,
    );
    expect(chunks.map((chunk) => chunk.content).join(), 'Saved.');
    expect(chunks.any((chunk) => chunk.isToolCallComplete), isTrue);
  });
}

Dio _streamingDio(List<RequestOptions> requests) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        final delta = jsonEncode({
          'type': 'response.output_text.delta',
          'delta': 'Done.',
        });
        final completed = jsonEncode({
          'type': 'response.completed',
          'response': {
            'id': 'resp_1',
            'model': (options.data as Map)['model'],
            'output': const [],
            'usage': {
              'input_tokens': 20,
              'output_tokens': 4,
              'total_tokens': 24,
            },
          },
        });
        handler.resolve(
          Response<ResponseBody>(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody.fromString(
              'data: $delta\n\ndata: $completed\n\ndata: [DONE]\n\n',
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

Dio _toolStreamingDio(List<RequestOptions> requests) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        final isFirstRound = requests.length == 1;
        final events = isFirstRound
            ? [
                {
                  'type': 'response.output_item.added',
                  'output_index': 0,
                  'item': {
                    'id': 'fc_1',
                    'type': 'function_call',
                    'call_id': 'call_1',
                    'name': 'test_echo',
                    'arguments': '',
                  },
                },
                {
                  'type': 'response.function_call_arguments.done',
                  'item_id': 'fc_1',
                  'arguments': '{"value":"saved"}',
                },
                {
                  'type': 'response.completed',
                  'response': {
                    'id': 'resp_tools',
                    'model': 'gpt-5.6-luna',
                    'output': [
                      {
                        'id': 'fc_1',
                        'type': 'function_call',
                        'call_id': 'call_1',
                        'name': 'test_echo',
                        'arguments': '{"value":"saved"}',
                      },
                    ],
                    'usage': {
                      'input_tokens': 10,
                      'output_tokens': 4,
                      'total_tokens': 14,
                    },
                  },
                },
              ]
            : [
                {'type': 'response.output_text.delta', 'delta': 'Saved.'},
                {
                  'type': 'response.completed',
                  'response': {
                    'id': 'resp_final',
                    'model': 'gpt-5.6-luna',
                    'output': [
                      {
                        'id': 'msg_1',
                        'type': 'message',
                        'role': 'assistant',
                        'content': [
                          {'type': 'output_text', 'text': 'Saved.'},
                        ],
                      },
                    ],
                    'usage': {
                      'input_tokens': 18,
                      'output_tokens': 3,
                      'total_tokens': 21,
                    },
                  },
                },
              ];
        final body = events
            .map((event) => 'data: ${jsonEncode(event)}')
            .join('\n\n');
        handler.resolve(
          Response<ResponseBody>(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody.fromString(
              '$body\n\ndata: [DONE]\n\n',
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

class _TestToolRegistry extends ToolRegistry {
  @override
  List<ToolDefinition> getAvailableTools() {
    return [
      ToolDefinition(
        name: 'test_echo',
        description: 'Echo test data.',
        parameters: const {
          'type': 'object',
          'properties': {
            'value': {'type': 'string'},
          },
          'required': ['value'],
        },
        handler: (arguments) async => {'ok': true, ...arguments},
      ),
    ];
  }
}
