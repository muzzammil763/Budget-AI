import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/tools/tools.dart';
import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:budget_ai/src/tools/tool_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

part 'chat_provider_helpers.dart';
part 'chat_message_models.dart';
part 'chat_system_prompt.dart';
part 'chat_provider_clients.dart';

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

  Future<Map<String, dynamic>> _buildUserMessage(
    String message,
    List<String>? imagePaths,
  ) async {
    if (imagePaths == null || imagePaths.isEmpty) {
      return {'role': 'user', 'content': message};
    }

    final content = <Map<String, dynamic>>[];
    final messageText = await _buildMessageTextWithSvgAttachments(
      message,
      imagePaths,
    );

    for (final path in imagePaths) {
      if (_isSvgPath(path)) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64Data = base64Encode(bytes);
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
  void dispose() {
    _chatHistory.clear();
    _cancelToken?.cancel('Provider disposed');
    _dio.close();
  }
}
