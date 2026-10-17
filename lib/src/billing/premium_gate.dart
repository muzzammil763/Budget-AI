import 'package:budget_ai/src/billing/paywall_screen.dart';
import 'package:budget_ai/src/billing/premium_plans.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Decides whether a new AI message (chat, voice, receipt, Monthly Summary)
/// may start, and answers refusals with the Premium sheet. The server
/// enforces the limits either way; this only avoids a wasted round trip.
class PremiumGate {
  PremiumGate._();

  /// Premium is sold on Android only; iOS keeps its legacy limits.
  static bool get paywallEnabled =>
      debugPaywallEnabled ?? AiUsageService.clientPlatform == 'android';

  @visibleForTesting
  static bool? debugPaywallEnabled;

  /// The server's plan wins; RevenueCat covers the seconds before the
  /// purchase webhook lands.
  static PremiumTier tierOf(AiUsageInfo? usage) {
    final serverTier = switch (usage?.plan) {
      AiPlanTier.lite => PremiumTier.lite,
      AiPlanTier.plus => PremiumTier.plus,
      AiPlanTier.pro => PremiumTier.pro,
      _ => PremiumTier.free,
    };
    final storeTier = SubscriptionService.instance.tier.value;
    return storeTier.index > serverTier.index ? storeTier : serverTier;
  }

  /// True when the next AI message can start. Otherwise shows the Premium
  /// sheet (or the reset date on the top plan) and returns whether a
  /// purchase unlocked it.
  static Future<bool> ensure(BuildContext context) async {
    final info = AiUsageService.instance.usage.value;
    if (!paywallEnabled || info == null || !info.enabled) return true;
    if (!info.blocksNewMessage) return true;
    // RevenueCat can report a purchase before its webhook reaches the server.
    if (!info.isPaid &&
        SubscriptionService.instance.tier.value != PremiumTier.free) {
      return true;
    }
    return _block(context, info);
  }

  /// Applies a server refusal (HTTP 402) the app could not predict.
  static Future<void> handleRefusal(
    BuildContext context,
    PremiumRequiredException error,
  ) async {
    AiUsageService.instance.markMessagesExhausted();
    final info = AiUsageService.instance.usage.value;
    if (!paywallEnabled) return;
    await _block(context, info, freeLimit: error.isFreeLimit);
  }

  static Future<bool> _block(
    BuildContext context,
    AiUsageInfo? info, {
    bool? freeLimit,
  }) async {
    final isFree = freeLimit ?? !(info?.isPaid ?? false);
    final isTopPlan = !isFree && info?.plan == AiPlanTier.pro;
    final seePlans = await _showSheet(
      context,
      isFree: isFree,
      isTopPlan: isTopPlan,
      renewsOn: info?.renewsOn,
    );
    if (seePlans != true || isTopPlan || !context.mounted) return false;
    return PaywallScreen.show(
      context,
      reason: isFree
          ? PaywallReason.freeMessageUsed
          : PaywallReason.planLimitReached,
    );
  }

  static Future<bool?> _showSheet(
    BuildContext context, {
    required bool isFree,
    required bool isTopPlan,
    DateTime? renewsOn,
  }) {
    final theme = Theme.of(context);
    final onPrimary = AppTheme.readableOn(theme.colorScheme.primary);
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: isFree ? 'Free AI messages used' : "This month's AI messages used",
      headerIcon: Icon(
        isFree ? CupertinoIcons.lock_open : CupertinoIcons.hourglass,
        size: 30,
        color: onPrimary,
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _PremiumSheetContent(
          isFree: isFree,
          isTopPlan: isTopPlan,
          resetLabel: renewsOn == null ? null : resetDateLabel(renewsOn),
        ),
      ],
    );
  }

  static String resetDateLabel(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _PremiumSheetContent extends StatelessWidget {
  const _PremiumSheetContent({
    required this.isFree,
    required this.isTopPlan,
    required this.resetLabel,
  });

  final bool isFree;
  final bool isTopPlan;
  final String? resetLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resets = resetLabel == null
        ? ''
        : ' Your limit resets on $resetLabel.';
    final intro = isFree
        ? "You've used this month's free AI messages. Manual entries, charts, "
              'and widgets stay free forever.'
        : isTopPlan
        ? "You've used all of this month's AI messages on Pro.$resets"
        : "You've used all of this month's AI messages on your plan. "
              'Upgrade for more, or wait for the monthly reset.$resets';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            intro,
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          if (!isTopPlan) ...[
            for (final plan in PremiumPlanInfo.paid)
              if (isFree || plan.tier != PremiumTier.lite)
                _PlanPoint(plan: plan),
            const SizedBox(height: 8),
            AppButton(
              key: const ValueKey('premium-sheet-see-plans'),
              text: 'See Premium plans',
              icon: CupertinoIcons.sparkles,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('premium-sheet-not-now'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ] else
            AppButton(
              key: const ValueKey('premium-sheet-ok'),
              text: 'Got it',
              onPressed: () => Navigator.of(context).pop(false),
            ),
        ],
      ),
    );
  }
}

class _PlanPoint extends StatelessWidget {
  const _PlanPoint({required this.plan});

  final PremiumPlanInfo plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extras = [
      plan.aiName,
      if (plan.deepAnalysis > 0) '${plan.deepAnalysis} Deep analysis',
      if (plan.fastReplies > 0) '${plan.fastReplies} Fast replies',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              plan.tier == PremiumTier.pro
                  ? CupertinoIcons.star_fill
                  : plan.tier == PremiumTier.plus
                  ? CupertinoIcons.sparkles
                  : CupertinoIcons.bolt,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.name} · ${plan.messages} AI messages a month',
                    style: AppTheme.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    extras,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
