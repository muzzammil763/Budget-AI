part of 'chat_provider.dart';

abstract class ChatProvider {
  final ChatModelConfig config;

  ChatProvider(this.config);

  Map<String, dynamic>? get lastResponseMetadata => null;

  Future<void> initialize();

  Future<bool> isReady();

  Stream<String> sendMessageStream(String message, {List<String>? imagePaths});

  /// Enhanced stream with thinking/reasoning tokens
  Stream<ChatStreamChunk> sendMessageStreamWithThinking(
    String message, {
    List<String>? imagePaths,
    bool enableToolCalls = true,
  });

  Future<String> generateTitle(List<ChatMessage> messages);

  Future<String> runUtilityPrompt(
    String prompt, {
    int maxTokens = 400,
    double temperature = 0.2,
  });

  /// Cancel the current in-flight request
  void cancelRequest();

  /// Update the selected model ID
  void updateModel(String modelId);

  /// Load chat history from storage to maintain conversation context
  void loadChatHistory(List<ChatMessage> messages);

  /// Load the exact provider-facing conversation state.
  void loadConversationState(List<Map<String, dynamic>> items);

  /// Export the exact provider-facing conversation state.
  List<Map<String, dynamic>> exportConversationState();

  /// Clear chat history
  void clearHistory();

  void dispose();

  factory ChatProvider.create(ChatModelConfig config) {
    return ChatCompletionsProvider(config);
  }
}

abstract class BaseChatProvider extends ChatProvider {
  String? _apiKey;
  List<String> _apiKeys = [];
  String _selectedModel;
  final List<Map<String, dynamic>> _chatHistory = [];
  final ToolRegistry _toolRegistry;
  Map<String, dynamic>? _lastResponseMetadata;
  final Dio _dio;
  CancelToken? _cancelToken;

  BaseChatProvider(
    super.config, {
    required String defaultSelectedModel,
    Dio? dio,
    ToolRegistry? toolRegistry,
  }) : _selectedModel = defaultSelectedModel,
       _dio = dio ?? _createProviderDio(),
       _toolRegistry = toolRegistry ?? ToolRegistry();

  static Dio _createProviderDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 5),
      ),
    );
  }

  String get _providerName => config.displayName;

  bool get _preserveReasoningContentForHistory =>
      config.type == ChatModelType.deepseek;

  String get _baseUrl;

  @override
  Map<String, dynamic>? get lastResponseMetadata => _lastResponseMetadata;

  @override
  Future<void> initialize() async {
    _apiKey = AppConstants.deepSeekApiKey.isNotEmpty
        ? AppConstants.deepSeekApiKey
        : null;
    _apiKeys = _apiKey != null ? [_apiKey!] : [];
    // Always default to flash on startup. Pro can be selected in-session.
    _selectedModel = 'deepseek-v4-flash';
    _dio.options.headers = {'Accept': 'application/json'};
  }

  @override
  Future<bool> isReady() async {
    return _apiKeys.isNotEmpty;
  }

  @override
  void cancelRequest() {
    _toolRegistry.cancelActiveRequests();
    _cancelToken?.cancel('User cancelled the request');
  }

  @override
  void updateModel(String modelId) {
    _selectedModel = modelId;
  }

  @override
  Future<String> runUtilityPrompt(
    String prompt, {
    int maxTokens = 400,
    double temperature = 0.2,
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return '';
    }

    try {
      final response = await _postJsonWithApiKeyFallback(
        dio: _dio,
        url: '$_baseUrl/chat/completions',
        apiKeys: _apiKeys,
        providerName: _providerName,
        data: {
          'model': _selectedModel,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': maxTokens,
          'temperature': temperature,
        },
        onKeySelected: (apiKey) => _apiKey = apiKey,
      );

      if (response.statusCode == 200) {
        return _firstChoice(
              response.data,
            )?['message']?['content']?.toString().trim() ??
            '';
      }
    } catch (e) {
      debugPrint('[$_providerName] Utility prompt failed: $e');
    }

    return '';
  }

  @override
  Future<String> generateTitle(List<ChatMessage> messages) async {
    try {
      if (_apiKey == null || _apiKey!.isEmpty) {
        return messages.firstWhere((m) => m.isUser).text;
      }

      final conversationSummary = messages
          .take(4)
          .map((m) => '${m.isUser ? "User" : "AI"}: ${m.text}')
          .join('\n');

      final titlePrompt =
          '''Based on this conversation, generate a short, concise title (maximum 6 words) that captures the main topic. Only return the title, nothing else:

$conversationSummary

Title:''';

      debugPrint('[$_providerName] Generating title...');
      final generatedTitle = await runUtilityPrompt(
        titlePrompt,
        maxTokens: 80,
        temperature: 0.2,
      );
      if (generatedTitle.isNotEmpty) {
        return generatedTitle;
      }
    } catch (e) {
      debugPrint('[$_providerName] Error Generating Title: $e');
    }

    return messages.firstWhere((m) => m.isUser).text;
  }

  @override
  void loadChatHistory(List<ChatMessage> messages) {
    final nextState = <Map<String, dynamic>>[];
    _chatHistory.clear();
    for (var msg in messages) {
      if (msg.isUser && msg.imagePaths != null && msg.imagePaths!.isNotEmpty) {
        final content = <Map<String, dynamic>>[];

        for (var i = 0; i < msg.imagePaths!.length; i++) {
          content.add({
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,placeholder'},
          });
        }

        content.add({'type': 'text', 'text': msg.text});
        nextState.add({'role': 'user', 'content': content});
      } else {
        nextState.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text,
        });
      }
    }
    loadConversationState(nextState);
  }

  @override
  void loadConversationState(List<Map<String, dynamic>> items) {
    _chatHistory
      ..clear()
      ..addAll(_deepCopyConversationState(items));
  }

  @override
  List<Map<String, dynamic>> exportConversationState() {
    return _deepCopyConversationState(_chatHistory);
  }

  @override
  void clearHistory() {
    _chatHistory.clear();
  }

  @override
  void dispose() {
    _chatHistory.clear();
    _cancelToken?.cancel('Provider disposed');
    _dio.close();
  }
}

/// Chat completions implementation using Dio with cancellation support.
class ChatCompletionsProvider extends BaseChatProvider {
  @override
  String get _baseUrl => config.apiBaseUrl;

  ChatCompletionsProvider(super.config, {super.dio})
    : super(defaultSelectedModel: AIModels.getDefaultModel(config.modelName));

  @override
  Stream<String> sendMessageStream(
    String message, {
    List<String>? imagePaths,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw _providerException(
        _providerName,
        '$_providerName API key is missing. Add it in Settings > API Keys.',
      );
    }

    // Add user message to history with images if provided
    final userMessage = await _buildUserMessage(message, imagePaths);
    _chatHistory.add(userMessage);

    debugPrint(
      '[$_providerName] Sending request to $_baseUrl/chat/completions',
    );
    debugPrint('[$_providerName] Model: $_selectedModel');

    // Create a new cancel token for this request
    _cancelToken = CancelToken();
    _lastResponseMetadata = null;

    try {
      final response = await _postStreamWithApiKeyFallback(
        dio: _dio,
        url: '$_baseUrl/chat/completions',
        apiKeys: _apiKeys,
        providerName: _providerName,
        data: {
          'model': _selectedModel,
          'messages': await _buildMessagesWithContext(
            _chatHistory,
            preserveReasoningContent: _preserveReasoningContentForHistory,
          ),
          'stream': true,
        },
        cancelToken: _cancelToken,
        onKeySelected: (apiKey) => _apiKey = apiKey,
      );

      String fullResponse = '';

      await for (final chunk in response.data!.stream) {
        // Check if cancelled during streaming
        if (_cancelToken?.isCancelled ?? false) {
          throw CancelledException();
        }

        final lines = utf8.decode(chunk).split('\n');

        for (final line in lines) {
          if (line.startsWith('data: ') && line != 'data: [DONE]') {
            final data = line.substring(6);
            if (data.isNotEmpty) {
              try {
                final json = jsonDecode(data);
                final responseMetadata = _extractResponseMetadata(
                  Map<String, dynamic>.from(json as Map),
                  requestedModel: _selectedModel,
                  providerName: _providerName,
                );
                if (responseMetadata.length > 2) {
                  _lastResponseMetadata = mergeResponseMetadata(
                    _lastResponseMetadata ?? const <String, dynamic>{},
                    responseMetadata,
                  );
                }
                final delta = _firstChoice(json)?['delta']?['content'];
                if (delta != null && delta.isNotEmpty) {
                  fullResponse += delta;
                  yield delta;
                }
              } catch (e) {
                debugPrint('[$_providerName] Error parsing SSE: $e');
              }
            }
          }
        }
      }

      // Add assistant response to history
      _chatHistory.add({'role': 'assistant', 'content': fullResponse});
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw CancelledException();
      }
      throw await _mapDioException(_providerName, e);
    } finally {
      _cancelToken = null;
    }
  }

  /// Build user message content, supporting both text and images
  Future<Map<String, dynamic>> _buildUserMessage(
    String message,
    List<String>? imagePaths,
  ) async {
    if (imagePaths == null || imagePaths.isEmpty) {
      return {'role': 'user', 'content': message};
    }

    // Build content array with text and images for vision models
    final content = <Map<String, dynamic>>[];
    final messageText = await _buildMessageTextWithSvgAttachments(
      message,
      imagePaths,
    );

    // Add images first
    for (final path in imagePaths) {
      if (_isSvgPath(path)) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64Data = base64Encode(bytes);
          // Determine mime type from extension
          final mimeType = _getMimeType(path);
          content.add({
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
          });
        }
      } catch (e) {
        debugPrint('[$_providerName] Error reading image $path: $e');
      }
    }

    // Add text part last
    content.add({'type': 'text', 'text': messageText});

    return {'role': 'user', 'content': content};
  }

  String _getMimeType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Stream<ChatStreamChunk> sendMessageStreamWithThinking(
    String message, {
    List<String>? imagePaths,
    bool enableToolCalls = true,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw _providerException(
        _providerName,
        '$_providerName API key is missing. Add it in Settings > API Keys.',
      );
    }

    // Add user message to history with images if provided
    final userMessage = await _buildUserMessage(message, imagePaths);
    _chatHistory.add(userMessage);

    // Skip tools when images are attached — router endpoints on providers like
    // Xiaomi/Fireworks cannot route a request combining vision content with
    // tool_calls and return a 404 routing error.
    final hasImages = imagePaths != null && imagePaths.isNotEmpty;
    _toolRegistry.setActiveProviderInfo(
      modelId: _selectedModel,
      apiKey: _apiKey ?? '',
      baseUrl: config.apiBaseUrl,
    );
    _toolRegistry.setActiveMessageImagePaths(imagePaths);
    final tools = enableToolCalls && !hasImages
        ? _toolRegistry.getAvailableTools()
        : [];
    final hasTools = tools.isNotEmpty;

    debugPrint(
      '[$_providerName] Sending request to $_baseUrl/chat/completions',
    );
    debugPrint('[$_providerName] Model: $_selectedModel');
    debugPrint('[$_providerName] Tool calls enabled: $enableToolCalls');
    debugPrint(
      '[$_providerName] Tools available: ${tools.map((t) => t.name).toList()}',
    );

    _cancelToken = CancelToken();
    _lastResponseMetadata = null;

    // Skills removed in Budget AI

    try {
      String fullResponse = '';
      String finalAssistantResponse = '';
      bool shouldContinue = false;
      final toolCallTracker = _ToolCallTracker(
        maxRounds: 25,
        maxTotalCalls: 60,
      );
      var duplicateToolCallRounds = 0;

      do {
        shouldContinue = false;
        toolCallTracker.beginRound();
        String roundResponse = '';
        String roundReasoningText = '';
        bool isInReasoningPhase = true;
        final Map<String, ToolCallChunk> activeToolCalls = {};
        finalAssistantResponse = '';
        String buffer = '';

        final requestData = <String, dynamic>{
          'model': _selectedModel,
          'messages': await _buildAgenticMessages(
            _chatHistory,
            preserveReasoningContent: _preserveReasoningContentForHistory,
          ),
          'stream': true,
        };

        if (hasTools) {
          requestData['tools'] = tools.map((t) => t.toJson()).toList();
          requestData['tool_choice'] = 'auto';
        }

        final response = await _postStreamWithApiKeyFallback(
          dio: _dio,
          url: '$_baseUrl/chat/completions',
          apiKeys: _apiKeys,
          providerName: _providerName,
          data: requestData,
          cancelToken: _cancelToken,
          onKeySelected: (apiKey) => _apiKey = apiKey,
        );

        await for (final chunk in response.data!.stream) {
          if (_cancelToken?.isCancelled ?? false) {
            throw CancelledException();
          }

          buffer += utf8.decode(chunk);
          final lines = buffer.split('\n');
          buffer = lines.isNotEmpty ? lines.last : "";
          final completeLines = lines.length > 1
              ? lines.sublist(0, lines.length - 1)
              : <String>[];

          for (final line in completeLines) {
            if (line.startsWith('data: ') && line != 'data: [DONE]') {
              final data = line.substring(6);
              if (data.isEmpty) continue;

              try {
                final json = jsonDecode(data);
                final responseMetadata = _extractResponseMetadata(
                  Map<String, dynamic>.from(json as Map),
                  requestedModel: _selectedModel,
                  providerName: _providerName,
                );
                if (responseMetadata.length > 2) {
                  _lastResponseMetadata = mergeResponseMetadata(
                    _lastResponseMetadata ?? const <String, dynamic>{},
                    responseMetadata,
                  );
                  yield ChatStreamChunk(
                    content: '',
                    responseMetadata: responseMetadata,
                  );
                }
                final choice = _firstChoice(json);
                final delta = choice?['delta'];
                final finishReason = choice?['finish_reason'];

                final toolCallsDelta = delta?['tool_calls'];
                if (toolCallsDelta != null && toolCallsDelta is List) {
                  for (final tc in toolCallsDelta) {
                    final index = tc['index']?.toString() ?? '0';
                    final id =
                        tc['id'] ?? activeToolCalls[index]?.id ?? 'call_$index';
                    final function = tc['function'] ?? {};

                    final existing = activeToolCalls[index];
                    final name = function['name'] ?? existing?.name;
                    final argsFragment = function['arguments'] ?? '';
                    final accumulatedArgs =
                        '${existing?.rawArguments ?? ''}$argsFragment';

                    final parsedArgs = _tryParseToolArguments(accumulatedArgs);

                    final status = name == null || parsedArgs == null
                        ? ToolCallStatus.creating
                        : ToolCallStatus.calling;

                    final toolCall = ToolCallChunk(
                      id: id,
                      name: name,
                      rawArguments: accumulatedArgs,
                      arguments: parsedArgs,
                      status: status,
                    );

                    activeToolCalls[index] = toolCall;

                    yield ChatStreamChunk(
                      content: '',
                      toolCall: toolCall,
                      isToolCallComplete: false,
                    );
                  }
                }

                final reasoning = _extractReasoningDelta(delta);
                if (reasoning != null && reasoning.isNotEmpty) {
                  roundReasoningText += reasoning;
                  yield ChatStreamChunk(
                    content: '',
                    thinking: reasoning,
                    isThinkingComplete: false,
                  );
                }

                final content = delta?['content'];
                if (content != null && content.isNotEmpty) {
                  if (isInReasoningPhase && roundReasoningText.isNotEmpty) {
                    isInReasoningPhase = false;
                    yield ChatStreamChunk(
                      content: '',
                      isThinkingComplete: true,
                    );
                  }

                  roundResponse += content;
                  finalAssistantResponse += content;
                  fullResponse += content;
                  yield ChatStreamChunk(content: content);
                }

                if (finishReason == 'tool_calls' &&
                    activeToolCalls.isNotEmpty) {
                  if (isInReasoningPhase && roundReasoningText.isNotEmpty) {
                    isInReasoningPhase = false;
                    yield ChatStreamChunk(
                      content: '',
                      isThinkingComplete: true,
                    );
                  }

                  final toolCallsList = activeToolCalls.values
                      .map(_toolCallPayloadForHistory)
                      .whereType<Map<String, dynamic>>()
                      .toList();
                  shouldContinue = toolCallsList.isNotEmpty;

                  if (toolCallsList.isNotEmpty) {
                    _chatHistory.add(
                      _assistantToolCallMessageForHistory(
                        roundResponse: roundResponse,
                        roundReasoningText: roundReasoningText,
                        preserveReasoningContent:
                            _preserveReasoningContentForHistory,
                        toolCallsList: toolCallsList,
                      ),
                    );
                  }

                  var stopAfterDuplicateLoop = false;
                  for (final toolCall in activeToolCalls.values) {
                    final resolvedArgs =
                        toolCall.arguments ??
                        _tryParseToolArguments(toolCall.rawArguments);
                    if (toolCall.name == null) {
                      continue;
                    }

                    dynamic result;
                    if (resolvedArgs == null) {
                      result = _malformedToolCallResult(toolCall);
                    } else if (toolCallTracker.isLoop(
                      toolCall.name!,
                      resolvedArgs,
                    )) {
                      duplicateToolCallRounds++;
                      final cachedResult = toolCallTracker.latestResult(
                        toolCall.name!,
                        resolvedArgs,
                      );
                      result =
                          cachedResult ??
                          {
                            'ok': true,
                            'note':
                                'Already completed successfully. Give the final response now.',
                          };
                      stopAfterDuplicateLoop = duplicateToolCallRounds > 1;
                    } else {
                      toolCallTracker.recordCall(toolCall.name!, resolvedArgs);
                      try {
                        if (_cancelToken?.isCancelled ?? false) {
                          throw CancelledException();
                        }
                        await for (final chunk in _executeToolAndStreamChunks(
                          toolRegistry: _toolRegistry,
                          toolCall: toolCall,
                          arguments: resolvedArgs,
                          isCancelled: () => _cancelToken?.isCancelled ?? false,
                          onResult: (value) => result = value,
                        )) {
                          yield chunk;
                        }
                        if (_cancelToken?.isCancelled ?? false) {
                          throw CancelledException();
                        }
                      } catch (e) {
                        if (_cancelToken?.isCancelled ?? false) {
                          throw CancelledException();
                        }
                        result = {'error': e.toString()};
                      }
                      toolCallTracker.recordResult(
                        toolCall.name!,
                        resolvedArgs,
                        result,
                      );
                    }

                    if (resolvedArgs != null) {
                      _chatHistory.add({
                        'role': 'tool',
                        'tool_call_id': toolCall.id,
                        'content': _toolResultContent(result),
                      });
                    }

                    yield ChatStreamChunk(
                      content: '',
                      toolCall: toolCall.copyWith(
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
                      var isAfterFailedTool = false;
                      for (final remainingToolCall in activeToolCalls.values) {
                        if (remainingToolCall.id == toolCall.id) {
                          isAfterFailedTool = true;
                          continue;
                        }
                        if (!isAfterFailedTool) continue;
                        final skippedResult = _skippedToolAfterFailureResult(
                          toolCall.name ?? '',
                        );
                        final remainingId = remainingToolCall.id;
                        if (remainingId.isNotEmpty) {
                          _chatHistory.add({
                            'role': 'tool',
                            'tool_call_id': remainingId,
                            'content': _toolResultContent(skippedResult),
                          });
                        }
                        yield ChatStreamChunk(
                          content: '',
                          toolCall: remainingToolCall.copyWith(
                            result: skippedResult,
                            status: ToolCallStatus.failed,
                          ),
                          isToolCallComplete: true,
                        );
                      }
                      finalAssistantResponse += failureResponse;
                      fullResponse += failureResponse;
                      yield ChatStreamChunk(content: failureResponse);
                      shouldContinue = false;
                      break;
                    }
                  }
                  if (stopAfterDuplicateLoop) {
                    shouldContinue = false;
                  }

                  break;
                }

                if (finishReason == 'stop') {
                  if (isInReasoningPhase && roundReasoningText.isNotEmpty) {
                    isInReasoningPhase = false;
                    yield ChatStreamChunk(
                      content: '',
                      isThinkingComplete: true,
                    );
                  }

                  for (final toolCall in activeToolCalls.values) {
                    if (toolCall.status == ToolCallStatus.completed ||
                        toolCall.status == ToolCallStatus.failed) {
                      continue;
                    }

                    yield ChatStreamChunk(
                      content: '',
                      toolCall: toolCall.copyWith(
                        status: ToolCallStatus.completed,
                      ),
                      isToolCallComplete: true,
                    );
                  }
                }
              } catch (e) {
                debugPrint('[$_providerName] Error parsing SSE: $e');
              }
            }
          }
        }
      } while (shouldContinue);

      _chatHistory.add({
        'role': 'assistant',
        'content': _assistantContentForHistory(
          finalAssistantResponse: finalAssistantResponse,
          fullResponse: fullResponse,
        ),
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw CancelledException();
      }
      throw await _mapDioException(_providerName, e);
    } finally {
      // Skills removed in Budget AI
      _cancelToken = null;
    }
  }
}

/// Fireworks API chat provider using Dio with cancellation support.
class FireworksChatProvider extends BaseChatProvider {
  static const String _fireworksBaseUrl =
      'https://api.fireworks.ai/inference/v1';

  @override
  String get _baseUrl => _fireworksBaseUrl;

  FireworksChatProvider(super.config, {super.dio})
    : super(defaultSelectedModel: AIModels.getDefaultModel(config.modelName));

  /// Build user message content, supporting both text and images
  Future<Map<String, dynamic>> _buildUserMessage(
    String message,
    List<String>? imagePaths,
  ) async {
    if (imagePaths == null || imagePaths.isEmpty) {
      return {'role': 'user', 'content': message};
    }

    // Build content array with text and images for vision models
    final content = <Map<String, dynamic>>[];
    final messageText = await _buildMessageTextWithSvgAttachments(
      message,
      imagePaths,
    );

    // Add images first
    for (final path in imagePaths) {
      if (_isSvgPath(path)) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64Data = base64Encode(bytes);
          // Determine mime type from extension
          final mimeType = _getMimeType(path);
          content.add({
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
          });
        }
      } catch (e) {
        debugPrint('[$_providerName] Error reading image $path: $e');
      }
    }

    // Add text part last
    content.add({'type': 'text', 'text': messageText});

    return {'role': 'user', 'content': content};
  }

  String _getMimeType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Stream<String> sendMessageStream(
    String message, {
    List<String>? imagePaths,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw _providerException(
        _providerName,
        '$_providerName API key is missing. Add it in Settings > API Keys.',
      );
    }

    // Add user message to history with images if provided
    final userMessage = await _buildUserMessage(message, imagePaths);
    _chatHistory.add(userMessage);

    debugPrint(
      '[$_providerName] Sending request to $_baseUrl/chat/completions',
    );
    debugPrint('[$_providerName] Model: $_selectedModel');

    // Create a new cancel token for this request
    _cancelToken = CancelToken();
    _lastResponseMetadata = null;

    try {
      final response = await _postStreamWithApiKeyFallback(
        dio: _dio,
        url: '$_baseUrl/chat/completions',
        apiKeys: _apiKeys,
        providerName: _providerName,
        data: {
          'model': _selectedModel,
          'messages': await _buildMessagesWithContext(
            _chatHistory,
            preserveReasoningContent: _preserveReasoningContentForHistory,
          ),
          'stream': true,
        },
        cancelToken: _cancelToken,
        onKeySelected: (apiKey) => _apiKey = apiKey,
      );

      String fullResponse = '';

      await for (final chunk in response.data!.stream) {
        // Check if cancelled during streaming
        if (_cancelToken?.isCancelled ?? false) {
          throw CancelledException();
        }

        final lines = utf8.decode(chunk).split('\n');

        for (final line in lines) {
          if (line.startsWith('data: ') && line != 'data: [DONE]') {
            final data = line.substring(6);
            if (data.isNotEmpty) {
              try {
                final json = jsonDecode(data);
                final responseMetadata = _extractResponseMetadata(
                  Map<String, dynamic>.from(json as Map),
                  requestedModel: _selectedModel,
                  providerName: _providerName,
                );
                if (responseMetadata.length > 2) {
                  _lastResponseMetadata = mergeResponseMetadata(
                    _lastResponseMetadata ?? const <String, dynamic>{},
                    responseMetadata,
                  );
                }
                final delta = _firstChoice(json)?['delta'];

                // Debug: Log delta structure to understand API response format
                if (delta != null &&
                    delta.isNotEmpty &&
                    (delta['content'] != null ||
                        delta['reasoning_content'] != null)) {
                  debugPrint(
                    '[$_providerName] Delta keys: ${delta.keys.toList()}',
                  );
                }

                final content = delta?['content'];
                if (content != null && content.isNotEmpty) {
                  fullResponse += content;
                  yield content;
                }
              } catch (e) {
                debugPrint('[$_providerName] Error parsing SSE: $e');
              }
            }
          }
        }
      }

      // Add assistant response to history
      _chatHistory.add({'role': 'assistant', 'content': fullResponse});
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw CancelledException();
      }
      throw await _mapDioException(_providerName, e);
    } finally {
      _cancelToken = null;
    }
  }

  @override
  Stream<ChatStreamChunk> sendMessageStreamWithThinking(
    String message, {
    List<String>? imagePaths,
    bool enableToolCalls = true,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw _providerException(
        _providerName,
        '$_providerName API key is missing. Add it in Settings > API Keys.',
      );
    }

    // Add user message to history with images if provided
    final userMessage = await _buildUserMessage(message, imagePaths);
    _chatHistory.add(userMessage);

    // Skip tools when images are attached — router endpoints on providers like
    // Xiaomi/Fireworks cannot route a request combining vision content with
    // tool_calls and return a 404 routing error.
    final hasImages = imagePaths != null && imagePaths.isNotEmpty;
    _toolRegistry.setActiveProviderInfo(
      modelId: _selectedModel,
      apiKey: _apiKey ?? '',
      baseUrl: config.apiBaseUrl,
    );
    _toolRegistry.setActiveMessageImagePaths(imagePaths);
    final tools = enableToolCalls && !hasImages
        ? _toolRegistry.getAvailableTools()
        : [];
    final hasTools = tools.isNotEmpty;

    debugPrint(
      '[$_providerName] Sending request to $_baseUrl/chat/completions',
    );
    debugPrint('[$_providerName] Model: $_selectedModel');
    debugPrint('[$_providerName] Tool calls enabled: $enableToolCalls');
    debugPrint(
      '[$_providerName] Tools available: ${tools.map((t) => t.name).toList()}',
    );

    _cancelToken = CancelToken();
    _lastResponseMetadata = null;

    // Skills removed in Budget AI

    try {
      String fullResponse = '';
      String finalAssistantResponse = '';
      bool shouldContinue = false;
      final toolCallTracker = _ToolCallTracker(
        maxRounds: 25,
        maxTotalCalls: 60,
      );
      var duplicateToolCallRounds = 0;

      do {
        shouldContinue = false;
        toolCallTracker.beginRound();
        String roundResponse = '';
        String roundReasoningText = '';
        bool isInReasoningPhase = true;
        final Map<String, ToolCallChunk> activeToolCalls = {};
        finalAssistantResponse = '';
        String buffer = '';

        final requestData = <String, dynamic>{
          'model': _selectedModel,
          'messages': await _buildAgenticMessages(
            _chatHistory,
            preserveReasoningContent: _preserveReasoningContentForHistory,
          ),
          'stream': true,
        };

        if (hasTools) {
          requestData['tools'] = tools.map((t) => t.toJson()).toList();
          requestData['tool_choice'] = 'auto';
        }

        final response = await _postStreamWithApiKeyFallback(
          dio: _dio,
          url: '$_baseUrl/chat/completions',
          apiKeys: _apiKeys,
          providerName: _providerName,
          data: requestData,
          cancelToken: _cancelToken,
          onKeySelected: (apiKey) => _apiKey = apiKey,
        );

        await for (final chunk in response.data!.stream) {
          if (_cancelToken?.isCancelled ?? false) {
            throw CancelledException();
          }

          buffer += utf8.decode(chunk);
          final lines = buffer.split('\n');
          buffer = lines.isNotEmpty ? lines.last : "";
          final completeLines = lines.length > 1
              ? lines.sublist(0, lines.length - 1)
              : <String>[];

          for (final line in completeLines) {
            if (line.startsWith('data: ') && line != 'data: [DONE]') {
              final data = line.substring(6);
              if (data.isEmpty) continue;

              try {
                final json = jsonDecode(data);
                final responseMetadata = _extractResponseMetadata(
                  Map<String, dynamic>.from(json as Map),
                  requestedModel: _selectedModel,
                  providerName: _providerName,
                );
                if (responseMetadata.length > 2) {
                  _lastResponseMetadata = mergeResponseMetadata(
                    _lastResponseMetadata ?? const <String, dynamic>{},
                    responseMetadata,
                  );
                  yield ChatStreamChunk(
                    content: '',
                    responseMetadata: responseMetadata,
                  );
                }
                final choice = _firstChoice(json);
                final delta = choice?['delta'];
                final finishReason = choice?['finish_reason'];

                if (delta != null && delta.isNotEmpty) {
                  debugPrint(
                    '[$_providerName] Delta keys: ${delta.keys.toList()}',
                  );
                }

                final toolCallsDelta = delta?['tool_calls'];
                if (toolCallsDelta != null && toolCallsDelta is List) {
                  for (final tc in toolCallsDelta) {
                    final index = tc['index']?.toString() ?? '0';
                    final id =
                        tc['id'] ?? activeToolCalls[index]?.id ?? 'call_$index';
                    final function = tc['function'] ?? {};

                    final existing = activeToolCalls[index];
                    final name = function['name'] ?? existing?.name;
                    final argsFragment = function['arguments'] ?? '';
                    final accumulatedArgs =
                        '${existing?.rawArguments ?? ''}$argsFragment';

                    final parsedArgs = _tryParseToolArguments(accumulatedArgs);

                    final status = name == null || parsedArgs == null
                        ? ToolCallStatus.creating
                        : ToolCallStatus.calling;

                    final toolCall = ToolCallChunk(
                      id: id,
                      name: name,
                      rawArguments: accumulatedArgs,
                      arguments: parsedArgs,
                      status: status,
                    );

                    activeToolCalls[index] = toolCall;

                    yield ChatStreamChunk(
                      content: '',
                      toolCall: toolCall,
                      isToolCallComplete: false,
                    );
                  }
                }

                final reasoning = _extractReasoningDelta(delta);
                if (reasoning != null && reasoning.isNotEmpty) {
                  roundReasoningText += reasoning;
                  yield ChatStreamChunk(
                    content: '',
                    thinking: reasoning,
                    isThinkingComplete: false,
                  );
                }

                final content = delta?['content'];
                if (content != null && content.isNotEmpty) {
                  if (isInReasoningPhase && roundReasoningText.isNotEmpty) {
                    isInReasoningPhase = false;
                    yield ChatStreamChunk(
                      content: '',
                      isThinkingComplete: true,
                    );
                  }

                  roundResponse += content;
                  finalAssistantResponse += content;
                  fullResponse += content;
                  yield ChatStreamChunk(content: content);
                }

                if (finishReason == 'tool_calls' &&
                    activeToolCalls.isNotEmpty) {
                  if (isInReasoningPhase && roundReasoningText.isNotEmpty) {
                    isInReasoningPhase = false;
                    yield ChatStreamChunk(
                      content: '',
                      isThinkingComplete: true,
                    );
                  }

                  final toolCallsList = activeToolCalls.values
                      .map(_toolCallPayloadForHistory)
                      .whereType<Map<String, dynamic>>()
                      .toList();
                  shouldContinue = toolCallsList.isNotEmpty;

                  if (toolCallsList.isNotEmpty) {
                    _chatHistory.add(
                      _assistantToolCallMessageForHistory(
                        roundResponse: roundResponse,
                        roundReasoningText: roundReasoningText,
                        preserveReasoningContent:
                            _preserveReasoningContentForHistory,
                        toolCallsList: toolCallsList,
                      ),
                    );
                  }

                  var stopAfterDuplicateLoop = false;
                  for (final toolCall in activeToolCalls.values) {
                    final resolvedArgs =
                        toolCall.arguments ??
                        _tryParseToolArguments(toolCall.rawArguments);
                    if (toolCall.name == null) {
                      continue;
                    }

                    dynamic result;
                    if (resolvedArgs == null) {
                      result = _malformedToolCallResult(toolCall);
                    } else if (toolCallTracker.isLoop(
                      toolCall.name!,
                      resolvedArgs,
                    )) {
                      duplicateToolCallRounds++;
                      final cachedResult = toolCallTracker.latestResult(
                        toolCall.name!,
                        resolvedArgs,
                      );
                      result =
                          cachedResult ??
                          {
                            'ok': true,
                            'note':
                                'Already completed successfully. Give the final response now.',
                          };
                      stopAfterDuplicateLoop = duplicateToolCallRounds > 1;
                    } else {
                      toolCallTracker.recordCall(toolCall.name!, resolvedArgs);
                      try {
                        if (_cancelToken?.isCancelled ?? false) {
                          throw CancelledException();
                        }
                        await for (final chunk in _executeToolAndStreamChunks(
                          toolRegistry: _toolRegistry,
                          toolCall: toolCall,
                          arguments: resolvedArgs,
                          isCancelled: () => _cancelToken?.isCancelled ?? false,
                          onResult: (value) => result = value,
                        )) {
                          yield chunk;
                        }
                        if (_cancelToken?.isCancelled ?? false) {
                          throw CancelledException();
                        }
                      } catch (e) {
                        if (_cancelToken?.isCancelled ?? false) {
                          throw CancelledException();
                        }
                        result = {'error': e.toString()};
                      }
                      toolCallTracker.recordResult(
                        toolCall.name!,
                        resolvedArgs,
                        result,
                      );
                    }

                    if (resolvedArgs != null) {
                      _chatHistory.add({
                        'role': 'tool',
                        'tool_call_id': toolCall.id,
                        'content': _toolResultContent(result),
                      });
                    }

                    yield ChatStreamChunk(
                      content: '',
                      toolCall: toolCall.copyWith(
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
                      var isAfterFailedTool = false;
                      for (final remainingToolCall in activeToolCalls.values) {
                        if (remainingToolCall.id == toolCall.id) {
                          isAfterFailedTool = true;
                          continue;
                        }
                        if (!isAfterFailedTool) continue;
                        final skippedResult = _skippedToolAfterFailureResult(
                          toolCall.name ?? '',
                        );
                        final remainingId = remainingToolCall.id;
                        if (remainingId.isNotEmpty) {
                          _chatHistory.add({
                            'role': 'tool',
                            'tool_call_id': remainingId,
                            'content': _toolResultContent(skippedResult),
                          });
                        }
                        yield ChatStreamChunk(
                          content: '',
                          toolCall: remainingToolCall.copyWith(
                            result: skippedResult,
                            status: ToolCallStatus.failed,
                          ),
                          isToolCallComplete: true,
                        );
                      }
                      finalAssistantResponse += failureResponse;
                      fullResponse += failureResponse;
                      yield ChatStreamChunk(content: failureResponse);
                      shouldContinue = false;
                      break;
                    }
                  }
                  if (stopAfterDuplicateLoop) {
                    shouldContinue = false;
                  }

                  break;
                }

                if (finishReason == 'stop') {
                  if (isInReasoningPhase && roundReasoningText.isNotEmpty) {
                    isInReasoningPhase = false;
                    yield ChatStreamChunk(
                      content: '',
                      isThinkingComplete: true,
                    );
                  }

                  for (final toolCall in activeToolCalls.values) {
                    if (toolCall.status == ToolCallStatus.completed ||
                        toolCall.status == ToolCallStatus.failed) {
                      continue;
                    }

                    yield ChatStreamChunk(
                      content: '',
                      toolCall: toolCall.copyWith(
                        status: ToolCallStatus.completed,
                      ),
                      isToolCallComplete: true,
                    );
                  }
                }
              } catch (e) {
                debugPrint('[$_providerName] Error parsing SSE: $e');
              }
            }
          }
        }
      } while (shouldContinue);

      _chatHistory.add({
        'role': 'assistant',
        'content': _assistantContentForHistory(
          finalAssistantResponse: finalAssistantResponse,
          fullResponse: fullResponse,
        ),
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw CancelledException();
      }
      throw await _mapDioException(_providerName, e);
    } finally {
      // Skills removed in Budget AI
      _cancelToken = null;
    }
  }
}
