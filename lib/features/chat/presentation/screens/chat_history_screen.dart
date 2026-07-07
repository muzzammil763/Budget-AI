import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/data/repositories/chat_session_repository.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/chat/presentation/widgets/chat_loading_widgets.dart';
import 'package:toastification/toastification.dart';

class ChatHistorySelection {
  final String? sessionId;
  final bool createNewChat;

  const ChatHistorySelection._({
    required this.sessionId,
    required this.createNewChat,
  });

  const ChatHistorySelection.openSession(String sessionId)
    : this._(sessionId: sessionId, createNewChat: false);

  const ChatHistorySelection.newChat()
    : this._(sessionId: null, createNewChat: true);
}

class ChatHistoryScreen extends StatefulWidget {
  final List<ChatSessionSummary> sessions;
  final String? currentSessionId;
  final VoidCallback onClose;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSessionSelected;
  final Future<void> Function(String sessionId) onSessionDeleted;
  final Future<void> Function(String sessionId, String title) onSessionRenamed;

  const ChatHistoryScreen({
    super.key,
    required this.sessions,
    required this.currentSessionId,
    required this.onClose,
    required this.onNewChat,
    required this.onSessionSelected,
    required this.onSessionDeleted,
    required this.onSessionRenamed,
  });

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final ScrollController _scrollController;
  late List<ChatSessionSummary> _sessions;
  bool _isSearchMode = false;
  bool _isMutatingSession = false;

  List<ChatSessionSummary> get _visibleSessions {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _sessions;
    return _sessions
        .where((s) => s.title.toLowerCase().contains(query))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _sessions = _sortSessions(widget.sessions);
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant ChatHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.sessions, oldWidget.sessions)) {
      _sessions = _sortSessions(widget.sessions);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ChatSessionSummary> _sortSessions(List<ChatSessionSummary> sessions) {
    return [...sessions]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(sessionDay).inDays;

    if (diff == 0) {
      final h = date.hour;
      final m = date.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final display = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return 'Today $display:$m $period';
    } else if (diff == 1) {
      return 'Yesterday';
    } else if (diff < 7) {
      const days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return days[date.weekday - 1];
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _showDeleteAllChatHistoryConfirmation() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Delete All Chats?',
      message:
          'This will permanently remove every chat session, all messages, and attachment files. This action cannot be undone.',
      icon: CupertinoIcons.trash,
      confirmLabel: 'Continue',
    );

    if (confirmed != true || !mounted) return;

    final localAuth = LocalAuthentication();
    final canCheckBiometrics = await localAuth.canCheckBiometrics;
    final isDeviceSupported = await localAuth.isDeviceSupported();

    if (!canCheckBiometrics && !isDeviceSupported) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Biometrics not available on this device',
        type: ToastificationType.error,
      );
      return;
    }

    try {
      final authenticated = await localAuth.authenticate(
        localizedReason: 'Authenticate to delete all chat history',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!authenticated || !mounted) {
        if (mounted) {
          showAppToast(
            context,
            message: 'Authentication failed. Chat history was not deleted.',
            type: ToastificationType.error,
          );
        }
        return;
      }

      await ChatSessionRepository.instance.deleteAllSessions();

      if (!mounted) return;
      setState(() => _sessions.clear());
      showAppToast(
        context,
        message: 'All chat history has been deleted.',
        type: ToastificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Authentication error: ${e.toString()}',
        type: ToastificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = _visibleSessions;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onClose,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: _isSearchMode ? _buildSearchField() : const Text('Chat History'),
        actions: _isSearchMode
            ? [
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => setState(() {
                    _isSearchMode = false;
                    _searchController.clear();
                  }),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(CupertinoIcons.search),
                  onPressed: _sessions.isEmpty
                      ? null
                      : () => setState(() => _isSearchMode = true),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.square_pencil),
                  onPressed: widget.onNewChat,
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.trash),
                  onPressed: _sessions.isEmpty
                      ? null
                      : _showDeleteAllChatHistoryConfirmation,
                ),
              ],
      ),
      body: sessions.isEmpty
          ? _buildEmpty(theme)
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isActive = session.id == widget.currentSessionId;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index < sessions.length - 1 ? 8 : 0,
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(session.id),
                    child: _buildSessionTile(context, session, isActive),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final isSearching = _searchController.text.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              isSearching
                  ? CupertinoIcons.search
                  : CupertinoIcons.chat_bubble_2,
              size: 32,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isSearching ? 'No chats found' : 'No chat history yet',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearching
                ? 'Try a different search term.'
                : 'Start a conversation and\nit will show up here.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      autofocus: true,
      cursorColor: theme.colorScheme.primary,
      onChanged: (_) => setState(() {}),
      style: AppTheme.bodyLarge.copyWith(
        color: theme.colorScheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Search chats',
        hintStyle: AppTheme.bodyLarge.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
      ),
    );
  }

  Widget _buildSessionTile(
    BuildContext context,
    ChatSessionSummary session,
    bool isActive,
  ) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: InkWell(
        onTap: () => widget.onSessionSelected(session.id),
        onLongPress: () async {
          if (_isMutatingSession) return;
          final confirmed = await _confirmDeleteSession(session);
          if (confirmed && mounted) await _deleteSession(session);
        },
        borderRadius: BorderRadius.circular(32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.headingSmall.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(session.updatedAt),
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteSession(ChatSessionSummary session) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Delete Chat?',
      message:
          'This will permanently remove "${session.title}" from your history.',
      icon: CupertinoIcons.trash,
      confirmLabel: 'Delete',
    );
    return confirmed == true;
  }

  Future<void> _deleteSession(ChatSessionSummary session) async {
    setState(() => _isMutatingSession = true);
    try {
      await widget.onSessionDeleted(session.id);
      if (!mounted) return;
      setState(() => _sessions.removeWhere((item) => item.id == session.id));
    } finally {
      if (mounted) setState(() => _isMutatingSession = false);
    }
  }
}

class ChatHistoryLoadingScreen extends StatelessWidget {
  final VoidCallback onClose;

  const ChatHistoryLoadingScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: ChatShimmerBlock(
          width: 112,
          height: 20,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: 14,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  ChatShimmerBlock(
                    width: 20,
                    height: 20,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ChatShimmerBlock(
                          width: _ChatHistoryLoadingMetrics.titleWidth(index),
                          height: 14,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 6),
                        ChatShimmerBlock(
                          width: 80,
                          height: 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatHistoryLoadingMetrics {
  static double titleWidth(int index) {
    const widths = [220.0, 168.0, 260.0, 188.0, 236.0, 146.0];
    return widths[index % widths.length];
  }
}
