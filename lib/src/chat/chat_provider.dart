import 'dart:async';
import 'dart:convert';

import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/chat/active_model_resolver.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/ai_response_settings_service.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:budget_ai/src/tools/tools.dart';
import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:budget_ai/src/tools/tool_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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
    return ResponsesProvider(config);
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
  final String? Function() _accessTokenProvider;
  final bool Function() _fastResponsesProvider;
  CancelToken? _cancelToken;

  BaseChatProvider(
    super.config, {
    required String defaultSelectedModel,
    Dio? dio,
    ToolRegistry? toolRegistry,
    String? Function()? accessTokenProvider,
    bool Function()? fastResponsesProvider,
  }) : _selectedModel = defaultSelectedModel,
       _dio = dio ?? _createProviderDio(),
       _accessTokenProvider =
           accessTokenProvider ?? (() => AuthService.instance.accessToken),
       _fastResponsesProvider =
           fastResponsesProvider ??
           (() =>
               AiResponseSettingsService.instance.fastResponsesEnabled.value),
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

  String get _baseUrl;

  Map<String, String> get _additionalRequestHeaders => {
    'apikey': AppConstants.supabasePublishableKey,
    if (AppConstants.supabaseFunctionRegion.isNotEmpty)
      'x-region': AppConstants.supabaseFunctionRegion,
  };

  Map<String, dynamic> get _responseModelOptions {
    if (_selectedModel.startsWith('gpt-5')) {
      return const {
        'reasoning': {'effort': 'low'},
        'text': {'verbosity': 'low'},
      };
    }
    if (_selectedModel == 'o3') {
      return const {
        'reasoning': {'effort': 'low'},
      };
    }
    return const {};
  }

  Map<String, dynamic> get _responseServiceTierOptions =>
      _fastResponsesProvider() ? const {'service_tier': 'fast'} : const {};

  @override
  Map<String, dynamic>? get lastResponseMetadata => _lastResponseMetadata;

  @override
  Future<void> initialize() async {
    _apiKey = _accessTokenProvider();
    _apiKeys = _apiKey != null ? [_apiKey!] : [];
    _selectedModel = await ActiveModelResolver.instance.resolve();
    _dio.options.headers = {'Accept': 'application/json'};
  }

  void _refreshSessionCredential() {
    _apiKey = _accessTokenProvider();
    _apiKeys = _apiKey != null && _apiKey!.isNotEmpty ? [_apiKey!] : [];
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
    _refreshSessionCredential();
    if (_apiKey == null || _apiKey!.isEmpty) {
      return '';
    }

    try {
      final response = await _postJsonWithApiKeyFallback(
        dio: _dio,
        url: _baseUrl,
        apiKeys: _apiKeys,
        providerName: _providerName,
        data: {
          'model': _selectedModel,
          ..._responseModelOptions,
          ..._responseServiceTierOptions,
          'input': prompt,
          'max_output_tokens': maxTokens,
          'client_turn_id': const Uuid().v4(),
        },
        additionalHeaders: _additionalRequestHeaders,
        onKeySelected: (apiKey) => _apiKey = apiKey,
      );

      if (response.statusCode == 200) {
        return _responseOutputText(response.data).trim();
      }
    } catch (e) {
      debugPrint('[$_providerName] Utility prompt failed: $e');
    }

    return '';
  }

  String _responseOutputText(dynamic payload) {
    if (payload is! Map) return '';
    final direct = payload['output_text']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final output = payload['output'];
    if (output is! List) return '';
    final buffer = StringBuffer();
    for (final item in output.whereType<Map>()) {
      if (item['type'] != 'message' || item['content'] is! List) continue;
      for (final content in (item['content'] as List).whereType<Map>()) {
        if (content['type'] == 'output_text') {
          buffer.write(content['text']?.toString() ?? '');
        }
      }
    }
    return buffer.toString();
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
