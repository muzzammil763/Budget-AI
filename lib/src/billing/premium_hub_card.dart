import 'package:budget_ai/src/billing/paywall_screen.dart';
import 'package:budget_ai/src/billing/premium_gate.dart';
import 'package:budget_ai/src/billing/premium_plans.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Budget Hub's Premium card: the current plan, this month's AI messages,
/// and Upgrade or Manage subscription.
class PremiumHubCard extends StatelessWidget {
  const PremiumHubCard({super.key});

  static final Uri _manageUri = Uri.parse(
    'https://play.google.com/store/account/subscriptions'
    '?package=com.budgetai.android',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        AiUsageService.instance.usage,
        SubscriptionService.instance.tier,
      ]),
      builder: (context, _) {
        final usage = AiUsageService.instance.usage.value;
        final tier = PremiumGate.tierOf(usage);
        final plan = PremiumPlanInfo.of(tier);
        final muted = theme.colorScheme.onSurfaceVariant;
        final isTop = tier == PremiumTier.pro;
        final hasStoreSubscription =
            SubscriptionService.instance.tier.value != PremiumTier.free;

        return Container(
          key: const ValueKey('premium-hub-card'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    tier == PremiumTier.free
                        ? CupertinoIcons.sparkles
                        : CupertinoIcons.checkmark_seal_fill,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tier == PremiumTier.free
                          ? 'Free plan'
                          : 'Budget AI ${plan.name}',
                      style: AppTheme.headingSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _subtitle(usage, plan),
                style: AppTheme.bodyMedium.copyWith(color: muted),
              ),
              if (usage != null && usage.messagesLimit > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: usage.messagesFraction,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${usage.messagesUsed} of ${usage.messagesLimit} AI messages '
                  'used · resets ${PremiumGate.resetDateLabel(usage.renewsOn)}',
                  style: AppTheme.bodySmall.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!isTop)
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('premium-hub-upgrade'),
                        text: tier == PremiumTier.free
                            ? 'Unlock Premium'
                            : 'Upgrade',
                        height: 44,
                        onPressed: () => PaywallScreen.show(context),
                      ),
                    ),
                  if (!isTop && hasStoreSubscription) const SizedBox(width: 8),
                  if (hasStoreSubscription)
                    Expanded(
                      child: AppButton(
                        text: 'Manage',
                        height: 44,
                        variant: AppButtonVariant.outlined,
                        onPressed: () => launchUrl(
                          _manageUri,
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _subtitle(AiUsageInfo? usage, PremiumPlanInfo plan) {
    if (plan.tier == PremiumTier.free) {
      return '1 free AI message a month. Manual entries, charts, and widgets '
          'are always free.';
    }
    final parts = ['${plan.messages} AI messages a month', plan.aiName];
    if (plan.deepAnalysis > 0) {
      final left = usage == null
          ? plan.deepAnalysis
          : (usage.deepLimit - usage.deepUsed).clamp(0, usage.deepLimit);
      parts.add('$left Deep analysis left');
    }
    final status = usage?.subscriptionStatus;
    final expires = usage?.subscriptionExpiresAt;
    if (status == 'cancelled' && expires != null) {
      parts.add('ends ${PremiumGate.resetDateLabel(expires.toLocal())}');
    } else if (status == 'grace' || status == 'billing_issue') {
      parts.add('payment issue — update it in Google Play');
    }
    return parts.join(' · ');
  }
}
