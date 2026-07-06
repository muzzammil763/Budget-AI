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

class _ContextUsageBreakdown {
  final int currentContextTokens;
  final int? contextLimit;

  const _ContextUsageBreakdown({
    required this.currentContextTokens,
    required this.contextLimit,
  });

  int? get remainingTokens {
    final limit = contextLimit;
    if (limit == null || limit <= 0) return null;
    return limit - currentContextTokens;
  }

  bool get isOverLimit {
    final limit = contextLimit;
    return limit != null && limit > 0 && currentContextTokens >= limit;
  }

  double get progress {
    final limit = contextLimit;
    if (limit == null || limit <= 0) return 0;
    return (currentContextTokens / limit).clamp(0.0, 1.0);
  }

  int get percentUsed => (progress * 100).round();
}

// ignore: unused_element
class _ContextOverviewSummary extends StatelessWidget {
  final _ContextUsageBreakdown usage;
  final String modelName;
  final String percentLabel;
  final String remainingLabel;
  final String Function(int value) formatTokens;
  final String Function(int value) formatCompactTokens;

  const _ContextOverviewSummary({
    required this.usage,
    required this.modelName,
    required this.percentLabel,
    required this.remainingLabel,
    required this.formatTokens,
    required this.formatCompactTokens,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressColor = (usage.isOverLimit || usage.progress >= 0.80)
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final contextLimit = usage.contextLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 40,
                    width: 40,
                    child: CircularProgressIndicator(
                      value: contextLimit == null ? null : usage.progress,
                      strokeWidth: 3,
                      strokeCap: StrokeCap.round,
                      backgroundColor: progressColor.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                    ),
                  ),
                  Text(
                    percentLabel,
                    style: AppTheme.bodySmall.copyWith(
                      color: progressColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width:12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${formatTokens(usage.currentContextTokens)} tokens in context',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: contextLimit == null ? null : usage.progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(32),
          stopIndicatorRadius: 32,
          backgroundColor: progressColor.withValues(
            alpha: 0.1,
          ),
          valueColor: AlwaysStoppedAnimation<Color>(progressColor),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ContextMetric(
                label: 'Used',
                value: formatCompactTokens(usage.currentContextTokens),
              ),
            ),
            Container(
              width: 1,
              height: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(
              child: _ContextMetric(
                label: 'Remaining',
                value: remainingLabel,
              ),
            ),
            Container(
              width: 1,
              height: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(
              child: _ContextMetric(
                label: 'Limit',
                value: contextLimit == null
                    ? 'Unknown'
                    : formatCompactTokens(contextLimit),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ContextMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ContextMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}


class _MarkdownActionTile extends StatelessWidget {
  const _MarkdownActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Icon(icon, size: 20, color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ApprovalDetailsBox extends StatelessWidget {
  const _ApprovalDetailsBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: AppTheme.bodySmall.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurface,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _TimelineStatusItem extends _TimelineViewItem {
  final Map<String, dynamic> payload;

  const _TimelineStatusItem({required this.payload, required super.entryId});

  String get kind => payload['kind']?.toString() ?? 'unknown';

  Map<String, dynamic> get data {
    final rawData = payload['data'];
    if (rawData is Map<String, dynamic>) {
      return rawData;
    }
    if (rawData is Map) {
      return rawData.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  _TimelineStatusItem copyWith({Map<String, dynamic>? payload, int? entryId}) {
    return _TimelineStatusItem(
      payload: payload ?? this.payload,
      entryId: entryId ?? this.entryId,
    );
  }
}
