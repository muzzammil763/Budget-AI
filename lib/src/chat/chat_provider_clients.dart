part of 'chat_provider.dart';

/// OpenAI Responses API implementation with streaming and local function tools.
class ResponsesProvider extends BaseChatProvider {
  @override
  String get _baseUrl => AppConstants.openAIResponsesEndpoint;

  ResponsesProvider(
    super.config, {
    super.dio,
    super.toolRegistry,
    super.accessTokenProvider,
    super.fastResponsesProvider,
  }) : super(defaultSelectedModel: ActiveModelResolver.defaultModelId);

  @override
  Stream<String> sendMessageStream(String message) async* {
    await for (final chunk in sendMessageStreamWithThinking(
      message,
      enableToolCalls: false,
    )) {
      if (chunk.content.isNotEmpty) yield chunk.content;
    }
  }

  @override
  Stream<ChatStreamChunk> sendMessageStreamWithThinking(
    String message, {
    bool enableToolCalls = true,
  }) async* {
    _refreshSessionCredential();
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw _providerException(
        _providerName,
        'Sign in again to continue using $_providerName.',
      );
    }

    _chatHistory.add({'role': 'user', 'content': message});
    final tools = enableToolCalls ? _toolRegistry.getAvailableTools() : [];
    final hasTools = tools.isNotEmpty;

    debugPrint('[$_providerName] Sending authenticated request to $_baseUrl');
    debugPrint('[$_providerName] Model: $_selectedModel');
    debugPrint('[$_providerName] Tool calls enabled: $enableToolCalls');

    _cancelToken = CancelToken();
    _lastResponseMetadata = null;

    try {
      var shouldContinue = false;
      final toolCallTracker = _ToolCallTracker(
        maxRounds: 25,
        maxTotalCalls: 60,
      );
      var duplicateToolCallRounds = 0;

      do {
        shouldContinue = false;
        toolCallTracker.beginRound();
        if (toolCallTracker.isBudgetExhausted) {
          yield ChatStreamChunk(
            content:
                'I stopped because the tool-call safety limit was reached.',
          );
          break;
        }

        var roundResponse = '';
        var finalResponsePayload = <String, dynamic>{};
        final activeToolCalls = <String, ToolCallChunk>{};

        final requestData = <String, dynamic>{
          'model': _selectedModel,
          'top_p': 1.0,
          ..._responseModelOptions,
          ..._responseServiceTierOptions,
          'instructions': await _buildChatSystemPrompt(),
          'input': _sanitizeConversationStateForApi(_chatHistory),
          'stream': true,
          'client_turn_id': const Uuid().v4(),
        };
        if (hasTools) {
          requestData['tools'] = tools
              .map((tool) => tool.toResponsesJson())
              .toList();
          requestData['tool_choice'] = 'auto';
          requestData['parallel_tool_calls'] = false;
        }

        final requestStopwatch = Stopwatch()..start();
        final response = await _postStreamWithApiKeyFallback(
          dio: _dio,
          url: _baseUrl,
          apiKeys: _apiKeys,
          providerName: _providerName,
          data: requestData,
          cancelToken: _cancelToken,
          additionalHeaders: _additionalRequestHeaders,
          onKeySelected: (apiKey) => _apiKey = apiKey,
        );
        if (kDebugMode) {
          debugPrint(
            '[$_providerName] Proxy headers received in '
            '${requestStopwatch.elapsedMilliseconds}ms '
            '(region: ${response.headers.value('x-budget-ai-edge-region') ?? response.headers.value('x-sb-edge-region') ?? 'unknown'}, '
            'quota: ${response.headers.value('x-budget-ai-quota-ms') ?? '?'}ms, '
            'OpenAI headers: ${response.headers.value('x-budget-ai-openai-headers-ms') ?? '?'}ms)',
          );
        }

        final eventLines = utf8.decoder
            .bind(response.data!.stream)
            .transform(const LineSplitter());
        var firstEventLogged = false;
        await for (final line in eventLines) {
          if (_cancelToken?.isCancelled ?? false) throw CancelledException();
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data.isEmpty || data == '[DONE]') continue;
          if (!firstEventLogged && kDebugMode) {
            firstEventLogged = true;
            debugPrint(
              '[$_providerName] First streamed event received in '
              '${requestStopwatch.elapsedMilliseconds}ms',
            );
          }

          final decoded = jsonDecode(data);
          if (decoded is! Map) continue;
          final event = Map<String, dynamic>.from(decoded);
          final eventType = event['type']?.toString() ?? '';

          switch (eventType) {
            case 'response.output_text.delta':
              final delta = event['delta']?.toString() ?? '';
              if (delta.isNotEmpty) {
                roundResponse += delta;
                yield ChatStreamChunk(content: delta);
              }
            case 'response.reasoning_summary_text.delta':
              final delta = event['delta']?.toString() ?? '';
              if (delta.isNotEmpty) {
                yield ChatStreamChunk(content: '', thinking: delta);
              }
            case 'response.output_item.added':
              final item = event['item'];
              if (item is Map && item['type'] == 'function_call') {
                final key = _responseToolKey(event, item);
                final toolCall = ToolCallChunk(
                  id: item['call_id']?.toString() ?? key,
                  name: item['name']?.toString(),
                  rawArguments: item['arguments']?.toString() ?? '',
                  status: ToolCallStatus.creating,
                );
                activeToolCalls[key] = toolCall;
                yield ChatStreamChunk(content: '', toolCall: toolCall);
              }
            case 'response.function_call_arguments.delta':
              final key = _responseToolKey(event, null);
              final existing = activeToolCalls[key];
              if (existing != null) {
                final raw =
                    '${existing.rawArguments ?? ''}${event['delta']?.toString() ?? ''}';
                final updated = existing.copyWith(
                  rawArguments: raw,
                  arguments: _tryParseToolArguments(raw),
                  status: ToolCallStatus.calling,
                );
                activeToolCalls[key] = updated;
                yield ChatStreamChunk(content: '', toolCall: updated);
              }
            case 'response.function_call_arguments.done':
              final key = _responseToolKey(event, null);
              final existing = activeToolCalls[key];
              if (existing != null) {
                final raw =
                    event['arguments']?.toString() ??
                    existing.rawArguments ??
                    '';
                activeToolCalls[key] = existing.copyWith(
                  rawArguments: raw,
                  arguments: _tryParseToolArguments(raw),
                  status: ToolCallStatus.calling,
                );
              }
            case 'response.completed':
              final rawResponse = event['response'];
              if (rawResponse is Map) {
                finalResponsePayload = Map<String, dynamic>.from(rawResponse);
                _mergeCompletedToolCalls(finalResponsePayload, activeToolCalls);
                final metadata = _extractResponseMetadata(
                  finalResponsePayload,
                  requestedModel: _selectedModel,
                  providerName: _providerName,
                );
                _lastResponseMetadata = mergeResponseMetadata(
                  _lastResponseMetadata ?? const <String, dynamic>{},
                  metadata,
                );
                yield ChatStreamChunk(
                  content: '',
                  responseMetadata: metadata,
                  isThinkingComplete: true,
                );
              }
            case 'response.failed':
              final responseError = event['response'] is Map
                  ? (event['response'] as Map)['error']
                  : event['error'];
              throw _providerException(
                _providerName,
                responseError?.toString() ?? 'OpenAI response failed.',
              );
            case 'error':
              throw _providerException(
                _providerName,
                event['message']?.toString() ?? 'OpenAI streaming error.',
              );
          }
        }

        final responseOutput = finalResponsePayload['output'];
        final hasResponseOutputItems = responseOutput is List;
        if (hasResponseOutputItems) {
          _chatHistory.addAll(
            responseOutput.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          );
        } else if (roundResponse.isNotEmpty) {
          _chatHistory.add({'role': 'assistant', 'content': roundResponse});
        }

        final toolCalls = activeToolCalls.values
            .where((call) => call.name?.trim().isNotEmpty == true)
            .toList();
        shouldContinue = toolCalls.isNotEmpty;

        for (final toolCall in toolCalls) {
          final rawArguments = toolCall.rawArguments ?? '';
          final arguments =
              toolCall.arguments ?? _tryParseToolArguments(rawArguments);
          if (!hasResponseOutputItems) {
            _chatHistory.add({
              'type': 'function_call',
              'call_id': toolCall.id,
              'name': toolCall.name,
              'arguments': rawArguments,
            });
          }

          dynamic result;
          var stopAfterDuplicateLoop = false;
          if (arguments == null) {
            result = _malformedToolCallResult(toolCall);
          } else if (toolCallTracker.isLoop(toolCall.name!, arguments)) {
            duplicateToolCallRounds++;
            result =
                toolCallTracker.latestResult(toolCall.name!, arguments) ??
                {
                  'ok': true,
                  'note':
                      'Already completed successfully. Give the final response now.',
                };
            stopAfterDuplicateLoop = duplicateToolCallRounds > 1;
          } else {
            toolCallTracker.recordCall(toolCall.name!, arguments);
            await for (final chunk in _executeToolAndStreamChunks(
              toolRegistry: _toolRegistry,
              toolCall: toolCall,
              arguments: arguments,
              isCancelled: () => _cancelToken?.isCancelled ?? false,
              onResult: (value) => result = value,
            )) {
              yield chunk;
            }
            toolCallTracker.recordResult(toolCall.name!, arguments, result);
          }

          _chatHistory.add({
            'type': 'function_call_output',
            'call_id': toolCall.id,
            'output': _toolResultContent(result),
          });
          yield ChatStreamChunk(
            content: '',
            toolCall: toolCall.copyWith(
              arguments: arguments,
              result: result,
              status: _toolStatusForResult(result),
            ),
            isToolCallComplete: true,
          );

          final failureResponse = _terminalToolFailureResponse(
            toolCall.name,
            result,
          );
          if (failureResponse != null) {
            _chatHistory.add({'role': 'assistant', 'content': failureResponse});
            yield ChatStreamChunk(content: failureResponse);
            shouldContinue = false;
            break;
          }
          if (stopAfterDuplicateLoop) shouldContinue = false;
        }

        if (finalResponsePayload.isEmpty &&
            roundResponse.isEmpty &&
            toolCalls.isEmpty) {
          throw _providerException(
            _providerName,
            'OpenAI returned no response output.',
          );
        }
      } while (shouldContinue);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw CancelledException();
      throw await _mapDioException(_providerName, error);
    } finally {
      _cancelToken = null;
    }
  }

  String _responseToolKey(Map<String, dynamic> event, Map? item) {
    return item?['id']?.toString() ??
        event['item_id']?.toString() ??
        event['output_index']?.toString() ??
        'tool_${event.hashCode}';
  }

  void _mergeCompletedToolCalls(
    Map<String, dynamic> response,
    Map<String, ToolCallChunk> activeToolCalls,
  ) {
    final output = response['output'];
    if (output is! List) return;
    for (var index = 0; index < output.length; index++) {
      final rawItem = output[index];
      if (rawItem is! Map || rawItem['type'] != 'function_call') continue;
      final item = Map<String, dynamic>.from(rawItem);
      final key = item['id']?.toString() ?? index.toString();
      final rawArguments = item['arguments']?.toString() ?? '';
      activeToolCalls[key] = ToolCallChunk(
        id: item['call_id']?.toString() ?? key,
        name: item['name']?.toString(),
        rawArguments: rawArguments,
        arguments: _tryParseToolArguments(rawArguments),
        status: ToolCallStatus.calling,
      );
    }
  }
}
