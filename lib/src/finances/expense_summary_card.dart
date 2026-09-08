import 'package:flutter/material.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'finance_service.dart';

/// Shared income and expense overview for month and Overall scopes on both finance screens.
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
    final scopedEntries =
        FinanceService.reportingEntries(this.entries, includeRollovers: false)
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
    final entries = FinanceService.expenseEntries(scopedEntries);
    final income = FinanceService.instance.totalAmount(
      scopedEntries,
      type: FinanceEntryType.income,
    );
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
    String dateLabel(DateTime date) =>
        '${date.day} ${_monthLabel(date, short: true)}';
    final currentMonth =
        scope != null &&
        scope.year == current.year &&
        scope.month == current.month;
    final range = scope != null
        ? 'Month · ${_monthLabel(scope)}'
        : scopedEntries.isEmpty
        ? 'Through ${dateLabel(current)}'
        : 'From ${dateLabel(scopedEntries.first.date)} To ${dateLabel(current)}';
    final subtitle = scope != null
        ? 'Income and expenses in ${_monthLabel(scope, short: true)}${currentMonth ? ' · 1–${current.day} ${_monthLabel(scope, short: true).split(' ').first}' : ''}'
        : 'Income and expenses through ${dateLabel(current)}';

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
          _buildTotal(
            onCard,
            'Expenses',
            total,
            Icons.arrow_outward,
            Colors.red,
          ),
          const SizedBox(height: 12),
          _buildTotal(onCard, 'Income', income, Icons.south_west, Colors.green),
          const SizedBox(height: 2),
          Text(
            subtitle,
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
                child: _buildHeroStat(
                  onCard,
                  'Expense entries',
                  '${entries.length}',
                ),
              ),
              Expanded(
                child: _buildHeroStat(onCard, 'Active days', '${days.length}'),
              ),
              Expanded(
                child: _buildHeroStat(
                  onCard,
                  'Daily expense avg',
                  FinanceEntry.money(average),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotal(
    Color onCard,
    String label,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.bodySmall.copyWith(color: onCard)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  FinanceEntry.money(amount),
                  style: AppTheme.headingLarge.copyWith(
                    color: onCard,
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Boldonse',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
