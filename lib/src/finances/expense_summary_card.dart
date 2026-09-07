import 'package:flutter/material.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'finance_service.dart';

/// Shared expense overview for month and Overall scopes on both finance screens.
class ExpenseSummaryCard extends StatelessWidget {
  const ExpenseSummaryCard({
    super.key,
    required this.entries,
    this.month,
    this.now,
  });

  final List<FinanceEntry> entries;
  final DateTime? month;
  final DateTime? now;

  static String _monthLabel(DateTime date, {bool short = false}) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final name = names[date.month - 1];
    return '${short ? name.substring(0, 3) : name} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = now ?? DateTime.now();
    final scope = month;
    final entries =
        FinanceService.expenseEntries(this.entries)
            .where(
              (e) =>
                  !e.date.isAfter(current) &&
                  (scope == null ||
                      (e.date.year == scope.year &&
                          e.date.month == scope.month)),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    DateTime day(DateTime date) =>
        DateTime.utc(date.year, date.month, date.day);
    final days = entries.map((e) => day(e.date)).toSet();
    final total = FinanceService.instance.totalAmount(entries);
    final end =
        scope != null &&
            DateTime(
              scope.year,
              scope.month,
            ).isBefore(DateTime(current.year, current.month))
        ? DateTime(scope.year, scope.month + 1, 0)
        : current;
    final count = entries.isEmpty
        ? 0
        : day(end).difference(day(entries.first.date)).inDays + 1;
    final average = count <= 0 ? 0.0 : total / count;
    final cardColor = theme.colorScheme.primary;
    final onCard = AppTheme.readableOn(cardColor);
    final range = scope != null
        ? 'Month · ${_monthLabel(scope)}'
        : entries.isEmpty
        ? 'Until today'
        : 'From ${'${entries.first.date.day.toString().padLeft(2, '0')} ${_monthLabel(entries.first.date, short: true)}'} To Today';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cardColor, Color.lerp(cardColor, AppTheme.highlight, 0.28)!],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: onCard.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insights_rounded, color: onCard, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySmall.copyWith(
                    color: onCard.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            FinanceEntry.money(total),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headingLarge.copyWith(
              color: onCard,
              fontSize: 32,
              fontWeight: FontWeight.w500,
              fontFamily: "Boldonse",
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            scope != null
                ? 'Total spent in ${_monthLabel(scope, short: true)}'
                : 'Total spent until today',
            style: AppTheme.bodySmall.copyWith(
              color: onCard.withValues(alpha: 0.72),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildHeroStat(onCard, 'Entries', '${entries.length}'),
              ),
              Expanded(
                child: _buildHeroStat(onCard, 'Active days', '${days.length}'),
              ),
              Expanded(
                child: _buildHeroStat(
                  onCard,
                  'Daily avg',
                  FinanceEntry.money(average),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStat(Color onCard, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: onCard,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: onCard.withValues(alpha: 0.62),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
