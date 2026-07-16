import 'dart:math';

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:flutter/material.dart';

class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({super.key, required this.onPromptTap});

  final ValueChanged<String> onPromptTap;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState> {
  static const _prompts = <(IconData, String)>[
    (Icons.pie_chart_outline_rounded, 'Break down my spending by category'),
    (Icons.savings_outlined, 'Help me plan a savings goal'),
    (Icons.trending_down_rounded, 'Where can I cut back this month?'),
    (Icons.calculate_outlined, 'Build me a 50/30/20 budget'),
    (Icons.calendar_month_outlined, 'What bills are coming up soon?'),
    (Icons.shopping_cart_outlined, 'Create a weekly grocery budget'),
    (
      Icons.account_balance_wallet_outlined,
      'How much can I safely spend today?',
    ),
    (Icons.query_stats_rounded, 'Compare this month with last month'),
    (Icons.manage_search_rounded, 'Find unusual transactions'),
    (Icons.credit_score_outlined, 'Make a debt payoff plan'),
  ];

  late final List<(IconData, String)> _shuffledPrompts;

  @override
  void initState() {
    super.initState();
    _shuffledPrompts = List.of(_prompts)..shuffle(Random());
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  double _stagger(double t, double start, double end) {
    return Curves.easeOutCubic.transform(
      ((t - start) / (end - start)).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _EdgeFadeMask(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 112, 12, 112),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              builder: (context, t, _) {
                final markT = _stagger(t, 0.0, 0.55);
                final headT = _stagger(t, 0.15, 0.6);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: markT,
                      child: CustomPaint(
                        size: const Size(120, 120),
                        painter: BudgetMarkPainter(
                          progress: t,
                          primary: theme.colorScheme.primary,
                          surface: theme.scaffoldBackgroundColor,
                          accent: AppTheme.highlight,
                          isDark: theme.brightness == Brightness.dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: headT,
                      child: Transform.translate(
                        offset: Offset(0, (1 - headT) * 10),
                        child: Column(
                          children: [
                            Text(
                              'Let\'s make your money\nmake sense',
                              textAlign: TextAlign.center,
                              style: AppTheme.headingLarge.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.6,
                                fontFamily: "Boldonse"
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _shuffledPrompts.length; i++)
                      _PromptCard(
                        icon: _shuffledPrompts[i].$1,
                        label: _shuffledPrompts[i].$2,
                        reveal: _stagger(t, 0.38 + i * 0.045, 0.72 + i * 0.045),
                        onTap: () => widget.onPromptTap(_shuffledPrompts[i].$2),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.icon,
    required this.label,
    required this.reveal,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double reveal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, (1 - reveal) * 14),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            borderRadius: BorderRadius.circular(32),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(32),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: onSurface.withValues(alpha: 0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: AppTheme.highlight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: AppTheme.bodyMedium.copyWith(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 15,
                      color: onSurface.withValues(alpha: 0.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeFadeMask extends StatelessWidget {
  const _EdgeFadeMask({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.12, 0.88, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
