import 'dart:convert';

import 'package:budget_ai/src/chat/active_model_resolver.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/tools/tools.dart';
import 'package:dio/dio.dart';
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
  });

  test(
    'OpenAI Responses API streams default model with concise low reasoning',
    () async {
      final requests = <RequestOptions>[];
      final provider = ResponsesProvider(
        ChatModelConfig.openAI,
        dio: _streamingDio(requests),
        accessTokenProvider: () => 'test-user-jwt',
      );
      await provider.initialize();
      provider.updateModel(ActiveModelResolver.defaultModelId);

      final chunks = await provider
          .sendMessageStreamWithThinking(
            'Summarize my spending',
            enableToolCalls: false,
          )
          .toList();

      expect(requests, hasLength(1));
      expect(
        requests.single.path,
        'https://bzxsgpsacouvhxepfuca.supabase.co/functions/v1/openai-responses',
      );
      expect(requests.single.headers['Authorization'], 'Bearer test-user-jwt');
      expect(requests.single.headers['apikey'], startsWith('sb_publishable_'));
      expect(requests.single.headers.containsKey('x-region'), isFalse);
      final body = Map<String, dynamic>.from(requests.single.data as Map);
      expect(body['model'], ActiveModelResolver.defaultModelId);
      expect(body['reasoning'], {'effort': 'low'});
      expect(body['text'], {'verbosity': 'low'});
      expect(body['stream'], isTrue);
      expect(body.containsKey('service_tier'), isFalse);
      expect(body['client_turn_id'], isNotEmpty);
      final instructions = body['instructions'] as String;
      expect(instructions.length, lessThan(3000));
      expect(instructions, isNot(contains('Current finance snapshot')));
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
      accessTokenProvider: () => 'test-user-jwt',
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

  test('Fast responses applies to utility requests', () async {
    final requests = <RequestOptions>[];
    final provider = ResponsesProvider(
      ChatModelConfig.openAI,
      dio: _jsonDio(requests),
      accessTokenProvider: () => 'test-user-jwt',
      fastResponsesProvider: () => true,
    );
    await provider.initialize();

    final result = await provider.runUtilityPrompt('Name this chat');

    expect(result, 'Fast title');
    expect((requests.single.data as Map)['service_tier'], 'fast');
  });

  test('Responses tool output is replayed before the final answer', () async {
    final requests = <RequestOptions>[];
    final provider = ResponsesProvider(
      ChatModelConfig.openAI,
      dio: _toolStreamingDio(requests),
      toolRegistry: _TestToolRegistry(),
      accessTokenProvider: () => 'test-user-jwt',
      fastResponsesProvider: () => true,
    );
    await provider.initialize();

    final chunks = await provider
        .sendMessageStreamWithThinking('Save this', enableToolCalls: true)
        .toList();

    expect(requests, hasLength(2));
    expect(
      requests.every(
        (request) => (request.data as Map)['service_tier'] == 'fast',
      ),
      isTrue,
    );
    expect(
      (requests[0].data as Map)['client_turn_id'],
      isNot((requests[1].data as Map)['client_turn_id']),
    );
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

  test(
    'completed turns drop internal payloads and keep recent dialogue',
    () async {
      final requests = <RequestOptions>[];
      final provider = ResponsesProvider(
        ChatModelConfig.openAI,
        dio: _streamingDio(requests),
        accessTokenProvider: () => 'test-user-jwt',
      );
      await provider.initialize();

      final state = <Map<String, dynamic>>[];
      for (var index = 0; index < 12; index++) {
        state.add({'role': 'user', 'content': 'Old user $index'});
        state.add({
          'type': 'reasoning',
          'id': 'reasoning_$index',
          'summary': const [],
        });
        state.add({
          'type': 'function_call',
          'call_id': 'call_$index',
          'name': 'finance_list',
          'arguments': '{}',
        });
        state.add({
          'type': 'function_call_output',
          'call_id': 'call_$index',
          'output': '{"large":"internal payload $index"}',
        });
        state.add({'role': 'assistant', 'content': 'Old answer $index'});
      }
      provider.loadConversationState(state);

      await provider
          .sendMessageStreamWithThinking(
            'Current question',
            enableToolCalls: false,
          )
          .drain<void>();

      final input = (requests.single.data as Map)['input'] as List;
      expect(input, hasLength(17));
      expect((input.first as Map)['content'], 'Old user 4');
      expect((input.last as Map)['content'], 'Current question');
      expect(
        input.whereType<Map>().any(
          (item) =>
              item['type'] == 'reasoning' ||
              item['type'] == 'function_call' ||
              item['type'] == 'function_call_output',
        ),
        isFalse,
      );
    },
  );
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

Dio _jsonDio(List<RequestOptions> requests) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {'output_text': 'Fast title'},
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
