import 'dart:async';

import 'package:budget_ai/src/billing/premium_plans.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:budget_ai/src/settings/legal_screens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Why the paywall opened; it only changes the headline.
enum PaywallReason { browse, freeMessageUsed, planLimitReached }

/// Budget AI Premium plans: Monthly/Yearly toggle, Lite/Plus/Pro cards, a
/// Free-to-Pro comparison, and Google Play's renewal terms.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    this.reason = PaywallReason.browse,
    this.subscriptions,
  });

  final PaywallReason reason;

  @visibleForTesting
  final SubscriptionService? subscriptions;

  /// Opens the paywall and resolves to true after a successful purchase or
  /// restore.
  static Future<bool> show(
    BuildContext context, {
    PaywallReason reason = PaywallReason.browse,
  }) async {
    final purchased = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaywallScreen(reason: reason),
      ),
    );
    return purchased ?? false;
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final SubscriptionService _subscriptions =
      widget.subscriptions ?? SubscriptionService.instance;
  PremiumPeriod _period = PremiumPeriod.yearly;
  PremiumTier _selected = PremiumTier.plus;
  List<PremiumPlanOption> _options = const [];
  bool _loadingPlans = true;
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    final current = _subscriptions.tier.value;
    if (current == PremiumTier.plus) _selected = PremiumTier.pro;
    unawaited(_loadPlans());
  }

  Future<void> _loadPlans() async {
    try {
      final options = await _subscriptions.loadPlans();
      if (mounted) setState(() => _options = options);
    } catch (error) {
      debugPrint('[Paywall] Could not load plans: $error');
    } finally {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  PremiumPlanOption? _option(PremiumTier tier, PremiumPeriod period) {
    for (final option in _options) {
      if (option.tier == tier && option.period == period) return option;
    }
    return null;
  }

  String _price(PremiumPlanInfo plan, PremiumPeriod period) =>
      _option(plan.tier, period)?.price ??
      (period == PremiumPeriod.yearly
          ? plan.fallbackYearly
          : plan.fallbackMonthly);

  Future<void> _purchase() async {
    final option = _option(_selected, _period);
    if (option == null) {
      showAppToast(
        context,
        message: _subscriptions.isAvailable
            ? 'Plans are still loading. Try again in a moment.'
            : 'Purchases are not available on this device yet.',
        type: ToastificationType.info,
      );
      return;
    }
    setState(() => _purchasing = true);
    final outcome = await _subscriptions.purchase(option);
    if (!mounted) return;
    setState(() => _purchasing = false);
    switch (outcome) {
      case PremiumPurchaseOutcome.purchased:
        await _finish(
          'Welcome to Budget AI ${PremiumPlanInfo.of(option.tier).name}!',
        );
      case PremiumPurchaseOutcome.pending:
        showAppToast(
          context,
          message:
              'Your payment is pending. Premium unlocks as soon as Google Play confirms it.',
          type: ToastificationType.info,
        );
      case PremiumPurchaseOutcome.cancelled:
        break;
      case PremiumPurchaseOutcome.failed:
        showAppToast(
          context,
          message: 'The purchase could not be completed. Please try again.',
          type: ToastificationType.error,
        );
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final tier = await _subscriptions.restore();
      if (!mounted) return;
      if (tier == PremiumTier.free) {
        showAppToast(
          context,
          message:
              'No active Budget AI subscription was found for this Google account.',
          type: ToastificationType.info,
        );
      } else {
        await _finish('${PremiumPlanInfo.of(tier).name} restored.');
      }
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Purchases could not be restored. Please try again.',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// The server learns about the purchase from RevenueCat's webhook, usually
  /// within seconds; refresh until the new plan shows up.
  Future<void> _finish(String message) async {
    showAppToast(context, message: message);
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await AiUsageService.instance.refresh();
      } catch (_) {}
      if (AiUsageService.instance.usage.value?.isPaid ?? false) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  String get _headline => switch (widget.reason) {
    PaywallReason.freeMessageUsed => 'Keep chatting\nwith Budget AI',
    PaywallReason.planLimitReached => 'Get more\nAI messages',
    PaywallReason.browse => 'Budget AI\nPremium',
  };

  String get _subtitle => switch (widget.reason) {
    PaywallReason.freeMessageUsed =>
      "You've used this month's free AI message. Manual entries, charts, and widgets stay free forever.",
    PaywallReason.planLimitReached =>
      "You've reached this month's AI messages on your plan. Upgrade for more, or wait for the monthly reset.",
    PaywallReason.browse =>
      'Log by chat, voice, and receipt photos, and ask anything about your spending.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _subscriptions.tier.value;
    final isCurrent = current == _selected && current != PremiumTier.free;
    final selectedPlan = PremiumPlanInfo.of(_selected);
    final busy = _purchasing || _restoring;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : _restore,
            child: _restoring
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Restore'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  Text(
                    _headline,
                    style: TextStyle(
                      fontFamily: 'Boldonse',
                      fontSize: 26,
                      height: 1.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _subtitle,
                    style: AppTheme.bodyLarge.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _PeriodToggle(
                    period: _period,
                    onChanged: (period) => setState(() => _period = period),
                  ),
                  const SizedBox(height: 14),
                  for (final plan in PremiumPlanInfo.paid) ...[
                    _PlanCard(
                      plan: plan,
                      price: _price(plan, _period),
                      perMonth: _period == PremiumPeriod.yearly
                          ? _option(plan.tier, _period)?.monthlyEquivalent
                          : null,
                      period: _period,
                      selected: _selected == plan.tier,
                      isCurrent: current == plan.tier,
                      onTap: () => setState(() => _selected = plan.tier),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                  const _ComparisonTable(),
                  const SizedBox(height: 16),
                  Text(
                    'Powered by OpenAI',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    key: const ValueKey('paywall-continue'),
                    text: isCurrent
                        ? 'Your current plan'
                        : 'Continue with ${selectedPlan.name} · '
                              '${_price(selectedPlan, _period)}'
                              '${_period == PremiumPeriod.yearly ? '/yr' : '/mo'}',
                    isLoading:
                        _purchasing ||
                        (_loadingPlans && _subscriptions.isAvailable),
                    onPressed: isCurrent || busy ? null : _purchase,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Renews automatically until cancelled. Cancel anytime in '
                    'Google Play › Payments & subscriptions at least 24 hours '
                    'before renewal. Upgrades start now with credit for unused '
                    'time; downgrades start at your next renewal.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodySmall.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _FinePrintLink(
                        label: 'Terms',
                        builder: (_) => const TermsScreen(),
                      ),
                      Text(
                        '·',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      _FinePrintLink(
                        label: 'Privacy',
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ],
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

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.period, required this.onChanged});

  final PremiumPeriod period;
  final ValueChanged<PremiumPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget segment(PremiumPeriod value, String label, String? badge) {
      final selected = period == value;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('paywall-period-${value.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge,
                        style: AppTheme.bodySmall.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          segment(PremiumPeriod.monthly, 'Monthly', null),
          segment(PremiumPeriod.yearly, 'Yearly', 'Save up to 30%'),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.price,
    required this.perMonth,
    required this.period,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  final PremiumPlanInfo plan;
  final String price;
  final String? perMonth;
  final PremiumPeriod period;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final features = [
      '${plan.messages} AI messages a month',
      '${plan.aiName} answers',
      if (plan.deepAnalysis > 0)
        '${plan.deepAnalysis} Deep analysis with Expert AI',
      plan.fastReplies > 0
          ? '${plan.fastReplies} Fast replies'
          : 'Voice and receipt photos',
    ];
    return GestureDetector(
      key: ValueKey('paywall-plan-${plan.tier.name}'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: selected ? 2 : 1,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: selected ? theme.colorScheme.primary : muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        plan.name,
                        style: AppTheme.headingSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (plan.tier == PremiumTier.plus)
                        _Badge(
                          label: 'Most popular',
                          color: theme.colorScheme.primary,
                        ),
                      if (isCurrent)
                        _Badge(label: 'Current', color: Colors.green.shade600),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final feature in features)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        feature,
                        style: AppTheme.bodyMedium.copyWith(color: muted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  period == PremiumPeriod.yearly ? 'per year' : 'per month',
                  style: AppTheme.bodySmall.copyWith(color: muted),
                ),
                if (perMonth != null)
                  Text(
                    '$perMonth/mo',
                    style: AppTheme.bodySmall.copyWith(color: muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: AppTheme.bodySmall.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const plans = [
      PremiumPlanInfo.free,
      PremiumPlanInfo.lite,
      PremiumPlanInfo.plus,
      PremiumPlanInfo.pro,
    ];
    final rows = <(String, List<String>)>[
      ('AI messages / month', [for (final p in plans) '${p.messages}']),
      ('AI', [for (final p in plans) p.aiName]),
      (
        'Deep analysis',
        [for (final p in plans) p.deepAnalysis > 0 ? '${p.deepAnalysis}' : '—'],
      ),
      (
        'Fast replies',
        [for (final p in plans) p.fastReplies > 0 ? '${p.fastReplies}' : '—'],
      ),
      ('Chat, voice & receipts', ['✓', '✓', '✓', '✓']),
      ('Manual entries, charts, widgets', ['✓', '✓', '✓', '✓']),
    ];

    Widget cell(String text, {bool header = false, bool label = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Text(
            text,
            textAlign: label ? TextAlign.start : TextAlign.center,
            style: (header ? AppTheme.bodySmall : AppTheme.bodySmall).copyWith(
              fontSize: 12,
              fontWeight: header || label ? FontWeight.w800 : FontWeight.w600,
              color: label ? theme.colorScheme.onSurface : muted,
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              cell('Compare plans', header: true, label: true),
              for (final p in plans) cell(p.name, header: true),
            ],
          ),
          for (final row in rows)
            TableRow(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                  ),
                ),
              ),
              children: [
                cell(row.$1, label: true),
                for (final value in row.$2) cell(value),
              ],
            ),
        ],
      ),
    );
  }
}

class _FinePrintLink extends StatelessWidget {
  const _FinePrintLink({required this.label, required this.builder});

  final String label;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: () =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)),
    child: Text(label, style: AppTheme.bodySmall.copyWith(fontSize: 12)),
  );
}
