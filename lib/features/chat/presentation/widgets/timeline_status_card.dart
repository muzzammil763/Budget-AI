import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/data/repositories/chat_session_repository.dart';

class TimelineStatusCard extends StatelessWidget {
  final String kind;
  final Map<String, dynamic> data;
  final bool isActiveContextLimit;
  final VoidCallback onChangeModel;

  const TimelineStatusCard({
    super.key,
    required this.kind,
    required this.data,
    required this.isActiveContextLimit,
    required this.onChangeModel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final content = _statusContent(kind, data);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(content.icon, color: primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  content.title,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content.description,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (isActiveContextLimit) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onChangeModel,
              child: const Text('Change Model'),
            ),
          ],
        ],
      ),
    );
  }

  _TimelineStatusContent _statusContent(
    String kind,
    Map<String, dynamic> data,
  ) {
    switch (kind) {
      case kChatStatusContextLimitReached:
        final usedTokens = data['used_tokens']?.toString() ?? 'Unknown';
        final contextLimit = data['context_limit']?.toString() ?? 'Unknown';
        return _TimelineStatusContent(
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          title: 'Context limit reached',
          description:
              'This chat needs about $usedTokens tokens, but the current model only supports $contextLimit. Change the model before sending more messages.',
        );
      case kChatStatusModelChanged:
        return _TimelineStatusContent(
          icon: CupertinoIcons.arrow_swap,
          title: 'Model changed',
          description:
              'The active model is now ${data['model_name'] ?? data['model_id'] ?? 'the selected model'}.',
        );
      case kChatStatusWorkspaceUnavailable:
        return _TimelineStatusContent(
          icon: CupertinoIcons.folder_badge_minus,
          title: 'Workspace unavailable',
          description:
              'The saved workspace ${data['label'] ?? data['path'] ?? ''} could not be restored automatically.',
        );
      default:
        return const _TimelineStatusContent(
          icon: CupertinoIcons.info_circle,
          title: 'Session update',
          description: 'Saved session state',
        );
    }
  }
}

class _TimelineStatusContent {
  final IconData icon;
  final String title;
  final String description;

  const _TimelineStatusContent({
    required this.icon,
    required this.title,
    required this.description,
  });
}
