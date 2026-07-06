import 'dart:math' as math;

import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class FinanceInsightsScreen extends StatelessWidget {
  final List<FinanceEntry> entries;
  final DateTime selectedMonth;

  const FinanceInsightsScreen({
    super.key,
    required this.entries,
    required this.selectedMonth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insights = _FinanceInsights.fromEntries(
      entries,
      selectedMonth: selectedMonth,
      now: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Finance Insights'),
      ),
      body: insights.isEmpty
          ? _buildEmpty(theme)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
              children: [
                _buildHeroCard(theme, insights),
                const SizedBox(height: 12),
                _buildMetricGrid(theme, insights),
                const SizedBox(height: 12),
                _buildProgressPanel(theme, insights),
                const SizedBox(height: 12),
                _buildHighlights(theme, insights),
                if (insights.topCategories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildCategoryBreakdown(theme, insights),
                ],
                const SizedBox(height: 12),
                _buildLastSevenDays(theme, insights),
              ],
            ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                CupertinoIcons.chart_bar_alt_fill,
                color: theme.colorScheme.primary,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No finance entries yet',
              style: AppTheme.headingSmall.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add expenses from chat and this screen will show totals, trends, and category breakdowns.',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(ThemeData theme, _FinanceInsights insights) {
    final cardColor = theme.colorScheme.primary;
    final onCard = AppTheme.readableOn(cardColor);
    final range = insights.firstDate == null
        ? 'Until today'
        : '${_compactDate(insights.firstDate!)} - Today';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cardColor,
            Color.lerp(cardColor, theme.colorScheme.secondary, 0.34)!,
          ],
        ),
        borderRadius: BorderRadius.circular(8),
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
                  borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 18),
          Text(
            _money(insights.total),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headingLarge.copyWith(
              color: onCard,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Total until today',
            style: AppTheme.bodySmall.copyWith(
              color: onCard.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildHeroStat(
                  onCard,
                  'Entries',
                  '${insights.entryCount}',
                ),
              ),
              Expanded(
                child: _buildHeroStat(
                  onCard,
                  'Active days',
                  '${insights.activeDays}',
                ),
              ),
              Expanded(
                child: _buildHeroStat(
                  onCard,
                  'Daily avg',
                  _money(insights.averagePerDay),
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
      crossAxisAlignment: CrossAxisAlignment.start,
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

  Widget _buildMetricGrid(ThemeData theme, _FinanceInsights insights) {
    final metrics = [
      _Metric(Icons.today_rounded, 'Today', _money(insights.todayTotal)),
      _Metric(
        Icons.view_week_rounded,
        'This week',
        _money(insights.currentWeekTotal),
      ),
      _Metric(
        Icons.calendar_month_rounded,
        'This month',
        _money(insights.currentMonthTotal),
      ),
      _Metric(
        Icons.speed_rounded,
        'Active day avg',
        _money(insights.averagePerActiveDay),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _buildMetricCard(theme, metric),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildMetricCard(ThemeData theme, _Metric metric) {
    return Container(
      height: 98,
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, color: theme.colorScheme.primary, size: 20),
          const Spacer(),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressPanel(ThemeData theme, _FinanceInsights insights) {
    final monthDayProgress = _monthDayProgress(DateTime.now());
    final weekShare = insights.currentMonthTotal == 0
        ? 0.0
        : insights.currentWeekTotal / insights.currentMonthTotal;
    final activeShare = insights.trackedDays == 0
        ? 0.0
        : insights.activeDays / insights.trackedDays;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Momentum'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildCircularMetric(
                  theme,
                  label: 'Month time',
                  value: monthDayProgress,
                  center: '${(monthDayProgress * 100).round()}%',
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: _buildCircularMetric(
                  theme,
                  label: 'Week share',
                  value: weekShare.clamp(0.0, 1.0),
                  center: '${(weekShare.clamp(0.0, 1.0) * 100).round()}%',
                  color: theme.colorScheme.secondary,
                ),
              ),
              Expanded(
                child: _buildCircularMetric(
                  theme,
                  label: 'Active days',
                  value: activeShare.clamp(0.0, 1.0),
                  center: '${(activeShare.clamp(0.0, 1.0) * 100).round()}%',
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProgressSlider(
            theme,
            label: '${_monthLabel(selectedMonth)} vs previous month',
            value: insights.previousMonthTotal == 0
                ? 1
                : (insights.selectedMonthTotal / insights.previousMonthTotal)
                      .clamp(0.0, 1.0),
            trailing: _signedMoney(insights.previousMonthDelta),
            color: insights.previousMonthDelta >= 0
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
        ],
      ),
    );
  }

  Widget _buildCircularMetric(
    ThemeData theme, {
    required String label,
    required double value,
    required String center,
    required Color color,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 74,
                height: 74,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                center,
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSlider(
    ThemeData theme, {
    required String label,
    required double value,
    required String trailing,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              trailing,
              style: AppTheme.bodySmall.copyWith(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: value,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildHighlights(ThemeData theme, _FinanceInsights insights) {
    final cards = <Widget>[
      if (insights.mostSpentDayOverall != null)
        _buildHighlightCard(
          theme,
          icon: CupertinoIcons.flame_fill,
          label: 'Most spent day',
          value: _money(insights.mostSpentDayOverall!.total),
          caption: _compactDate(insights.mostSpentDayOverall!.date),
        ),
      if (insights.mostSpentDaySelectedMonth != null)
        _buildHighlightCard(
          theme,
          icon: Icons.stacked_line_chart_rounded,
          label: '${_monthLabel(selectedMonth)} peak',
          value: _money(insights.mostSpentDaySelectedMonth!.total),
          caption: _compactDate(insights.mostSpentDaySelectedMonth!.date),
        ),
      if (insights.mostSpentWeekOverall != null)
        _buildHighlightCard(
          theme,
          icon: Icons.view_week_rounded,
          label: 'Most spent week',
          value: _money(insights.mostSpentWeekOverall!.total),
          caption: 'From ${_compactDate(insights.mostSpentWeekOverall!.date)}',
        ),
      if (insights.mostSpentMonthOverall != null)
        _buildHighlightCard(
          theme,
          icon: Icons.calendar_month_rounded,
          label: 'Most spent month',
          value: _money(insights.mostSpentMonthOverall!.total),
          caption: _monthLabel(insights.mostSpentMonthOverall!.date),
        ),
      if (insights.largestEntry != null)
        _buildHighlightCard(
          theme,
          icon: CupertinoIcons.arrow_up_circle_fill,
          label: 'Largest expense',
          value: insights.largestEntry!.displayAmount,
          caption: insights.largestEntry!.description,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Highlights'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: cards
                    .map((card) => SizedBox(width: width, child: card))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightCard(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required String caption,
  }) {
    return Container(
      height: 116,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(ThemeData theme, _FinanceInsights insights) {
    final maxTotal = insights.topCategories.first.value;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Top Categories'),
          const SizedBox(height: 12),
          ...insights.topCategories.take(6).map((entry) {
            final percent = insights.total == 0
                ? 0.0
                : entry.value / insights.total;
            final widthFactor = maxTotal == 0 ? 0.0 : entry.value / maxTotal;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_money(entry.value)} - ${(percent * 100).round()}%',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 9,
                      value: widthFactor.clamp(0.0, 1.0),
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.10,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLastSevenDays(ThemeData theme, _FinanceInsights insights) {
    final maxTotal = insights.lastSevenDays.fold<double>(
      0,
      (max, day) => day.total > max ? day.total : max,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Last 7 Days'),
          const SizedBox(height: 14),
          SizedBox(
            height: 154,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: insights.lastSevenDays.map((day) {
                final value = maxTotal == 0 ? 0.0 : day.total / maxTotal;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          day.total == 0
                              ? '-'
                              : FinanceEntry.formatAmount(day.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: math.max(
                                value,
                                day.total == 0 ? 0.06 : 0.12,
                              ),
                              child: Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(maxWidth: 28),
                                decoration: BoxDecoration(
                                  color: day.total == 0
                                      ? theme.colorScheme.outline.withValues(
                                          alpha: 0.18,
                                        )
                                      : theme.colorScheme.secondary,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _shortDayLabel(day.date),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Text(
      title.toUpperCase(),
      style: AppTheme.bodySmall.copyWith(
        color: theme.colorScheme.primary,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }

  BoxDecoration _cardDecoration(ThemeData theme) {
    return BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.18)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.16 : 0.05,
          ),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  double _monthDayProgress(DateTime now) {
    final start = DateTime(now.year, now.month);
    final next = DateTime(now.year, now.month + 1);
    final elapsed = now.difference(start).inDays + 1;
    final total = next.difference(start).inDays;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  String _money(double amount) => '${FinanceEntry.formatAmount(amount)} Rs';

  String _signedMoney(double amount) {
    if (amount == 0) return _money(0);
    final sign = amount > 0 ? '+' : '-';
    return '$sign${_money(amount.abs())}';
  }

  String _compactDate(DateTime date) {
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
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  String _shortDayLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]}\n${date.day.toString().padLeft(2, '0')}';
  }

  String _monthLabel(DateTime dt) {
    const names = [
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
    return '${names[dt.month - 1]} ${dt.year}';
  }
}

class _FinanceInsights {
  final bool isEmpty;
  final double total;
  final double todayTotal;
  final double currentWeekTotal;
  final double currentMonthTotal;
  final double selectedMonthTotal;
  final double previousMonthTotal;
  final double averagePerDay;
  final double averagePerActiveDay;
  final double previousMonthDelta;
  final int trackedDays;
  final int activeDays;
  final int entryCount;
  final DateTime? firstDate;
  final _DatedTotal? mostSpentDayOverall;
  final _DatedTotal? mostSpentDaySelectedMonth;
  final _DatedTotal? mostSpentWeekOverall;
  final _DatedTotal? mostSpentMonthOverall;
  final FinanceEntry? largestEntry;
  final List<MapEntry<String, double>> topCategories;
  final List<_DatedTotal> lastSevenDays;

  const _FinanceInsights({
    required this.isEmpty,
    required this.total,
    required this.todayTotal,
    required this.currentWeekTotal,
    required this.currentMonthTotal,
    required this.selectedMonthTotal,
    required this.previousMonthTotal,
    required this.averagePerDay,
    required this.averagePerActiveDay,
    required this.previousMonthDelta,
    required this.trackedDays,
    required this.activeDays,
    required this.entryCount,
    required this.firstDate,
    required this.mostSpentDayOverall,
    required this.mostSpentDaySelectedMonth,
    required this.mostSpentWeekOverall,
    required this.mostSpentMonthOverall,
    required this.largestEntry,
    required this.topCategories,
    required this.lastSevenDays,
  });

  factory _FinanceInsights.fromEntries(
    List<FinanceEntry> entries, {
    required DateTime selectedMonth,
    required DateTime now,
  }) {
    final today = _dateOnly(now);
    final usableEntries =
        entries.where((entry) => !_dateOnly(entry.date).isAfter(today)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (usableEntries.isEmpty) {
      return const _FinanceInsights(
        isEmpty: true,
        total: 0,
        todayTotal: 0,
        currentWeekTotal: 0,
        currentMonthTotal: 0,
        selectedMonthTotal: 0,
        previousMonthTotal: 0,
        averagePerDay: 0,
        averagePerActiveDay: 0,
        previousMonthDelta: 0,
        trackedDays: 0,
        activeDays: 0,
        entryCount: 0,
        firstDate: null,
        mostSpentDayOverall: null,
        mostSpentDaySelectedMonth: null,
        mostSpentWeekOverall: null,
        mostSpentMonthOverall: null,
        largestEntry: null,
        topCategories: [],
        lastSevenDays: [],
      );
    }

    final currentWeekStart = _weekStart(today);
    final currentMonthStart = DateTime(today.year, today.month);
    final selectedMonthStart = DateTime(
      selectedMonth.year,
      selectedMonth.month,
    );
    final previousMonthStart = DateTime(
      selectedMonthStart.year,
      selectedMonthStart.month - 1,
    );

    final totalsByDay = <DateTime, double>{};
    final totalsByWeek = <DateTime, double>{};
    final totalsByMonth = <DateTime, double>{};
    final categoryTotals = <String, double>{};
    var total = 0.0;
    var todayTotal = 0.0;
    var currentWeekTotal = 0.0;
    var currentMonthTotal = 0.0;
    var selectedMonthTotal = 0.0;
    var previousMonthTotal = 0.0;
    FinanceEntry? largestEntry;

    for (final entry in usableEntries) {
      final day = _dateOnly(entry.date);
      final week = _weekStart(day);
      final month = DateTime(day.year, day.month);
      total += entry.amount;
      totalsByDay[day] = (totalsByDay[day] ?? 0) + entry.amount;
      totalsByWeek[week] = (totalsByWeek[week] ?? 0) + entry.amount;
      totalsByMonth[month] = (totalsByMonth[month] ?? 0) + entry.amount;
      categoryTotals[entry.category] =
          (categoryTotals[entry.category] ?? 0) + entry.amount;

      if (day == today) todayTotal += entry.amount;
      if (!day.isBefore(currentWeekStart)) currentWeekTotal += entry.amount;
      if (month == currentMonthStart) currentMonthTotal += entry.amount;
      if (month == selectedMonthStart) selectedMonthTotal += entry.amount;
      if (month == previousMonthStart) previousMonthTotal += entry.amount;
      if (largestEntry == null || entry.amount > largestEntry.amount) {
        largestEntry = entry;
      }
    }

    final firstDate = _dateOnly(usableEntries.first.date);
    final trackedDays = today.difference(firstDate).inDays + 1;
    final activeDays = totalsByDay.length;
    final selectedMonthDayTotals = Map.fromEntries(
      totalsByDay.entries.where(
        (entry) =>
            entry.key.year == selectedMonthStart.year &&
            entry.key.month == selectedMonthStart.month,
      ),
    );
    final topCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final lastSevenDays = List.generate(7, (index) {
      final day = today.subtract(Duration(days: 6 - index));
      return _DatedTotal(day, totalsByDay[day] ?? 0);
    });

    return _FinanceInsights(
      isEmpty: false,
      total: total,
      todayTotal: todayTotal,
      currentWeekTotal: currentWeekTotal,
      currentMonthTotal: currentMonthTotal,
      selectedMonthTotal: selectedMonthTotal,
      previousMonthTotal: previousMonthTotal,
      averagePerDay: trackedDays == 0 ? 0 : total / trackedDays,
      averagePerActiveDay: activeDays == 0 ? 0 : total / activeDays,
      previousMonthDelta: selectedMonthTotal - previousMonthTotal,
      trackedDays: trackedDays,
      activeDays: activeDays,
      entryCount: usableEntries.length,
      firstDate: firstDate,
      mostSpentDayOverall: _maxDatedTotal(totalsByDay),
      mostSpentDaySelectedMonth: _maxDatedTotal(selectedMonthDayTotals),
      mostSpentWeekOverall: _maxDatedTotal(totalsByWeek),
      mostSpentMonthOverall: _maxDatedTotal(totalsByMonth),
      largestEntry: largestEntry,
      topCategories: topCategories,
      lastSevenDays: lastSevenDays,
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _weekStart(DateTime date) {
    final day = _dateOnly(date);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static _DatedTotal? _maxDatedTotal(Map<DateTime, double> totals) {
    if (totals.isEmpty) return null;
    return totals.entries
        .map((entry) => _DatedTotal(entry.key, entry.value))
        .reduce((a, b) => a.total >= b.total ? a : b);
  }
}

class _DatedTotal {
  final DateTime date;
  final double total;

  const _DatedTotal(this.date, this.total);
}

class _Metric {
  final IconData icon;
  final String label;
  final String value;

  const _Metric(this.icon, this.label, this.value);
}
