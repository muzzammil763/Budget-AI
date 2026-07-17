import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/settings_screen.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:budget_ai/src/helpers/app_route_observer.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/helpers/notification_payload.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/helpers/vibration_manager.dart';
import 'package:budget_ai/src/chat/chat_session_repository.dart';
import 'package:budget_ai/src/helpers/network_reachability_service.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/ios_background_task_service.dart';

import 'package:budget_ai/src/chat/chat_history_screen.dart';
import 'package:budget_ai/src/chat/chat_empty_state.dart';
import 'package:budget_ai/src/chat/chat_response_markdown.dart';
import 'package:budget_ai/src/chat/markdown_table_view.dart';

import 'package:budget_ai/src/chat/chat_loading_widgets.dart';
import 'package:budget_ai/src/chat/expandable_user_message_text.dart';
import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';

import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

import 'package:uuid/uuid.dart';

part 'unified_chat_widgets.dart';

class UnifiedChatScreen extends StatefulWidget {
  final ChatModelConfig config;
  final String? heroTag;

  const UnifiedChatScreen({super.key, required this.config, this.heroTag});

  @override
  State<UnifiedChatScreen> createState() => _UnifiedChatScreenState();
}

class _UnifiedChatScreenState extends State<UnifiedChatScreen>
    with RouteAware, WidgetsBindingObserver {
  static const String _continueInterruptedResponsePrompt =
      'Continue from the previous assistant turn. Use the completed tool results already in this conversation. Do not repeat successful tool calls unless required. Finish the original request.';
  static const int _maxAutomaticToolContinuations = 3;
  static const int _maxSilentPostToolErrorContinuations = 1;

  static const int _maxReconnectAttempts = 5;
  static const List<Duration> _reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _messageInputScrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<_TimelineViewItem> _timelineItems = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isAppInBackground = false;
  bool _isAppInactive = false;
  bool _isOnChatScreen = true;
  late ChatProvider _provider;
  int? _streamingMessageIndex;
  bool _isStreaming = false;
  bool _isReconnectingStream = false;
  bool _isWaitingForNetwork = false;
  DateTime? _suppressNetworkWaitingUntil;
  Timer? _streamingDurationTimer;
  String _selectedModel = '';
  ChatSessionRecord? _activeSession;
  final ValueNotifier<bool> _showScrollToBottomButton = ValueNotifier<bool>(
    false,
  );
  bool _shouldFollowChatScroll = true;
  bool _isShowingLeaveConfirmation = false;
  bool _isShowingStopConfirmation = false;
  final ValueNotifier<int> _tokenUiRevision = ValueNotifier(0);
  List<ChatSessionSummary>? _cachedSessionSummaries;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Future<List<ChatSessionSummary>>? _historySessionsFuture;
  final ValueNotifier<ChatMessage?> _streamingBubble = ValueNotifier(null);
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier(false);
  Timer? _streamingThrottleTimer;
  ChatMessage? _pendingStreamMessage;
  bool _scrollToBottomScheduled = false;
  bool _historySwipeEligible = false;
  double _historySwipeDistance = 0;
  double _historySwipeVerticalDistance = 0;
  int? _historySwipePointer;
  bool _tableGestureActive = false;
  StreamSubscription<void>? _notificationActionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _provider = ChatProvider.create(widget.config);
    _messageController.addListener(_handleComposerTextChanged);
    _messageController.addListener(_updateCanSend);
    _messageFocusNode.addListener(_handleComposerFocusChanged);
    _scrollController.addListener(_handleChatScroll);
    NetworkReachabilityService.instance.status.addListener(
      _handleNetworkStatusChanged,
    );
    NetworkReachabilityService.instance.start();
    _initialize();

    // Process any notification actions that arrived while the screen was
    // not mounted, and subscribe to new ones.
    _processPendingNotificationActions();
    _notificationActionSubscription = NotificationService
        .instance
        .onPendingActions
        .listen((_) {
          if (mounted) _processPendingNotificationActions();
        });
  }

  Future<void> _initialize() async {
    setState(() {
      _selectedModel = ModelSettingsService.instance.current;
    });
    await _refreshProviderState();
    _provider.updateModel(_selectedModel);
  }

  Future<void> _refreshChatConfiguration() async {
    await _loadSelectedModel();
    await _refreshProviderState();
  }

  Future<void> _refreshProviderState() async {
    try {
      await _provider.initialize();
    } catch (_) {
      // The provider will surface API-key or request failures during send.
    }
  }

  Future<void> _loadSelectedModel() async {
    setState(() {
      _selectedModel = ModelSettingsService.instance.current;
    });
    _provider.updateModel(_selectedModel);
  }

  ChatSessionRepository get _chatSessions => ChatSessionRepository.instance;

  void _rebuildMessagesFromTimeline() {
    _messages.clear();
    var msgIdx = 0;
    for (var i = 0; i < _timelineItems.length; i++) {
      final item = _timelineItems[i];
      if (item is! _TimelineMessageItem) continue;
      _messages.add(item.message);
      if (item.messageIndex != msgIdx) {
        _timelineItems[i] = item.copyWith(messageIndex: msgIdx);
      }
      msgIdx++;
    }
  }

  void _appendTimelineMessage(ChatMessage message, {int? entryId}) {
    final messageIndex = _messages.length;
    _messages.add(message);
    _timelineItems.add(
      _TimelineMessageItem(
        message: message,
        messageIndex: messageIndex,
        entryId: entryId,
      ),
    );
  }

  void _replaceTimelineMessageAt(int timelineIndex, ChatMessage message) {
    if (timelineIndex < 0 || timelineIndex >= _timelineItems.length) return;
    final item = _timelineItems[timelineIndex];
    if (item is! _TimelineMessageItem) return;
    _timelineItems[timelineIndex] = item.copyWith(message: message);
    final messageIndex = item.messageIndex;
    if (messageIndex >= 0 && messageIndex < _messages.length) {
      _messages[messageIndex] = message;
    } else {
      _rebuildMessagesFromTimeline();
    }
  }

  int? _timelineEntryIdForMessageIndex(int messageIndex) {
    var seenMessages = 0;
    for (final item in _timelineItems) {
      if (item is! _TimelineMessageItem) continue;
      if (seenMessages == messageIndex) return item.entryId;
      seenMessages++;
    }
    return null;
  }

  int? _timelineIndexForMessageIndex(int messageIndex) {
    var seenMessages = 0;
    for (var i = 0; i < _timelineItems.length; i++) {
      final item = _timelineItems[i];
      if (item is! _TimelineMessageItem) continue;
      if (seenMessages == messageIndex) return i;
      seenMessages++;
    }
    return null;
  }

  void _replaceTimelineEntryIdAt(int timelineIndex, int entryId) {
    if (timelineIndex < 0 || timelineIndex >= _timelineItems.length) return;
    final item = _timelineItems[timelineIndex];
    if (item is _TimelineMessageItem) {
      _timelineItems[timelineIndex] = item.copyWith(entryId: entryId);
    }
  }

  void _resetComposer() {
    _messageController.clear();
  }

  Future<void> _resetToFreshDraft() async {
    if (_isResponseInProgress) {
      await _showNewChatBlockedSheet();
      return;
    }

    setState(() {
      _activeSession = null;
      _messages.clear();
      _timelineItems.clear();
      _streamingMessageIndex = null;
      _isLoading = false;
      _isStreaming = false;
      _isReconnectingStream = false;
      _isWaitingForNetwork = false;
      _resetComposer();
    });

    _provider.clearHistory();
  }

  String _sanitizeChatTitle(String value) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return 'New chat';
    final first = collapsed.characters.first.toUpperCase();
    final rest = collapsed.characters.skip(1).toString();
    return '$first$rest';
  }

  Future<ChatSessionRecord> _ensureSessionCreated(
    ChatMessage firstUserMessage,
  ) async {
    final existing = _activeSession;
    if (existing != null) return existing;

    final session = await _chatSessions.createSession(
      id: const Uuid().v4(),
      title: _sanitizeChatTitle(firstUserMessage.text),
      titleSource: 'first_message',
      providerKey: widget.config.modelName,
      modelId: _selectedModel,
    );

    if (!mounted) return session;
    setState(() {
      _activeSession = session;
    });

    return session;
  }

  Future<void> _syncProviderStateToSession({
    ChatSessionLifecycleState? lifecycleState,
  }) async {
    final session = _activeSession;
    if (session == null) return;
    final exportedState = _provider.exportConversationState();
    final nextSession = session.copyWith(
      updatedAt: DateTime.now(),
      lastProviderKey: widget.config.modelName,
      lastModelId: _selectedModel,
      lifecycleState: lifecycleState ?? session.lifecycleState,
    );

    await _chatSessions.replaceActiveContextItems(
      sessionId: nextSession.id,
      generation: nextSession.activeGeneration,
      items: exportedState,
      providerKey: widget.config.modelName,
      modelId: _selectedModel,
      lifecycleState: nextSession.lifecycleState,
    );

    if (!mounted) return;
    setState(() {
      _activeSession = nextSession;
    });
  }

  void _removeProviderUserMessageFromHistory(String messageText) {
    final normalizedMessage = messageText.trim();
    if (normalizedMessage.isEmpty) return;

    final nextState = _provider.exportConversationState();
    for (var i = nextState.length - 1; i >= 0; i--) {
      final item = nextState[i];
      if (item['role'] != 'user') continue;
      final content = item['content'];
      final text = content is String ? content.trim() : '';
      if (text == normalizedMessage) {
        nextState.removeAt(i);
        _provider.loadConversationState(nextState);
        return;
      }
    }
  }

  Future<void> _loadPersistedSession(
    String sessionId, {
    Future<LoadedChatSession?>? preloadFuture,
  }) async {
    final loaded =
        await (preloadFuture ?? _chatSessions.loadSession(sessionId));
    if (loaded == null || !mounted) return;
    final timelineItems = <_TimelineViewItem>[];
    final messages = <ChatMessage>[];
    for (final entry in loaded.timelineEntries) {
      if (entry.type == ChatTimelineEntryType.statusCard) continue;
      final message = entry.message;
      if (message == null) continue;
      final messageIndex = messages.length;
      messages.add(message);
      timelineItems.add(
        _TimelineMessageItem(
          message: message,
          messageIndex: messageIndex,
          entryId: entry.id,
        ),
      );
    }

    final loadedActiveState = loaded.activeContextItems
        .map((item) => Map<String, dynamic>.from(item.payload))
        .toList();

    _provider.clearHistory();
    _provider.loadConversationState(loadedActiveState);
    if (!mounted) return;
    setState(() {
      _activeSession = loaded.session;
      _messages
        ..clear()
        ..addAll(messages);
      _timelineItems
        ..clear()
        ..addAll(timelineItems);
      _streamingMessageIndex = null;
      _isReconnectingStream = false;
      _isWaitingForNetwork = false;
      _resetComposer();
    });
    _scrollToBottom(force: true);
  }

  Future<void> _deleteHistorySession(String sessionId) async {
    await _chatSessions.deleteSession(sessionId);
    if (!mounted) return;
    _cachedSessionSummaries?.removeWhere((s) => s.id == sessionId);
    if (_activeSession?.id == sessionId) {
      await _resetToFreshDraft();
    }
  }

  Future<void> _renameHistorySession(String sessionId, String title) async {
    final sanitizedTitle = _sanitizeChatTitle(title);
    await _chatSessions.updateSessionTitle(
      sessionId: sessionId,
      title: sanitizedTitle,
    );
    if (!mounted) return;
    final cacheIndex =
        _cachedSessionSummaries?.indexWhere((s) => s.id == sessionId) ?? -1;
    if (cacheIndex != -1) {
      final old = _cachedSessionSummaries![cacheIndex];
      _cachedSessionSummaries![cacheIndex] = ChatSessionSummary(
        id: old.id,
        title: sanitizedTitle,
        updatedAt: old.updatedAt,
        lastProviderKey: old.lastProviderKey,
        lastModelId: old.lastModelId,
        lifecycleState: old.lifecycleState,
      );
    }
    if (_activeSession?.id == sessionId) {
      final current = _activeSession;
      if (current == null) return;
      setState(() {
        _activeSession = current.copyWith(
          title: sanitizedTitle,
          titleSource: 'manual',
          updatedAt: DateTime.now(),
        );
      });
    }
  }

  Future<void> _showNewChatBlockedSheet() async {
    _unfocusComposer();
    await ResponsiveInfoSheet.show(
      context,
      title: 'New Chat Unavailable',
      headerIcon: Icon(
        CupertinoIcons.exclamationmark_triangle_fill,
        color: Theme.of(context).colorScheme.onPrimary,
        size: 28,
      ),
      gradientColors: [
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Budget AI is still responding.',
          style: AppTheme.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Wait for it to finish before starting a new chat.',
          style: AppTheme.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Future<void> _handlePostTurnSessionState() async {
    await _syncProviderStateToSession();
  }

  void _handleComposerTextChanged() {}

  void _updateCanSend() {
    final next = _canSubmitCurrentMessage;
    if (_canSendNotifier.value != next) _canSendNotifier.value = next;
  }

  void _handleComposerFocusChanged() {}

  void _unfocusComposer() {
    if (_messageFocusNode.hasFocus) {
      _messageFocusNode.unfocus();
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _prepareMessageForProvider(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized == 'retry & continue' || normalized == 'continue') {
      return _continueInterruptedResponsePrompt;
    }

    return message;
  }

  String _prepareProviderOverrideMessage(String message) => message;

  void _stopStreamingThrottleTimer() {
    _streamingThrottleTimer?.cancel();
    _streamingThrottleTimer = null;
    _pendingStreamMessage = null;
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _messageController.removeListener(_handleComposerTextChanged);
    _messageController.removeListener(_updateCanSend);
    _messageFocusNode.removeListener(_handleComposerFocusChanged);
    _scrollController.removeListener(_handleChatScroll);
    _showScrollToBottomButton.dispose();
    _canSendNotifier.dispose();
    _tokenUiRevision.dispose();
    NetworkReachabilityService.instance.status.removeListener(
      _handleNetworkStatusChanged,
    );
    _messageController.dispose();
    _messageFocusNode.dispose();
    _messageInputScrollController.dispose();
    _scrollController.dispose();
    _streamingDurationTimer?.cancel();
    _stopStreamingThrottleTimer();
    _streamingBubble.dispose();
    _notificationActionSubscription?.cancel();
    _provider.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startStreamingDurationTimer(DateTime startedAt) {
    _streamingDurationTimer?.cancel();
    unawaited(AndroidBackgroundChatService.start());
    unawaited(IosBackgroundTaskService.start());
    var tickCount = 0;
    _streamingDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isStreaming) {
        _streamingDurationTimer?.cancel();
        _streamingDurationTimer = null;
        return;
      }
      tickCount++;
      // Refresh the context-limit button every 2 seconds so token counts
      // stay visually current during long streaming responses.
      if (tickCount % 2 == 0) {
        _tokenUiRevision.value++;
      }
    });
  }

  void _stopStreamingDurationTimer() {
    _streamingDurationTimer?.cancel();
    _streamingDurationTimer = null;
    unawaited(AndroidBackgroundChatService.stop());
    unawaited(IosBackgroundTaskService.stop());
  }

  // Used by streaming paths so multiple requests within the same frame
  // collapse to a single postFrameCallback instead of stacking up.
  void _scheduleScrollToBottom() {
    if (_scrollToBottomScheduled) return;
    _scrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomScheduled = false;
      if (mounted) _scrollToBottom(animate: true);
    });
  }

  void _scrollToBottom({bool force = false, bool animate = false}) {
    if (force) {
      _shouldFollowChatScroll = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (!_shouldScrollChatToBottom(force: force)) return;
      final bottom = _scrollController.position.maxScrollExtent;
      if (animate && !force) {
        unawaited(
          _scrollController
              .animateTo(
                bottom,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
              )
              .catchError((_) {}),
        );
        return;
      }
      _scrollController.jumpTo(bottom);
      // Second pass: lazy ListView may not have measured all items in the
      // first frame, so the initial jumpTo can undershoot. Check again before
      // moving because the user may have started scrolling in between frames.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        if (!_shouldScrollChatToBottom(force: force)) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  bool _shouldScrollChatToBottom({required bool force}) {
    if (force) return true;
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return true;
    return _shouldFollowChatScroll;
  }

  bool _handleChatScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    var shouldFollow = _shouldFollowChatScroll;
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        shouldFollow = false;
      } else if (_isChatMetricsNearBottom(notification.metrics)) {
        shouldFollow = true;
      }
    } else if (notification is ScrollUpdateNotification &&
        (notification.dragDetails != null ||
            notification.scrollDelta != null)) {
      final delta = notification.scrollDelta ?? 0;
      if (delta < 0) {
        shouldFollow = false;
      } else if (_isChatMetricsNearBottom(notification.metrics)) {
        shouldFollow = true;
      }
    } else if (notification is ScrollEndNotification &&
        _isChatMetricsNearBottom(notification.metrics)) {
      shouldFollow = true;
    }

    // No setState: this flag only feeds _shouldAutoScroll() at scroll-time
    // and is not read from any build(), so a rebuild here would be pure waste.
    _shouldFollowChatScroll = shouldFollow;
    return false;
  }

  bool _isChatMetricsNearBottom(ScrollMetrics metrics) {
    if (!metrics.maxScrollExtent.isFinite || !metrics.pixels.isFinite) {
      return true;
    }
    return metrics.maxScrollExtent - metrics.pixels < 100;
  }

  void _handleChatScroll() {
    if (!mounted) return;
    _showScrollToBottomButton.value = _shouldShowScrollToBottomButton;
  }

  bool get _shouldShowScrollToBottomButton {
    if (!_scrollController.hasClients) {
      return false;
    }

    final position = _scrollController.position;
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      return false;
    }

    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    return distanceFromBottom > 1.0;
  }

  Future<void> _sendMessage({
    bool appendUserMessage = true,
    String? providerMessageOverride,
    bool removeProviderMessageFromHistory = false,
    int? replaceAssistantMessageIndex,
    int automaticToolContinuationDepth = 0,
  }) async {
    final hasText = _messageController.text.trim().isNotEmpty;

    if (!hasText && providerMessageOverride == null) return;

    _unfocusComposer();

    final userMessageText = _messageController.text.trim();

    final providerMessageText = providerMessageOverride == null
        ? _prepareMessageForProvider(userMessageText)
        : _prepareProviderOverrideMessage(providerMessageOverride);
    final visibleUserMessageText = userMessageText.isNotEmpty
        ? userMessageText
        : providerMessageText;
    final provisionalUserMessage = ChatMessage(
      text: visibleUserMessageText,
      isUser: true,
      timestamp: DateTime.now(),
    );
    int? userTimelineIndex;
    if (appendUserMessage) {
      userTimelineIndex = _timelineItems.length;
    }

    setState(() {
      _isLoading = true;
      if (appendUserMessage) {
        _appendTimelineMessage(provisionalUserMessage, entryId: null);
      }
    });

    _messageController.clear();
    _scrollToBottom(force: true);

    final chatFlowPromptSnapshot = await _buildChatFlowPromptSnapshot();
    final session = await _ensureSessionCreated(provisionalUserMessage);
    int? userEntryId;
    if (appendUserMessage) {
      userEntryId = await _chatSessions.appendMessageEntry(
        sessionId: session.id,
        type: ChatTimelineEntryType.userMessage,
        message: provisionalUserMessage,
      );
    }

    if (appendUserMessage && userTimelineIndex != null && userEntryId != null) {
      setState(() {
        _replaceTimelineEntryIdAt(userTimelineIndex!, userEntryId!);
      });
    }

    int? aiMessageIndex;
    int? aiTimelineIndex;
    String fullResponse = '';
    List<ChatMessageBlock> messageBlocks = [];
    DateTime startTime = DateTime.now();
    int? responseTimeMs;
    int tokenCount = 0;
    Map<String, dynamic> responseMetadata = _buildChatFlowMetadata(
      userMessage: visibleUserMessageText,
      providerMessage: providerMessageText,
      systemPrompt: chatFlowPromptSnapshot,
    );
    ChatMessage? finalAssistantMessage;
    int? assistantEntryId;
    bool shouldSilentlyContinueAfterToolError = false;

    try {
      final replacingAssistant =
          replaceAssistantMessageIndex != null &&
          replaceAssistantMessageIndex >= 0 &&
          replaceAssistantMessageIndex < _messages.length &&
          !_messages[replaceAssistantMessageIndex].isUser;

      if (replacingAssistant) {
        aiMessageIndex = replaceAssistantMessageIndex;
        aiTimelineIndex = _timelineIndexForMessageIndex(aiMessageIndex);
        assistantEntryId = _timelineEntryIdForMessageIndex(aiMessageIndex);
        final existingMessage = _messages[aiMessageIndex];
        messageBlocks = _blocksForContinuingResponse(existingMessage);
        final checkpointMessage = _buildAssistantMessageFromBlocks(
          blocks: messageBlocks,
          timestamp: existingMessage.timestamp,
          modelUsed: existingMessage.modelUsed,
          tokensUsed: existingMessage.tokensUsed,
          tokensPerSec: existingMessage.tokensPerSec,
          responseTime: existingMessage.responseTime,
          responseMetadata: existingMessage.responseMetadata,
        );
        setState(() {
          if (aiTimelineIndex != null) {
            _replaceTimelineMessageAt(aiTimelineIndex, checkpointMessage);
          }
          _streamingMessageIndex = aiMessageIndex;
          _isLoading = false;
          _isStreaming = true;
          _isReconnectingStream = false;
          _isWaitingForNetwork = false;
        });
        _startStreamingDurationTimer(startTime);
        if (assistantEntryId != null) {
          unawaited(
            _chatSessions.updateMessageEntry(
              entryId: assistantEntryId,
              message: checkpointMessage,
            ),
          );
        }
      } else {
        aiMessageIndex = _messages.length;
        aiTimelineIndex = _timelineItems.length;

        // Insert an empty assistant message immediately; the streaming cursor
        // below is the visible waiting indicator until content arrives.
        setState(() {
          _appendTimelineMessage(
            ChatMessage(text: '', isUser: false, timestamp: startTime),
            entryId: null,
          );
          _streamingMessageIndex = aiMessageIndex;
          _isLoading = false;
          _isStreaming = true;
          _isReconnectingStream = false;
          _isWaitingForNetwork = false;
        });
        _startStreamingDurationTimer(startTime);

        assistantEntryId = await _chatSessions.appendMessageEntry(
          sessionId: session.id,
          type: ChatTimelineEntryType.assistantMessage,
          message: ChatMessage(text: '', isUser: false, timestamp: startTime),
        );
      }
      final activeAssistantEntryId = assistantEntryId;
      DateTime lastPersistedAssistantAt = DateTime.now();

      if (assistantEntryId != null && aiTimelineIndex != null) {
        setState(() {
          _replaceTimelineEntryIdAt(aiTimelineIndex!, assistantEntryId!);
        });
      }

      final currentModel = AIModels.getModelById(_selectedModel);
      final supportsReasoning = currentModel?.supportsThinking ?? false;
      final supportsToolCall = currentModel?.supportsToolCall ?? false;

      bool firstChunk = true;
      int chunkCount = 0;
      String lastDisplayedText = '';
      bool hasReceivedContent = false;
      bool hasReceivedToolCalls = false;
      const networkInactivityTimeout = Duration(seconds: 12);
      const postToolInactivityTimeout = Duration(seconds: 90);
      const activeToolInactivityTimeout = Duration(minutes: 20);

      Stream<ChatStreamChunk> createStream() {
        if (supportsReasoning || supportsToolCall) {
          return _provider.sendMessageStreamWithThinking(
            providerMessageText,
            enableToolCalls: supportsToolCall,
          );
        }

        return _provider
            .sendMessageStream(providerMessageText)
            .map((content) => ChatStreamChunk(content: content));
      }

      Duration currentStreamTimeout() {
        final hasActiveTool = messageBlocks.any(
          (block) =>
              block.type == ChatMessageBlockType.toolCall &&
              !(block.toolCall?.isComplete ?? block.isComplete),
        );
        if (hasReceivedToolCalls && hasActiveTool) {
          return activeToolInactivityTimeout;
        }

        final latestCompletedTool = _latestCompletedTool(
          messageBlocks,
          successfulOnly: false,
        );
        final waitingForModelAfterTool =
            hasReceivedToolCalls &&
            latestCompletedTool != null &&
            !_hasResponseAfterToolBlock(messageBlocks, latestCompletedTool.id);
        if (waitingForModelAfterTool) {
          return postToolInactivityTimeout;
        }

        return networkInactivityTimeout;
      }

      final retryConversationState = _provider.exportConversationState();
      var reconnectAttempt = 0;

      while (true) {
        try {
          if (reconnectAttempt > 0) {
            _provider.loadConversationState(retryConversationState);
          }

          final iterator = StreamIterator<ChatStreamChunk>(createStream());
          try {
            while (await iterator.moveNext().timeout(currentStreamTimeout())) {
              final chunk = iterator.current;
              if (_isReconnectingStream) {
                setState(() {
                  _isReconnectingStream = false;
                  _isWaitingForNetwork = false;
                });
              }

              responseMetadata = mergeResponseMetadata(
                responseMetadata,
                chunk.responseMetadata,
              );

              // Bump the token UI revision when new usage metadata arrives
              // so the context-limit indicator refreshes in near-realtime.
              final chunkMeta = chunk.responseMetadata;
              if (chunkMeta != null &&
                  (chunkMeta.containsKey('workflowTotalTokens') ||
                      chunkMeta.containsKey('totalTokens') ||
                      chunkMeta.containsKey('promptTokens') ||
                      chunkMeta.containsKey('usageRounds'))) {
                _tokenUiRevision.value++;
              }

              if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
                _appendThinkingBlock(messageBlocks, chunk.thinking!);
              }

              if (chunk.content.isNotEmpty) {
                hasReceivedContent = true;
                _appendResponseBlock(messageBlocks, chunk.content);
              }

              if (chunk.toolCall != null) {
                hasReceivedToolCalls = true;

                _upsertToolBlock(messageBlocks, chunk.toolCall!);
              }

              fullResponse += chunk.content;

              if (chunk.isThinkingComplete) {
                _markLatestThinkingBlockComplete(messageBlocks);
              }

              bool shouldReplacePlaceholder = false;
              if (firstChunk) {
                if (hasReceivedToolCalls) {
                  shouldReplacePlaceholder = true;
                } else if (hasReceivedContent) {
                  shouldReplacePlaceholder = true;
                } else if (!supportsReasoning &&
                    !supportsToolCall &&
                    hasReceivedContent) {
                  shouldReplacePlaceholder = true;
                }
              }

              chunkCount++;
              final hasUserVisibleUpdate =
                  chunk.content.isNotEmpty || chunk.toolCall != null;
              final shouldUpdate =
                  hasUserVisibleUpdate &&
                  !shouldReplacePlaceholder &&
                  (chunkCount % 3 == 0 ||
                      chunk.content.length > 50 ||
                      fullResponse.length - lastDisplayedText.length > 100 ||
                      chunk.isToolCallComplete ||
                      (chunk.toolCall != null &&
                          (chunk.toolCall!.status == ToolCallStatus.calling ||
                              chunk.toolCall!.status ==
                                  ToolCallStatus.completed ||
                              chunk.toolCall!.status ==
                                  ToolCallStatus.failed)));

              if (shouldUpdate) {
                lastDisplayedText = fullResponse;
                final checkpointMessage = _buildAssistantMessageFromBlocks(
                  blocks: messageBlocks,
                  timestamp: startTime,
                  modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
                  responseMetadata: responseMetadata.isEmpty
                      ? null
                      : responseMetadata,
                );
                // Update internal state without a full setState — the
                // ValueListenableBuilder on _streamingBubble rebuilds only
                // the active streaming bubble, not the whole screen.
                _replaceTimelineMessageAt(aiTimelineIndex!, checkpointMessage);
                // Tool-state transitions must reach the UI immediately.
                // Regular text/thinking chunks are throttled: buffered here
                // and flushed by the timer at most every 100 ms, capping
                // markdown re-parses to ~10/s.
                final isImmediateEvent =
                    chunk.isThinkingComplete ||
                    chunk.isToolCallComplete ||
                    (chunk.toolCall != null &&
                        (chunk.toolCall!.status == ToolCallStatus.calling ||
                            chunk.toolCall!.status ==
                                ToolCallStatus.completed ||
                            chunk.toolCall!.status == ToolCallStatus.failed));
                if (isImmediateEvent) {
                  _pendingStreamMessage = null;
                  _streamingBubble.value = checkpointMessage;
                  _scheduleScrollToBottom();
                } else {
                  _pendingStreamMessage = checkpointMessage;
                  _streamingThrottleTimer ??= Timer.periodic(
                    const Duration(milliseconds: 100),
                    (_) {
                      final msg = _pendingStreamMessage;
                      if (msg != null && mounted) {
                        _streamingBubble.value = msg;
                        _pendingStreamMessage = null;
                        _scheduleScrollToBottom();
                      }
                    },
                  );
                }
                if (activeAssistantEntryId != null &&
                    (chunk.isToolCallComplete ||
                        DateTime.now().difference(lastPersistedAssistantAt) >
                            const Duration(seconds: 2))) {
                  lastPersistedAssistantAt = DateTime.now();
                  unawaited(
                    _chatSessions.updateMessageEntry(
                      entryId: activeAssistantEntryId,
                      message: checkpointMessage,
                    ),
                  );
                }
              }

              // Premium haptic feedback during streaming — the lightest tap
              // for every response text chunk while the chat screen is visible
              // and the app is in the foreground, including intermediate
              // tool-result responses before the final one.
              if (chunk.content.isNotEmpty) {
                unawaited(
                  VibrationManager.instance.triggerStreamingFeedback(
                    isForeground: !_isAppInBackground && _isOnChatScreen,
                  ),
                );
              }

              if (shouldReplacePlaceholder) {
                firstChunk = false;
                lastDisplayedText = fullResponse;
                final checkpointMessage = _buildAssistantMessageFromBlocks(
                  blocks: messageBlocks,
                  timestamp: startTime,
                  modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
                  responseMetadata: responseMetadata.isEmpty
                      ? null
                      : responseMetadata,
                );
                _replaceTimelineMessageAt(aiTimelineIndex!, checkpointMessage);
                // First content always pushes immediately; discard any older
                // buffered update that the shouldUpdate block may have queued.
                _pendingStreamMessage = null;
                _streamingBubble.value = checkpointMessage;
                _scheduleScrollToBottom();
                if (activeAssistantEntryId != null) {
                  lastPersistedAssistantAt = DateTime.now();
                  unawaited(
                    _chatSessions.updateMessageEntry(
                      entryId: activeAssistantEntryId,
                      message: checkpointMessage,
                    ),
                  );
                }

                // First-content haptic already covered by the per-chunk
                // trigger above; no duplicate needed here.
              }
            }
          } finally {
            await iterator.cancel();
          }

          if (_isReconnectingStream) {
            setState(() {
              _isReconnectingStream = false;
              _isWaitingForNetwork = false;
            });
          }
          break;
        } catch (error) {
          if (error is CancelledException) {
            rethrow;
          }

          _provider.cancelRequest();
          if (!_isRetryableNetworkError(error) ||
              reconnectAttempt >= _maxReconnectAttempts) {
            if (_isReconnectingStream) {
              setState(() {
                _isReconnectingStream = false;
                _isWaitingForNetwork = false;
              });
            }
            if (reconnectAttempt >= _maxReconnectAttempts) {
              throw _buildReconnectFailure(error);
            }
            rethrow;
          }

          final waitedForNetwork = await _waitForNetworkBeforeReconnect(error);
          if (!mounted) {
            return;
          }
          if (waitedForNetwork) {
            _provider.loadConversationState(retryConversationState);
          }

          reconnectAttempt += 1;
          messageBlocks = _blocksForStreamRetry(messageBlocks);
          fullResponse = _responseTextFromBlocks(messageBlocks);
          lastDisplayedText = fullResponse;
          firstChunk = true;
          chunkCount = 0;
          hasReceivedContent = fullResponse.trim().isNotEmpty;
          hasReceivedToolCalls = messageBlocks.any(
            (block) => block.type == ChatMessageBlockType.toolCall,
          );

          final checkpointMessage = _buildAssistantMessageFromBlocks(
            blocks: messageBlocks,
            timestamp: startTime,
            modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
            responseMetadata: responseMetadata.isEmpty
                ? null
                : responseMetadata,
          );
          _replaceTimelineMessageAt(aiTimelineIndex!, checkpointMessage);
          _streamingBubble.value = checkpointMessage;
          setState(() {
            _isReconnectingStream = true;
            _isWaitingForNetwork = false;
          });
          _scheduleScrollToBottom();

          await Future<void>.delayed(_reconnectDelays[reconnectAttempt - 1]);
        }
      }

      responseMetadata = mergeResponseMetadata(
        responseMetadata,
        _provider.lastResponseMetadata,
      );

      responseTimeMs = DateTime.now().difference(startTime).inMilliseconds;
      tokenCount = (fullResponse.length / 4).ceil();
      final tokensPerSecond = responseTimeMs > 0
          ? (tokenCount / (responseTimeMs / 1000))
          : 0.0;

      _markAllOpenTextBlocksComplete(messageBlocks);
      final willAutoContinueToolTurn =
          mounted &&
          automaticToolContinuationDepth < _maxAutomaticToolContinuations &&
          _shouldAutoContinueAfterToolBlocks(messageBlocks);
      final postToolFallback = willAutoContinueToolTurn
          ? null
          : _buildPostToolCompletionFallback(messageBlocks);
      if (postToolFallback != null && postToolFallback.isNotEmpty) {
        _appendResponseBlock(messageBlocks, postToolFallback);
        _markAllOpenTextBlocksComplete(messageBlocks);
      }

      finalAssistantMessage = _buildAssistantMessageFromBlocks(
        blocks: messageBlocks,
        timestamp: DateTime.now(),
        modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
        tokensUsed: tokenCount,
        tokensPerSec: tokensPerSecond,
        responseTime: Duration(milliseconds: responseTimeMs),
        responseMetadata: responseMetadata.isEmpty ? null : responseMetadata,
      );
      // Stop the throttle timer so no buffered chunk overwrites the final
      // message after we push it below.
      _stopStreamingThrottleTimer();
      // Push the final message through the VLB before updating timeline state
      // so the typewriter always receives the complete response target.
      _streamingBubble.value = finalAssistantMessage;
      setState(() {
        _replaceTimelineMessageAt(aiTimelineIndex!, finalAssistantMessage!);
        if (!willAutoContinueToolTurn) {
          _isStreaming = false;
        }
        _isReconnectingStream = false;
        _isWaitingForNetwork = false;
      });
      // The timeline now owns the final message; the VLB stays mounted only
      // until the buffered typewriter reveal catches up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _streamingBubble.value = null;
      });
      if (!willAutoContinueToolTurn) {
        _stopStreamingDurationTimer();
        final shouldNotifyResponseComplete =
            _isAppInBackground || _isAppInactive || !_isOnChatScreen;
        if (shouldNotifyResponseComplete) {
          final toolCallCount = _countToolCallsInMessage(finalAssistantMessage);
          final responseText = finalAssistantMessage.text;
          final summary = responseText.isNotEmpty
              ? responseText
              : 'Response complete. ${toolCallCount > 0 ? '$toolCallCount tool call(s) executed.' : ''}';
          final responsePayload = ResponseReadyPayload(
            chatId: _activeSession?.id ?? '',
            modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
            toolCallCount: toolCallCount,
            status: 'success',
            summary: summary,
            timestamp: DateTime.now(),
            hasError: false,
          );
          unawaited(
            NotificationService.instance.showResponseReadyNotification(
              responsePayload,
              appInBackground: shouldNotifyResponseComplete,
            ),
          );
        }
        if (!_isAppInBackground && _isOnChatScreen) {
          // Medium haptic removed; keep only streaming haptics.
        }
      }
      if (activeAssistantEntryId != null) {
        await _chatSessions.updateMessageEntry(
          entryId: activeAssistantEntryId,
          message: finalAssistantMessage,
        );
      }
    } on TimeoutException catch (_) {
      _provider.cancelRequest();
      final blocks = _cloneBlocks(
        aiMessageIndex != null && aiMessageIndex < _messages.length
            ? _getMessageBlocks(_messages[aiMessageIndex])
            : messageBlocks,
      );

      _appendResponseBlock(
        blocks,
        '\n\nThe model stopped responding before it finished the reply.',
      );
      _markAllOpenTextBlocksComplete(blocks);

      responseTimeMs = DateTime.now().difference(startTime).inMilliseconds;
      tokenCount = (fullResponse.length / 4).ceil();
      final tokensPerSecond = responseTimeMs > 0
          ? (tokenCount / (responseTimeMs / 1000))
          : 0.0;

      finalAssistantMessage = _buildAssistantMessageFromBlocks(
        blocks: blocks,
        timestamp: DateTime.now(),
        modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
        tokensUsed: tokenCount,
        tokensPerSec: tokensPerSecond,
        responseTime: Duration(milliseconds: responseTimeMs),
        responseMetadata: responseMetadata.isEmpty ? null : responseMetadata,
      );

      _stopStreamingThrottleTimer();
      _streamingBubble.value = finalAssistantMessage;
      setState(() {
        _replaceTimelineMessageAt(aiTimelineIndex!, finalAssistantMessage!);
        _isLoading = false;
        _isStreaming = false;
        _isReconnectingStream = false;
        _isWaitingForNetwork = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _streamingBubble.value = null;
      });
      _stopStreamingDurationTimer();
      if (assistantEntryId != null) {
        await _chatSessions.updateMessageEntry(
          entryId: assistantEntryId,
          message: finalAssistantMessage,
        );
      }
    } on CancelledException catch (_) {
      final lastMessage = _messages.isNotEmpty && !_messages.last.isUser
          ? _messages.last
          : ChatMessage(text: '', isUser: false, timestamp: DateTime.now());
      final blocks = _cloneBlocks(_getMessageBlocks(lastMessage));
      final wasPlaceholder =
          lastMessage.text.trim().isEmpty ||
          lastMessage.text == 'Just a sec ...' ||
          (_responseTextFromBlocks(blocks).trim().isEmpty &&
              blocks.length == 1 &&
              blocks.first.type == ChatMessageBlockType.thinking &&
              (blocks.first.text ?? '').trim() == 'Thinking');
      _markOpenToolBlocksCancelled(blocks);
      _appendResponseBlock(
        blocks,
        wasPlaceholder || lastMessage.text.isEmpty
            ? 'Request Cancelled'
            : '\n\nRequest Cancelled',
      );
      _markAllOpenTextBlocksComplete(blocks);
      finalAssistantMessage = _buildAssistantMessageFromBlocks(
        blocks: blocks,
        timestamp: DateTime.now(),
        modelUsed: lastMessage.modelUsed,
        tokensUsed: lastMessage.tokensUsed,
        tokensPerSec: lastMessage.tokensPerSec,
        responseTime: lastMessage.responseTime,
        responseMetadata: lastMessage.responseMetadata,
      );

      _stopStreamingThrottleTimer();
      _streamingBubble.value = finalAssistantMessage;
      setState(() {
        _isLoading = false;
        _isStreaming = false;
        _isReconnectingStream = false;
        _isWaitingForNetwork = false;
        _replaceTimelineMessageAt(aiTimelineIndex!, finalAssistantMessage!);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _streamingBubble.value = null;
      });
      _stopStreamingDurationTimer();
      if (assistantEntryId != null) {
        await _chatSessions.updateMessageEntry(
          entryId: assistantEntryId,
          message: finalAssistantMessage,
        );
      }
    } catch (e) {
      final errorMessage = _buildAssistantErrorMessage(e);

      final blocks = _cloneBlocks(
        aiMessageIndex != null && aiMessageIndex < _messages.length
            ? _getMessageBlocks(_messages[aiMessageIndex])
            : messageBlocks,
      );
      final hasExistingResponse = _responseTextFromBlocks(
        blocks,
      ).trim().isNotEmpty;
      final hasOnlyPlaceholder =
          blocks.isEmpty ||
          (blocks.length == 1 &&
              blocks.first.type == ChatMessageBlockType.response &&
              ((blocks.first.text ?? '').trim().isEmpty ||
                  (blocks.first.text ?? '').trim() == 'Just a sec ...'));
      final shouldKeepPartialResponse =
          hasExistingResponse && _isRecoverableStreamInterruption(e);
      shouldSilentlyContinueAfterToolError =
          automaticToolContinuationDepth <
              _maxSilentPostToolErrorContinuations &&
          _shouldSilentlyContinueAfterPostToolError(e, blocks);

      if (shouldSilentlyContinueAfterToolError || shouldKeepPartialResponse) {
        _markAllOpenTextBlocksComplete(blocks);
      } else if (hasOnlyPlaceholder) {
        blocks
          ..clear()
          ..add(
            ChatMessageBlock(
              id: _newBlockId('response'),
              type: ChatMessageBlockType.response,
              text: errorMessage,
              isComplete: true,
            ),
          );
      } else {
        _appendResponseBlock(
          blocks,
          hasExistingResponse ? '\n\n$errorMessage' : errorMessage,
        );
        _markAllOpenTextBlocksComplete(blocks);
      }

      responseTimeMs = DateTime.now().difference(startTime).inMilliseconds;
      tokenCount = (fullResponse.length / 4).ceil();
      final tokensPerSecond = responseTimeMs > 0
          ? (tokenCount / (responseTimeMs / 1000))
          : 0.0;

      finalAssistantMessage = _buildAssistantMessageFromBlocks(
        blocks: blocks,
        timestamp: DateTime.now(),
        modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
        tokensUsed: tokenCount,
        tokensPerSec: tokensPerSecond,
        responseTime: Duration(milliseconds: responseTimeMs),
        responseMetadata: responseMetadata.isEmpty ? null : responseMetadata,
      );

      final streamingEndsNow = !shouldSilentlyContinueAfterToolError;
      if (streamingEndsNow) {
        _stopStreamingThrottleTimer();
        _streamingBubble.value = finalAssistantMessage;
      }
      setState(() {
        if (aiTimelineIndex == null ||
            aiTimelineIndex >= _timelineItems.length) {
          _appendTimelineMessage(
            finalAssistantMessage!,
            entryId: assistantEntryId,
          );
        } else {
          _replaceTimelineMessageAt(aiTimelineIndex, finalAssistantMessage!);
        }
        _isLoading = false;
        if (shouldSilentlyContinueAfterToolError) {
          _isStreaming = true;
          _streamingMessageIndex = aiMessageIndex;
        } else if (streamingEndsNow) {
          _isStreaming = false;
        }
        _isReconnectingStream = false;
        _isWaitingForNetwork = false;
      });
      if (streamingEndsNow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _streamingBubble.value = null;
        });
      }
      if (!shouldSilentlyContinueAfterToolError) {
        _stopStreamingDurationTimer();
      }
      if (assistantEntryId != null) {
        await _chatSessions.updateMessageEntry(
          entryId: assistantEntryId,
          message: finalAssistantMessage,
        );
      }
    }

    if (mounted && aiTimelineIndex != null && assistantEntryId != null) {
      final timelineIndex = aiTimelineIndex;
      final entryId = assistantEntryId;
      setState(() {
        _replaceTimelineEntryIdAt(timelineIndex, entryId);
      });
    }

    if (removeProviderMessageFromHistory) {
      _removeProviderUserMessageFromHistory(providerMessageText);
    }
    await _syncProviderStateToSession();
    final shouldContinueToolTurn =
        mounted &&
        automaticToolContinuationDepth < _maxAutomaticToolContinuations &&
        aiMessageIndex != null &&
        (shouldSilentlyContinueAfterToolError ||
            _shouldAutoContinueAfterToolTurn(finalAssistantMessage));
    if (shouldContinueToolTurn) {
      await _sendMessage(
        appendUserMessage: false,
        providerMessageOverride: _continueInterruptedResponsePrompt,
        removeProviderMessageFromHistory: true,
        replaceAssistantMessageIndex: aiMessageIndex,
        automaticToolContinuationDepth: automaticToolContinuationDepth + 1,
      );
      return;
    }

    await _handlePostTurnSessionState();
    _unfocusComposer();
    _scrollToBottom();
  }

  Future<void> _handleComposerSubmit() async {
    await _sendMessage();
  }

  Future<void> _confirmAndCancelRequest() async {
    if (!mounted) return;
    if (!_isBusyBlockingNavigation) return;
    if (_isShowingStopConfirmation) return;

    _isShowingStopConfirmation = true;
    final theme = Theme.of(context);
    try {
      final shouldStop = await ResponsiveInfoSheet.show<bool>(
        context,
        title: 'Stop Response?',
        headerIcon: Icon(
          CupertinoIcons.stop_circle_fill,
          color: theme.colorScheme.onPrimary,
          size: 28,
        ),
        gradientColors: [
          theme.colorScheme.primary,
          theme.colorScheme.primary.withValues(alpha: 0.78),
        ],
        contentWidgets: [
          Text(
            'Budget AI is still working on a reply.',
            style: AppTheme.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Stopping keeps the partial response in this chat. Queued follow-ups will run after the current request stops.',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: theme.colorScheme.outline),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Keep Working'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Stop Response'),
                ),
              ),
            ],
          ),
        ],
      );

      if (shouldStop == true) {
        _cancelRequest();
      }
    } finally {
      _isShowingStopConfirmation = false;
    }
  }

  void _cancelRequest() {
    _provider.cancelRequest();
  }

  bool get _canSubmitCurrentMessage {
    final hasText = _messageController.text.trim().isNotEmpty;
    return !_isStreaming && hasText;
  }

  bool get _isResponseInProgress => _isLoading || _isStreaming;

  bool get _isBusyBlockingNavigation => _isResponseInProgress;

  bool get _hasChatStateToClear {
    return _activeSession != null ||
        _messages.isNotEmpty ||
        _timelineItems.isNotEmpty ||
        _messageController.text.trim().isNotEmpty;
  }

  Future<bool> _showLeaveWhileStreamingSheet() async {
    if (!_isBusyBlockingNavigation) {
      return true;
    }

    if (_isShowingLeaveConfirmation) {
      return false;
    }

    _isShowingLeaveConfirmation = true;
    final theme = Theme.of(context);

    try {
      final shouldLeave = await ResponsiveInfoSheet.show<bool>(
        context,
        title: 'Stop Response?',
        headerIcon: Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          color: theme.colorScheme.onPrimary,
          size: 28,
        ),
        gradientColors: [
          theme.colorScheme.primary,
          theme.colorScheme.primary.withValues(alpha: 0.78),
        ],
        contentWidgets: [
          Text(
            'Budget AI is still working on a reply.',
            style: AppTheme.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'If you go back now, the current response will be stopped. Do you want to leave this chat?',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: theme.colorScheme.outline),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Stop And Go Back'),
                ),
              ),
            ],
          ),
        ],
      );

      return shouldLeave ?? false;
    } finally {
      _isShowingLeaveConfirmation = false;
    }
  }

  Future<void> _attemptBackNavigation([Object? result]) async {
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState?.isDrawerOpen ?? false) {
      scaffoldState?.closeDrawer();
      return;
    }

    if (_isBusyBlockingNavigation) {
      final shouldLeave = await _showLeaveWhileStreamingSheet();
      if (!mounted || !shouldLeave) {
        return;
      }

      _cancelRequest();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isStreaming = false;
          _isWaitingForNetwork = false;
        });
      }
    }

    if (!mounted) return;
    if (_hasChatStateToClear) {
      await _resetToFreshDraft();
      return;
    }

    final shouldClose = await _showExitAppSheet();
    if (!mounted || shouldClose != true) return;
    await SystemNavigator.pop();
  }

  Future<bool> _showExitAppSheet() async {
    final theme = Theme.of(context);
    final result = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Close Budget AI?',
      headerIcon: Icon(
        CupertinoIcons.square_arrow_left,
        color: AppTheme.readableOn(theme.colorScheme.primary),
        size: 28,
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'You are already on a new chat.',
          style: AppTheme.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Do you want to close the app?',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(color: theme.colorScheme.outline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ],
    );
    return result ?? false;
  }

  String? _formatToolResult(dynamic result) {
    if (result == null) return null;
    return truncateToolPayloadForStorage(result);
  }

  String _newBlockId(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_messages.length}';
  }

  List<ChatMessageBlock> _cloneBlocks(List<ChatMessageBlock> blocks) {
    return List<ChatMessageBlock>.from(blocks);
  }

  void _completeLatestTextBlock(List<ChatMessageBlock> blocks) {
    for (int i = blocks.length - 1; i >= 0; i--) {
      final block = blocks[i];
      final isTextBlock =
          block.type == ChatMessageBlockType.thinking ||
          block.type == ChatMessageBlockType.response;
      if (isTextBlock && !block.isComplete) {
        blocks[i] = block.copyWith(isComplete: true);
        return;
      }
    }
  }

  void _markLatestThinkingBlockComplete(List<ChatMessageBlock> blocks) {
    for (int i = blocks.length - 1; i >= 0; i--) {
      final block = blocks[i];
      if (block.type == ChatMessageBlockType.thinking && !block.isComplete) {
        final completedBlock = block.copyWith(isComplete: true);
        if (_isDuplicateCompletedThinkingBlock(blocks, i, completedBlock)) {
          blocks.removeAt(i);
        } else {
          blocks[i] = completedBlock;
        }
        return;
      }
    }
  }

  bool _isDuplicateCompletedThinkingBlock(
    List<ChatMessageBlock> blocks,
    int candidateIndex,
    ChatMessageBlock candidate,
  ) {
    final candidateText = _normalizeThinkingForComparison(candidate.text);
    if (candidateText.isEmpty) return false;

    for (int i = 0; i < candidateIndex; i++) {
      final block = blocks[i];
      if (block.type != ChatMessageBlockType.thinking) continue;
      final existingText = _normalizeThinkingForComparison(block.text);
      if (existingText == candidateText) {
        return true;
      }
    }
    return false;
  }

  String _normalizeThinkingForComparison(String? text) {
    return (text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _markAllOpenTextBlocksComplete(List<ChatMessageBlock> blocks) {
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isTextBlock =
          block.type == ChatMessageBlockType.thinking ||
          block.type == ChatMessageBlockType.response;
      if (isTextBlock && !block.isComplete) {
        final completedBlock = block.copyWith(isComplete: true);
        if (block.type == ChatMessageBlockType.thinking &&
            _isDuplicateCompletedThinkingBlock(blocks, i, completedBlock)) {
          blocks.removeAt(i);
          i--;
        } else {
          blocks[i] = completedBlock;
        }
      }
    }
  }

  void _markOpenToolBlocksCancelled(List<ChatMessageBlock> blocks) {
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final toolCall = block.toolCall;
      if (block.type != ChatMessageBlockType.toolCall || toolCall == null) {
        continue;
      }

      if (toolCall.status == ToolCallStatus.completed ||
          toolCall.status == ToolCallStatus.failed ||
          toolCall.status == ToolCallStatus.cancelled) {
        continue;
      }

      blocks[i] = block.copyWith(
        toolCall: toolCall.copyWith(
          status: ToolCallStatus.cancelled,
          result: toolCall.result ?? 'Tool call cancelled',
          isComplete: true,
        ),
        isComplete: true,
      );
    }
  }

  bool _hasOpenToolCall(List<ChatMessageBlock> blocks) {
    return blocks.any(
      (block) =>
          block.type == ChatMessageBlockType.toolCall &&
          !(block.toolCall?.isComplete ?? block.isComplete),
    );
  }

  void _appendThinkingBlock(List<ChatMessageBlock> blocks, String text) {
    if (blocks.isNotEmpty &&
        blocks.last.type == ChatMessageBlockType.thinking &&
        !blocks.last.isComplete) {
      final last = blocks.last;
      if ((last.text ?? '').trim() == 'Thinking') {
        blocks[blocks.length - 1] = last.copyWith(text: text);
        return;
      }
      blocks[blocks.length - 1] = last.copyWith(
        text: '${last.text ?? ''}$text',
      );
      return;
    }

    _completeLatestTextBlock(blocks);

    blocks.add(
      ChatMessageBlock(
        id: _newBlockId('thinking'),
        type: ChatMessageBlockType.thinking,
        text: text,
      ),
    );
  }

  void _appendResponseBlock(List<ChatMessageBlock> blocks, String text) {
    if (blocks.isNotEmpty &&
        blocks.last.type == ChatMessageBlockType.response &&
        !blocks.last.isComplete) {
      final last = blocks.last;
      blocks[blocks.length - 1] = last.copyWith(
        text: '${last.text ?? ''}$text',
      );
      return;
    }

    _markLatestThinkingBlockComplete(blocks);

    blocks.add(
      ChatMessageBlock(
        id: _newBlockId('response'),
        type: ChatMessageBlockType.response,
        text: text,
      ),
    );
  }

  void _upsertToolBlock(List<ChatMessageBlock> blocks, ToolCallChunk chunk) {
    _completeLatestTextBlock(blocks);

    final toolName = (chunk.name?.trim().isNotEmpty ?? false)
        ? chunk.name!.trim()
        : 'Tool call';

    final toolCall = ToolCall(
      id: chunk.id,
      name: toolName,
      arguments: chunk.arguments ?? {},
      rawArguments: chunk.rawArguments,
      result: _formatToolResult(chunk.result),
      status: chunk.status,
      isComplete:
          chunk.status == ToolCallStatus.completed ||
          chunk.status == ToolCallStatus.failed,
    );

    final existingIndex = blocks.indexWhere(
      (block) =>
          block.type == ChatMessageBlockType.toolCall &&
          block.toolCall?.id == chunk.id,
    );

    if (existingIndex >= 0) {
      final existing = blocks[existingIndex];
      blocks[existingIndex] = existing.copyWith(
        toolCall: toolCall,
        isComplete: toolCall.isComplete,
      );
      return;
    }

    blocks.add(
      ChatMessageBlock(
        id: 'tool_${chunk.id}',
        type: ChatMessageBlockType.toolCall,
        toolCall: toolCall,
        isComplete: toolCall.isComplete,
      ),
    );
  }

  /// Process pending notification actions that arrived while the app was in
  /// the background or another screen.
  void _processPendingNotificationActions() {
    final actions = NotificationService.instance.flushPendingActions();
    for (final action in actions) {
      final actionId = action['actionId'] ?? '';
      final payload = action['payload'] ?? '';
      if (payload.isEmpty) continue;

      final payloadType = NotificationService.instance.parsePayloadType(
        payload,
      );
      if (payloadType == NotificationPayloadType.responseReady ||
          actionId == NotificationActions.openApp ||
          actionId == NotificationActions.dismiss) {
        // Nothing to do; opening the app already navigates here.
      }
    }
  }

  String _responseTextFromBlocks(List<ChatMessageBlock> blocks) {
    return blocks
        .where(
          (block) =>
              block.type == ChatMessageBlockType.response &&
              (block.text?.isNotEmpty ?? false),
        )
        .map((block) => block.text!)
        .join();
  }

  String _finalResponseTextFromBlocks(List<ChatMessageBlock> blocks) {
    final hasActivityBlocks = blocks.any(
      (block) => block.type != ChatMessageBlockType.response,
    );
    if (!hasActivityBlocks) {
      return _responseTextFromBlocks(blocks).trim();
    }

    final lastActivityIndex = blocks.lastIndexWhere(
      (block) => block.type != ChatMessageBlockType.response,
    );
    if (lastActivityIndex < 0) {
      return _responseTextFromBlocks(blocks).trim();
    }

    return blocks
        .skip(lastActivityIndex + 1)
        .where(
          (block) =>
              block.type == ChatMessageBlockType.response &&
              (block.text?.isNotEmpty ?? false),
        )
        .map((block) => block.text!)
        .join()
        .trim();
  }

  String _shareableAssistantText(ChatMessage message, int messageIndex) {
    final isFinalInTurn =
        messageIndex == _messages.length - 1 ||
        _messages[messageIndex + 1].isUser;
    // Reasoning blocks remain in the message model for provider continuity,
    // but are intentionally never rendered as user-facing chat content.
    final blocks = _getEffectiveBlocks(
      messageIndex,
      isFinalInTurn,
    ).where((block) => block.type != ChatMessageBlockType.thinking).toList();
    return _finalResponseTextFromBlocks(blocks);
  }

  String? _thinkingTextFromBlocks(List<ChatMessageBlock> blocks) {
    final thinkingText = blocks
        .where(
          (block) =>
              block.type == ChatMessageBlockType.thinking &&
              (block.text?.isNotEmpty ?? false),
        )
        .map((block) => block.text!)
        .join('\n\n');

    return thinkingText.isEmpty ? null : thinkingText;
  }

  List<ToolCall>? _toolCallsFromBlocks(List<ChatMessageBlock> blocks) {
    final toolCalls = blocks
        .where((block) => block.type == ChatMessageBlockType.toolCall)
        .map((block) => block.toolCall)
        .whereType<ToolCall>()
        .toList();

    return toolCalls.isEmpty ? null : toolCalls;
  }

  ChatMessage _buildAssistantMessageFromBlocks({
    required List<ChatMessageBlock> blocks,
    required DateTime timestamp,
    String? modelUsed,
    int? tokensUsed,
    double? tokensPerSec,
    Duration? responseTime,
    Map<String, dynamic>? responseMetadata,
  }) {
    final toolCalls = _toolCallsFromBlocks(blocks);
    final hasOpenThinking = blocks.any(
      (block) =>
          block.type == ChatMessageBlockType.thinking && !block.isComplete,
    );
    final hasOpenTool = blocks.any(
      (block) =>
          block.type == ChatMessageBlockType.toolCall &&
          !(block.toolCall?.isComplete ?? block.isComplete),
    );

    return ChatMessage(
      text: _responseTextFromBlocks(blocks),
      isUser: false,
      timestamp: timestamp,
      thinkingText: _thinkingTextFromBlocks(blocks),
      isThinkingComplete: !hasOpenThinking,
      toolCalls: toolCalls,
      isToolCallsComplete: !hasOpenTool,
      modelUsed: modelUsed,
      tokensUsed: tokensUsed,
      tokensPerSec: tokensPerSec,
      responseTime: responseTime,
      responseMetadata: responseMetadata,
      blocks: _cloneBlocks(blocks),
    );
  }

  List<ChatMessageBlock> _getMessageBlocks(ChatMessage message) {
    if (message.blocks != null && message.blocks!.isNotEmpty) {
      return message.blocks!;
    }

    final blocks = <ChatMessageBlock>[];

    if (message.thinkingText != null && message.thinkingText!.isNotEmpty) {
      blocks.add(
        ChatMessageBlock(
          id: 'legacy_thinking_${message.timestamp.microsecondsSinceEpoch}',
          type: ChatMessageBlockType.thinking,
          text: message.thinkingText,
          isComplete: message.isThinkingComplete,
        ),
      );
    }

    if (message.toolCalls != null) {
      for (final toolCall in message.toolCalls!) {
        blocks.add(
          ChatMessageBlock(
            id: 'legacy_tool_${toolCall.id ?? message.timestamp.microsecondsSinceEpoch}',
            type: ChatMessageBlockType.toolCall,
            toolCall: toolCall,
            isComplete: toolCall.isComplete,
          ),
        );
      }
    }

    if (message.text.isNotEmpty) {
      blocks.add(
        ChatMessageBlock(
          id: 'legacy_response_${message.timestamp.microsecondsSinceEpoch}',
          type: ChatMessageBlockType.response,
          text: message.text,
          isComplete: true,
        ),
      );
    }

    return blocks;
  }

  int _countToolCallsInMessage(ChatMessage? message) {
    if (message == null) return 0;
    final blocks = _getMessageBlocks(message);
    return blocks.where((b) => b.type == ChatMessageBlockType.toolCall).length;
  }

  String _buildAssistantErrorMessage(Object error) {
    if (error is ChatProviderException) {
      if (_isReconnectExhaustedMessage(error.userMessage)) {
        return error.userMessage;
      }
      final diagnostics = error.diagnosticMessage?.trim();
      if (diagnostics != null && diagnostics.isNotEmpty) {
        final formattedDiagnostics = _formatProviderDiagnostics(diagnostics);
        return 'Unable to send message.\n\n${error.userMessage}\n\nDetails:\n$formattedDiagnostics';
      }
      return 'Unable to send message.\n\n${error.userMessage}';
    }

    final normalized = error.toString().replaceFirst('Exception: ', '').trim();
    final details = normalized.isEmpty
        ? 'An unexpected error occurred while contacting ${widget.config.displayName}.'
        : normalized;

    return 'Unable to send message.\n\n$details';
  }

  /// Wraps the JSON portion after "Provider response:" in markdown ```json
  /// fences so the chat markdown renderer uses [ThemedCodeBlock].
  String _formatProviderDiagnostics(String diagnostics) {
    const prefix = 'Provider response: ';
    final idx = diagnostics.indexOf(prefix);
    if (idx == -1) return diagnostics;

    final before = diagnostics.substring(0, idx + prefix.length);
    final jsonText = diagnostics.substring(idx + prefix.length).trim();
    if (jsonText.isEmpty) return diagnostics;

    String prettyJson;
    try {
      final decoded = jsonDecode(jsonText);
      prettyJson = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      prettyJson = jsonText;
    }

    return '$before\n```json\n$prettyJson\n```';
  }

  bool _isRecoverableStreamInterruption(Object error) {
    if (error is ChatProviderException) {
      final userMessage = error.userMessage.toLowerCase();
      final debugMessage = error.debugMessage.toLowerCase();
      return _looksLikeStreamInterruption(userMessage) ||
          _looksLikeStreamInterruption(debugMessage);
    }

    return _looksLikeStreamInterruption(error.toString().toLowerCase());
  }

  bool _isRetryableNetworkError(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return true;
    }
    if (error is HttpException || error is HandshakeException) {
      return true;
    }
    if (error is ChatProviderException) {
      final userMessage = error.userMessage.toLowerCase();
      final debugMessage = error.debugMessage.toLowerCase();
      return _looksLikeNetworkError(userMessage) ||
          _looksLikeNetworkError(debugMessage);
    }

    return _looksLikeNetworkError(error.toString().toLowerCase());
  }

  bool _shouldWaitForNetworkBeforeReconnect(Object error) {
    if (NetworkReachabilityService.instance.isOffline) {
      return true;
    }

    final message = error is ChatProviderException
        ? '${error.userMessage}\n${error.debugMessage}'.toLowerCase()
        : error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('no address associated with hostname') ||
        message.contains('could not connect');
  }

  Future<bool> _waitForNetworkBeforeReconnect(Object error) async {
    if (!_shouldWaitForNetworkBeforeReconnect(error)) {
      final status = await NetworkReachabilityService.instance.refresh();
      if (status != NetworkReachabilityStatus.offline) {
        return false;
      }
    }

    if (!mounted) return false;
    if (_isAppInBackground || _isNetworkWaitingSuppressed) {
      if (_isWaitingForNetwork) {
        setState(() => _isWaitingForNetwork = false);
      }
    } else {
      setState(() {
        _isWaitingForNetwork = true;
        _isReconnectingStream = true;
      });
    }

    final restored = await NetworkReachabilityService.instance.waitUntilOnline(
      timeout: const Duration(minutes: 5),
    );

    if (mounted) {
      setState(() {
        _isWaitingForNetwork = false;
      });
    }

    return restored;
  }

  bool _shouldSilentlyContinueAfterPostToolError(
    Object error,
    List<ChatMessageBlock> blocks,
  ) {
    if (blocks.isEmpty || _hasOpenToolCall(blocks)) {
      return false;
    }

    final latestTool = _latestCompletedTool(blocks, successfulOnly: false);
    if (latestTool == null ||
        latestTool.status == ToolCallStatus.failed ||
        _hasResponseAfterToolBlock(blocks, latestTool.id)) {
      return false;
    }

    if (!_shouldAutoContinueAfterToolBlocks(blocks)) {
      return false;
    }

    final message = error is ChatProviderException
        ? '${error.userMessage}\n${error.debugMessage}'.toLowerCase()
        : error.toString().toLowerCase();
    return message.contains('request failed unexpectedly') ||
        message.contains('unexpectedly') ||
        _looksLikeNetworkError(message) ||
        _looksLikeStreamInterruption(message);
  }

  ChatProviderException _buildReconnectFailure(Object error) {
    final details = error is ChatProviderException
        ? error.userMessage
        : error.toString().replaceFirst('Exception: ', '').trim();
    final detailText = details.isEmpty ? '' : '\n\nLast error: $details';
    return ChatProviderException(
      providerName: widget.config.displayName,
      userMessage:
          'The response was interrupted after $_maxReconnectAttempts reconnect attempts.\n\n'
          'Press Continue to resume from the current conversation without adding a new user message.$detailText',
      debugMessage: error.toString(),
    );
  }

  bool _isReconnectExhaustedMessage(String message) {
    return message.contains(
          'Connection failed after $_maxReconnectAttempts attempts.',
        ) ||
        message.contains(
          'The response was interrupted after $_maxReconnectAttempts reconnect attempts.',
        );
  }

  bool _looksLikeNetworkError(String message) {
    return _looksLikeStreamInterruption(message) ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('connection error') ||
        message.contains('could not connect') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('no address associated with hostname') ||
        message.contains('connection refused') ||
        message.contains('connection aborted') ||
        message.contains('broken pipe') ||
        message.contains('clientexception') ||
        message.contains('httpexception');
  }

  bool _looksLikeStreamInterruption(String message) {
    return message.contains('connection closed while receiving data') ||
        message.contains('httpconnection closed') ||
        message.contains('connection reset') ||
        message.contains('connection closed') ||
        message.contains('stream closed') ||
        message.contains('socketexception');
  }

  List<ChatMessageBlock> _blocksForStreamRetry(List<ChatMessageBlock> blocks) {
    final lastToolIndex = blocks.lastIndexWhere(
      (block) => block.type == ChatMessageBlockType.toolCall,
    );
    if (lastToolIndex < 0) {
      return _cloneBlocks(blocks)
          .map((block) {
            if ((block.text?.trim().isEmpty ?? true) ||
                _isPlaceholderThinkingText(block.text)) {
              return null;
            }
            return block.copyWith(isComplete: true);
          })
          .whereType<ChatMessageBlock>()
          .toList();
    }

    final retryBlocks = _cloneBlocks(blocks.sublist(0, lastToolIndex + 1));
    for (var i = lastToolIndex + 1; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.type != ChatMessageBlockType.thinking) {
        continue;
      }
      if ((block.text?.trim().isEmpty ?? true) ||
          _isPlaceholderThinkingText(block.text)) {
        continue;
      }
      retryBlocks.add(block.copyWith(isComplete: true));
    }

    return retryBlocks;
  }

  List<ChatMessageBlock> _blocksForContinuingResponse(ChatMessage message) {
    final blocks = _cloneBlocks(_getMessageBlocks(message));
    return blocks
        .map((block) {
          if (block.type != ChatMessageBlockType.response) return block;
          final text = block.text ?? '';
          final cleaned = _removeContinuationFallbackText(text);
          if (cleaned.trim().isEmpty) return null;
          return block.copyWith(text: cleaned);
        })
        .whereType<ChatMessageBlock>()
        .toList();
  }

  String _removeContinuationFallbackText(String text) {
    var next = text;
    final fallbackPatterns = <RegExp>[
      RegExp(
        r'\n\nThe model stopped responding after finishing the tool call\.$',
      ),
      RegExp(
        r'\n\nThe model stopped responding before it finished the reply\.$',
      ),
      RegExp(
        r'(?:\n\n)?Unable to send message\.\n\nConnection failed after \d+ attempts\.[\s\S]*$',
      ),
      RegExp(r'(?:\n\n)?Connection failed after \d+ attempts\.[\s\S]*$'),
      RegExp(
        r'(?:\n\n)?The response was interrupted after \d+ reconnect attempts\.[\s\S]*$',
      ),
    ];

    for (final pattern in fallbackPatterns) {
      next = next.replaceFirst(pattern, '');
    }
    return next;
  }

  bool _isContinuationFallbackText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return _removeContinuationFallbackText('\n\n$trimmed').trim().isEmpty ||
        trimmed ==
            'The model stopped responding after finishing the tool call.' ||
        trimmed ==
            'The model stopped responding before it finished the reply.' ||
        _isReconnectExhaustedMessage(trimmed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _isOnChatScreen = true;
    _unfocusComposer();
    if (!_isResponseInProgress) {
      _refreshChatConfiguration();
    }
  }

  @override
  void didPushNext() {
    _isOnChatScreen = false;
    _unfocusComposer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      _isAppInactive = false;
      _suppressNetworkWaitingUntil = DateTime.now().add(
        const Duration(seconds: 3),
      );
      if (_isWaitingForNetwork && mounted) {
        setState(() => _isWaitingForNetwork = false);
      }
      NetworkReachabilityService.instance.start();
      unawaited(NetworkReachabilityService.instance.refresh());
      if (_isResponseInProgress) {
        _scrollToBottom();
      }
    } else if (state == AppLifecycleState.inactive) {
      _isAppInactive = true;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isAppInBackground = true;
      _isAppInactive = false;
      NetworkReachabilityService.instance.stop();
    }
  }

  void _handleNetworkStatusChanged() {
    if (!mounted) return;

    if (_isAppInBackground || _isNetworkWaitingSuppressed) {
      if (_isWaitingForNetwork) {
        setState(() => _isWaitingForNetwork = false);
      }
      return;
    }

    final isWaiting =
        _isResponseInProgress && NetworkReachabilityService.instance.isOffline;
    if (_isWaitingForNetwork == isWaiting) return;

    setState(() {
      _isWaitingForNetwork = isWaiting;
    });
  }

  bool get _isNetworkWaitingSuppressed {
    final until = _suppressNetworkWaitingUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _attemptBackNavigation(result);
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildHistoryDrawer(),
        drawerScrimColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.18),
        // Opening is coordinated manually so horizontal tables can reserve
        // their gestures without disabling the history swipe elsewhere.
        drawerEnableOpenDragGesture: false,
        onDrawerChanged: (isOpened) {
          if (isOpened) {
            _ensureHistorySessionsFuture();
          } else {
            _historySessionsFuture = null;
          }
        },
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleHistoryPointerDown,
          onPointerMove: _handleHistoryPointerMove,
          onPointerUp: _handleHistoryPointerUp,
          onPointerCancel: _handleHistoryPointerCancel,
          child: Stack(
            children: [
              Positioned.fill(child: _buildBody()),
              _buildTopChrome(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(child: _buildComposerFade()),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _buildInputArea(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleHistoryPointerDown(PointerDownEvent event) {
    if (_historySwipePointer != null) return;
    final drawerIsOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
    _historySwipePointer = event.pointer;
    _historySwipeEligible = !drawerIsOpen && !_tableGestureActive;
    _historySwipeDistance = 0;
    _historySwipeVerticalDistance = 0;
  }

  void _handleHistoryPointerMove(PointerMoveEvent event) {
    if (_historySwipePointer != event.pointer || !_historySwipeEligible) return;
    _historySwipeDistance += event.delta.dx;
    _historySwipeVerticalDistance += event.delta.dy;
  }

  void _handleHistoryPointerUp(PointerUpEvent event) {
    if (_historySwipePointer != event.pointer) return;
    final horizontalDistance = _historySwipeDistance;
    final verticalDistance = _historySwipeVerticalDistance.abs();
    final shouldOpen =
        _historySwipeEligible &&
        horizontalDistance >= 44 &&
        horizontalDistance > verticalDistance * 1.2;
    _resetHistorySwipe();
    if (shouldOpen) unawaited(_openHistoryScreen());
  }

  void _handleHistoryPointerCancel(PointerCancelEvent event) {
    if (_historySwipePointer == event.pointer) _resetHistorySwipe();
  }

  void _resetHistorySwipe() {
    _historySwipePointer = null;
    _historySwipeEligible = false;
    _historySwipeDistance = 0;
    _historySwipeVerticalDistance = 0;
  }

  Widget _buildTopChrome() {
    final theme = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Stack(
        children: [
          IgnorePointer(child: _buildAppBarFade(theme)),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, Platform.isIOS ? 0 : 12, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFloatingAppBarButton(
                        theme,
                        icon: CupertinoIcons.line_horizontal_3,
                        tooltip: 'Chats',
                        onPressed: _openHistoryScreen,
                      ),
                      const Spacer(),
                      _buildFloatingAppBarButton(
                        theme,
                        icon: CupertinoIcons.settings,
                        tooltip: 'Settings',
                        onPressed: _openSettingsScreen,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingAppBarButton(
    ThemeData theme, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Container(
        width: 56,
        height: 48,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
                : theme.colorScheme.onSurface.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: onPressed,
            child: Tooltip(
              message: tooltip,
              child: SizedBox(
                width: 64,
                height: 48,
                child: Icon(icon, color: theme.colorScheme.onSurface, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarFade(ThemeData theme) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.scaffoldBackgroundColor,
            theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
            theme.scaffoldBackgroundColor.withValues(alpha: 0),
          ],
          stops: const [0, 0.50, 1],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_timelineItems.isEmpty) {
      return _buildEmptyState();
    }
    return NotificationListener<MarkdownTableGestureNotification>(
      onNotification: (notification) {
        _tableGestureActive = notification.isActive;
        if (notification.isActive) _resetHistorySwipe();
        return true;
      },
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _handleChatScrollNotification,
            child: ListView.builder(
              padding: EdgeInsets.only(
                top: Platform.isIOS ? 120 : 100,
                bottom: 112,
              ),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              // Keep a modest cache around the viewport. Chat rows can contain
              // expensive markdown and tool sections, so prebuilding several
              // screens of them causes noticeable frame-time spikes.
              scrollCacheExtent: const ScrollCacheExtent.pixels(700.0),
              itemCount: _timelineItems.length,
              itemBuilder: (context, index) {
                final item = _timelineItems[index];
                // ValueKey preserves widget state (e.g. expanded/collapsed tool
                // sections) across rebuilds triggered by streaming setState calls.
                // RepaintBoundary isolates each bubble so streaming updates to the
                // last item don't repaint the entire visible list.
                // ValueListenableBuilder for the active streaming bubble means chunk
                // updates go directly to that one widget — no full-screen setState.
                final isStreamingItem =
                    item is _TimelineMessageItem &&
                    item.messageIndex == _streamingMessageIndex;
                return KeyedSubtree(
                  key: _timelineItemKey(item, index),
                  child: RepaintBoundary(
                    child: isStreamingItem
                        ? ValueListenableBuilder<ChatMessage?>(
                            valueListenable: _streamingBubble,
                            builder: (context, streamingMsg, _) {
                              final effectiveItem = streamingMsg != null
                                  ? item.copyWith(message: streamingMsg)
                                  : item;
                              return _buildTimelineItem(effectiveItem);
                            },
                          )
                        : _buildTimelineItem(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Key _timelineItemKey(_TimelineViewItem item, int index) {
    return switch (item) {
      _TimelineMessageItem() => ValueKey('message_${item.messageIndex}'),
    };
  }

  Widget _buildEmptyState() {
    return ChatEmptyState(onPromptTap: _submitSuggestedPrompt);
  }

  void _submitSuggestedPrompt(String prompt) {
    _messageController.text = prompt;
    _messageController.selection = TextSelection.collapsed(
      offset: prompt.length,
    );
    _sendMessage();
  }

  Widget _buildTimelineItem(_TimelineViewItem item) {
    switch (item) {
      case _TimelineMessageItem():
        return _buildMessageBubble(
          item.message,
          messageIndex: item.messageIndex,
        );
    }
  }

  Future<void> _openHistoryScreen() async {
    _ensureHistorySessionsFuture();
    _scaffoldKey.currentState?.openDrawer();
  }

  // Refresh sessions list in background. If we have a cache, the drawer
  // renders immediately on the first frame; the cache is swapped in when
  // fresh data arrives so the user never sees a shimmer on repeat opens.
  Future<List<ChatSessionSummary>> _ensureHistorySessionsFuture() {
    final existing = _historySessionsFuture;
    if (existing != null) return existing;
    final future = _chatSessions.listRecentSessions();
    _historySessionsFuture = future;
    future.then((sessions) {
      if (mounted) _cachedSessionSummaries = sessions;
    });
    return future;
  }

  void _closeHistoryDrawer() {
    _scaffoldKey.currentState?.closeDrawer();
  }

  Widget _buildHistoryDrawer() {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Drawer(
      width: screenWidth,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(),
      child: FutureBuilder<List<ChatSessionSummary>>(
        future: _ensureHistorySessionsFuture(),
        initialData: _cachedSessionSummaries,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return ChatHistoryLoadingScreen(onClose: _closeHistoryDrawer);
          }

          return ChatHistoryScreen(
            sessions: snapshot.data!,
            currentSessionId: _activeSession?.id,
            onClose: _closeHistoryDrawer,
            onNewChat: () {
              _closeHistoryDrawer();
              _resetToFreshDraft();
            },
            onSessionSelected: (sessionId) {
              // Start the DB load immediately; it runs during the drawer
              // close animation rather than after it.
              final preloadFuture = _chatSessions.loadSession(sessionId);
              _closeHistoryDrawer();
              _loadPersistedSession(sessionId, preloadFuture: preloadFuture);
            },
            onSessionDeleted: _deleteHistorySession,
            onSessionRenamed: _renameHistorySession,
          );
        },
      ),
    );
  }

  Future<void> _openSettingsScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    await _refreshChatConfiguration();
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final hintColor = theme.colorScheme.onSurfaceVariant;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    // Keyboard ki approx height ko threshold bana kar 0->1 factor nikalein.
    // Isse padding keyboard ke actual movement ke sath frame-by-frame sync hoti hai,
    // instead of a separate delayed 300ms AnimatedPadding tween.
    const double kKeyboardHeightApprox = 280.0;
    final double t = (bottomInset / kKeyboardHeightApprox).clamp(0.0, 1.0);

    final double horizontalPadding = 32 - (32 - 8) * t;
    final double safeAreaBottom = 32 - (32 - 12) * t;
    final isWorking = _isResponseInProgress;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: safeAreaBottom),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatWorkingComposerFrame(
              isWorking: isWorking,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(
                  minHeight: 56,
                  maxHeight: 148,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isWorking
                        ? Colors.transparent
                        : theme.brightness == Brightness.dark
                        ? theme.colorScheme.outline.withValues(alpha: 0.2)
                        : theme.colorScheme.outline.withValues(alpha: 0.06),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: IgnorePointer(
                  ignoring: isWorking,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    reverseDuration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [...previousChildren, ?currentChild],
                    ),
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      final scale = Tween<double>(
                        begin: 0.96,
                        end: 1,
                      ).animate(animation);
                      return ClipRect(
                        child: FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slide,
                            child: ScaleTransition(
                              alignment: Alignment.centerLeft,
                              scale: scale,
                              child: child,
                            ),
                          ),
                        ),
                      );
                    },
                    child: isWorking
                        ? _buildWorkingComposerContent(theme)
                        : _buildNormalComposerContent(
                            theme,
                            textColor: textColor,
                            hintColor: hintColor,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalComposerContent(
    ThemeData theme, {
    required Color textColor,
    required Color hintColor,
  }) {
    return Row(
      key: const ValueKey('normal-composer'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: 'Add',
            onPressed: () {},
            icon: Icon(
              CupertinoIcons.plus,
              size: 28,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              focusNode: _messageFocusNode,
              scrollController: _messageInputScrollController,
              cursorColor: theme.colorScheme.primary,
              controller: _messageController,
              enabled: true,
              autofocus: false,
              decoration: InputDecoration(
                hoverColor: Colors.transparent,
                hintText: 'Ask Budget AI',
                hintStyle: TextStyle(
                  color: hintColor.withValues(alpha: 0.72),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                fillColor: Colors.transparent,
              ),
              maxLines: 1,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 16, color: textColor),
            ),
          ),
        ),
        const SizedBox(width: 6),
        ValueListenableBuilder<bool>(
          valueListenable: _canSendNotifier,
          builder: (context, canSend, child) => _buildComposerSendButton(theme),
        ),
      ],
    );
  }

  Widget _buildWorkingComposerContent(ThemeData theme) {
    return Row(
      key: const ValueKey('working-composer'),
      children: [
        const SizedBox.square(
          dimension: 44,
          child: RepaintBoundary(child: ChatBudgetLoadingIndicator(size: 44)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChatShimmerText(
            text: 'Budget AI Is Working',
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposerFade() {
    final theme = Theme.of(context);
    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.scaffoldBackgroundColor.withValues(alpha: 0),
            theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
            theme.scaffoldBackgroundColor,
          ],
          stops: const [0, 0.50, 1],
        ),
      ),
    );
  }

  Widget _buildComposerSendButton(ThemeData theme) {
    if (_isResponseInProgress && !_canSubmitCurrentMessage) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _confirmAndCancelRequest,
            child: Icon(
              Icons.stop_rounded,
              color: theme.colorScheme.primary.withValues(alpha: 0.72),
            ),
          ),
        ),
      );
    }

    final canSend = _canSubmitCurrentMessage;
    final activeColor = theme.colorScheme.primary;
    final disabledColor = theme.colorScheme.primary.withValues(alpha: 0.16);
    final iconColor = canSend
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.primary.withValues(alpha: 0.56);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: canSend ? 1 : 0.65,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: canSend ? activeColor : disabledColor,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: canSend ? _handleComposerSubmit : null,
            child: Icon(CupertinoIcons.arrow_up, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, {int? messageIndex}) {
    // O(1) identity checks instead of O(n) indexOf scan.
    final isLastMessage =
        _messages.isNotEmpty && identical(message, _messages.last);
    final resolvedMessageIndex =
        messageIndex ??
        (isLastMessage
            ? _messages.length - 1
            : _messages.indexWhere((m) => identical(m, message)));

    if (message.isUser) {
      final bubbleStyle = BubbleStyleSettingsService.instance.current;
      final userTextColor = UserBubbleStyleSurface.foregroundColor(
        context,
        bubbleStyle,
      );

      Widget buildContent() {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.text.isNotEmpty)
              ExpandableUserMessageText(
                text: message.text,
                style: AppTheme.bodyMedium.copyWith(
                  color: userTextColor,
                  fontSize: 16,
                ),
              ),
          ],
        );
      }

      Widget buildCopyableUserBubble() {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: message.text.trim().isEmpty
              ? null
              : () => _copyMessage(message.text),
          child: Container(
            margin: const EdgeInsets.only(left: 12, right: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            ),
            child: UserBubbleStyleSurface(
              style: bubbleStyle,
              child: buildContent(),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: buildCopyableUserBubble(),
        ),
      );
    } else {
      // Keep the final bubble on its streaming widget path until its buffered
      // typewriter reveal has caught up, even if the network stream ended.
      final isCurrentlyStreaming =
          resolvedMessageIndex == _streamingMessageIndex;
      final isFollowedByAssistant =
          resolvedMessageIndex < _messages.length - 1 &&
          !_messages[resolvedMessageIndex + 1].isUser;
      if (isFollowedByAssistant) {
        return const SizedBox.shrink();
      }
      _shouldShowRetryContinue(message, resolvedMessageIndex);
      _shareableAssistantText(message, resolvedMessageIndex);
      _cacheUsageLabel(message.responseMetadata);

      Widget messageContent = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildToolMessageBody(
                    message,
                    resolvedMessageIndex,
                    isCurrentlyStreaming,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      return messageContent;
    }
  }

  bool _shouldShowRetryContinue(ChatMessage message, int messageIndex) {
    if (message.isUser || _isResponseInProgress) {
      return false;
    }
    final isLastAssistantInTurn =
        messageIndex == _messages.length - 1 ||
        _messages[messageIndex + 1].isUser;
    if (!isLastAssistantInTurn) {
      return false;
    }

    final blocks = _getMessageBlocks(message);
    if (blocks.isEmpty) {
      return _isReconnectExhaustedMessage(message.text);
    }

    final hasToolCalls = blocks.any(
      (block) => block.type == ChatMessageBlockType.toolCall,
    );
    if (!hasToolCalls) {
      return _isReconnectExhaustedMessage(_responseTextFromBlocks(blocks));
    }

    final lastMeaningfulIndex = blocks.lastIndexWhere((block) {
      if (block.type == ChatMessageBlockType.toolCall) return true;
      return (block.text?.trim().isNotEmpty ?? false);
    });
    if (lastMeaningfulIndex < 0) {
      return false;
    }

    final lastBlock = blocks[lastMeaningfulIndex];
    if (lastBlock.type == ChatMessageBlockType.toolCall ||
        lastBlock.type == ChatMessageBlockType.thinking) {
      return true;
    }

    final lastToolIndex = blocks.lastIndexWhere(
      (block) => block.type == ChatMessageBlockType.toolCall,
    );
    final responseBlocksAfterLastTool = blocks
        .skip(lastToolIndex + 1)
        .where(
          (block) =>
              block.type == ChatMessageBlockType.response &&
              (block.text?.trim().isNotEmpty ?? false),
        )
        .toList();
    final hasResponseAfterLastTool = responseBlocksAfterLastTool.isNotEmpty;
    if (hasResponseAfterLastTool &&
        responseBlocksAfterLastTool.every(
          (block) => _isContinuationFallbackText(block.text ?? ''),
        )) {
      return true;
    }

    return !hasResponseAfterLastTool;
  }

  bool _shouldAutoContinueAfterToolTurn(ChatMessage message) {
    if (message.isUser) {
      return false;
    }

    final blocks = _getMessageBlocks(message);
    return _shouldAutoContinueAfterToolBlocks(blocks);
  }

  bool _shouldAutoContinueAfterToolBlocks(List<ChatMessageBlock> blocks) {
    if (blocks.isEmpty || _hasOpenToolCall(blocks)) {
      return false;
    }

    final hasToolCalls = blocks.any(
      (block) => block.type == ChatMessageBlockType.toolCall,
    );
    if (!hasToolCalls) {
      return false;
    }

    final lastMeaningfulIndex = blocks.lastIndexWhere((block) {
      if (block.type == ChatMessageBlockType.toolCall) return true;
      return (block.text?.trim().isNotEmpty ?? false);
    });
    if (lastMeaningfulIndex < 0) {
      return false;
    }

    final lastBlock = blocks[lastMeaningfulIndex];
    if (lastBlock.type == ChatMessageBlockType.toolCall ||
        lastBlock.type == ChatMessageBlockType.thinking) {
      return true;
    }

    final lastToolIndex = blocks.lastIndexWhere(
      (block) => block.type == ChatMessageBlockType.toolCall,
    );
    final responseBlocksAfterLastTool = blocks
        .skip(lastToolIndex + 1)
        .where(
          (block) =>
              block.type == ChatMessageBlockType.response &&
              (block.text?.trim().isNotEmpty ?? false),
        )
        .toList();
    if (responseBlocksAfterLastTool.isEmpty) {
      return true;
    }

    return responseBlocksAfterLastTool.every(
      (block) => _isContinuationFallbackText(block.text ?? ''),
    );
  }

  List<ChatMessageBlock> _getEffectiveBlocks(
    int messageIndex,
    bool isFinalInTurn,
  ) {
    final baseBlocks = _getMessageBlocks(_messages[messageIndex]);

    if (!isFinalInTurn) {
      return baseBlocks
          .where((b) => b.type == ChatMessageBlockType.response)
          .toList();
    }

    if (messageIndex > 0 && !_messages[messageIndex - 1].isUser) {
      final earlierActivityBlocks = <ChatMessageBlock>[];
      var startIndex = messageIndex;
      for (var i = messageIndex; i >= 0; i--) {
        if (_messages[i].isUser) {
          startIndex = i + 1;
          break;
        }
        startIndex = i;
      }
      for (var i = startIndex; i < messageIndex; i++) {
        if (!_messages[i].isUser) {
          earlierActivityBlocks.addAll(
            _getMessageBlocks(_messages[i]).where(
              (b) =>
                  b.type == ChatMessageBlockType.thinking ||
                  b.type == ChatMessageBlockType.toolCall,
            ),
          );
        }
      }
      return [...earlierActivityBlocks, ...baseBlocks];
    }

    return baseBlocks;
  }

  Widget _buildToolMessageBody(
    ChatMessage message,
    int messageIndex,
    bool isCurrentlyStreaming,
  ) {
    final isFinalInTurn =
        messageIndex == _messages.length - 1 ||
        _messages[messageIndex + 1].isUser;
    final blocks = _getEffectiveBlocks(messageIndex, isFinalInTurn);
    final responseBuffer = StringBuffer();
    for (final block in blocks) {
      if (block.type == ChatMessageBlockType.response) {
        responseBuffer.write(block.text ?? '');
      }
    }
    final responseText = responseBuffer.toString();
    if (responseText.trim().isEmpty) {
      if (isCurrentlyStreaming) {
        return const ChatResponseShimmer();
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildResponseMarkdown(
          responseText,
          isStreaming: isCurrentlyStreaming,
          messageIndex: messageIndex,
        ),
      ],
    );
  }

  bool _isPlaceholderThinkingText(String? text) {
    final normalized = (text ?? '').trim().toLowerCase();
    return normalized == 'thinking' ||
        normalized == 'reviewing' ||
        normalized == 'planning' ||
        normalized == 'checking' ||
        normalized == 'working' ||
        normalized == 'processing';
  }

  dynamic _decodeToolResult(String? rawResult) {
    final text = rawResult?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  Widget _buildResponseMarkdown(
    String text, {
    required bool isStreaming,
    required int messageIndex,
  }) {
    return ChatResponseMarkdown(
      text: text,
      isStreaming: isStreaming,
      onLinkTap: _handleMarkdownLinkTap,
      onTypewriterProgress: isStreaming ? _scheduleScrollToBottom : null,
      onTypewriterComplete: isStreaming
          ? () => _finishTypewriterForMessage(messageIndex)
          : null,
    );
  }

  void _finishTypewriterForMessage(int messageIndex) {
    if (!mounted || _isStreaming || _streamingMessageIndex != messageIndex) {
      return;
    }
    setState(() => _streamingMessageIndex = null);
  }

  Future<void> _handleMarkdownLinkTap(String url, String title) async {
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      showAppToast(
        context,
        message: 'Link copied',
        type: ToastificationType.success,
      );
    }
  }

  String? _cacheUsageLabel(Map<String, dynamic>? metadata) {
    final cacheReadTokens =
        _metadataInt(metadata, 'workflowCacheReadTokens') ??
        _metadataInt(metadata, 'cacheReadTokens');
    final cacheWriteTokens =
        _metadataInt(metadata, 'workflowCacheWriteTokens') ??
        _metadataInt(metadata, 'cacheWriteTokens');

    final parts = <String>[];
    if (cacheReadTokens != null && cacheReadTokens > 0) {
      parts.add('Cache ${_formatCompactTokenCount(cacheReadTokens)}');
    }
    if (cacheWriteTokens != null && cacheWriteTokens > 0) {
      parts.add('Write ${_formatCompactTokenCount(cacheWriteTokens)}');
    }

    return parts.isEmpty ? null : parts.join(' / ');
  }

  Future<String> _buildChatFlowPromptSnapshot() async {
    try {
      return await buildChatSystemPromptSnapshotForDiagnostics();
    } catch (error) {
      debugPrint('[UnifiedChatScreen] Could not build prompt snapshot: $error');
      return '';
    }
  }

  Map<String, dynamic> _buildChatFlowMetadata({
    required String userMessage,
    required String providerMessage,
    required String systemPrompt,
  }) {
    const maxPromptChars = 60000;
    final trimmedPrompt = systemPrompt.trim();
    final promptPreview = trimmedPrompt.length > maxPromptChars
        ? trimmedPrompt.substring(0, maxPromptChars)
        : trimmedPrompt;

    return {
      'chatFlowUserMessage': userMessage,
      'chatFlowProviderMessage': providerMessage,
      'chatFlowSystemPrompt': promptPreview,
      'chatFlowSystemPromptIsSnapshot': trimmedPrompt.isNotEmpty,
      'chatFlowSystemPromptTruncated': trimmedPrompt.length > maxPromptChars,
      'chatFlowPromptLength': trimmedPrompt.length,
      'chatFlowModel': _selectedModel,
      'chatFlowProvider': widget.config.modelName,
      'chatFlowStartedAt': DateTime.now().toIso8601String(),
    };
  }

  int? _metadataInt(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is num) return value.round();
    return null;
  }

  String _formatCompactTokenCount(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  String? _buildPostToolCompletionFallback(List<ChatMessageBlock> blocks) {
    final latestTool = _latestCompletedTool(blocks, successfulOnly: false);
    if (latestTool == null ||
        _hasResponseAfterToolBlock(blocks, latestTool.id)) {
      return null;
    }

    return null;
  }

  ToolCall? _latestCompletedTool(
    List<ChatMessageBlock> blocks, {
    required bool successfulOnly,
  }) {
    for (int i = blocks.length - 1; i >= 0; i--) {
      final toolCall = blocks[i].toolCall;
      if (blocks[i].type != ChatMessageBlockType.toolCall || toolCall == null) {
        continue;
      }
      if (_isLoopDetectedToolCall(toolCall)) {
        continue;
      }
      if (successfulOnly && toolCall.status != ToolCallStatus.completed) {
        continue;
      }
      if (!successfulOnly &&
          toolCall.status != ToolCallStatus.completed &&
          toolCall.status != ToolCallStatus.failed) {
        continue;
      }
      return toolCall;
    }
    return null;
  }

  bool _hasResponseAfterToolBlock(
    List<ChatMessageBlock> blocks,
    String? toolId,
  ) {
    if (toolId == null) {
      return false;
    }

    final toolIndex = blocks.indexWhere(
      (block) =>
          block.type == ChatMessageBlockType.toolCall &&
          block.toolCall?.id == toolId,
    );
    if (toolIndex < 0) {
      return false;
    }

    for (int i = toolIndex + 1; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.type == ChatMessageBlockType.response &&
          (block.text?.trim().isNotEmpty ?? false)) {
        return true;
      }
    }

    return false;
  }

  bool _isLoopDetectedToolCall(ToolCall toolCall) {
    final decoded = _decodeToolResult(toolCall.result);
    if (decoded is! Map) return false;
    final error = decoded['error']?.toString().toLowerCase() ?? '';
    return error.contains('tool call loop detected');
  }
}
