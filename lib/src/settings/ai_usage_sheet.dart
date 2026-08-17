import 'dart:async';

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AiUsageAppBarAction extends StatelessWidget {
  const AiUsageAppBarAction({super.key});

  static Future<void> show(BuildContext context) async {
    unawaited(AiUsageService.instance.refresh());
    final theme = Theme.of(context);
    await ResponsiveInfoSheet.show(
      context,
      title: 'AI Usage This Month',
      headerIcon: Icon(
        CupertinoIcons.speedometer,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: const [_AiUsageContent()],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      key: const ValueKey('settings-ai-usage-action'),
      tooltip: 'AI usage',
      onPressed: () => show(context),
      icon: AnimatedBuilder(
        animation: Listenable.merge([
          AiUsageService.instance.usage,
          AiUsageService.instance.isLoading,
        ]),
        builder: (context, _) {
          final info = AiUsageService.instance.usage.value;
          if (info == null) {
            return SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            );
          }
          final color = _usageColor(theme, info);
          return SizedBox.square(
            dimension: 26,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: info.enabled ? info.quotaFraction : 1,
                    strokeWidth: 2.6,
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                Text(
                  info.enabled ? '${(info.quotaFraction * 100).round()}%' : '!',
                  style: AppTheme.bodySmall.copyWith(
                    color: color,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AiUsageContent extends StatelessWidget {
  const _AiUsageContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        AiUsageService.instance.usage,
        AiUsageService.instance.isLoading,
      ]),
      builder: (context, _) {
        final info = AiUsageService.instance.usage.value;
        if (info == null || AiUsageService.instance.isLoading.value) {
          return _loading(theme);
        }
        final color = _usageColor(theme, info);
        return Column(
          children: [
            _overview(theme, info, color),
            const SizedBox(height: 12),
            if (!info.enabled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'Due to some irrelevant activity, your access to AI has '
                  'been blocked. Please contact support if you believe this '
                  'is a mistake.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      theme,
                      CupertinoIcons.bolt,
                      'Requests',
                      info.requestsUsed,
                      info.requestsLimit,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metric(
                      theme,
                      CupertinoIcons.textformat_123,
                      'Tokens',
                      info.tokensUsed,
                      info.tokensLimit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _metric(
                theme,
                CupertinoIcons.bolt_fill,
                'Fast requests',
                info.fastRequestsUsed,
                info.fastRequestsLimit,
              ),
              const SizedBox(height: 12),
              _renewal(theme, info.renewsOn),
            ],
          ],
        );
      },
    );
  }

  Widget _loading(ThemeData theme) => Column(
    children: List.generate(
      3,
      (index) => Container(
        height: index == 0 ? 96 : 64,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );

  Widget _overview(ThemeData theme, AiUsageInfo info, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        SizedBox.square(
          dimension: 68,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: info.enabled ? info.quotaFraction : 1,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              Text(
                info.enabled ? '${(info.quotaFraction * 100).round()}%' : '!',
                style: AppTheme.headingSmall.copyWith(
                  color: color,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.enabled ? 'Monthly quota used' : 'AI access disabled',
                style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                info.enabled
                    ? 'The limit closest to full controls this percentage.'
                    : 'AI requests are disabled for this account.',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _metric(
    ThemeData theme,
    IconData icon,
    String label,
    int used,
    int limit,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.colorScheme.outline.withValues(alpha: 0.3),
      ),
    ),
    child: Column(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: 7),
        Text(
          label,
          style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        FittedBox(
          child: Text(
            '${_count(used)} / ${_count(limit)}',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );

  Widget _renewal(ThemeData theme, DateTime date) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.colorScheme.outline.withValues(alpha: 0.3),
      ),
    ),
    child: Column(
      children: [
        Icon(CupertinoIcons.calendar, color: theme.colorScheme.primary),
        const SizedBox(height: 7),
        Text(
          'Renews ${_date(date)}',
          style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          'Monthly limits reset at 00:00 UTC',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  String _count(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  String _date(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

Color _usageColor(ThemeData theme, AiUsageInfo info) {
  if (!info.enabled || info.quotaFraction >= 1) return theme.colorScheme.error;
  if (info.quotaFraction >= 0.85) return Colors.orange;
  return theme.colorScheme.primary;
}
