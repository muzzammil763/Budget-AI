import 'dart:async';
import 'dart:math' as math;

import 'package:budget_ai/src/billing/bubble_style_access.dart';
import 'package:budget_ai/src/billing/premium_plans.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:budget_ai/src/settings/legal_screens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Why the paywall opened; it only changes the headline.
enum PaywallReason { browse, freeMessageUsed, planLimitReached }

/// Budget AI Premium: a hero with the benefits, Lite/Plus/Pro cards that each
/// open Monthly and Yearly options, a Free-to-Pro comparison, and Google
/// Play's renewal terms.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    this.reason = PaywallReason.browse,
    this.initialTier,
    this.subscriptions,
  });

  final PaywallReason reason;

  /// The plan card selected on open, e.g. the plan that unlocks a feature.
  final PremiumTier? initialTier;

  @visibleForTesting
  final SubscriptionService? subscriptions;

  /// Opens the paywall and resolves to true after a successful purchase or
  /// restore.
  static Future<bool> show(
    BuildContext context, {
    PaywallReason reason = PaywallReason.browse,
    PremiumTier? initialTier,
  }) async {
    final purchased = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaywallScreen(reason: reason, initialTier: initialTier),
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
  PremiumPeriod _period = PremiumPeriod.monthly;
  PremiumTier _selected = PremiumTier.plus;
  List<PremiumPlanOption> _options = const [];
  bool _loadingPlans = true;
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTier;
    if (initial != null && initial != PremiumTier.free) {
      _selected = initial;
    } else if (_subscriptions.tier.value == PremiumTier.plus) {
      _selected = PremiumTier.pro;
    }
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

  double? _priceValue(PremiumPlanInfo plan, PremiumPeriod period) {
    final store = _option(plan.tier, period)?.package.storeProduct.price;
    if (store != null && store > 0) return store;
    final fallback = period == PremiumPeriod.yearly
        ? plan.fallbackYearly
        : plan.fallbackMonthly;
    return double.tryParse(fallback.replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  /// How much cheaper a year is than twelve months, as a whole percent.
  int? _yearlySavings(PremiumPlanInfo plan) {
    final monthly = _priceValue(plan, PremiumPeriod.monthly);
    final yearly = _priceValue(plan, PremiumPeriod.yearly);
    if (monthly == null || yearly == null || monthly <= 0) return null;
    final percent = ((1 - yearly / (monthly * 12)) * 100).round();
    return percent > 0 ? percent : null;
  }

  /// A yearly price spread over twelve months, for "$6.67/mo".
  String? _yearlyPerMonth(PremiumPlanInfo plan) {
    final store = _option(plan.tier, PremiumPeriod.yearly)?.monthlyEquivalent;
    if (store != null) return store;
    final yearly = _priceValue(plan, PremiumPeriod.yearly);
    if (yearly == null) return null;
    final symbol = plan.fallbackYearly.replaceAll(RegExp(r'[0-9.,\s]'), '');
    return '$symbol${(yearly / 12).toStringAsFixed(2)}';
  }

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
    PaywallReason.freeMessageUsed => 'Keep your\nmoney talking',
    PaywallReason.planLimitReached => 'Get more\nAI messages',
    PaywallReason.browse => 'Budget AI\nPremium',
  };

  String get _subtitle => switch (widget.reason) {
    PaywallReason.freeMessageUsed =>
      "You've used this month's free AI messages. Pick a plan and keep logging in seconds.",
    PaywallReason.planLimitReached =>
      "You've reached this month's AI messages on your plan. Upgrade for more right now.",
    PaywallReason.browse =>
      'Your money assistant that logs, sorts, and explains every expense for you.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _subscriptions.tier.value;
    final isCurrent = current == _selected && current != PremiumTier.free;
    final selectedPlan = PremiumPlanInfo.of(_selected);
    final busy = _purchasing || _restoring;
    final isYearly = _period == PremiumPeriod.yearly;
    final ctaPrice =
        '${_price(selectedPlan, _period)}${isYearly ? '/year' : '/month'}';

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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _Hero(headline: _headline, subtitle: _subtitle),
                  const SizedBox(height: 18),
                  for (final plan in PremiumPlanInfo.paid) ...[
                    _PlanCard(
                      plan: plan,
                      selected: _selected == plan.tier,
                      isCurrent: current == plan.tier,
                      period: _period,
                      monthlyPrice: _price(plan, PremiumPeriod.monthly),
                      yearlyPrice: _price(plan, PremiumPeriod.yearly),
                      yearlyPerMonth: _yearlyPerMonth(plan),
                      yearlySavings: _yearlySavings(plan),
                      onTap: () => setState(() => _selected = plan.tier),
                      onPeriod: (period) => setState(() {
                        _selected = plan.tier;
                        _period = period;
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                  const _TrustRow(),
                  const SizedBox(height: 18),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                  _ShimmerButton(
                    key: const ValueKey('paywall-continue'),
                    tier: _selected,
                    label: isCurrent
                        ? 'Your current plan'
                        : 'Get ${selectedPlan.name} · $ctaPrice',
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

/// Dark gradient banner with the headline and what Premium unlocks. It stays
/// dark in both themes so the paywall always opens with the same look.
class _Hero extends StatelessWidget {
  const _Hero({required this.headline, required this.subtitle});

  final String headline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    const benefits = [
      (CupertinoIcons.mic_fill, 'Log by voice or a receipt photo'),
      (CupertinoIcons.chat_bubble_2_fill, 'Ask anything about your spending'),
      (CupertinoIcons.sparkles, 'Monthly summaries and smart insights'),
      (CupertinoIcons.paintbrush_fill, 'Exclusive message bubble styles'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF070B1C), Color(0xFF1B1550), Color(0xFF3A1F78)],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: 0,
            top: 0,
            child: Icon(
              CupertinoIcons.sparkles,
              color: Color(0xFFB9A4FF),
              size: 30,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: const TextStyle(
                  fontFamily: 'Boldonse',
                  fontSize: 23,
                  height: 1.55,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: AppTheme.bodyMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              for (final (icon, text) in benefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, size: 15, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text,
                          style: AppTheme.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.isCurrent,
    required this.period,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.yearlyPerMonth,
    required this.yearlySavings,
    required this.onTap,
    required this.onPeriod,
  });

  final PremiumPlanInfo plan;
  final bool selected;
  final bool isCurrent;
  final PremiumPeriod period;
  final String monthlyPrice;
  final String yearlyPrice;
  final String? yearlyPerMonth;
  final int? yearlySavings;
  final VoidCallback onTap;
  final ValueChanged<PremiumPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = premiumTierAccent(plan.tier);
    final summary = [
      '${plan.messages} AI messages a month',
      plan.aiName,
      if (plan.deepAnalysis > 0) '${plan.deepAnalysis} Deep analysis',
      if (plan.fastReplies > 0) '${plan.fastReplies} Fast replies',
      plan.tier == PremiumTier.pro
          ? 'All bubble styles + custom'
          : '${BubbleStyleAccess.presetCount(plan.tier)} bubble styles',
    ].join(' · ');

    return GestureDetector(
      key: ValueKey('paywall-plan-${plan.tier.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            width: selected ? 2 : 1,
            color: selected
                ? accent
                : theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PremiumTierBadge(tier: plan.tier, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
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
                              color: accent,
                              filled: true,
                            ),
                          if (isCurrent)
                            _Badge(
                              label: 'Current',
                              color: Colors.green.shade600,
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        summary,
                        style: AppTheme.bodySmall.copyWith(
                          color: muted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!selected) ...[
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        monthlyPrice,
                        style: AppTheme.bodyLarge.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'per month',
                        style: AppTheme.bodySmall.copyWith(color: muted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          _PeriodOption(
                            key: ValueKey(
                              'paywall-option-${plan.tier.name}-monthly',
                            ),
                            accent: accent,
                            selected: period == PremiumPeriod.monthly,
                            title: 'Monthly',
                            subtitle: 'Billed every month',
                            price: monthlyPrice,
                            priceSuffix: '/mo',
                            onTap: () => onPeriod(PremiumPeriod.monthly),
                          ),
                          const SizedBox(height: 8),
                          _PeriodOption(
                            key: ValueKey(
                              'paywall-option-${plan.tier.name}-yearly',
                            ),
                            accent: accent,
                            selected: period == PremiumPeriod.yearly,
                            title: 'Yearly',
                            subtitle: yearlyPerMonth == null
                                ? 'Billed once a year'
                                : 'Just $yearlyPerMonth/mo, billed yearly',
                            price: yearlyPrice,
                            priceSuffix: '/yr',
                            savings: yearlySavings,
                            onTap: () => onPeriod(PremiumPeriod.yearly),
                          ),
                        ],
                      ),
                    )
                  : yearlySavings == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8, left: 60),
                      child: Text(
                        'Save $yearlySavings% when you pay yearly',
                        style: AppTheme.bodySmall.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodOption extends StatelessWidget {
  const _PeriodOption({
    super.key,
    required this.accent,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.priceSuffix,
    required this.onTap,
    this.savings,
  });

  final Color accent;
  final bool selected;
  final String title;
  final String subtitle;
  final String price;
  final String priceSuffix;
  final int? savings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: selected ? 1.6 : 1,
            color: selected
                ? accent
                : theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.largecircle_fill_circle
                  : CupertinoIcons.circle,
              size: 20,
              color: selected ? accent : muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (savings != null)
                        _Badge(
                          label: 'SAVE $savings%',
                          color: Colors.green.shade600,
                          filled: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.bodySmall.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: price,
                    style: AppTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: priceSuffix,
                    style: AppTheme.bodySmall.copyWith(color: muted),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.filled = false});

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: AppTheme.bodySmall.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: filled ? Colors.white : color,
      ),
    ),
  );
}

/// The tier's mark, drawn like its Google Play subscription icon: the ring
/// fills further and the sparkles multiply from Lite to Pro.
class PremiumTierBadge extends StatelessWidget {
  const PremiumTierBadge({super.key, required this.tier, required this.size});

  final PremiumTier tier;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _TierBadgePainter(tier)),
  );
}

class _TierBadgePainter extends CustomPainter {
  const _TierBadgePainter(this.tier);

  final PremiumTier tier;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final accent = premiumTierAccent(tier);
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(s * 0.26)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF05070D),
            Color.lerp(const Color(0xFF05070D), accent, 0.28)!,
          ],
        ).createShader(rect),
    );

    final fill = switch (tier) {
      PremiumTier.pro => 1.0,
      PremiumTier.plus => 0.7,
      _ => 0.42,
    };
    final center = Offset(s * 0.5, s * 0.52);
    final radius = s * 0.31;
    final ring = Rect.fromCircle(center: center, radius: radius);
    final stroke = s * 0.045;
    const start = math.pi * 0.68;
    const sweep = math.pi * 1.53;
    canvas.drawArc(
      ring,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.22),
    );
    canvas.drawArc(
      ring,
      start,
      sweep * fill,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );

    final barPaint = Paint()..color = Colors.white;
    final barWidth = s * 0.085;
    final bottom = center.dy + s * 0.15;
    for (final (dx, height) in [(-0.12, 0.15), (0.0, 0.24), (0.12, 0.33)]) {
      final x = center.dx + s * dx - barWidth / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
          x,
          bottom - s * height,
          x + barWidth,
          bottom,
          Radius.circular(barWidth / 2),
        ),
        barPaint,
      );
    }

    final sparkles = switch (tier) {
      PremiumTier.pro => const [
        (0.82, 0.18, 0.1),
        (0.9, 0.36, 0.06),
        (0.66, 0.1, 0.05),
      ],
      PremiumTier.plus => const [(0.82, 0.18, 0.1), (0.9, 0.36, 0.06)],
      _ => const [(0.82, 0.18, 0.1)],
    };
    final sparklePaint = Paint()..color = accent;
    for (final (x, y, r) in sparkles) {
      canvas.drawPath(_sparkle(Offset(s * x, s * y), s * r), sparklePaint);
    }
  }

  Path _sparkle(Offset c, double r) {
    final k = r * 0.18;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(_TierBadgePainter old) => old.tier != tier;
}

/// The purchase button in the selected tier's colors, with a light sweep
/// that plays a few times to draw the eye, then rests.
class _ShimmerButton extends StatefulWidget {
  const _ShimmerButton({
    super.key,
    required this.tier,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final PremiumTier tier;
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  State<_ShimmerButton> createState() => _ShimmerButtonState();
}

class _ShimmerButtonState extends State<_ShimmerButton>
    with SingleTickerProviderStateMixin {
  // Each cycle sweeps during its first 60% and rests for the remainder.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _sweep.repeat(count: 4);
    });
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final accent = premiumTierAccent(widget.tier);
    final deep = premiumTierAccentDeep(widget.tier);
    return Opacity(
      opacity: widget.onPressed == null && !widget.isLoading ? 0.55 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: [deep, accent]),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? widget.onPressed : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, _) {
                          final t = _sweep.value / 0.6;
                          if (!_sweep.isAnimating || t >= 1) {
                            return const SizedBox.shrink();
                          }
                          final x = -1.6 + Curves.easeInOut.transform(t) * 3.2;
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(x - 0.5, -1),
                                end: Alignment(x + 0.5, 1),
                                colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: 0.32),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (widget.isLoading)
                    const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.label,
                          style: AppTheme.bodyLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Honest reassurance under the plans; no ratings or user counts.
class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const items = [
      (CupertinoIcons.arrow_uturn_left_circle, 'Cancel anytime'),
      (CupertinoIcons.lock_shield, 'Secure Google Play checkout'),
      (CupertinoIcons.hand_raised, 'No ads · data never sold'),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final (icon, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.green.shade600),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: AppTheme.bodySmall.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
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
      (
        'Bubble styles',
        [
          for (final p in plans)
            p.tier == PremiumTier.pro
                ? 'All'
                : '${BubbleStyleAccess.presetCount(p.tier)}',
        ],
      ),
      ('Custom bubble styles', ['—', '—', '—', '✓']),
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
