import 'dart:async';
import 'dart:convert';

import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
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

  Stream<String> sendMessageStream(String message);

  /// Enhanced stream with thinking/reasoning tokens
  Stream<ChatStreamChunk> sendMessageStreamWithThinking(
    String message, {
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

  bool get _preserveReasoningContentForHistory => true;

  String get _baseUrl;

  @override
  Map<String, dynamic>? get lastResponseMetadata => _lastResponseMetadata;

  @override
  Future<void> initialize() async {
    _apiKey = AppConstants.deepSeekApiKey.isNotEmpty
        ? AppConstants.deepSeekApiKey
        : null;
    _apiKeys = _apiKey != null ? [_apiKey!] : [];
    _selectedModel = ModelSettingsService.instance.current;
    _dio.options.headers = {'Accept': 'application/json'};
  }

  @override
  void cancelRequest() {
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
      nextState.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.text,
      });
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
