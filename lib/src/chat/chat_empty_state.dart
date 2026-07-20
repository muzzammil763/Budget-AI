import 'dart:math';

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:flutter/material.dart';

class ChatStarterPrompt {
  const ChatStarterPrompt({
    required this.icon,
    required this.label,
    required this.prompt,
  });

  final IconData icon;
  final String label;
  final String prompt;
}

/// Starters are limited to questions the current local finance tools can
/// answer from completed income and expense records.
const chatStarterPrompts = <ChatStarterPrompt>[
  ChatStarterPrompt(
    icon: Icons.pie_chart_outline_rounded,
    label: 'Break down this month by category',
    prompt:
        'Summarize my recorded expenses for the current month by category. Rank categories from highest to lowest and include the total spending.',
  ),
  ChatStarterPrompt(
    icon: Icons.query_stats_rounded,
    label: 'Compare this month with last month',
    prompt:
        'Compare my recorded expenses for this month-to-date with the same number of days in the previous month. Show the totals, difference, and categories with the largest changes.',
  ),
  ChatStarterPrompt(
    icon: Icons.trending_down_rounded,
    label: 'Where could I cut back?',
    prompt:
        'Review my recorded expenses from the last 30 days. Identify up to three categories where I may be able to cut back, using the actual entries to explain each suggestion.',
  ),
  ChatStarterPrompt(
    icon: Icons.calendar_month_outlined,
    label: 'Estimate bills that may repeat',
    prompt:
        'Review my recorded expenses from the last 60 days for bill-like payments, including categories or descriptions related to Bills, rent, utilities, subscriptions, internet, or phone service. Identify payments that may repeat based on similar descriptions or amounts. Clearly label this as an estimate from past records, not a due-date or scheduled-bill list.',
  ),
  ChatStarterPrompt(
    icon: Icons.shopping_cart_outlined,
    label: 'Suggest a weekly grocery limit',
    prompt:
        'Review my recorded Groceries expenses from the last 28 days. Calculate the weekly average and suggest a realistic weekly limit based only on those records.',
  ),
  ChatStarterPrompt(
    icon: Icons.account_balance_wallet_outlined,
    label: 'Show this month’s cash flow',
    prompt:
        'Summarize my recorded income, expenses, and net balance for the current month. Mention that the result reflects only entries saved in this app.',
  ),
  ChatStarterPrompt(
    icon: Icons.format_list_numbered_rounded,
    label: 'Show my five largest expenses',
    prompt:
        'List my five largest recorded expenses from the last 30 days, including date, description, category, and amount.',
  ),
  ChatStarterPrompt(
    icon: Icons.manage_search_rounded,
    label: 'Check for unusual expenses',
    prompt:
        'Review my recorded expenses from the last 60 days and flag any unusually large entries or notable spending patterns. Treat this as a simple heuristic based only on my saved records.',
  ),
  ChatStarterPrompt(
    icon: Icons.copy_all_outlined,
    label: 'Check for possible duplicates',
    prompt:
        'Review my recorded entries from the last 30 days for possible duplicates with the same or very similar date, description, and amount. Do not delete or edit anything; only list possible matches.',
  ),
  ChatStarterPrompt(
    icon: Icons.savings_outlined,
    label: 'Estimate a savings target',
    prompt:
        'Use my recorded income and expenses from the last three complete months to estimate my average monthly surplus and suggest a conservative savings target. State clearly if the records are incomplete or insufficient.',
  ),
];

class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({super.key, required this.onPromptTap});

  final ValueChanged<String> onPromptTap;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState> {
  late final List<ChatStarterPrompt> _shuffledPrompts;

  @override
  void initState() {
    super.initState();
    _shuffledPrompts = List.of(chatStarterPrompts)..shuffle(Random());
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
                                fontFamily: "Boldonse",
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _shuffledPrompts.length; i++)
                      _PromptCard(
                        icon: _shuffledPrompts[i].icon,
                        label: _shuffledPrompts[i].label,
                        reveal: _stagger(t, 0.38 + i * 0.045, 0.72 + i * 0.045),
                        onTap: () =>
                            widget.onPromptTap(_shuffledPrompts[i].prompt),
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
