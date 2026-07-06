import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:budget_ai/features/chat/domain/models/ai_models.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/settings/presentation/screens/settings_screen.dart';
import 'package:budget_ai/features/settings/data/api_key_storage_service.dart';
import 'package:budget_ai/app/navigation/app_route_observer.dart';
import 'package:budget_ai/features/chat/domain/chat_model_config.dart';
import 'package:budget_ai/features/chat/data/services/chat_provider.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/core/models/notification_payload.dart';
import 'package:budget_ai/core/services/notification_service.dart';
import 'package:budget_ai/core/utils/vibration_manager.dart';
import 'package:budget_ai/features/chat/domain/workspace_mentions.dart';
import 'package:budget_ai/features/chat/presentation/screens/model_selector_screen.dart';
import 'package:budget_ai/features/chat/data/repositories/chat_session_repository.dart';
import 'package:budget_ai/features/github/data/local_github_service.dart';
import 'package:budget_ai/features/mac_companion/data/mac_companion_service.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';
import 'package:budget_ai/features/skills/data/agent_skill_service.dart';
import 'package:budget_ai/core/network/network_reachability_service.dart';
import 'package:budget_ai/core/platform/android_background_agent_service.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';

import 'package:budget_ai/features/chat/domain/chat_mode.dart';
import 'package:budget_ai/features/chat/presentation/screens/chat_history_screen.dart';
import 'package:budget_ai/features/chat/presentation/widgets/chat_empty_state.dart';
import 'package:budget_ai/features/chat/presentation/widgets/chat_response_markdown.dart';
import 'package:budget_ai/features/chat/presentation/widgets/agentic_message_sections.dart';

import 'package:budget_ai/features/chat/presentation/widgets/chat_loading_widgets.dart';
import 'package:budget_ai/features/chat/presentation/widgets/expandable_user_message_text.dart';

import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/features/chat/presentation/widgets/timeline_status_card.dart';
import 'package:budget_ai/features/chat/presentation/widgets/workspace_mention_suggestions_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:budget_ai/features/chat/presentation/widgets/streaming_text_reveal.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

part 'unified_chat_models.dart';
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
  static const String _workspaceSourceRemoteMac = 'remote_mac';
  static const String _workspaceSourceLocalGithub = 'local_github';
  static const String _continueInterruptedResponsePrompt =
      'Continue from the previous assistant turn. Use the completed tool results already in this conversation, especially any read results. Do not repeat successful read/tool calls unless a specific missing line range or query is required. Finish the original request.';
  static const String _continueAfterRecoverableEditFailurePrompt =
      'Continue from the previous assistant turn. The last edit tool call failed because its oldText did not match the current file. Use the failed tool result and its suggestions as retry guidance. Read the current target file again if needed, then retry with exact current text or a smaller unique replacement. Do not ask the user to continue manually.';
  static const String _continueAfterRecoverableFileAccessFailurePrompt =
      'Continue from the previous assistant turn. The last workspace file tool failed because the backend could not read the target path. Retry internally: verify the exact file path/workspace root, prefer a relative path from the connected workspace when possible, and use another available file access route such as bash if the file API still fails. Do not ask the user to continue manually.';
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
  final ScrollController _workspaceMentionSuggestionsScrollController =
      ScrollController();
  bool _isLoading = false;
  bool _isAppInBackground = false;
  bool _isOnChatScreen = true;
  final Set<String> _sentApprovalNotificationIds = {};
  late ChatProvider _provider;
  int? _streamingMessageIndex;
  bool _isStreaming = false;
  bool _isReconnectingStream = false;
  int _reconnectAttempt = 0;
  bool _isWaitingForNetwork = false;
  DateTime? _suppressNetworkWaitingUntil;
  Timer? _streamingDurationTimer;
  DateTime? _turnWallClockStart;
  final Map<int, Duration> _turnWallClockDurations = {};
  bool _isModelReady = false;
  String? _token;
  String _selectedModel = '';
  ChatSessionRecord? _activeSession;
  String? _workspaceRoot;
  String? _workspaceLabel;
  List<_ConnectedWorkspace> _connectedWorkspaces = const [];

  // Bumped whenever workspace-mention suggestion state changes.
  // Lets the suggestion overlay rebuild without going through setState, which
  // would otherwise rebuild the entire 9k-line screen on every keystroke that
  // matches a `/` or `@` query.
  final ValueNotifier<int> _suggestionVersion = ValueNotifier<int>(0);

  void _bumpSuggestionVersion() {
    if (!mounted) return;
    _suggestionVersion.value = _suggestionVersion.value + 1;
  }

  String? _workspaceMentionIndexedRoot;
  List<WorkspaceMentionEntry> _workspaceMentionEntries = const [];
  List<WorkspaceMentionEntry> _workspaceMentionSuggestions = const [];
  WorkspaceMentionQuery? _activeWorkspaceMentionQuery;
  int _activeWorkspaceMentionSuggestionIndex = -1;
  bool _githubModeActive = false;
  final ValueNotifier<bool> _showScrollToBottomButton = ValueNotifier<bool>(
    false,
  );
  bool _shouldFollowChatScroll = true;
  bool _isShowingLeaveConfirmation = false;
  bool _isShowingStopConfirmation = false;
  final List<String> _attachedImages = [];
  final List<String> _attachedVideos = [];
  final List<String> _attachedPdfs = [];
  String? _pendingWhatsAppFilePath;
  final Set<String> _shownApprovalDialogRequestIds = {};
  final ValueNotifier<int> _tokenUiRevision = ValueNotifier(0);
  bool _isCommandApprovalDialogOpen = false;
  final List<Map<String, dynamic>> _pendingApprovalDialogQueue = [];
  List<ChatSessionSummary>? _cachedSessionSummaries;
  final ValueNotifier<ChatMessage?> _streamingBubble = ValueNotifier(null);
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier(false);
  Timer? _streamingThrottleTimer;
  ChatMessage? _pendingStreamMessage;
  bool _scrollToBottomScheduled = false;
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
    await _loadToken();
    // Batch synchronous prefs reads into one setState instead of two separate
    // rebuilds — each setState on this large screen is expensive.
    final savedModel = SharedPrefsService.instance.getString(
      '${widget.config.modelName}_selected_model',
    );
    // Also check the global selected model from settings
    final globalModel = SharedPrefsService.getSelectedDeepSeekModel();
    final saved = globalModel ?? savedModel;
    if (!mounted) return;
    setState(() {
      _selectedModel =
          saved ?? AIModels.getDefaultModel(widget.config.modelName);
    });
    await _clearTransientWorkspaceSelection();
    await _refreshProviderState();
  }

  void _loadChatMode() {
  }

  Future<void> _applyModeAndRefresh(ChatModePreset preset) async {
    // Optimistic update — button and toast appear instantly.
    showAppToast(
      context,
      message: preset.isDefault ? 'Fast Mode: Off' : 'Fast Mode: On',
      type: ToastificationType.success,
    );
    // Persist in parallel in the background.
    await ChatModes.applyMode(preset);
    if (mounted) _loadChatMode();
  }


  Future<void> _refreshChatConfiguration() async {
    await _loadToken();
    await _loadSelectedModel();
    await _refreshProviderState();
  }

  Future<void> _clearTransientWorkspaceSelection() async {
    await SharedPrefsService.clearWorkspaceRoot();
    await SharedPrefsService.clearWorkspaceSource();
    await SharedPrefsService.clearConnectedWorkspaceProjects();
    await MacCompanionService.instance.clearSelectedRemoteWorkspace();
  }

  Future<void> _refreshProviderState() async {
    try {
      await _provider.initialize();
      final isReady = await _provider.isReady();
      if (!mounted) return;
      setState(() {
        _isModelReady = isReady;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isModelReady = false;
      });
    }
  }

  Future<void> _loadSelectedModel() async {
    final prefs = SharedPrefsService.instance;
    final savedModel = prefs.getString(
      '${widget.config.modelName}_selected_model',
    );
    final globalModel = widget.config.modelName == 'deepseek'
        ? SharedPrefsService.getSelectedDeepSeekModel()
        : null;
    setState(() {
      _selectedModel =
          globalModel ??
          savedModel ??
          AIModels.getDefaultModel(widget.config.modelName);
    });
  }

  Future<void> _clearWorkspaceSelection() async {
    await SharedPrefsService.clearWorkspaceRoot();
    await SharedPrefsService.clearWorkspaceSource();
    await SharedPrefsService.clearConnectedWorkspaceProjects();
    await MacCompanionService.instance.clearSelectedRemoteWorkspace();
    if (!mounted) return;
    setState(() {
      _connectedWorkspaces = const [];
      _workspaceRoot = null;
      _workspaceLabel = null;
      _workspaceMentionIndexedRoot = null;
      _workspaceMentionEntries = const [];
      _workspaceMentionSuggestions = const [];
      _activeWorkspaceMentionQuery = null;
      _activeWorkspaceMentionSuggestionIndex = -1;
    });
  }

  void _syncPrimaryWorkspaceFromConnected() {
    final activeSource = _activeWorkspaceSource;
    final primary = _firstConnectedWorkspaceForSource(activeSource);
    _workspaceRoot = primary?.path;
    _workspaceLabel = primary?.label;
  }

  _ConnectedWorkspace? _firstConnectedWorkspaceForSource(String source) {
    for (final workspace in _connectedWorkspaces) {
      if (workspace.source == source) return workspace;
    }
    return null;
  }

  Future<void> _persistConnectedWorkspaces() async {
    final completed = _connectedWorkspaces
        .where((item) => !item.isConnecting && item.path.trim().isNotEmpty)
        .toList();
    await SharedPrefsService.setConnectedWorkspaceProjects(
      completed.map((item) => item.toPrefs()).toList(),
    );

    _ConnectedWorkspace? primary;
    for (final workspace in completed) {
      if (workspace.source == _activeWorkspaceSource) {
        primary = workspace;
        break;
      }
    }
    if (primary == null) {
      await SharedPrefsService.clearWorkspaceRoot();
      await SharedPrefsService.clearWorkspaceSource();
      return;
    }

    await SharedPrefsService.setWorkspaceRoot(primary.path);
    await SharedPrefsService.setWorkspaceLabel(primary.label);
    await SharedPrefsService.setWorkspaceArchiveName('');
    await SharedPrefsService.setWorkspaceSource(primary.source);
  }


  Future<void> _changeModel(String newModel) async {
    final prefs = SharedPrefsService.instance;
    await prefs.setString(
      '${widget.config.modelName}_selected_model',
      newModel,
    );
    if (widget.config.modelName == 'deepseek') {
      await SharedPrefsService.setSelectedDeepSeekModel(newModel);
    }

    final modelInfo = AIModels.getModelById(widget.config.modelName, newModel);

    setState(() {
      _selectedModel = newModel;
    });

    _provider.updateModel(newModel);

    if (_activeSession != null) {
      await _syncProviderStateToSession();
      await _handlePostTurnSessionState();
    }

    if (mounted) {
      showAppToast(
        context,
        message: 'Model changed to ${modelInfo?.name ?? newModel}',
        type: ToastificationType.success,
      );
    }
  }

  Future<void> _loadToken() async {
    if (widget.config.tokenKey != null) {
      final token = await ApiKeyStorageService.getApiKey(
        widget.config.modelName,
      );
      setState(() {
        _token = token;
      });
    }
  }

  bool get _hasApiKey => (_token ?? '').trim().isNotEmpty;

  bool get _hasRemoteMacConnection =>
      MacCompanionService.instance.stateNotifier.value.hasRemoteConnection;

  bool get _isGithubMode => _githubModeActive;



  String get _activeWorkspaceSource =>
      _isGithubMode ? _workspaceSourceLocalGithub : _workspaceSourceRemoteMac;

  List<_ConnectedWorkspace> get _visibleConnectedWorkspaces =>
      _connectedWorkspaces
          .where((item) => item.source == _activeWorkspaceSource)
          .toList(growable: false);

  bool get _shouldShowRemoteWorkspaceUi =>
      _hasRemoteMacConnection && _hasApiKey && !_isGithubMode;

  bool get _shouldShowWorkspaceUi =>
      _shouldShowRemoteWorkspaceUi || _isGithubMode;

  ChatSessionRepository get _chatSessions => ChatSessionRepository.instance;

  AIModel? get _currentModelInfo =>
      AIModels.getModelById(widget.config.modelName, _selectedModel);

  int? get _currentContextLimit => _currentModelInfo?.contextLength;

  ChatWorkspaceSnapshot get _emptyWorkspaceSnapshot =>
      const ChatWorkspaceSnapshot(path: '', label: '', source: '');

  bool get _isContextLimitBlocked =>
      _activeSession?.flags.isContextLimitBlocked ?? false;

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

  void _appendTimelineStatus(Map<String, dynamic> payload, {int? entryId}) {
    _timelineItems.add(_TimelineStatusItem(payload: payload, entryId: entryId));
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
    switch (item) {
      case _TimelineMessageItem():
        _timelineItems[timelineIndex] = item.copyWith(entryId: entryId);
      case _TimelineStatusItem():
        _timelineItems[timelineIndex] = item.copyWith(entryId: entryId);
    }
  }

  void _resetComposerAndAttachments() {
    _messageController.clear();
    _attachedImages.clear();
    _attachedVideos.clear();
    _attachedPdfs.clear();
    _pendingWhatsAppFilePath = null;
    _workspaceMentionSuggestions = const [];
    _activeWorkspaceMentionQuery = null;
    _activeWorkspaceMentionSuggestionIndex = -1;
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
      _reconnectAttempt = 0;
      _isWaitingForNetwork = false;
      _githubModeActive = false;
      _resetComposerAndAttachments();
    });

    _provider.clearHistory();
    await MacCompanionService.instance.clearActiveCommandSessionAllowlist();
    MacCompanionService.instance.setActiveChatSessionId(null);
    await _clearWorkspaceSelection();
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
      workspaceSnapshot: _emptyWorkspaceSnapshot,
    );

    if (!mounted) return session;
    setState(() {
      _activeSession = session;
    });

    return session;
  }

  Future<void> _syncProviderStateToSession({
    ChatSessionLifecycleState? lifecycleState,
    ChatSessionFlags? flags,
    int? contextLimit,
  }) async {
    final session = _activeSession;
    if (session == null) return;
    final exportedState = _provider.exportConversationState();
    final nextSession = session.copyWith(
      updatedAt: DateTime.now(),
      lastProviderKey: widget.config.modelName,
      lastModelId: _selectedModel,
      lifecycleState: lifecycleState ?? session.lifecycleState,
      activeContextTokens: 0,
      lastKnownContextLimit: contextLimit ?? _currentContextLimit,
      workspaceSnapshot: _emptyWorkspaceSnapshot,
      flags: flags ?? session.flags,
    );

    await _chatSessions.replaceActiveContextItems(
      sessionId: nextSession.id,
      generation: nextSession.activeGeneration,
      items: exportedState,
      activeContextTokens: 0,
      providerKey: widget.config.modelName,
      modelId: _selectedModel,
      lifecycleState: nextSession.lifecycleState,
      workspaceSnapshot: _emptyWorkspaceSnapshot,
      flags: nextSession.flags,
      lastKnownContextLimit: nextSession.lastKnownContextLimit,
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

  void _removeProviderAssistantMessageFromHistory(String messageText) {
    final normalizedMessage = messageText.trim();
    if (normalizedMessage.isEmpty) return;

    final nextState = _provider.exportConversationState();
    for (var i = nextState.length - 1; i >= 0; i--) {
      final item = nextState[i];
      if (item['role'] != 'assistant') continue;
      final content = item['content'];
      final text = content is String ? content.trim() : '';
      if (text == normalizedMessage) {
        nextState.removeAt(i);
        _provider.loadConversationState(nextState);
        return;
      }
    }
  }

  Future<int?> _appendStatusCard({
    required String kind,
    Map<String, dynamic> data = const {},
    ChatSessionLifecycleState? lifecycleState,
    ChatSessionFlags? flags,
  }) async {
    final session = _activeSession;
    if (session == null) return null;
    final payload = {
      'kind': kind,
      'data': data,
      'created_at': DateTime.now().toIso8601String(),
    };
    final entryId = await _chatSessions.appendStatusCard(
      sessionId: session.id,
      payload: payload,
    );

    final nextSession = session.copyWith(
      updatedAt: DateTime.now(),
      lifecycleState: lifecycleState ?? session.lifecycleState,
      flags: flags ?? session.flags,
      lastProviderKey: widget.config.modelName,
      lastModelId: _selectedModel,
      lastKnownContextLimit: _currentContextLimit,
      workspaceSnapshot: _emptyWorkspaceSnapshot,
    );
    await _chatSessions.saveSession(nextSession);

    if (!mounted) return entryId;
    setState(() {
      _activeSession = nextSession;
      _appendTimelineStatus(payload, entryId: entryId);
    });
    return entryId;
  }

  Future<void> _loadPersistedSession(
    String sessionId, {
    Future<LoadedChatSession?>? preloadFuture,
  }) async {
    // Run the DB load and workspace clear concurrently — they're independent.
    unawaited(_clearWorkspaceSelection());
    final loaded =
        await (preloadFuture ?? _chatSessions.loadSession(sessionId));
    if (loaded == null || !mounted) return;
    final timelineItems = <_TimelineViewItem>[];
    final messages = <ChatMessage>[];
    for (final entry in loaded.timelineEntries) {
      if (entry.type == ChatTimelineEntryType.statusCard) {
        timelineItems.add(
          _TimelineStatusItem(payload: entry.payload, entryId: entry.id),
        );
        continue;
      }
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
    MacCompanionService.instance.setActiveChatSessionId(loaded.session.id);

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
      _reconnectAttempt = 0;
      _isWaitingForNetwork = false;
      _githubModeActive = false;
      _syncPrimaryWorkspaceFromConnected();
      _resetComposerAndAttachments();
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
          'The agent is still responding.',
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

  bool get _wouldExceedContextLimit {
    final limit = _currentContextLimit;
    if (limit == null || limit <= 0) return false;
    final prompt = _currentContextPromptTokens;
    return prompt > 0 && prompt >= limit;
  }

  Future<void> _updateSessionFlags(
    ChatSessionFlags flags, {
    ChatSessionLifecycleState? lifecycleState,
  }) async {
    final session = _activeSession;
    if (session == null) return;
    final nextSession = session.copyWith(
      updatedAt: DateTime.now(),
      flags: flags,
      lifecycleState: lifecycleState ?? session.lifecycleState,
      lastProviderKey: widget.config.modelName,
      lastModelId: _selectedModel,
      lastKnownContextLimit: _currentContextLimit,
      workspaceSnapshot: _emptyWorkspaceSnapshot,
    );
    await _chatSessions.saveSession(nextSession);
    if (!mounted) return;
    setState(() {
      _activeSession = nextSession;
    });
  }

  Future<void> _clearContextLimitBlock() async {
    final session = _activeSession;
    if (session == null || !session.flags.isContextLimitBlocked) {
      return;
    }
    await _updateSessionFlags(
      session.flags.copyWith(
        clearActiveContextLimitEntryId: true,
        isContextLimitBlocked: false,
      ),
      lifecycleState: ChatSessionLifecycleState.idle,
    );
  }

  Future<void> _ensureContextLimitCard({bool forceNewCard = false}) async {
    final session = _activeSession;
    if (session == null) return;
    final flags = session.flags;
    if (!forceNewCard &&
        flags.activeContextLimitEntryId != null &&
        flags.isContextLimitBlocked) {
      return;
    }
    final entryId = await _appendStatusCard(
      kind: kChatStatusContextLimitReached,
      data: {
        'used_tokens': _estimatedConversationTokens,
        'context_limit': _currentContextLimit,
        'model_id': _selectedModel,
        'model_name': _currentModelInfo?.name ?? _selectedModel,
      },
      lifecycleState: ChatSessionLifecycleState.blockedContextLimit,
      flags: flags,
    );
    if (entryId == null) return;
    await _updateSessionFlags(
      flags.copyWith(
        activeContextLimitEntryId: entryId,
        isContextLimitBlocked: true,
      ),
      lifecycleState: ChatSessionLifecycleState.blockedContextLimit,
    );
  }

  Future<void> _handlePostTurnSessionState({
    bool afterSuccessfulMessage = false,
  }) async {
    final session = _activeSession;
    if (session == null) return;

    if (_wouldExceedContextLimit) {
      await _ensureContextLimitCard(forceNewCard: afterSuccessfulMessage);
      return;
    }

    if ((_activeSession?.flags.isContextLimitBlocked ?? false)) {
      await _clearContextLimitBlock();
    }
  }

  Future<void> _handleContextLimitChangeModel() async {
    await _navigateToModelSelection(fromContextLimitCard: true);
  }

  void _handleComposerTextChanged() {
    _updateWorkspaceMentionSuggestions();
    _syncGithubCloneSelectionWithComposer();
  }

  void _updateCanSend() {
    final next = _canSubmitCurrentMessage;
    if (_canSendNotifier.value != next) _canSendNotifier.value = next;
  }

  void _syncGithubCloneSelectionWithComposer() {
    final nextPrimary = _firstConnectedWorkspaceForSource(
      _activeWorkspaceSource,
    );
    if (_workspaceRoot == nextPrimary?.path &&
        _workspaceLabel == nextPrimary?.label) {
      return;
    }
    setState(() {
      _syncPrimaryWorkspaceFromConnected();
    });
    unawaited(_persistConnectedWorkspaces());
    unawaited(_refreshWorkspaceMentionIndex());
  }

  void _handleComposerFocusChanged() {
    if (_messageFocusNode.hasFocus) {
      _updateWorkspaceMentionSuggestions();
      return;
    }

    if (_workspaceMentionSuggestions.isEmpty &&
        _activeWorkspaceMentionQuery == null) {
      return;
    }

    _workspaceMentionSuggestions = const [];
    _activeWorkspaceMentionQuery = null;
    _activeWorkspaceMentionSuggestionIndex = -1;
    _bumpSuggestionVersion();
  }

  void _unfocusComposer() {
    if (_messageFocusNode.hasFocus) {
      _messageFocusNode.unfocus();
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _refreshWorkspaceMentionIndex({bool force = false}) async {
    final workspaces = _visibleConnectedWorkspaces
        .where((item) => !item.isConnecting && item.path.trim().isNotEmpty)
        .toList(growable: false);
    final indexedKey = workspaces.map((item) => item.key).join('|');
    if (workspaces.isEmpty) {
      if (!mounted) return;
      setState(() {
        _workspaceMentionIndexedRoot = null;
        _workspaceMentionEntries = const [];
        _workspaceMentionSuggestions = const [];
        _activeWorkspaceMentionQuery = null;
        _activeWorkspaceMentionSuggestionIndex = -1;
      });
      return;
    }

    if (!force &&
        _workspaceMentionIndexedRoot == indexedKey &&
        _workspaceMentionEntries.isNotEmpty) {
      return;
    }

    final includeWorkspaceInMention = workspaces.length > 1;
    final cachedEntries = <WorkspaceMentionEntry>[];
    final missingCacheWorkspaces = <_ConnectedWorkspace>[];
    for (final workspace in workspaces) {
      final cached = SharedPrefsService.getWorkspaceMentionIndexCache(
        workspace.path,
      );
      if (cached != null && cached.isNotEmpty) {
        cachedEntries.addAll(
          _parseRawWorkspaceMentionResults(
            cached,
            workspace: workspace,
            includeWorkspaceInMention: includeWorkspaceInMention,
          ),
        );
      } else {
        missingCacheWorkspaces.add(workspace);
      }
    }

    final hasCachedEntries = cachedEntries.isNotEmpty;
    if (hasCachedEntries && mounted) {
      cachedEntries.sort(compareWorkspaceMentionEntries);
      setState(() {
        _workspaceMentionIndexedRoot = indexedKey;
        _workspaceMentionEntries = cachedEntries;
      });
      _updateWorkspaceMentionSuggestions();
      if (!force && missingCacheWorkspaces.isEmpty) return;
    }

    // Network refresh — silent if cache was already applied.
    try {
      final refreshedEntries = <WorkspaceMentionEntry>[];
      for (final workspace in workspaces) {
        final result = await _listWorkspaceMentionFiles(
          workspaceRoot: workspace.path,
          workspaceSource: workspace.source,
        );

        if (!mounted) return;

        final error = result['error']?.toString();
        if (error != null && error.isNotEmpty) {
          continue;
        }

        final rawResults = (result['results'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        refreshedEntries.addAll(
          _parseRawWorkspaceMentionResults(
            rawResults,
            workspace: workspace,
            includeWorkspaceInMention: includeWorkspaceInMention,
          ),
        );
        unawaited(
          SharedPrefsService.saveWorkspaceMentionIndexCache(
            workspace.path,
            rawResults,
          ),
        );
      }

      if (!mounted) return;
      if (refreshedEntries.isEmpty && !hasCachedEntries) {
        setState(() {
          _workspaceMentionIndexedRoot = indexedKey;
          _workspaceMentionEntries = const [];
          _workspaceMentionSuggestions = const [];
          _activeWorkspaceMentionQuery = null;
          _activeWorkspaceMentionSuggestionIndex = -1;
        });
        return;
      }

      final entries = refreshedEntries.isEmpty
          ? cachedEntries
          : refreshedEntries;
      entries.sort(compareWorkspaceMentionEntries);
      setState(() {
        _workspaceMentionIndexedRoot = indexedKey;
        _workspaceMentionEntries = entries;
      });
      _updateWorkspaceMentionSuggestions();
    } catch (_) {
      if (!mounted) return;
      if (!hasCachedEntries) {
        setState(() {
          _workspaceMentionIndexedRoot = indexedKey;
          _workspaceMentionEntries = const [];
          _workspaceMentionSuggestions = const [];
          _activeWorkspaceMentionQuery = null;
          _activeWorkspaceMentionSuggestionIndex = -1;
        });
      }
    }
  }

  List<WorkspaceMentionEntry> _parseRawWorkspaceMentionResults(
    List<Map<String, dynamic>> rawResults, {
    _ConnectedWorkspace? workspace,
    bool includeWorkspaceInMention = false,
  }) {
    final entries = <WorkspaceMentionEntry>[];
    final seenPaths = <String>{};
    for (final item in rawResults) {
      final rawPath = item['path']?.toString().trim() ?? '';
      final type = item['type']?.toString().trim() ?? 'file';
      if (rawPath.isEmpty || rawPath == '.') continue;
      if (shouldIgnoreWorkspaceMentionPath(rawPath)) continue;
      final normalizedPath = rawPath.replaceAll('\\', '/');
      if (!seenPaths.add('${type.toLowerCase()}::$normalizedPath')) continue;
      entries.add(
        WorkspaceMentionEntry.fromRelativePath(
          normalizedPath,
          isDirectory: type == 'directory',
          workspaceRoot: workspace?.path ?? '',
          workspaceLabel: workspace?.label ?? '',
          workspaceSource: workspace?.source ?? '',
          includeWorkspaceInMention: includeWorkspaceInMention,
        ),
      );
    }
    entries.sort(compareWorkspaceMentionEntries);
    return entries;
  }

  Future<Map<String, dynamic>> _listWorkspaceMentionFiles({
    required String workspaceRoot,
    required String workspaceSource,
  }) async {
    if (workspaceSource == _workspaceSourceLocalGithub) {
      return _listGithubCloneMentionFiles(workspaceRoot: workspaceRoot);
    }

    final result = await MacCompanionService.instance.listRemoteFiles(
      workspaceRoot: workspaceRoot,
      path: '.',
      recursive: true,
      maxResults: 20000,
      ignoredDirectoryNames: kIgnoredWorkspaceMentionDirectoryNames,
    );
    if (result['ok'] == false) {
      return {
        'error':
            result['error']?.toString() ??
            'Could not index files from the remote backend workspace.',
      };
    }
    final files = result['files'];
    if (files is Map) {
      return Map<String, dynamic>.from(files);
    }
    return {'error': 'No remote workspace files were returned.'};
  }

  Future<Map<String, dynamic>> _listGithubCloneMentionFiles({
    required String workspaceRoot,
  }) async {
    final clones = await LocalGithubService.instance.listClones();
    Map<String, dynamic>? selected;
    for (final clone in clones) {
      if ((clone['path']?.toString().trim() ?? '') == workspaceRoot) {
        selected = clone;
        break;
      }
    }
    if (selected == null) {
      return {'error': 'Selected GitHub clone was not found.'};
    }

    final files = selected['files'];
    if (files is! Map) {
      return {'error': 'Selected GitHub clone has no file metadata.'};
    }

    final results = <Map<String, dynamic>>[];
    final directories = <String>{};
    for (final rawPath in files.keys) {
      final path = rawPath.toString().trim().replaceAll('\\', '/');
      if (path.isEmpty || shouldIgnoreWorkspaceMentionPath(path)) continue;
      results.add({'path': path, 'type': 'file'});

      final parts = path.split('/').where((part) => part.isNotEmpty).toList();
      for (var i = 1; i < parts.length; i++) {
        final directory = parts.take(i).join('/');
        if (!shouldIgnoreWorkspaceMentionPath(directory)) {
          directories.add(directory);
        }
      }
    }

    for (final directory in directories) {
      results.add({'path': directory, 'type': 'directory'});
    }

    return {'results': results};
  }

  void _updateWorkspaceMentionSuggestions() {
    final query = currentWorkspaceMentionQuery(_messageController.value);
    if (!_messageFocusNode.hasFocus ||
        !_shouldShowWorkspaceUi ||
        !_hasActiveWorkspaceContext ||
        _workspaceMentionEntries.isEmpty ||
        query == null) {
      if (_workspaceMentionSuggestions.isEmpty &&
          _activeWorkspaceMentionQuery == null) {
        return;
      }
      if (!mounted) return;
      _workspaceMentionSuggestions = const [];
      _activeWorkspaceMentionQuery = null;
      _activeWorkspaceMentionSuggestionIndex = -1;
      _bumpSuggestionVersion();
      return;
    }

    final suggestions = findWorkspaceMentionSuggestions(
      entries: _workspaceMentionEntries,
      query: query.query,
    );
    final queryChanged =
        _activeWorkspaceMentionQuery?.start != query.start ||
        _activeWorkspaceMentionQuery?.end != query.end ||
        _activeWorkspaceMentionQuery?.query != query.query;
    final hasChanged =
        !sameWorkspaceSuggestionList(
          _workspaceMentionSuggestions,
          suggestions,
        ) ||
        queryChanged;

    if (!hasChanged || !mounted) {
      return;
    }

    _activeWorkspaceMentionQuery = query;
    _workspaceMentionSuggestions = suggestions;
    _activeWorkspaceMentionSuggestionIndex = suggestions.isEmpty
        ? -1
        : (queryChanged
              ? -1
              : _activeWorkspaceMentionSuggestionIndex.clamp(
                  -1,
                  suggestions.length - 1,
                ));
    _bumpSuggestionVersion();

    if (suggestions.isEmpty) {
      _jumpWorkspaceMentionSuggestionsToTop();
      return;
    }

    if (queryChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpWorkspaceMentionSuggestionsToTop();
      });
    } else {
      _scheduleActiveWorkspaceMentionVisibility();
    }
  }

  void _scheduleActiveWorkspaceMentionVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_workspaceMentionSuggestionsScrollController.hasClients) {
        return;
      }

      const itemExtent = WorkspaceMentionSuggestionsCard.itemExtent;
      final position = _workspaceMentionSuggestionsScrollController.position;
      final targetOffset = _activeWorkspaceMentionSuggestionIndex * itemExtent;
      final minVisible = position.pixels;
      final maxVisible =
          position.pixels + position.viewportDimension - itemExtent;

      if (targetOffset < minVisible) {
        _workspaceMentionSuggestionsScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
        return;
      }

      if (targetOffset > maxVisible) {
        _workspaceMentionSuggestionsScrollController.animateTo(
          targetOffset - position.viewportDimension + itemExtent,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _jumpWorkspaceMentionSuggestionsToTop() {
    if (!_workspaceMentionSuggestionsScrollController.hasClients) {
      return;
    }
    _workspaceMentionSuggestionsScrollController.jumpTo(0);
  }

  String _prepareMessageForProvider(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized == 'retry & continue' || normalized == 'continue') {
      return _continueInterruptedResponsePrompt;
    }

    return prepareWorkspaceMentionsForProvider(
      message: message,
      entries: _workspaceMentionEntries,
    );
  }

  String _prepareProviderOverrideMessage(String message) => message;

  void _stopStreamingThrottleTimer() {
    _streamingThrottleTimer?.cancel();
    _streamingThrottleTimer = null;
    _pendingStreamMessage = null;
  }

  @override
  void dispose() {
    unawaited(_clearTransientWorkspaceSelection());
    appRouteObserver.unsubscribe(this);
    _messageController.removeListener(_handleComposerTextChanged);
    _messageController.removeListener(_updateCanSend);
    _messageFocusNode.removeListener(_handleComposerFocusChanged);
    _scrollController.removeListener(_handleChatScroll);
    _showScrollToBottomButton.dispose();
    _suggestionVersion.dispose();
    _canSendNotifier.dispose();
    _tokenUiRevision.dispose();
    NetworkReachabilityService.instance.status.removeListener(
      _handleNetworkStatusChanged,
    );
    _messageController.dispose();
    _messageFocusNode.dispose();
    _messageInputScrollController.dispose();
    _scrollController.dispose();
    _workspaceMentionSuggestionsScrollController.dispose();
    _streamingDurationTimer?.cancel();
    _stopStreamingThrottleTimer();
    _streamingBubble.dispose();
    _notificationActionSubscription?.cancel();
    _provider.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleCommandApprovalDialog(ToolCall toolCall) {
    final request = _approvalRequestFromToolCall(toolCall);
    if (request == null) return;

    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty ||
        _shownApprovalDialogRequestIds.contains(requestId)) {
      return;
    }

    _shownApprovalDialogRequestIds.add(requestId);

    // If a dialog is already open, queue this one so it is shown next.
    if (_isCommandApprovalDialogOpen) {
      _pendingApprovalDialogQueue.add({
        'toolCall': toolCall,
        'request': request,
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isCommandApprovalDialogOpen) {
        // Another dialog opened between the schedule and the frame callback,
        // queue this one instead.
        _pendingApprovalDialogQueue.add({
          'toolCall': toolCall,
          'request': request,
        });
        return;
      }
      _showCommandApprovalDialog(toolCall: toolCall, request: request);
    });
  }

  void _showNextPendingApprovalDialog() {
    if (_pendingApprovalDialogQueue.isEmpty || !mounted) return;
    final next = _pendingApprovalDialogQueue.removeAt(0);
    final nextToolCall = next['toolCall'] as ToolCall;
    final nextRequest = next['request'] as Map<String, dynamic>;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showCommandApprovalDialog(toolCall: nextToolCall, request: nextRequest);
    });
  }

  Map<String, dynamic>? _approvalRequestFromToolCall(ToolCall toolCall) {
    if (toolCall.status != ToolCallStatus.awaitingApproval) return null;
    final decoded = _decodeToolResult(toolCall.result);
    if (decoded is! Map) return null;
    if (decoded['approval_required'] != true ||
        decoded['approval_request'] is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(decoded['approval_request'] as Map);
  }

  Future<void> _showCommandApprovalDialog({
    required ToolCall toolCall,
    required Map<String, dynamic> request,
  }) async {
    _isCommandApprovalDialogOpen = true;
    try {
      final theme = Theme.of(context);

      void resolve({required bool approved, bool addToSession = false}) {
        Navigator.of(context).pop();
        unawaited(
          _resolveCommandApproval(
            sourceToolCall: toolCall,
            request: request,
            approved: approved,
            addToSession: addToSession,
          ),
        );
      }

      final command = request['command']?.toString() ?? '';
      final isLocalGithubDelete =
          request['kind'] == 'local_github_branch_delete';
      final isLocalToolApproval = request['kind'] == 'local_tool';
      final isSensitiveCommand =
          request['sensitive'] == true ||
          request['command_type'] == 'destructive' ||
          _isDestructiveShellCommand(command);
      final canAddToSession =
          request['can_add_to_session'] == true && !isSensitiveCommand;
      final requestTitle = request['title']?.toString().trim() ?? '';
      final title = requestTitle.isNotEmpty
          ? '$requestTitle Approval'
          : isLocalGithubDelete
          ? 'Delete Branch Approval'
          : 'Command Approval';
      final description = isLocalToolApproval
          ? 'Review this local app operation before it runs.'
          : isLocalGithubDelete
          ? 'Review this local GitHub operation before it runs.'
          : 'Review this MacRemote command before it runs.';
      final consequence = request['consequence']?.toString() ?? '';
      final displayText = [
        command,
        if (consequence.isNotEmpty) consequence,
      ].where((line) => line.trim().isNotEmpty).join('\n\n');

      await ResponsiveInfoSheet.show<void>(
        context,
        title: title,
        headerIcon: Icon(
          Icons.pending_outlined,
          color: AppTheme.readableOn(theme.colorScheme.primary),
          size: 28,
        ),
        gradientColors: [
          theme.colorScheme.primary,
          theme.colorScheme.primary.withValues(alpha: 0.78),
        ],
        isDismissible: false,
        enableDrag: false,
        showCloseButton: false,
        contentWidgets: [
          Text(
            description,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          _ApprovalDetailsBox(text: displayText),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      resolve(approved: true);
                    },
                    icon: const Icon(
                      CupertinoIcons.check_mark_circled,
                      size: 18,
                    ),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      resolve(approved: false);
                    },
                    icon: const Icon(CupertinoIcons.xmark_circle, size: 18),
                    label: const Text('Deny'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.45),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (canAddToSession) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () {
                  resolve(approved: true, addToSession: true);
                },
                icon: const Icon(CupertinoIcons.plus_circle, size: 18),
                label: const Text('Approve + Add to Session'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(color: theme.colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    } finally {
      _isCommandApprovalDialogOpen = false;
      // If there are other queued approvals, show the next one.
      _showNextPendingApprovalDialog();
    }
  }

  bool _isDestructiveShellCommand(String command) {
    final normalized = command.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return RegExp(r'(^|[;&|]+\s*)rm\b').hasMatch(normalized);
  }

  Future<Map<String, dynamic>> _resolveCommandApproval({
    required ToolCall sourceToolCall,
    required Map<String, dynamic> request,
    required bool approved,
    bool addToSession = false,
  }) async {
    if (request['kind'] == 'local_github_branch_delete') {
      return _resolveLocalGithubBranchDeleteApproval(
        sourceToolCall: sourceToolCall,
        request: request,
        approved: approved,
      );
    }
    if (request['kind'] == 'local_tool') {
      return _resolveLocalToolApproval(
        sourceToolCall: sourceToolCall,
        request: request,
        approved: approved,
      );
    }

    final requestId = request['id']?.toString() ?? '';
    final command = request['command']?.toString() ?? '';
    final workingDirectory = request['working_directory']?.toString();

    final response = await MacCompanionService.instance
        .respondToCommandApproval(requestId: requestId, approved: approved);
    if (response['ok'] != true) {
      return response;
    }

    if (!approved) {
      await _handleCommandApprovalResolved(sourceToolCall, {
        'approval_required': true,
        'approval_request': request,
        'approval_decision': 'denied',
        'content': 'User denied this command.',
      });
      return {'ok': true};
    }

    // Show "Running command ..." instantly in the chat timeline while the
    // remote command executes so the user knows work is in progress.
    await _updateToolCallResultInTimeline(sourceToolCall, {
      'approval_required': true,
      'approval_request': request,
      'approval_decision': 'approved',
      'content': 'Running command ...',
    }, markComplete: false);

    final commandResult = await _runApprovedRemoteCommandWithProgress(
      sourceToolCall: sourceToolCall,
      request: request,
      workspaceRoot: workingDirectory,
      command: command,
    );
    await _handleCommandApprovalResolved(sourceToolCall, {
      'approval_required': true,
      'approval_request': request,
      'approval_decision': 'approved',
      'added_to_session': addToSession,
      'command_result': commandResult,
      'content':
          commandResult['content']?.toString() ??
          commandResult['stdout']?.toString() ??
          commandResult['stderr']?.toString() ??
          'Command approved.',
    });
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _runApprovedRemoteCommandWithProgress({
    required ToolCall sourceToolCall,
    required Map<String, dynamic> request,
    required String? workspaceRoot,
    required String command,
  }) async {
    final root = workspaceRoot == null || workspaceRoot.trim().isEmpty
        ? null
        : workspaceRoot;
    final startResult = await MacCompanionService.instance
        .startRemoteTerminalCommand(workspaceRoot: root, command: command);
    if (startResult['error'] != null || startResult['command_id'] == null) {
      return startResult;
    }

    Future<void> pushProgress(Map<String, dynamic> progress) {
      final output = _remoteCommandOutput(progress);
      return _updateToolCallResultInTimeline(sourceToolCall, {
        'approval_required': true,
        'approval_request': request,
        'approval_decision': 'approved',
        'command_result': {
          ...progress,
          'command': command,
          'workspace_root': root,
          'working_directory': root,
          'content': output,
        },
        'content': output.isEmpty ? 'Running command ...' : output,
      }, markComplete: false);
    }

    var latest = Map<String, dynamic>.from(startResult);
    await pushProgress(latest);
    final commandId = startResult['command_id'].toString();

    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final progress = await MacCompanionService.instance
          .getRemoteTerminalProgress(commandId);
      if (progress['error'] != null) {
        return {
          ...latest,
          'success': false,
          'error': progress['error'],
          'content': progress['error']?.toString() ?? 'Command failed.',
        };
      }
      latest = Map<String, dynamic>.from(progress);
      await pushProgress(latest);
      if ((latest['status']?.toString() ?? 'running') != 'running') break;
    }

    final exitCode = (latest['exit_code'] as num?)?.toInt();
    return {
      'tool': 'terminal_command',
      'backend': 'terminal',
      'operation': 'execute',
      'workspace_root': root,
      'working_directory': root,
      'command': command,
      ...latest,
      'success': exitCode == 0,
      'stdout': latest['stdout_tail']?.toString().trim() ?? '',
      'stderr': latest['stderr_tail']?.toString().trim() ?? '',
      'content': _remoteCommandOutput(latest),
    };
  }

  String _remoteCommandOutput(Map<dynamic, dynamic> result) {
    for (final key in const [
      'content',
      'stdout',
      'stderr',
      'stdout_tail',
      'stderr_tail',
      'output_sample',
    ]) {
      final value = result[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<Map<String, dynamic>> _resolveLocalToolApproval({
    required ToolCall sourceToolCall,
    required Map<String, dynamic> request,
    required bool approved,
  }) async {
    final tool = request['tool']?.toString() ?? '';
    final args = request['arguments'] is Map
        ? Map<String, dynamic>.from(request['arguments'] as Map)
        : <String, dynamic>{};

    if (!approved) {
      await _handleCommandApprovalResolved(sourceToolCall, {
        'approval_required': true,
        'approval_request': request,
        'approval_decision': 'denied',
        'content': 'User denied this operation.',
      });
      return {'ok': true};
    }

    await _updateToolCallResultInTimeline(sourceToolCall, {
      'approval_required': true,
      'approval_request': request,
      'approval_decision': 'approved',
      'content': 'Running approved operation ...',
    }, markComplete: false);

    late final Map<String, dynamic> result;
    try {
      switch (tool) {
        case 'memory_delete':
          final id = args['id']?.toString() ?? '';
          final deleted = await MemoryService.instance.delete(id);
          result = {'ok': deleted, 'id': id};
        case 'finance_delete':
          final singleId = args['id']?.toString().trim() ?? '';
          final rawIds = args['ids'];
          final ids = singleId.isNotEmpty
              ? [singleId]
              : (rawIds is List ? rawIds : [])
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
          if (ids.length == 1) {
            final deleted = await FinanceService.instance.delete(ids.first);
            result = {'ok': deleted, 'id': ids.first};
          } else {
            final removed = await FinanceService.instance.deleteMany(ids);
            result = {'ok': true, 'removed': removed, 'requested': ids.length};
          }
        default:
          if (request['approval_scope'] == 'tool_manager') {
            result = await _provider.executeApprovedTool(tool, args);
          } else {
            result = {
              'ok': false,
              'error': 'No approval resolver is registered for $tool.',
            };
          }
      }
    } catch (e) {
      result = {'ok': false, 'error': e.toString()};
    }

    await _handleCommandApprovalResolved(sourceToolCall, {
      'approval_required': true,
      'approval_request': request,
      'approval_decision': 'approved',
      'command_result': result,
      'content':
          result['error']?.toString() ??
          (result['ok'] == true
              ? 'Approved operation completed.'
              : 'Operation was not completed.'),
    });
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _resolveLocalGithubBranchDeleteApproval({
    required ToolCall sourceToolCall,
    required Map<String, dynamic> request,
    required bool approved,
  }) async {
    if (!approved) {
      await _handleCommandApprovalResolved(sourceToolCall, {
        'approval_required': true,
        'approval_request': request,
        'approval_decision': 'denied',
        'content': 'User denied this branch delete operation.',
      });
      return {'ok': true};
    }

    await _updateToolCallResultInTimeline(sourceToolCall, {
      'approval_required': true,
      'approval_request': request,
      'approval_decision': 'approved',
      'content': 'Deleting branch...',
    }, markComplete: false);

    final repoPath = request['repo_path']?.toString() ?? '';
    final branch = request['branch']?.toString() ?? '';
    late final Map<String, dynamic> result;
    try {
      result = await LocalGithubService.instance.deleteRemoteBranch(
        repoPath,
        branch,
      );
    } catch (e) {
      result = {'success': false, 'error': 'Delete branch failed: $e'};
    }
    await _handleCommandApprovalResolved(sourceToolCall, {
      'approval_required': true,
      'approval_request': request,
      'approval_decision': 'approved',
      'command_result': result,
      'content':
          result['message']?.toString() ??
          result['error']?.toString() ??
          'Branch delete approval resolved.',
    });
    return {'ok': true};
  }

  void _startStreamingDurationTimer(DateTime startedAt) {
    _streamingDurationTimer?.cancel();
    unawaited(AndroidBackgroundAgentService.start());
    var tickCount = 0;
    _streamingDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isStreaming) {
        _streamingDurationTimer?.cancel();
        _streamingDurationTimer = null;
        return;
      }
      tickCount++;
      // Nudge only the streaming bubble to update the elapsed-time label.
      // copyWith() returns a new instance so ValueListenableBuilder fires
      // without a full-screen setState.
      final msg = _streamingBubble.value;
      if (msg != null) _streamingBubble.value = msg.copyWith();
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
    _turnWallClockStart = null;
    unawaited(AndroidBackgroundAgentService.stop());
  }

  // Used by streaming paths so multiple requests within the same frame
  // collapse to a single postFrameCallback instead of stacking up.
  void _scheduleScrollToBottom() {
    if (_scrollToBottomScheduled) return;
    _scrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomScheduled = false;
      if (mounted) _scrollToBottom();
    });
  }

  void _scrollToBottom({bool force = false}) {
    if (force) {
      _shouldFollowChatScroll = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (!_shouldScrollChatToBottom(force: force)) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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

  List<String> _continuationSourceImagePaths({
    required bool appendUserMessage,
    required String? providerMessageOverride,
    required int? replaceAssistantMessageIndex,
  }) {
    if (appendUserMessage || providerMessageOverride == null) {
      return const [];
    }

    final startIndex = replaceAssistantMessageIndex != null
        ? math.min(replaceAssistantMessageIndex - 1, _messages.length - 1)
        : _messages.length - 1;
    for (var i = startIndex; i >= 0; i--) {
      final message = _messages[i];
      final paths = message.imagePaths;
      if (message.isUser && paths != null && paths.isNotEmpty) {
        return paths
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
      }
    }

    return const [];
  }

  Future<void> _sendMessage({
    bool appendUserMessage = true,
    String? providerMessageOverride,
    List<String> providerImagePathsOverride = const [],
    bool removeProviderMessageFromHistory = false,
    int? replaceAssistantMessageIndex,
    int automaticToolContinuationDepth = 0,
    bool preserveTurnWallClock = false,
  }) async {
    final hasText = _messageController.text.trim().isNotEmpty;
    final hasImages = _attachedImages.isNotEmpty;
    final hasAttachments =
        hasImages || _attachedVideos.isNotEmpty || _attachedPdfs.isNotEmpty;

    if (!hasText && !hasAttachments && providerMessageOverride == null) return;

    if (widget.config.requiresDownload && !_isModelReady) {
      _showErrorToast('Please Download The Model First');
      return;
    }

    if (_isContextLimitBlocked || _wouldExceedContextLimit) {
      if (_activeSession != null) {
        await _ensureContextLimitCard();
      }
      _showErrorToast('Context limit reached for the selected model');
      return;
    }

    _unfocusComposer();

    final userMessageText = _messageController.text.trim();

    // Detect natural-language mode-change requests ("change my mode to finance mode").
    if (providerMessageOverride == null) {
      final modeChange = ChatModes.detectModeChangeFromMessage(userMessageText);
      if (modeChange != null) {
        await _applyModeAndRefresh(modeChange);
      }
    }

    final originalAttachedImages = List<String>.from(_attachedImages);
    final originalAttachedVideos = List<String>.from(_attachedVideos);
    final originalAttachedPdfs = List<String>.from(_attachedPdfs);
    final allOriginalAttachments = [
      ...originalAttachedImages,
      ...originalAttachedVideos,
      ...originalAttachedPdfs,
    ];
    final whatsappAttachedFile = _pendingWhatsAppFilePath;
    var providerMessageText = providerMessageOverride == null
        ? _prepareMessageForProvider(userMessageText)
        : _prepareProviderOverrideMessage(providerMessageOverride);
    if (whatsappAttachedFile != null) {
      providerMessageText +=
          '\n\n[WhatsApp file attachment: $whatsappAttachedFile]';
    }
    final visibleUserMessageText = userMessageText.isNotEmpty
        ? userMessageText
        : providerMessageText;
    final provisionalUserMessage = ChatMessage(
      text: visibleUserMessageText,
      isUser: true,
      timestamp: DateTime.now(),
      imagePaths: allOriginalAttachments.isEmpty
          ? null
          : allOriginalAttachments,
    );
    int? userTimelineIndex;
    if (appendUserMessage) {
      userTimelineIndex = _timelineItems.length;
    }

    setState(() {
      if (appendUserMessage) {
        _appendTimelineMessage(provisionalUserMessage, entryId: null);
      }
      _attachedImages.clear();
      _attachedVideos.clear();
      _attachedPdfs.clear();
      _pendingWhatsAppFilePath = null;
    });

    _messageController.clear();
    _scrollToBottom(force: true);

    await AgentSkillService.instance.activateForMessage(providerMessageText);
    final agentFlowPromptSnapshot = await _buildAgentFlowPromptSnapshot();
    final session = await _ensureSessionCreated(provisionalUserMessage);
    MacCompanionService.instance.setActiveChatSessionId(session.id);
    final storedAttachments = await _chatSessions.copyAttachmentsToSession(
      sessionId: session.id,
      originalPaths: allOriginalAttachments,
    );
    final storedImagePaths = storedAttachments
        .map((attachment) => attachment.storedPath)
        .toList();
    final toolImagePaths = providerImagePathsOverride.isNotEmpty
        ? providerImagePathsOverride
        : storedImagePaths.isNotEmpty
        ? storedImagePaths
        : _continuationSourceImagePaths(
            appendUserMessage: appendUserMessage,
            providerMessageOverride: providerMessageOverride,
            replaceAssistantMessageIndex: replaceAssistantMessageIndex,
          );
    final userMessage = provisionalUserMessage.copyWith(
      imagePaths: storedImagePaths.isEmpty ? null : storedImagePaths,
    );
    int? userEntryId;
    if (appendUserMessage) {
      userEntryId = await _chatSessions.appendMessageEntry(
        sessionId: session.id,
        type: ChatTimelineEntryType.userMessage,
        message: userMessage,
        attachments: storedAttachments,
      );
    }

    if (appendUserMessage &&
        userTimelineIndex != null &&
        (userEntryId != null || storedImagePaths.isNotEmpty)) {
      setState(() {
        _replaceTimelineMessageAt(userTimelineIndex!, userMessage);
        if (userEntryId != null) {
          _replaceTimelineEntryIdAt(userTimelineIndex, userEntryId);
        }
      });
    }

    int? aiMessageIndex;
    int? aiTimelineIndex;
    String fullResponse = '';
    List<ChatMessageBlock> messageBlocks = [];
    DateTime startTime = DateTime.now();
    if (automaticToolContinuationDepth == 0 && !preserveTurnWallClock) {
      _turnWallClockStart = startTime;
    } else {
      _turnWallClockStart ??= startTime;
    }
    int? responseTimeMs;
    int tokenCount = 0;
    Map<String, dynamic> responseMetadata = _buildAgentFlowMetadata(
      userMessage: visibleUserMessageText,
      providerMessage: providerMessageText,
      systemPrompt: agentFlowPromptSnapshot,
    );
    ChatMessage? finalAssistantMessage;
    int? assistantEntryId;
    bool shouldSilentlyContinueAfterToolError = false;
    bool shouldContinueAfterRecoverableEditFailure = false;
    bool shouldContinueAfterRecoverableFileAccessFailure = false;

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
          _isStreaming = true;
          _isReconnectingStream = false;
          _reconnectAttempt = 0;
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
          _isStreaming = true;
          _isReconnectingStream = false;
          _reconnectAttempt = 0;
          _isWaitingForNetwork = false;
        });
        _startStreamingDurationTimer(startTime);

        assistantEntryId = await _chatSessions.appendMessageEntry(
          sessionId: session.id,
          type: ChatTimelineEntryType.assistantMessage,
          message: ChatMessage(text: '', isUser: false, timestamp: startTime),
          attachments: const [],
        );
      }
      final activeAssistantEntryId = assistantEntryId;
      DateTime lastPersistedAssistantAt = DateTime.now();

      if (assistantEntryId != null && aiTimelineIndex != null) {
        setState(() {
          _replaceTimelineEntryIdAt(aiTimelineIndex!, assistantEntryId!);
        });
      }

      final currentModel = AIModels.getModelById(
        widget.config.modelName,
        _selectedModel,
      );
      final supportsReasoning = currentModel?.supportsThinking ?? false;
      final supportsToolCall = currentModel?.supportsToolCall ?? false;

      bool firstChunk = true;
      int chunkCount = 0;
      String lastDisplayedText = '';
      bool hasReceivedThinking = false;
      bool hasReceivedContent = false;
      bool hasReceivedToolCalls = false;
      const networkInactivityTimeout = Duration(seconds: 12);
      const postToolInactivityTimeout = Duration(seconds: 90);
      const activeToolInactivityTimeout = Duration(minutes: 20);

      Stream<ChatStreamChunk> createStream() {
        if (supportsReasoning || supportsToolCall) {
          return _provider.sendMessageStreamWithThinking(
            providerMessageText,
            imagePaths: toolImagePaths.isNotEmpty ? toolImagePaths : null,
            enableToolCalls: supportsToolCall,
          );
        }

        return _provider
            .sendMessageStream(
              providerMessageText,
              imagePaths: toolImagePaths.isNotEmpty ? toolImagePaths : null,
            )
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
                  _reconnectAttempt = 0;
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
                hasReceivedThinking = true;
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
                if (hasReceivedThinking) {
                  shouldReplacePlaceholder = true;
                } else if (hasReceivedToolCalls) {
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
              final shouldUpdate =
                  shouldReplacePlaceholder ||
                  chunkCount % 3 == 0 ||
                  chunk.content.length > 50 ||
                  fullResponse.length - lastDisplayedText.length > 100 ||
                  chunk.isThinkingComplete ||
                  chunk.isToolCallComplete ||
                  (chunk.toolCall != null &&
                      (chunk.toolCall!.status == ToolCallStatus.calling ||
                          chunk.toolCall!.status ==
                              ToolCallStatus.awaitingApproval ||
                          chunk.toolCall!.status == ToolCallStatus.completed ||
                          chunk.toolCall!.status == ToolCallStatus.failed));

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
                // Tool-state transitions (approval, complete, failed, etc.) must
                // reach the UI immediately. Regular text/thinking chunks are
                // throttled: buffered here and flushed by the timer at most
                // every 100 ms, capping markdown re-parses to ~10/s.
                final isImmediateEvent =
                    chunk.isThinkingComplete ||
                    chunk.isToolCallComplete ||
                    (chunk.toolCall != null &&
                        (chunk.toolCall!.status == ToolCallStatus.calling ||
                            chunk.toolCall!.status ==
                                ToolCallStatus.awaitingApproval ||
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
                // Runs in the streaming callback (background-safe) — send
                // approval notification the moment awaitingApproval is first
                // detected, before any frame is rendered.
                if (chunk.toolCall?.status == ToolCallStatus.awaitingApproval) {
                  final tcId = chunk.toolCall!.id;
                  if (_sentApprovalNotificationIds.add(tcId)) {
                    final toolCall = chunk.toolCall!;
                    final args = toolCall.arguments ?? {};
                    final command =
                        args['command']?.toString() ??
                        args['to']?.toString() ??
                        args['file_path']?.toString() ??
                        args['url']?.toString() ??
                        toolCall.name ??
                        'unknown command';
                    final riskLevel =
                        args['command']?.toString().contains('rm') == true ||
                            args['command']?.toString().contains('sudo') == true
                        ? 'destructive'
                        : 'caution';
                    final affectedPaths = <String>[];
                    if (args['file_path'] != null) {
                      affectedPaths.add(args['file_path'].toString());
                    }
                    if (args['path'] != null) {
                      affectedPaths.add(args['path'].toString());
                    }
                    // Extract the actual approval request ID and kind from the tool call result.
                    String? approvalRequestId;
                    String? kind;
                    final decodedResult = _decodeToolResult(toolCall.result);
                    if (decodedResult is Map) {
                      final request = decodedResult['approval_request'];
                      if (request is Map) {
                        approvalRequestId = request['id']?.toString();
                        kind = request['kind']?.toString();
                      }
                    }
                    final payload = ApprovalNotificationPayload(
                      requestId: tcId,
                      toolName: toolCall.name ?? 'unknown',
                      command: command,
                      arguments: Map<String, dynamic>.from(args),
                      riskLevel: riskLevel,
                      affectedPaths: affectedPaths,
                      sessionId: _activeSession?.id,
                      timestamp: DateTime.now(),
                      chatId: _activeSession?.id,
                      approvalRequestId: approvalRequestId,
                      kind: kind,
                    );
                    unawaited(
                      NotificationService.instance.showApprovalNotification(
                        payload,
                        appInBackground: _isAppInBackground,
                      ),
                    );
                  }
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
              // agentic responses before the final one.
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
              _reconnectAttempt = 0;
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
                _reconnectAttempt = 0;
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
          hasReceivedThinking = messageBlocks.any(
            (block) => block.type == ChatMessageBlockType.thinking,
          );
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
            _reconnectAttempt = reconnectAttempt;
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
          !_hasPendingCommandApproval(messageBlocks) &&
          _shouldAutoContinueAfterToolBlocks(messageBlocks);
      shouldContinueAfterRecoverableEditFailure =
          mounted &&
          automaticToolContinuationDepth < _maxAutomaticToolContinuations &&
          _hasRecoverableEditToolFailure(messageBlocks);
      shouldContinueAfterRecoverableFileAccessFailure =
          mounted &&
          automaticToolContinuationDepth < _maxAutomaticToolContinuations &&
          _hasRecoverableFileAccessToolFailure(messageBlocks);
      final postToolFallback =
          willAutoContinueToolTurn ||
              shouldContinueAfterRecoverableEditFailure ||
              shouldContinueAfterRecoverableFileAccessFailure
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
      final hasPendingApproval = _hasPendingCommandApproval(messageBlocks);

      // Stop the throttle timer so no buffered chunk overwrites the final
      // message after we push it below.
      _stopStreamingThrottleTimer();
      // Push the final message through the VLB before the setState that removes
      // _streamingMessageIndex — this way there is no frame where the bubble
      // briefly shows stale content from _timelineItems.
      _streamingBubble.value = finalAssistantMessage;
      setState(() {
        _replaceTimelineMessageAt(aiTimelineIndex!, finalAssistantMessage!);
        if (!hasPendingApproval &&
            !willAutoContinueToolTurn &&
            !shouldContinueAfterRecoverableEditFailure &&
            !shouldContinueAfterRecoverableFileAccessFailure) {
          _isStreaming = false;
          _streamingMessageIndex = null;
        }
        _isReconnectingStream = false;
        _reconnectAttempt = 0;
        _isWaitingForNetwork = false;
      });
      // VLB is removed from the tree by the setState above; free the reference.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _streamingBubble.value = null;
      });
      if (!hasPendingApproval &&
          !willAutoContinueToolTurn &&
          !shouldContinueAfterRecoverableEditFailure) {
        if (_turnWallClockStart != null) {
          _turnWallClockDurations[aiMessageIndex] = DateTime.now().difference(
            _turnWallClockStart!,
          );
        }
        _stopStreamingDurationTimer();
        if (_isAppInBackground || !_isOnChatScreen) {
          final toolCallCount = _countToolCallsInMessage(finalAssistantMessage);
          final responseText = finalAssistantMessage.text;
          final summary = responseText.isNotEmpty
              ? (responseText.length > 200
                    ? '${responseText.substring(0, 200)}...'
                    : responseText)
              : 'Response complete. ${toolCallCount > 0 ? '$toolCallCount tool call(s) executed.' : ''}';
          final responsePayload = ResponseReadyPayload(
            chatId: _activeSession?.id ?? '',
            modelUsed: _selectedModel.isNotEmpty ? _selectedModel : null,
            toolCallCount: toolCallCount,
            status: hasPendingApproval ? 'pending' : 'success',
            summary: summary,
            timestamp: DateTime.now(),
            hasError: false,
          );
          unawaited(
            NotificationService.instance.showResponseReadyNotification(
              responsePayload,
              appInBackground: _isAppInBackground,
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

      final fallbackText = _buildStreamTimeoutFallback(blocks);
      if (fallbackText != null && fallbackText.isNotEmpty) {
        _appendResponseBlock(blocks, fallbackText);
      } else {
        _appendResponseBlock(
          blocks,
          '\n\nThe model stopped responding before it finished the reply.',
        );
      }
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
        _streamingMessageIndex = null;
        _isReconnectingStream = false;
        _reconnectAttempt = 0;
        _isWaitingForNetwork = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _streamingBubble.value = null;
      });
      if (aiMessageIndex != null && _turnWallClockStart != null) {
        _turnWallClockDurations[aiMessageIndex] = DateTime.now().difference(
          _turnWallClockStart!,
        );
      }
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
        _streamingMessageIndex = null;
        _isReconnectingStream = false;
        _reconnectAttempt = 0;
        _isWaitingForNetwork = false;
        _replaceTimelineMessageAt(aiTimelineIndex!, finalAssistantMessage!);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _streamingBubble.value = null;
      });
      if (aiMessageIndex != null && _turnWallClockStart != null) {
        _turnWallClockDurations[aiMessageIndex] = DateTime.now().difference(
          _turnWallClockStart!,
        );
      }
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

      final streamingEndsNow =
          !shouldSilentlyContinueAfterToolError &&
          !_hasPendingCommandApproval(_getMessageBlocks(finalAssistantMessage));
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
          _streamingMessageIndex = null;
        }
        _isReconnectingStream = false;
        _reconnectAttempt = 0;
        _isWaitingForNetwork = false;
      });
      if (streamingEndsNow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _streamingBubble.value = null;
        });
      }
      if (!shouldSilentlyContinueAfterToolError &&
          !_hasPendingCommandApproval(
            _getMessageBlocks(finalAssistantMessage),
          )) {
        if (aiMessageIndex != null && _turnWallClockStart != null) {
          _turnWallClockDurations[aiMessageIndex] = DateTime.now().difference(
            _turnWallClockStart!,
          );
        }
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
            shouldContinueAfterRecoverableEditFailure ||
            shouldContinueAfterRecoverableFileAccessFailure ||
            _shouldAutoContinueAfterToolTurn(finalAssistantMessage));
    if (shouldContinueToolTurn) {
      await _sendMessage(
        appendUserMessage: false,
        providerMessageOverride: shouldContinueAfterRecoverableEditFailure
            ? _continueAfterRecoverableEditFailurePrompt
            : shouldContinueAfterRecoverableFileAccessFailure
            ? _continueAfterRecoverableFileAccessFailurePrompt
            : _continueInterruptedResponsePrompt,
        removeProviderMessageFromHistory: true,
        replaceAssistantMessageIndex: aiMessageIndex,
        automaticToolContinuationDepth: automaticToolContinuationDepth + 1,
        preserveTurnWallClock: true,
      );
      return;
    }

    await _handlePostTurnSessionState(afterSuccessfulMessage: true);
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
            'The agent is still working on a reply.',
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
    final hasAttachments =
        _attachedImages.isNotEmpty ||
        _attachedVideos.isNotEmpty ||
        _attachedPdfs.isNotEmpty ||
        _pendingWhatsAppFilePath != null;
    return !_isStreaming &&
        !_isContextLimitBlocked &&
        !_wouldExceedContextLimit &&
        (hasText || hasAttachments);
  }

  bool get _isResponseInProgress => _isLoading || _isStreaming;

  bool get _isBusyBlockingNavigation => _isResponseInProgress;

  bool get _hasChatStateToClear {
    return _activeSession != null ||
        _messages.isNotEmpty ||
        _timelineItems.isNotEmpty ||
        _messageController.text.trim().isNotEmpty ||
        _attachedImages.isNotEmpty ||
        _attachedVideos.isNotEmpty ||
        _attachedPdfs.isNotEmpty ||
        _pendingWhatsAppFilePath != null;
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
            'The agent is still working on a reply.',
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

  bool _hasPendingCommandApproval(List<ChatMessageBlock> blocks) {
    return blocks.any(
      (block) =>
          block.type == ChatMessageBlockType.toolCall &&
          block.toolCall != null &&
          !block.toolCall!.isComplete,
    );
  }

  bool _hasRecoverableEditToolFailure(List<ChatMessageBlock> blocks) {
    final latestTool = _latestCompletedTool(blocks, successfulOnly: false);
    if (latestTool == null ||
        latestTool.status != ToolCallStatus.failed ||
        !_isEditToolName(latestTool.name)) {
      return false;
    }

    final decoded = _decodeToolResult(latestTool.result);
    if (decoded is! Map) return false;
    final result = Map<String, dynamic>.from(decoded);

    final error = result['error']?.toString().toLowerCase() ?? '';
    final suggestions = result['suggestions'];
    return suggestions is List &&
        suggestions.isNotEmpty &&
        (error.contains('could not find') ||
            error.contains('oldtext') ||
            error.contains('unique') ||
            error.contains('not found'));
  }

  bool _hasRecoverableFileAccessToolFailure(List<ChatMessageBlock> blocks) {
    final latestTool = _latestCompletedTool(blocks, successfulOnly: false);
    if (latestTool == null || latestTool.status != ToolCallStatus.failed) {
      return false;
    }

    final toolName = latestTool.name.trim().toLowerCase();
    if (toolName != 'read' &&
        toolName != 'edit' &&
        toolName != 'read_workspace_file' &&
        toolName != 'edit_workspace_file') {
      return false;
    }

    final decoded = _decodeToolResult(latestTool.result);
    if (decoded is! Map) return false;
    final result = Map<String, dynamic>.from(decoded);
    final error = [result['error'], result['file_error']]
        .whereType<Object>()
        .map((value) => value.toString().toLowerCase())
        .join('\n');

    return error.contains('could not read') ||
        error.contains('dioexception') ||
        error.contains('bad response') ||
        error.contains('connection') ||
        error.contains('timed out') ||
        error.contains('socketexception') ||
        error.contains('httpexception');
  }

  bool _isEditToolName(String name) {
    final normalized = name.trim().toLowerCase();
    return normalized == 'edit' || normalized == 'edit_workspace_file';
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

  Future<void> _updateToolCallResultInTimeline(
    ToolCall sourceToolCall,
    Map<String, dynamic> result, {
    required bool markComplete,
  }) async {
    final sourceId = sourceToolCall.id;
    if (sourceId == null || sourceId.isEmpty) return;

    for (
      var timelineIndex = _timelineItems.length - 1;
      timelineIndex >= 0;
      timelineIndex--
    ) {
      final item = _timelineItems[timelineIndex];
      if (item is! _TimelineMessageItem) continue;

      final blocks = _cloneBlocks(_getMessageBlocks(item.message));
      final blockIndex = blocks.indexWhere(
        (block) =>
            block.type == ChatMessageBlockType.toolCall &&
            block.toolCall?.id == sourceId,
      );
      if (blockIndex < 0) continue;

      final currentBlock = blocks[blockIndex];
      final currentTool = currentBlock.toolCall;
      if (currentTool == null) return;

      final commandResult = result['command_result'];
      final success = result['approval_decision'] == 'denied'
          ? false
          : commandResult is Map
          ? commandResult['success'] == true ||
                commandResult['ok'] == true ||
                (commandResult['success'] != false &&
                    commandResult['error'] == null)
          : true;
      final updatedTool = currentTool.copyWith(
        result: _formatToolResult(result),
        status: markComplete
            ? (success ? ToolCallStatus.completed : ToolCallStatus.failed)
            : result['approval_decision'] == 'approved'
            ? ToolCallStatus.calling
            : currentTool.status,
        isComplete: markComplete,
      );
      blocks[blockIndex] = currentBlock.copyWith(
        toolCall: updatedTool,
        isComplete: markComplete,
      );
      final updatedMessage = item.message.copyWith(
        blocks: blocks,
        toolCalls: _toolCallsFromBlocks(blocks),
        isToolCallsComplete: !blocks.any(
          (block) =>
              block.type == ChatMessageBlockType.toolCall &&
              !(block.toolCall?.isComplete ?? block.isComplete),
        ),
      );

      setState(() {
        _replaceTimelineMessageAt(timelineIndex, updatedMessage);
      });

      if (item.entryId != null) {
        await _chatSessions.updateMessageEntry(
          entryId: item.entryId!,
          message: updatedMessage,
        );
      }
      return;
    }
  }

  Future<void> _handleCommandApprovalResolved(
    ToolCall sourceToolCall,
    Map<String, dynamic> result,
  ) async {
    await _updateToolCallResultInTimeline(
      sourceToolCall,
      result,
      markComplete: true,
    );
    final sourceId = sourceToolCall.id;
    if (sourceId == null || sourceId.isEmpty) return;

    _recordApprovalResolutionInProviderHistory(
      toolCallId: sourceId,
      result: result,
    );

    // Check if there are still other pending approvals in the last assistant
    // message. If so, wait until ALL are resolved before resuming.
    final lastAssistantMessage = _messages.isNotEmpty
        ? _messages.lastWhere(
            (m) => !m.isUser,
            orElse: () =>
                ChatMessage(text: '', isUser: false, timestamp: DateTime.now()),
          )
        : null;
    final hasOtherPendingApprovals =
        lastAssistantMessage != null &&
        _hasPendingCommandApproval(_getMessageBlocks(lastAssistantMessage));

    if (mounted && !hasOtherPendingApprovals) {
      unawaited(
        _resumeAfterCommandApproval(
          wasApproved: result['approval_decision'] == 'approved',
        ),
      );
    }
  }

  void _recordApprovalResolutionInProviderHistory({
    required String toolCallId,
    required Map<String, dynamic> result,
  }) {
    final nextState = _provider.exportConversationState();
    final commandResult = result['command_result'];
    final toolContent = _formatToolResult(
      commandResult is Map ? commandResult : result,
    );
    for (var i = nextState.length - 1; i >= 0; i--) {
      final item = nextState[i];
      if (item['role'] == 'tool' && item['tool_call_id'] == toolCallId) {
        item['content'] = toolContent ?? '';
        break;
      }
    }
    _provider.loadConversationState(nextState);
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
      if (payloadType == NotificationPayloadType.approval) {
        final approvalPayload = NotificationService.instance
            .parseApprovalPayload(payload);
        if (approvalPayload == null) continue;
        _resolveApprovalNotificationAction(
          actionId: actionId,
          payload: approvalPayload,
        );
      } else if (actionId == NotificationActions.openApp ||
          actionId == NotificationActions.dismiss) {
        // Nothing to do; opening the app already navigates here.
      }
    }
  }

  /// Resolve an approval that was triggered from a notification action.
  void _resolveApprovalNotificationAction({
    required String actionId,
    required ApprovalNotificationPayload payload,
  }) {
    if (actionId != NotificationActions.approve &&
        actionId != NotificationActions.deny) {
      return;
    }
    final approved = actionId == NotificationActions.approve;

    // Find the most recent assistant message with a pending approval that
    // matches the payload request ID.
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.isUser) continue;
      final blocks = _getMessageBlocks(message);
      for (final block in blocks) {
        if (block.type != ChatMessageBlockType.toolCall) continue;
        final toolCall = block.toolCall;
        if (toolCall == null ||
            toolCall.status != ToolCallStatus.awaitingApproval) {
          continue;
        }
        final decoded = _decodeToolResult(toolCall.result);
        if (decoded is! Map) continue;
        final request = decoded['approval_request'];
        if (request is! Map) continue;
        final requestId = request['id']?.toString() ?? '';
        if (requestId.isEmpty) continue;
        // Match using the actual approval request ID if available, otherwise fall back to tool call ID.
        final matchId = payload.approvalRequestId ?? payload.requestId;
        if (requestId != matchId) continue;

        unawaited(
          _resolveApprovalFromToolCall(
            toolCall: toolCall,
            request: Map<String, dynamic>.from(request),
            approved: approved,
          ),
        );
        return;
      }
    }
  }

  /// Resolve an approval given the source tool call and its decoded request.
  Future<void> _resolveApprovalFromToolCall({
    required ToolCall toolCall,
    required Map<String, dynamic> request,
    required bool approved,
  }) async {
    final kind = request['kind']?.toString() ?? '';
    if (kind == 'local_github_branch_delete') {
      await _resolveLocalGithubBranchDeleteApproval(
        sourceToolCall: toolCall,
        request: request,
        approved: approved,
      );
    } else if (kind == 'local_tool') {
      await _resolveLocalToolApproval(
        sourceToolCall: toolCall,
        request: request,
        approved: approved,
      );
    } else {
      await _resolveCommandApproval(
        sourceToolCall: toolCall,
        request: request,
        approved: approved,
      );
    }
  }

  Future<void> _resumeAfterCommandApproval({bool wasApproved = true}) async {
    if (_isContextLimitBlocked || _wouldExceedContextLimit || !_isModelReady) {
      return;
    }
    _messageController.text = wasApproved
        ? 'Continue after the approved command. Analyze the command result and answer my original request concisely.'
        : 'The user denied the command. Please respond to the user explaining what the command was for and suggest alternative approaches or ask for clarification.';
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
    await _sendMessage(appendUserMessage: false, preserveTurnWallClock: true);
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
    final hasAgenticBlocks = blocks.any(
      (block) => block.type != ChatMessageBlockType.response,
    );
    if (!hasAgenticBlocks) {
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
    final blocks = _getEffectiveBlocks(messageIndex, isFinalInTurn);
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

  void _showErrorToast(String message) {
    showAppToast(context, message: message, type: ToastificationType.error);
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
    if (blocks.isEmpty || _hasPendingCommandApproval(blocks)) {
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
        r'\n\n`[^`]+` was written in your workspace before the model stopped responding\.$',
      ),
      RegExp(
        r'\n\n`[^`]+` is ready, but the model stopped before finishing the response\.$',
      ),
      RegExp(
        r'\n\nEdited `?[^`\n]+`?\. The model finished the tool call but did not send a final summary\.$',
      ),
      RegExp(
        r'\n\nWrote `?[^`\n]+`? in your workspace\. The model finished the tool call but did not send a final summary\.$',
      ),
      RegExp(
        r'\n\n`?[^`\n]+`? is ready\. The model finished the tool call but did not send a final summary\.$',
      ),
      RegExp(
        r'\n\nApplied a patch in your workspace\. The model finished the tool call but did not send a final summary\.$',
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
        (trimmed.contains(
              'The model finished the tool call but did not send a final summary.',
            ) &&
            (trimmed.startsWith('Edited ') ||
                trimmed.startsWith('Wrote ') ||
                trimmed.startsWith('Applied a patch') ||
                trimmed.endsWith(
                  'is ready. The model finished the tool call but did not send a final summary.',
                ))) ||
        trimmed.endsWith('before the model stopped responding.') ||
        trimmed.endsWith(
          'but the model stopped before finishing the response.',
        ) ||
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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isAppInBackground = true;
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
        body: Stack(
          children: [
            Positioned.fill(child: _buildBody()),
            _buildTopChrome(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(child: _buildComposerFade()),
            ),
            Align(alignment: Alignment.bottomCenter, child: _buildInputArea()),
          ],
        ),
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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
                      _buildAppBarControlSurface(
                        theme,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPillAppBarButton(
                              theme,
                              icon: CupertinoIcons.slider_horizontal_3,
                              tooltip: 'Model',
                              onPressed: _navigateToModelSelection,
                            ),
                            _buildPillAppBarButton(
                              theme,
                              icon: CupertinoIcons.settings,
                              tooltip: 'Settings',
                              onPressed: _openSettingsScreen,
                            ),
                          ],
                        ),
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

  Widget _buildAppBarControlSurface(ThemeData theme, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
      child: child,
    );
  }

  Widget _buildPillAppBarButton(
    ThemeData theme, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: theme.colorScheme.onSurface, size: 25),
        splashRadius: 24,
      ),
    );
  }


  Widget _buildBody() {
    if (_timelineItems.isEmpty) {
      return _buildEmptyState();
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleChatScrollNotification,
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 112, bottom: 112),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(2000.0),
            itemCount: _timelineItems.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _timelineItems.length && _isLoading) {
                return _buildLoadingMessage();
              }
              final item = _timelineItems[index];
              // ValueKey preserves widget state (e.g. expanded/collapsed agentic
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
    );
  }

  Key _timelineItemKey(_TimelineViewItem item, int index) {
    return switch (item) {
      _TimelineMessageItem() => ValueKey('message_${item.messageIndex}'),
      _TimelineStatusItem() => ValueKey('status_${item.entryId ?? index}'),
    };
  }

  Widget _buildEmptyState() {
    return ChatEmptyState(
      onPromptTap: (prompt) {
        _messageController.text = prompt;
        _messageController.selection = TextSelection.collapsed(
          offset: prompt.length,
        );
        _sendMessage();
      },
    );
  }

  String get _workspaceDisplayName {
    if (_workspaceLabel != null && _workspaceLabel!.isNotEmpty) {
      return _workspaceLabel!;
    }
    final root = _workspaceRoot;
    if (root == null || root.isEmpty) {
      return '';
    }
    return _folderNameFromPath(root);
  }

  String _folderNameFromPath(String path) {
    return path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;
  }


  Widget _buildTimelineItem(_TimelineViewItem item) {
    switch (item) {
      case _TimelineMessageItem():
        return _buildMessageBubble(
          item.message,
          messageIndex: item.messageIndex,
        );
      case _TimelineStatusItem():
        return _buildStatusCard(item);
    }
  }

  Future<void> _openHistoryScreen() async {
    // Refresh sessions list in background. If we have a cache, the history
    // screen opens immediately on the first frame; the cache is swapped in when
    // fresh data arrives so the user never sees a shimmer on repeat opens.
    final sessionsFuture = _chatSessions.listRecentSessions();

    // Pre-load future captured the moment the user taps a session tile so the
    // DB query runs during the 240 ms close animation rather than after it.
    Future<LoadedChatSession?>? preloadFuture;

    final selection = await showGeneralDialog<ChatHistorySelection>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Chat History',
      barrierColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final historyWidth = screenWidth < 600 ? screenWidth : 500.0;

        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: historyWidth,
            height: double.infinity,
            child: FutureBuilder<List<ChatSessionSummary>>(
              future: sessionsFuture,
              // Cached list renders the screen on the very first frame so
              // there is no shimmer on repeat opens.
              initialData: _cachedSessionSummaries,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return ChatHistoryLoadingScreen(
                    onClose: () => Navigator.of(context).pop(),
                  );
                }

                return ChatHistoryScreen(
                  sessions: snapshot.data!,
                  currentSessionId: _activeSession?.id,
                  onClose: () => Navigator.of(context).pop(),
                  onNewChat: () => Navigator.of(
                    context,
                  ).pop(const ChatHistorySelection.newChat()),
                  onSessionSelected: (sessionId) {
                    // Start the DB load immediately; by the time the close
                    // animation finishes the data is likely already in memory.
                    preloadFuture = _chatSessions.loadSession(sessionId);
                    Navigator.of(
                      context,
                    ).pop(ChatHistorySelection.openSession(sessionId));
                  },
                  onSessionDeleted: _deleteHistorySession,
                  onSessionRenamed: _renameHistorySession,
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );

    // Update the cache with the freshly fetched list.
    sessionsFuture.then((sessions) {
      if (mounted) _cachedSessionSummaries = sessions;
    });

    if (!mounted || selection == null) return;

    if (selection.createNewChat) {
      await _resetToFreshDraft();
      return;
    }

    final sessionId = selection.sessionId;
    if (sessionId == null) return;

    await _loadPersistedSession(sessionId, preloadFuture: preloadFuture);
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
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: isKeyboardVisible ? 12 : 32),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: isKeyboardVisible ? 8 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 56, maxHeight: 148),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.outline.withValues(alpha: 0.2)
                      : theme.colorScheme.outline.withValues(alpha: 0.06),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
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
                        enabled: !_isContextLimitBlocked,
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
                    builder: (context, canSend, child) =>
                        _buildComposerSendButton(theme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

    final canSend = _canSubmitCurrentMessage && !_isContextLimitBlocked;
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












  Future<void> _navigateToModelSelection({
    bool fromContextLimitCard = false,
  }) async {
    _unfocusComposer();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ModelSelectorScreen(
          modelType: widget.config.modelName,
          themeColor: Theme.of(context).colorScheme.primary,
          selectedModel: _selectedModel,
          iconPath: widget.config.iconPath,
        ),
      ),
    );

    if (result != null && result != _selectedModel) {
      await _changeModel(result);
      if (fromContextLimitCard && _activeSession != null) {
        await _appendStatusCard(
          kind: kChatStatusModelChanged,
          data: {
            'model_id': result,
            'model_name': _currentModelInfo?.name ?? result,
          },
          lifecycleState: ChatSessionLifecycleState.idle,
          flags: _activeSession!.flags,
        );
        await _handlePostTurnSessionState();
      }
    }
  }

  Widget _buildMessageBubble(ChatMessage message, {int? messageIndex}) {
    final theme = Theme.of(context);
    // O(1) identity checks instead of O(n) indexOf scan.
    final isLastMessage =
        _messages.isNotEmpty && identical(message, _messages.last);
    final resolvedMessageIndex =
        messageIndex ??
        (isLastMessage
            ? _messages.length - 1
            : _messages.indexWhere((m) => identical(m, message)));

    if (message.isUser) {
      final userBubbleColor = theme.colorScheme.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.24 : 0.12,
      );
      final userTextColor = theme.colorScheme.onSurface;

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
          onLongPress: () =>
              _confirmDeleteUserMessage(message, resolvedMessageIndex),
          child: Container(
            margin: const EdgeInsets.only(left: 12, right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            ),
            decoration: BoxDecoration(
              color: userBubbleColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(8),
              ),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.14 : 0.06,
                ),
              ),
            ),
            child: buildContent(),
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
      final isCurrentlyStreaming =
          _isStreaming && resolvedMessageIndex == _streamingMessageIndex;
      final isFollowedByAssistant =
          resolvedMessageIndex < _messages.length - 1 &&
          !_messages[resolvedMessageIndex + 1].isUser;
      if (isFollowedByAssistant) {
        return const SizedBox.shrink();
      }
      _hasPendingCommandApproval(
        _getMessageBlocks(message),
      );
      _shouldShowRetryContinue(
        message,
        resolvedMessageIndex,
      );
      _shareableAssistantText(
        message,
        resolvedMessageIndex,
      );
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
                  _buildAgenticMessageBody(
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
    if (blocks.isEmpty || _hasPendingCommandApproval(blocks)) {
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

  Duration _getTurnDuration(int endIndex) {
    var total = Duration.zero;
    var startIndex = endIndex;
    for (var i = endIndex; i >= 0; i--) {
      if (_messages[i].isUser) {
        startIndex = i + 1;
        break;
      }
      startIndex = i;
    }
    for (var i = startIndex; i <= endIndex; i++) {
      if (!_messages[i].isUser && _messages[i].responseTime != null) {
        total += _messages[i].responseTime!;
      }
    }
    return total;
  }

  bool _isTurnInProgress(int endIndex) {
    if (_streamingMessageIndex == null) return false;

    var startIndex = endIndex;
    for (var i = endIndex; i >= 0; i--) {
      if (_messages[i].isUser) {
        startIndex = i + 1;
        break;
      }
      startIndex = i;
    }

    var turnEndIndex = endIndex;
    for (var i = endIndex + 1; i < _messages.length; i++) {
      if (_messages[i].isUser) break;
      turnEndIndex = i;
    }

    return _streamingMessageIndex! >= startIndex &&
        _streamingMessageIndex! <= turnEndIndex &&
        !_messages[_streamingMessageIndex!].isUser;
  }

  Widget _buildAgenticMessageBody(
    ChatMessage message,
    int messageIndex,
    bool isCurrentlyStreaming,
  ) {
    const double blockSpacing = 6;
    const double activityEntrySpacing = 3;

    // Only show reconnecting UI for actual network issues:
    // - When waiting for network to come back online
    // - When all reconnection attempts have been exhausted (max reached)
    // During normal retry attempts, show the cursor placeholder instead
    final isReconnecting =
        isCurrentlyStreaming &&
        (_isWaitingForNetwork ||
            (_isReconnectingStream &&
                _reconnectAttempt >= _maxReconnectAttempts));
    final isFinalInTurn =
        messageIndex == _messages.length - 1 ||
        _messages[messageIndex + 1].isUser;
    final blocks = _getEffectiveBlocks(messageIndex, isFinalInTurn);
    final hasAgenticBlocks = blocks.any(
      (block) => block.type != ChatMessageBlockType.response,
    );
    _screenshotUrlsFromMessage(message);
    _recordingUrlsFromMessage(message);
    _audioRecordingUrlsFromMessage(message);
    _fileInfosFromBlocks(blocks);
    final currentModel = AIModels.getModelById(
      widget.config.modelName,
      _selectedModel,
    );
    final shouldRenderOpenResponseAsProcess =
        isCurrentlyStreaming &&
        isFinalInTurn &&
        (currentModel?.supportsToolCall ?? false) &&
        _hasOpenResponseBlock(blocks);
    if (!hasAgenticBlocks) {
      if (shouldRenderOpenResponseAsProcess) {
        final turnInProgress = _isTurnInProgress(messageIndex);
        final Duration duration;
        if (turnInProgress && _turnWallClockStart != null) {
          duration = DateTime.now().difference(_turnWallClockStart!);
        } else if (_turnWallClockDurations.containsKey(messageIndex)) {
          duration = _turnWallClockDurations[messageIndex]!;
        } else {
          duration = _getTurnDuration(messageIndex);
        }

        final children = <Widget>[
          AgenticActivitySection(
            durationLabel: _formatWorkedDuration(
              duration,
              isInProgress: turnInProgress,
            ),
            initiallyExpanded: true,
            isInProgress: turnInProgress,
            detailsBuilder: (context) =>
                AgenticProcessTextSection(text: message.text),
          ),
        ];

        if (isReconnecting) {
          children
            ..add(const SizedBox(height: blockSpacing))
            ..add(const ChatLoadingLottie(size: 48, reverse: true));
        } else {
          children
            ..add(const SizedBox(height: blockSpacing))
            ..add(_buildStreamingCursorPlaceholder());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.text.trim().isNotEmpty)
            _buildResponseMarkdown(
              message.text,
              isStreaming: isCurrentlyStreaming,
            ),
          if (isReconnecting ||
              (isCurrentlyStreaming && message.text.trim().isEmpty)) ...[
            if (message.text.trim().isNotEmpty) const SizedBox(height: 6),
            const ChatLoadingLottie(size: 48, reverse: true),
          ],
        ],
      );
    }

    int streamingResponseIndex = -1;
    if (isCurrentlyStreaming) {
      for (int i = blocks.length - 1; i >= 0; i--) {
        if (blocks[i].type == ChatMessageBlockType.response &&
            !blocks[i].isComplete) {
          streamingResponseIndex = i;
          break;
        }
      }
    }

    final visibleBlocks = <ChatMessageBlock>[];
    final seenThinkingTexts = <String>{};

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.type == ChatMessageBlockType.thinking) {
        if (_isPlaceholderThinkingText(block.text)) {
          continue;
        }
        final thinkingSignature = _thinkingTextSignature(block.text);
        if (thinkingSignature != null &&
            seenThinkingTexts.contains(thinkingSignature)) {
          continue;
        }
        if (block.text?.isNotEmpty ?? false) {
          if (thinkingSignature != null) {
            seenThinkingTexts.add(thinkingSignature);
          }
          visibleBlocks.add(block);
        }
        continue;
      }
      if (block.type == ChatMessageBlockType.toolCall) {
        if (!_shouldShowToolCall(block.toolCall)) {
          continue;
        }
        visibleBlocks.add(block);
        continue;
      }
      if (block.text?.isNotEmpty ?? false) {
        visibleBlocks.add(block);
      }
    }

    final children = <Widget>[];
    final mergedEntries =
        <
          ({
            String? text,
            bool isStreaming,
            ToolCall? toolCall,
            ChatMessageBlockType type,
            bool isComplete,
          })
        >[];
    final responseBuffer = StringBuffer();
    bool mergedStreaming = false;

    void flushResponseBuffer() {
      final text = responseBuffer.toString();
      if (text.isEmpty) {
        return;
      }
      mergedEntries.add((
        text: text,
        isStreaming: mergedStreaming,
        toolCall: null,
        type: ChatMessageBlockType.response,
        isComplete: !mergedStreaming,
      ));
      responseBuffer.clear();
      mergedStreaming = false;
    }

    for (int index = 0; index < visibleBlocks.length; index++) {
      final block = visibleBlocks[index];
      final originalIndex = blocks.indexOf(block);

      if (block.type == ChatMessageBlockType.response) {
        responseBuffer.write(block.text ?? '');
        mergedStreaming =
            mergedStreaming ||
            (isCurrentlyStreaming && originalIndex == streamingResponseIndex);
        continue;
      }

      flushResponseBuffer();

      mergedEntries.add((
        text: block.text,
        isStreaming: false,
        toolCall: block.toolCall,
        type: block.type,
        isComplete: block.isComplete,
      ));
    }

    flushResponseBuffer();

    final lastVisibleEntry = mergedEntries.isEmpty ? null : mergedEntries.last;
    final lastVisibleEntryIsStreamingResponse =
        lastVisibleEntry != null &&
        lastVisibleEntry.type == ChatMessageBlockType.response &&
        lastVisibleEntry.isStreaming;

    Widget buildEntries(
      List<
        ({
          String? text,
          bool isStreaming,
          ToolCall? toolCall,
          ChatMessageBlockType type,
          bool isComplete,
        })
      >
      entries, {
      required bool responseAsProcess,
    }) {
      final entryChildren = <Widget>[];
      int index = 0;
      while (index < entries.length) {
        final entry = entries[index];

        if (index > 0) {
          entryChildren.add(const SizedBox(height: activityEntrySpacing));
        }

        if (entry.type == ChatMessageBlockType.thinking) {
          entryChildren.add(
            _buildResponseMarkdown(
              entry.text ?? '',
              isStreaming: entry.isStreaming,
            ),
          );
          index++;
          continue;
        }

        if (entry.type == ChatMessageBlockType.toolCall &&
            entry.toolCall != null) {
          final toolCalls = <ToolCall>[];
          int cursor = index;
          while (cursor < entries.length &&
              entries[cursor].type == ChatMessageBlockType.toolCall &&
              entries[cursor].toolCall != null) {
            toolCalls.add(entries[cursor].toolCall!);
            cursor++;
          }

          Widget buildToolSection(ToolCall toolCall) {
            if (toolCall.status == ToolCallStatus.awaitingApproval) {
              _scheduleCommandApprovalDialog(toolCall);
            }
            final toolSection = AgenticToolCallSection(
              key: ValueKey('tool_${toolCall.id}'),
              toolCall: toolCall,
              themeColor: Theme.of(context).colorScheme.primary,
              isInProgress: !toolCall.isComplete,
              markdownNormalizer: _prepareMarkdownForDisplay,
              onLinkTap: _handleMarkdownLinkTap,
              onCommandApprovalResolved: _handleCommandApprovalResolved,
              linkBuilder: (context, linkText, url, style) =>
                  _buildStyledMarkdownLink(
                    context,
                    linkText: linkText,
                    url: url,
                    style: style,
                  ),
            );
            return toolSection;
          }

          for (var i = 0; i < toolCalls.length; i++) {
            if (i > 0) {
              entryChildren.add(const SizedBox(height: activityEntrySpacing));
            }
            entryChildren.add(buildToolSection(toolCalls[i]));
          }

          index = cursor;
          continue;
        }

        entryChildren.add(
          responseAsProcess
              ? AgenticProcessTextSection(text: entry.text ?? '')
              : _buildResponseMarkdown(
                  entry.text ?? '',
                  isStreaming: entry.isStreaming,
                ),
        );
        index++;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entryChildren,
      );
    }

    final hasVisibleToolCalls = mergedEntries.any(
      (entry) => entry.type == ChatMessageBlockType.toolCall,
    );
    final hasVisibleThinking = mergedEntries.any(
      (entry) => entry.type == ChatMessageBlockType.thinking,
    );
    if (hasVisibleToolCalls || hasVisibleThinking) {
      // Schedule approval dialogs
      for (final entry in mergedEntries) {
        if (entry.toolCall?.status == ToolCallStatus.awaitingApproval) {
          _scheduleCommandApprovalDialog(entry.toolCall!);
        }
      }

      // Show all entries inline (thinking + tool calls + response)
      children.add(buildEntries(mergedEntries, responseAsProcess: false));
    } else {
      int index = 0;
      while (index < mergedEntries.length) {
        final entry = mergedEntries[index];

        if (index > 0) {
          children.add(const SizedBox(height: blockSpacing));
        }

        if (entry.type == ChatMessageBlockType.thinking) {
          children.add(
            RepaintBoundary(
              child: AgenticThinkingSection(
                text: entry.text ?? '',
                themeColor: Theme.of(context).colorScheme.primary,
                isComplete: entry.isComplete,
              ),
            ),
          );
          index++;
          continue;
        }

        if (entry.type == ChatMessageBlockType.toolCall &&
            entry.toolCall != null) {
          final toolCalls = <ToolCall>[];
          int cursor = index;
          while (cursor < mergedEntries.length &&
              mergedEntries[cursor].type == ChatMessageBlockType.toolCall &&
              mergedEntries[cursor].toolCall != null) {
            toolCalls.add(mergedEntries[cursor].toolCall!);
            cursor++;
          }

          Widget buildToolSection(ToolCall toolCall) {
            final toolSection = AgenticToolCallSection(
              key: ValueKey('tool_${toolCall.id}'),
              toolCall: toolCall,
              themeColor: Theme.of(context).colorScheme.primary,
              isInProgress: !toolCall.isComplete,
              markdownNormalizer: _prepareMarkdownForDisplay,
              onLinkTap: _handleMarkdownLinkTap,
              onCommandApprovalResolved: _handleCommandApprovalResolved,
              linkBuilder: (context, linkText, url, style) =>
                  _buildStyledMarkdownLink(
                    context,
                    linkText: linkText,
                    url: url,
                    style: style,
                  ),
            );
            return toolSection;
          }

          for (var i = 0; i < toolCalls.length; i++) {
            if (i > 0) {
              children.add(const SizedBox(height: blockSpacing));
            }
            children.add(buildToolSection(toolCalls[i]));
          }

          index = cursor;
          continue;
        }

        children.add(
          _buildResponseMarkdown(
            entry.text ?? '',
            isStreaming: entry.isStreaming,
          ),
        );
        index++;
      }
    }

    if (isReconnecting) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: blockSpacing));
      }
      children.add(const ChatLoadingLottie(size: 48, reverse: true));
    } else if (isCurrentlyStreaming && !lastVisibleEntryIsStreamingResponse) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: blockSpacing));
      }
      children.add(_buildStreamingCursorPlaceholder());
    }


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  bool _hasOpenResponseBlock(List<ChatMessageBlock> blocks) {
    return blocks.any(
      (block) =>
          block.type == ChatMessageBlockType.response &&
          !block.isComplete &&
          (block.text?.trim().isNotEmpty ?? false),
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

  String? _thinkingTextSignature(String? text) {
    final normalized = (text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? null : normalized.toLowerCase();
  }

  String _formatWorkedDuration(
    Duration duration, {
    required bool isInProgress,
  }) {
    final prefix = isInProgress ? 'Working for' : 'Worked for';
    final seconds = duration.inSeconds.clamp(0, 1 << 31);
    if (seconds < 60) {
      return '$prefix ${seconds}s';
    }

    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) {
      return remainingSeconds == 0
          ? '$prefix ${minutes}m'
          : '$prefix ${minutes}m ${remainingSeconds}s';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$prefix ${hours}h'
        : '$prefix ${hours}h ${remainingMinutes}m';
  }

  Widget _buildStreamingCursorPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: StreamingTextReveal(
        text: '',
        isStreaming: true,
        textAlign: TextAlign.start,
        style: AppTheme.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
          height: 1.5,
        ),
        cursorColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  List<String> _screenshotUrlsFromMessage(ChatMessage message) {
    final urls = <String>[];
    final seen = <String>{};

    void addFromToolCall(ToolCall? toolCall) {
      final imageUrl = _screenshotUrlFromToolCall(toolCall);
      if (imageUrl == null || !seen.add(imageUrl)) return;
      urls.add(imageUrl);
    }

    for (final toolCall in message.toolCalls ?? const <ToolCall>[]) {
      addFromToolCall(toolCall);
    }

    for (final block in message.blocks ?? const <ChatMessageBlock>[]) {
      addFromToolCall(block.toolCall);
    }

    return urls;
  }

  String? _screenshotUrlFromToolCall(ToolCall? toolCall) {
    if (toolCall == null ||
        (toolCall.name != 'remote_screenshot' &&
            toolCall.name != 'remote_camera_photo')) {
      return null;
    }
    if (toolCall.status != ToolCallStatus.completed) {
      return null;
    }

    final decoded = _decodeToolResult(toolCall.result);
    if (decoded is! Map) return null;

    final imageUrl = decoded['image_url'];
    if (imageUrl is! String) return null;

    final trimmed = imageUrl.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _recordingUrlsFromMessage(ChatMessage message) {
    final urls = <String>[];
    final seen = <String>{};

    void addFromToolCall(ToolCall? toolCall) {
      final videoUrl = _recordingUrlFromToolCall(toolCall);
      if (videoUrl == null || !seen.add(videoUrl)) return;
      urls.add(videoUrl);
    }

    for (final toolCall in message.toolCalls ?? const <ToolCall>[]) {
      addFromToolCall(toolCall);
    }

    for (final block in message.blocks ?? const <ChatMessageBlock>[]) {
      addFromToolCall(block.toolCall);
    }

    return urls;
  }

  String? _recordingUrlFromToolCall(ToolCall? toolCall) {
    if (toolCall == null ||
        (toolCall.name != 'remote_screen_recording' &&
            toolCall.name != 'remote_camera_video')) {
      return null;
    }
    if (toolCall.status != ToolCallStatus.completed) {
      return null;
    }

    final decoded = _decodeToolResult(toolCall.result);
    if (decoded is! Map) return null;

    final videoUrl = decoded['video_url'];
    if (videoUrl is! String) return null;

    final trimmed = videoUrl.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _audioRecordingUrlsFromMessage(ChatMessage message) {
    final urls = <String>[];
    final seen = <String>{};

    void addFromToolCall(ToolCall? toolCall) {
      final audioUrl = _audioRecordingUrlFromToolCall(toolCall);
      if (audioUrl == null || !seen.add(audioUrl)) return;
      urls.add(audioUrl);
    }

    for (final toolCall in message.toolCalls ?? const <ToolCall>[]) {
      addFromToolCall(toolCall);
    }

    for (final block in message.blocks ?? const <ChatMessageBlock>[]) {
      addFromToolCall(block.toolCall);
    }

    return urls;
  }

  String? _audioRecordingUrlFromToolCall(ToolCall? toolCall) {
    if (toolCall == null || toolCall.name != 'remote_audio_recording') {
      return null;
    }
    if (toolCall.status != ToolCallStatus.completed) {
      return null;
    }

    final decoded = _decodeToolResult(toolCall.result);
    if (decoded is! Map) return null;

    final audioUrl = decoded['audio_url'];
    if (audioUrl is! String) return null;

    final trimmed = audioUrl.trim();
    return trimmed.isEmpty ? null : trimmed;
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




  List<Map<String, dynamic>> _fileInfosFromBlocks(
    List<ChatMessageBlock> blocks,
  ) {
    final infos = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final block in blocks) {
      final info = _fileInfoFromToolCall(block.toolCall);
      if (info == null) continue;
      final url = info['file_url'] as String;
      if (!seen.add(url)) continue;
      infos.add(info);
    }
    return infos;
  }

  Map<String, dynamic>? _fileInfoFromToolCall(ToolCall? toolCall) {
    if (toolCall == null || toolCall.name != 'send_file') return null;
    if (toolCall.status != ToolCallStatus.completed) return null;

    final decoded = _decodeToolResult(toolCall.result);
    if (decoded is! Map) return null;

    final fileUrl = decoded['file_url'];
    if (fileUrl is! String || fileUrl.trim().isEmpty) return null;

    return {
      'file_url': fileUrl.trim(),
      'filename': decoded['filename'] as String? ?? 'file',
      'size_bytes': (decoded['size_bytes'] as num?)?.toInt() ?? 0,
      'mime_type': decoded['mime_type'] as String?,
    };
  }

  Widget _buildResponseMarkdown(String text, {required bool isStreaming}) {
    return ChatResponseMarkdown(
      text: text,
      isStreaming: isStreaming,
      onLinkTap: _handleMarkdownLinkTap,
      onTokenTap: _handleMarkdownTokenTap,
    );
  }

  String _prepareMarkdownForDisplay(String text) {
    return normalizeChatResponseMarkdown(text);
  }

  Widget _buildStyledMarkdownLink(
    BuildContext context, {
    required InlineSpan linkText,
    required String url,
    required TextStyle style,
  }) {
    return buildChatResponseMarkdownLink(
      context,
      linkText: linkText,
      url: url,
      style: style,
      onLinkTap: _handleMarkdownLinkTap,
    );
  }

  Future<void> _handleMarkdownLinkTap(String url, String title) async {
    await _showMarkdownLinkActions(url: url, title: title);
  }

  Future<void> _openMarkdownUrlExternal(String url) async {
    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null || !parsedUri.hasScheme) {
      showAppToast(
        context,
        message: 'Invalid link',
        type: ToastificationType.error,
      );
      return;
    }

    final launched = await launchUrl(
      parsedUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      showAppToast(
        context,
        message: 'Could not open link',
        type: ToastificationType.error,
      );
    }
  }

  Future<void> _handleMarkdownTokenTap(String token) async {
    final normalized = _cleanMarkdownActionToken(token);
    if (normalized.isEmpty) return;
    await _showMarkdownTokenActions(normalized);
  }

  Future<void> _showMarkdownLinkActions({
    required String url,
    required String title,
  }) async {
    final theme = Theme.of(context);
    final label = title.trim().isEmpty ? url : title.trim();
    await ResponsiveInfoSheet.show<void>(
      context,
      title: label,
      headerIcon: Icon(
        CupertinoIcons.link,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _MarkdownActionTile(
          icon: CupertinoIcons.arrow_up_right_square,
          title: 'Open Link',
          subtitle: url,
          onTap: () {
            Navigator.pop(context);
            unawaited(_openMarkdownUrlExternal(url));
          },
        ),
        _MarkdownActionTile(
          icon: CupertinoIcons.doc_on_doc,
          title: 'Copy Link',
          subtitle: url,
          onTap: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.pop(context);
            showAppToast(
              context,
              message: 'Link copied',
              type: ToastificationType.success,
            );
          },
        ),
      ],
    );
  }

  Future<void> _showMarkdownTokenActions(String token) async {
    final theme = Theme.of(context);
    final fileCandidate = _looksLikeWorkspacePath(token);
    await ResponsiveInfoSheet.show<void>(
      context,
      title: token,
      headerIcon: Icon(
        fileCandidate ? CupertinoIcons.doc_text_search : CupertinoIcons.scope,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        if (_hasWorkspaceForMarkdownActions && fileCandidate)
        if (_hasWorkspaceForMarkdownActions)
          _MarkdownActionTile(
            icon: CupertinoIcons.search,
            title: 'Find Definition And Uses',
            subtitle: _workspaceDisplayName,
            onTap: () {
              Navigator.pop(context);
          
            },
          ),
        _MarkdownActionTile(
          icon: CupertinoIcons.doc_on_doc,
          title: 'Copy',
          subtitle: token,
          onTap: () {
            Clipboard.setData(ClipboardData(text: token));
            Navigator.pop(context);
            showAppToast(
              context,
              message: 'Copied',
              type: ToastificationType.success,
            );
          },
        ),
        if (!_hasWorkspaceForMarkdownActions)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              'Connect a workspace to search definitions and usages.',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  bool get _hasWorkspaceForMarkdownActions =>
      (_workspaceRoot ?? '').trim().isNotEmpty;

  String _cleanMarkdownActionToken(String token) {
    var value = token.trim();
    const leadingTrim = {'`', '"', "'", ' ', '\n', '\r', '\t'};
    const trailingTrim = {
      '`',
      '"',
      "'",
      ' ',
      '\n',
      '\r',
      '\t',
      '.',
      ',',
      ';',
      ':',
    };
    while (value.isNotEmpty && leadingTrim.contains(value[0])) {
      value = value.substring(1);
    }
    while (value.isNotEmpty && trailingTrim.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    return value.trim();
  }

  bool _looksLikeWorkspacePath(String token) {
    final clean = _cleanMarkdownActionToken(token);
    if (clean.contains('/') || clean.contains('\\')) return true;
    return RegExp(
      r'\.(dart|py|js|ts|tsx|jsx|java|kt|swift|go|rs|json|ya?ml|md|txt|html|css|scss|xml|sql|sh)$',
      caseSensitive: false,
    ).hasMatch(clean);
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

  Future<String> _buildAgentFlowPromptSnapshot() async {
    try {
      return await buildAgenticSystemPromptSnapshotForDiagnostics();
    } catch (error) {
      debugPrint('[UnifiedChatScreen] Could not build prompt snapshot: $error');
      return '';
    }
  }

  Map<String, dynamic> _buildAgentFlowMetadata({
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
      'agentFlowUserMessage': userMessage,
      'agentFlowProviderMessage': providerMessage,
      'agentFlowSystemPrompt': promptPreview,
      'agentFlowSystemPromptIsSnapshot': trimmedPrompt.isNotEmpty,
      'agentFlowSystemPromptTruncated': trimmedPrompt.length > maxPromptChars,
      'agentFlowPromptLength': trimmedPrompt.length,
      'agentFlowModel': _selectedModel,
      'agentFlowProvider': widget.config.modelName,
      'agentFlowStartedAt': DateTime.now().toIso8601String(),
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






  Widget _buildStatusCard(_TimelineStatusItem item) {
    final data = item.data;
    final kind = item.kind;
    final isActiveContextLimit =
        kind == kChatStatusContextLimitReached &&
        item.entryId != null &&
        _activeSession?.flags.activeContextLimitEntryId == item.entryId &&
        (_activeSession?.flags.isContextLimitBlocked ?? false);

    return TimelineStatusCard(
      kind: kind,
      data: data,
      isActiveContextLimit: isActiveContextLimit,
      onChangeModel: _handleContextLimitChangeModel,
    );
  }


  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _confirmDeleteUserMessage(
    ChatMessage message,
    int messageIndex,
  ) async {
    final confirmed = await _showDeleteConfirmationDialog(
      'Delete this message?',
      'This will remove your message from the current chat so it is not sent to the AI in subsequent messages.',
    );
    if (confirmed != true || !mounted) return;
    await _deleteMessage(messageIndex);
  }


  Future<bool?> _showDeleteConfirmationDialog(
    String title,
    String message,
  ) async {
    final theme = Theme.of(context);
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: title,
      headerIcon: Icon(
        CupertinoIcons.trash,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          message,
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 0,
                    side: BorderSide(color: theme.colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteMessage(int messageIndex) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;

    final message = _messages[messageIndex];

    // Find the timeline entry and its index
    final timelineIndex = _timelineIndexForMessageIndex(messageIndex);
    if (timelineIndex == null) return;

    final entryId = _timelineEntryIdForMessageIndex(messageIndex);

    // Remove from provider history
    if (message.isUser) {
      _removeProviderUserMessageFromHistory(message.text);
    } else {
      _removeProviderAssistantMessageFromHistory(message.text);
    }

    // Delete from database
    if (entryId != null) {
      await _chatSessions.deleteTimelineEntry(entryId: entryId);
    }

    // Remove from local state
    setState(() {
      _timelineItems.removeAt(timelineIndex);
      _rebuildMessagesFromTimeline();

      // Adjust streaming message index if needed
      if (_streamingMessageIndex != null &&
          _streamingMessageIndex! > messageIndex) {
        _streamingMessageIndex = _streamingMessageIndex! - 1;
      } else if (_streamingMessageIndex == messageIndex) {
        _streamingMessageIndex = null;
      }
    });

    // Sync provider state to session
    if (_activeSession != null) {
      await _syncProviderStateToSession();
      await _handlePostTurnSessionState();
    }
  }

  /// The most recent response's prompt tokens — represents the actual
  /// context window size currently in use. Used for limit checks.
  int get _currentContextPromptTokens {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.isUser) continue;
      final metadata = message.responseMetadata;
      if (metadata == null) continue;

      final rounds = metadata['usageRounds'] as List?;
      if (rounds != null && rounds.isNotEmpty) {
        final lastRound = rounds.last;
        if (lastRound is Map) {
          final promptTokens = lastRound['promptTokens'];
          if (promptTokens is num) return promptTokens.round();
        }
      }

      final promptTokens = metadata['promptTokens'];
      if (promptTokens is num) return promptTokens.round();
    }
    return 0;
  }

  int get _estimatedConversationTokens => _currentContextPromptTokens;



  String? _buildStreamTimeoutFallback(List<ChatMessageBlock> blocks) {
    final successfulWorkspaceTool = _latestCompletedWorkspaceMutationTool(
      blocks,
      successfulOnly: true,
    );
    if (successfulWorkspaceTool == null) {
      return null;
    }

    final filePath = (successfulWorkspaceTool.arguments['path'] ?? '')
        .toString()
        .trim();
    final fileName = filePath.isEmpty
        ? 'generated file'
        : _fileNameFromPath(filePath);

    if (_hasResponseAfterToolBlock(blocks, successfulWorkspaceTool.id)) {
      return '\n\nThe model stopped responding after finishing the tool call.';
    }

    if (_hasActiveWorkspaceContext) {
      return '\n\n`$fileName` was written in your workspace before the model stopped responding.';
    }

    return '\n\n`$fileName` is ready, but the model stopped before finishing the response.';
  }

  String? _buildPostToolCompletionFallback(List<ChatMessageBlock> blocks) {
    final latestTool = _latestCompletedTool(blocks, successfulOnly: false);
    if (latestTool == null ||
        _hasResponseAfterToolBlock(blocks, latestTool.id)) {
      return null;
    }

    final toolName = latestTool.name.trim().toLowerCase();
    final filePath = (latestTool.arguments['path'] ?? '').toString().trim();
    final fileLabel = filePath.isEmpty ? 'the file' : '`$filePath`';
    final isWorkspaceMutationTool = {
      'write_workspace_file',
      'edit_workspace_file',
      'write',
      'edit',
      'patch',
    }.contains(toolName);

    if (latestTool.status == ToolCallStatus.failed && isWorkspaceMutationTool) {
      if (_hasRecoverableEditToolFailure(blocks)) {
        return null;
      }
      return '\n\nThe last tool call failed. Open the tool details above for the exact error and retry context.';
    }

    if (toolName == 'edit_workspace_file' || toolName == 'edit') {
      return '\n\nEdited $fileLabel. The model finished the tool call but did not send a final summary.';
    }

    if (toolName == 'write_workspace_file' || toolName == 'write') {
      return _hasActiveWorkspaceContext
          ? '\n\nWrote $fileLabel in your workspace. The model finished the tool call but did not send a final summary.'
          : '\n\n$fileLabel is ready. The model finished the tool call but did not send a final summary.';
    }

    if (toolName == 'patch') {
      return '\n\nApplied a patch in your workspace. The model finished the tool call but did not send a final summary.';
    }

    if (toolName == 'bash' ||
        toolName == 'terminal_command' ||
        toolName == 'git_repository' ||
        toolName == 'makefile_command') {
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

  ToolCall? _latestCompletedWorkspaceMutationTool(
    List<ChatMessageBlock> blocks, {
    required bool successfulOnly,
  }) {
    const mutationTools = {
      'write_workspace_file',
      'edit_workspace_file',
      'write',
      'edit',
      'patch',
    };

    for (int i = blocks.length - 1; i >= 0; i--) {
      final toolCall = blocks[i].toolCall;
      if (blocks[i].type != ChatMessageBlockType.toolCall || toolCall == null) {
        continue;
      }
      if (!mutationTools.contains(toolCall.name.trim().toLowerCase())) {
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

  bool get _hasActiveWorkspaceContext {
    return _visibleConnectedWorkspaces.isNotEmpty;
  }


  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  Widget _buildLoadingMessage() {
    return ChatLoadingMessage(
      iconPath: widget.config.iconPath,
      message: "Just a sec -- I'm thinking",
    );
  }

  bool _shouldShowToolCall(ToolCall? toolCall) {
    if (toolCall == null) return false;

    final hasNamedTool =
        toolCall.name.trim().isNotEmpty &&
        toolCall.name.trim().toLowerCase() != 'tool call';
    final hasArguments = toolCall.arguments.isNotEmpty;
    final hasResult = _hasMeaningfulToolResult(toolCall.result);

    return hasNamedTool || hasArguments || hasResult;
  }

  bool _isLoopDetectedToolCall(ToolCall toolCall) {
    final decoded = _decodeToolResult(toolCall.result);
    if (decoded is! Map) return false;
    final error = decoded['error']?.toString().toLowerCase() ?? '';
    return error.contains('tool call loop detected');
  }

  bool _hasMeaningfulToolResult(String? result) {
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;
    if (trimmed == '{}' || trimmed == '[]' || trimmed == 'null') return false;
    return true;
  }
}
