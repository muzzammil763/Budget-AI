part of 'unified_chat_screen.dart';

sealed class _TimelineViewItem {
  final int? entryId;

  const _TimelineViewItem({required this.entryId});
}

class _TimelineMessageItem extends _TimelineViewItem {
  final ChatMessage message;
  final int messageIndex;

  const _TimelineMessageItem({
    required this.message,
    required this.messageIndex,
    required super.entryId,
  });

  _TimelineMessageItem copyWith({
    ChatMessage? message,
    int? messageIndex,
    int? entryId,
  }) {
    return _TimelineMessageItem(
      message: message ?? this.message,
      messageIndex: messageIndex ?? this.messageIndex,
      entryId: entryId ?? this.entryId,
    );
  }
}
