import 'dart:async';
import 'dart:math' as math;

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/pill_nav_bar.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class FinanceInsightsScreen extends StatefulWidget {
  final List<FinanceEntry> entries;
  final DateTime selectedMonth;

  const FinanceInsightsScreen({
    super.key,
    required this.entries,
    required this.selectedMonth,
  });

  @override
  State<FinanceInsightsScreen> createState() => _FinanceInsightsScreenState();
}

class _FinanceInsightsScreenState extends State<FinanceInsightsScreen> {
  DateTime? _scopeMonth;
  List<DateTime> _months = const [];
  int _entriesRevision = 0;
  int? _cachedRevision;
  DateTime? _cachedScopeMonth;
  DateTime? _cachedToday;
  _FinanceScopeData? _cachedScopeData;

  bool get _isOverall => _scopeMonth == null;

  bool get _isPastMonthScope {
    final scope = _scopeMonth;
    if (scope == null) return false;
    final now = DateTime.now();
    return !(scope.year == now.year && scope.month == now.month);
  }

  @override
  void initState() {
    super.initState();
    _months = _buildAvailableMonths();
    // Open scoped to the passed month (the current month from both entry
    // points) rather than the Overall tab, mirroring how the finances screen
    // lands on the current month instead of Overall.
    final month = DateTime(
      widget.selectedMonth.year,
      widget.selectedMonth.month,
    );
    _scopeMonth =
        _months.any((m) => m.year == month.year && m.month == month.month)
        ? month
        : null;
  }

  @override
  void didUpdateWidget(covariant FinanceInsightsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entries, oldWidget.entries) ||
        widget.selectedMonth != oldWidget.selectedMonth) {
      _entriesRevision++;
      _cachedScopeData = null;
      _months = _buildAvailableMonths();
    }
  }

  List<DateTime> _buildAvailableMonths() {
    final months = <DateTime>{};
    for (final e in widget.entries) {
      months.add(DateTime(e.date.year, e.date.month));
    }
    final now = DateTime.now();
    months.add(DateTime(now.year, now.month));
    return months.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final scope = _scopeMonth;
    final scopeData = _scopeData(scope, now);
    final insights = scopeData.insights;
    final months = _months;
    final selectedIndex = scope == null
        ? 0
        : 1 +
              months.indexWhere(
                (m) => m.year == scope.year && m.month == scope.month,
              );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Finance Insights'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PillNavBar(
            items: ['Overall', ...months.map(_pillMonthLabel)],
            selectedIndex: selectedIndex,
            onSelected: (index) => setState(() {
              _scopeMonth = index == 0 ? null : months[index - 1];
            }),
          ),
          Expanded(
            child: insights.isEmpty
                ? _buildEmpty(theme)
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: scope == null
                        ? [
                            _buildHeroCard(theme, insights),
                            const SizedBox(height: 12),
                            _buildIncomeExpenseCard(theme, insights),
                            const SizedBox(height: 12),
                            _buildMetricGrid(theme, insights),
                            const SizedBox(height: 12),
                            _buildProgressPanel(theme, insights),
                            const SizedBox(height: 12),
                            _buildSpendingHeatmap(theme, insights),
                            const SizedBox(height: 12),
                            _buildBudgetSignals(theme, insights),
                            const SizedBox(height: 12),
                            _buildHighlights(theme, insights),
                            if (insights.topCategories.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildCategoryBreakdown(
                                theme,
                                insights,
                                title: 'Top Categories',
                                limit: 3,
                              ),
                              const SizedBox(height: 12),
                              _CategoryBreakdownCard(insights: insights),
                            ],
                            const SizedBox(height: 12),
                            _DailyTrendsCard(insights: insights),
                          ]
                        : _buildMonthViewCards(
                            theme,
                            insights,
                            scope,
                            scopeData.monthDays,
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  _FinanceScopeData _scopeData(DateTime? scope, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (_cachedScopeData != null &&
        _cachedRevision == _entriesRevision &&
        _sameMonth(_cachedScopeMonth, scope) &&
        _cachedToday == today) {
      return _cachedScopeData!;
    }

    final scopedEntries = scope == null
        ? widget.entries
        : widget.entries
              .where(
                (e) => e.date.year == scope.year && e.date.month == scope.month,
              )
              .toList();
    final isPastMonthScope = scope != null && !_sameMonth(scope, now);
    // For a past month, anchor "today" to that month's last day so all
    // time-relative metrics describe the month itself.
    final effectiveNow = isPastMonthScope
        ? DateTime(scope.year, scope.month + 1, 0, 23, 59, 59)
        : now;
    final insights = _FinanceInsights.fromEntries(
      scopedEntries,
      selectedMonth: scope ?? widget.selectedMonth,
      now: effectiveNow,
    );
    final data = _FinanceScopeData(
      insights: insights,
      monthDays: scope == null
          ? const <_DatedTotal>[]
          : _monthDays(scope, scopedEntries, effectiveNow),
    );

    _cachedRevision = _entriesRevision;
    _cachedScopeMonth = scope == null
        ? null
        : DateTime(scope.year, scope.month);
    _cachedToday = today;
    _cachedScopeData = data;
    return data;
  }

  bool _sameMonth(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.year == b.year && a.month == b.month;
  }

  String _pillMonthLabel(DateTime dt) {
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
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                CupertinoIcons.chart_bar_alt_fill,
                color: theme.colorScheme.onPrimary,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isOverall
                  ? 'No finance entries yet'
                  : 'No entries for ${_pillMonthLabel(_scopeMonth!)}',
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
    final scope = _scopeMonth;
    final range = scope != null
        ? 'Month · ${_monthLabel(scope)}'
        : insights.firstDate == null
        ? 'Until today'
        : 'From ${_compactDate(insights.firstDate!)} To Today';

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
            _money(insights.total),
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
                ? 'Total spent in ${_pillMonthLabel(scope)}'
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

  Widget _buildIncomeExpenseCard(ThemeData theme, _FinanceInsights insights) {
    final monthNet = insights.currentMonthIncome - insights.currentMonthTotal;
    final scopedNet = insights.totalIncome - insights.total;
    // Savings rollovers are transfers of an earlier month's leftover, not new
    // income. Keep them in monthly income so the destination month's available
    // balance is correct, but exclude them from all-time income/net to avoid
    // counting the same money a second time.
    final overallIncome = insights.totalIncome - insights.savingsRolloverIncome;
    final overallNet = overallIncome - insights.total;
    final scope = _scopeMonth;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Income vs Expenses'),
          const SizedBox(height: 12),
          if (scope != null)
            _buildIncomeExpenseColumn(
              theme,
              label: _monthLabel(scope),
              income: insights.totalIncome,
              expense: insights.total,
              net: scopedNet,
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildIncomeExpenseColumn(
                    theme,
                    label: 'THIS MONTH',
                    income: insights.currentMonthIncome,
                    expense: insights.currentMonthTotal,
                    net: monthNet,
                  ),
                ),
                Container(
                  width: 1,
                  height: 92,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: theme.dividerColor.withValues(alpha: 0.18),
                ),
                Expanded(
                  child: _buildIncomeExpenseColumn(
                    theme,
                    label: 'ALL TIME',
                    income: overallIncome,
                    expense: insights.total,
                    net: overallNet,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildIncomeExpenseColumn(
    ThemeData theme, {
    required String label,
    required double income,
    required double expense,
    required double net,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildIncomeExpenseRow(
          theme,
          'Income',
          '+${_money(income)}',
          Colors.green,
        ),
        const SizedBox(height: 6),
        _buildIncomeExpenseRow(
          theme,
          'Expenses',
          '-${_money(expense)}',
          Colors.red,
        ),
        const SizedBox(height: 6),
        _buildIncomeExpenseRow(
          theme,
          'Net',
          _signedMoney(net),
          net >= 0 ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  Widget _buildIncomeExpenseRow(
    ThemeData theme,
    String label,
    String value,
    Color color,
  ) {
    return Row(
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
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodySmall.copyWith(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricGrid(ThemeData theme, _FinanceInsights insights) {
    final isPast = _isPastMonthScope;
    final metrics = [
      _Metric(
        Icons.today_rounded,
        isPast ? 'Last day' : 'Today',
        _money(insights.todayTotal),
      ),
      _Metric(
        Icons.view_week_rounded,
        isPast ? 'Last week' : 'This week',
        _money(insights.currentWeekTotal),
      ),
      _Metric(
        Icons.calendar_month_rounded,
        _isOverall ? 'This month' : 'Month total',
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
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),

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
      padding: const EdgeInsets.all(12),
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
            label: '${_monthLabel(widget.selectedMonth)} VS PREVIOUS MONTH',
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

  Widget _buildSpendingHeatmap(ThemeData theme, _FinanceInsights insights) {
    final weeks = _chunkHeatmapWeeks(insights.yearlyActivity);
    final monthLabels = _heatmapMonthLabels(weeks);
    final activeColor = theme.colorScheme.primary;
    final emptyColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.34 : 0.58,
    );
    // When tracking started less than a year ago the grid is clipped to the
    // first entry, so label it by its real span instead of "Last 12 months".
    final firstDate = insights.firstDate;
    final windowStart = DateTime.now().subtract(const Duration(days: 364));
    final rangeLabel = firstDate != null && firstDate.isAfter(windowStart)
        ? 'Since ${_shortMonthLabel(firstDate)} ${firstDate.year}'
        : 'Last 12 months';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle(theme, 'Spending Activity')),
              Text(
                rangeLabel,
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Darker squares mean heavier spending days. Blank days mean nothing was tracked.',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Row(
                    children: [
                      for (var i = 0; i < weeks.length; i++)
                        SizedBox(
                          width: 15,
                          child: Text(
                            monthLabels[i],
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            style: AppTheme.bodySmall.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Column(
                        children: [
                          for (var weekday = 1; weekday <= 7; weekday++)
                            SizedBox(
                              height: 15,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  switch (weekday) {
                                    1 => 'M',
                                    3 => 'W',
                                    5 => 'F',
                                    _ => '',
                                  },
                                  style: AppTheme.bodySmall.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        for (final week in weeks)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Column(
                              children: [
                                for (final day in week)
                                  _HeatmapCell(
                                    day: day,
                                    maxTotal: insights.yearlyMaxDailyTotal,
                                    activeColor: activeColor,
                                    emptyColor: emptyColor,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Less',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              for (var i = 0; i < 5; i++) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? emptyColor
                        : _heatmapColor(activeColor, i / 4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                if (i < 4) const SizedBox(width: 4),
              ],
              const SizedBox(width: 6),
              Text(
                'More',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetSignals(ThemeData theme, _FinanceInsights insights) {
    final topCategory = insights.topCategories.isEmpty
        ? null
        : insights.topCategories.first;
    final topCategoryShare = insights.total == 0 || topCategory == null
        ? 0.0
        : topCategory.value / insights.total;
    final consistency = insights.trackedDays == 0
        ? 0.0
        : insights.activeDays / insights.trackedDays;

    final signals = [
      _Metric(
        Icons.show_chart_rounded,
        _isPastMonthScope ? 'Month total' : 'Projected month',
        _money(insights.currentMonthProjected),
      ),
      _Metric(
        Icons.nights_stay_outlined,
        'No-spend days',
        '${insights.currentMonthNoSpendDays}/${insights.currentMonthElapsedDays}',
      ),
      _Metric(
        Icons.category_outlined,
        topCategory == null ? 'Top category' : topCategory.key,
        '${(topCategoryShare * 100).round()}%',
      ),
      _Metric(
        Icons.check_circle_outline_rounded,
        'Tracking cadence',
        '${(consistency * 100).round()}%',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Budget Signals'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: signals
                    .map(
                      (signal) => SizedBox(
                        width: width,
                        child: _buildSignalCard(theme, signal),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(ThemeData theme, _Metric signal) {
    return Container(
      height: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.13),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(signal.icon, color: theme.colorScheme.primary, size: 20),
          const Spacer(),
          Text(
            signal.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            signal.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
          label: '${_monthLabel(_scopeMonth ?? widget.selectedMonth)} peak',
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
      padding: const EdgeInsets.all(12),
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

  List<Widget> _buildMonthViewCards(
    ThemeData theme,
    _FinanceInsights insights,
    DateTime month,
    List<_DatedTotal> days,
  ) {
    return [
      _buildHeroCard(theme, insights),
      const SizedBox(height: 12),
      _buildIncomeExpenseCard(theme, insights),
      const SizedBox(height: 12),
      _buildMonthSummaryGrid(theme, insights, month, days),
      const SizedBox(height: 12),
      _buildMonthDailyActivity(theme, month, days),
      const SizedBox(height: 12),
      _buildMonthHighlights(theme, insights, month),
      if (insights.topCategories.isNotEmpty) ...[
        const SizedBox(height: 12),
        _buildCategoryBreakdown(
          theme,
          insights,
          title: '${_shortMonthLabel(month)} Categories',
        ),
      ],
    ];
  }

  Widget _buildMonthSummaryGrid(
    ThemeData theme,
    _FinanceInsights insights,
    DateTime month,
    List<_DatedTotal> days,
  ) {
    final dayCount = days.length;
    final noSpendDays = dayCount - insights.activeDays;
    final peakDay = _maxDatedTotal(days);
    final metrics = [
      _Metric(
        Icons.calendar_month_rounded,
        'Month total',
        _money(insights.total),
      ),
      _Metric(
        Icons.event_available_rounded,
        'Active days',
        '${insights.activeDays}/$dayCount',
      ),
      _Metric(
        Icons.do_not_disturb_on_outlined,
        'No-spend days',
        '$noSpendDays',
      ),
      _Metric(
        Icons.trending_up_rounded,
        'Peak day',
        peakDay == null ? _money(0) : _money(peakDay.total),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle(theme, 'Month Snapshot')),
              Text(
                _monthLabel(month),
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
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
                        child: _buildSignalCard(theme, metric),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildProgressSlider(
            theme,
            label: 'DAILY AVERAGE',
            value: peakDay == null || peakDay.total == 0
                ? 0
                : (insights.averagePerActiveDay / peakDay.total).clamp(
                    0.0,
                    1.0,
                  ),
            trailing: _money(insights.averagePerActiveDay),
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildMonthDailyActivity(
    ThemeData theme,
    DateTime month,
    List<_DatedTotal> days,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle(theme, _fullMonthLabel(month))),
              Text(
                '${days.length} DAYS',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            child: _SpendingActivityBars(
              days: days,
              barColor: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Tap or hold a bar to see that day’s total',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthHighlights(
    ThemeData theme,
    _FinanceInsights insights,
    DateTime month,
  ) {
    final cards = <Widget>[
      if (insights.mostSpentDayOverall != null)
        _buildHighlightCard(
          theme,
          icon: CupertinoIcons.flame_fill,
          label: 'Highest day',
          value: _money(insights.mostSpentDayOverall!.total),
          caption: _compactDate(insights.mostSpentDayOverall!.date),
        ),
      if (insights.mostSpentWeekOverall != null)
        _buildHighlightCard(
          theme,
          icon: Icons.view_week_rounded,
          label: 'Highest week',
          value: _money(insights.mostSpentWeekOverall!.total),
          caption: 'From ${_compactDate(insights.mostSpentWeekOverall!.date)}',
        ),
      if (insights.largestEntry != null)
        _buildHighlightCard(
          theme,
          icon: CupertinoIcons.arrow_up_circle_fill,
          label: 'Largest expense',
          value: insights.largestEntry!.displayAmount,
          caption: insights.largestEntry!.description,
        ),
      _buildHighlightCard(
        theme,
        icon: Icons.savings_outlined,
        label: 'Net balance',
        value: _signedMoney(insights.totalIncome - insights.total),
        caption: _monthLabel(month),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, 'Month Highlights'),
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
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(12),
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

  Widget _buildCategoryBreakdown(
    ThemeData theme,
    _FinanceInsights insights, {
    required String title,
    int? limit,
  }) {
    final maxTotal = insights.topCategories.first.value;
    final categories = limit == null
        ? insights.topCategories
        : insights.topCategories.take(limit).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, title),
          const SizedBox(height: 12),
          ...categories.map(
            (entry) => _buildCategoryRow(
              theme,
              entry,
              total: insights.total,
              maxTotal: maxTotal,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildCategoryRow(
    ThemeData theme,
    MapEntry<String, double> entry, {
    required double total,
    required double maxTotal,
  }) {
    final percent = total == 0 ? 0.0 : entry.value / total;
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
  }

  List<List<_DatedTotal>> _chunkHeatmapWeeks(List<_DatedTotal> days) {
    final weeks = <List<_DatedTotal>>[];
    for (var index = 0; index < days.length; index += 7) {
      weeks.add(days.sublist(index, math.min(index + 7, days.length)));
    }
    return weeks;
  }

  List<String> _heatmapMonthLabels(List<List<_DatedTotal>> weeks) {
    var previousMonth = 0;
    return weeks.map((week) {
      final firstMonthDay = week.where((day) => day.date.day <= 7).toList();
      final candidate = firstMonthDay.isNotEmpty ? firstMonthDay.first : null;
      if (candidate == null || candidate.date.month == previousMonth) {
        return '';
      }
      previousMonth = candidate.date.month;
      return _shortMonthLabel(candidate.date);
    }).toList();
  }

  static Color _heatmapColor(Color color, double intensity) {
    final clamped = intensity.clamp(0.0, 1.0);
    return Color.lerp(color.withValues(alpha: 0.24), color, clamped)!;
  }

  static Widget _sectionTitle(ThemeData theme, String title) {
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

  static BoxDecoration _cardDecoration(ThemeData theme) {
    return BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
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

  List<_DatedTotal> _monthDays(
    DateTime month,
    List<FinanceEntry> entries,
    DateTime now,
  ) {
    final totalsByDay = <DateTime, double>{};
    for (final entry in entries) {
      if (entry.type != FinanceEntryType.expense) continue;
      final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
      totalsByDay[day] = (totalsByDay[day] ?? 0) + entry.amount;
    }

    final monthStart = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final daysInMonth = nextMonth.difference(monthStart).inDays;
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final visibleDays = isCurrentMonth
        ? math.min(now.day, daysInMonth)
        : daysInMonth;

    return List.generate(visibleDays, (index) {
      final day = DateTime(month.year, month.month, index + 1);
      return _DatedTotal(day, totalsByDay[day] ?? 0);
    });
  }

  _DatedTotal? _maxDatedTotal(List<_DatedTotal> days) {
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a.total >= b.total ? a : b);
  }

  String _fullMonthLabel(DateTime dt) {
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
    return '${names[dt.month - 1]} ${dt.year}';
  }

  static String _money(double amount) => FinanceEntry.money(amount);

  String _signedMoney(double amount) {
    if (amount == 0) return _money(0);
    final sign = amount > 0 ? '+' : '-';
    return '$sign${_money(amount.abs())}';
  }

  String _compactDate(DateTime date) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  static String _shortDayLabel(DateTime date) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return '${days[date.weekday - 1]}\n${date.day.toString().padLeft(2, '0')}';
  }

  String _monthLabel(DateTime dt) {
    const names = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${names[dt.month - 1]} ${dt.year}';
  }

  String _shortMonthLabel(DateTime dt) {
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
    return names[dt.month - 1];
  }
}

class _FinanceScopeData {
  const _FinanceScopeData({required this.insights, required this.monthDays});

  final _FinanceInsights insights;
  final List<_DatedTotal> monthDays;
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.day,
    required this.maxTotal,
    required this.activeColor,
    required this.emptyColor,
  });

  final _DatedTotal day;
  final double maxTotal;
  final Color activeColor;
  final Color emptyColor;

  @override
  Widget build(BuildContext context) {
    final total = day.total;
    final intensity = maxTotal == 0 ? 0.0 : total / maxTotal;
    final color = total == 0
        ? emptyColor
        : _FinanceInsightsScreenState._heatmapColor(activeColor, intensity);

    return Tooltip(
      message: total == 0
          ? 'No spending on ${_tooltipDate(day.date)}'
          : '${FinanceEntry.money(total)} on ${_tooltipDate(day.date)}',
      child: Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  String _tooltipDate(DateTime date) {
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

class _FinanceInsights {
  final bool isEmpty;
  final double total;
  final double todayTotal;
  final double currentWeekTotal;
  final double currentMonthTotal;
  final double currentMonthProjected;
  final double selectedMonthTotal;
  final double previousMonthTotal;
  final double averagePerDay;
  final double averagePerActiveDay;
  final double previousMonthDelta;
  final int trackedDays;
  final int activeDays;
  final int currentMonthElapsedDays;
  final int currentMonthNoSpendDays;
  final int entryCount;
  final DateTime? firstDate;
  final _DatedTotal? mostSpentDayOverall;
  final _DatedTotal? mostSpentDaySelectedMonth;
  final _DatedTotal? mostSpentWeekOverall;
  final _DatedTotal? mostSpentMonthOverall;
  final FinanceEntry? largestEntry;
  final List<MapEntry<String, double>> topCategories;
  final List<_DatedTotal> lastSevenDays;
  final List<_DatedTotal> lastThirtyDays;
  final List<_DatedTotal> yearlyActivity;
  final double yearlyMaxDailyTotal;
  final double totalIncome;
  final double savingsRolloverIncome;
  final double currentMonthIncome;
  final double selectedMonthIncome;

  const _FinanceInsights({
    required this.isEmpty,
    required this.total,
    required this.todayTotal,
    required this.currentWeekTotal,
    required this.currentMonthTotal,
    required this.currentMonthProjected,
    required this.selectedMonthTotal,
    required this.previousMonthTotal,
    required this.averagePerDay,
    required this.averagePerActiveDay,
    required this.previousMonthDelta,
    required this.trackedDays,
    required this.activeDays,
    required this.currentMonthElapsedDays,
    required this.currentMonthNoSpendDays,
    required this.entryCount,
    required this.firstDate,
    required this.mostSpentDayOverall,
    required this.mostSpentDaySelectedMonth,
    required this.mostSpentWeekOverall,
    required this.mostSpentMonthOverall,
    required this.largestEntry,
    required this.topCategories,
    required this.lastSevenDays,
    required this.lastThirtyDays,
    required this.yearlyActivity,
    required this.yearlyMaxDailyTotal,
    required this.totalIncome,
    required this.savingsRolloverIncome,
    required this.currentMonthIncome,
    required this.selectedMonthIncome,
  });

  factory _FinanceInsights.fromEntries(
    List<FinanceEntry> entries, {
    required DateTime selectedMonth,
    required DateTime now,
  }) {
    final today = _dateOnly(now);
    final allUsableEntries =
        entries
            .where(
              (entry) =>
                  !entry.excludedFromBudget &&
                  !_dateOnly(entry.date).isAfter(today),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final usableEntries = allUsableEntries
        .where((entry) => entry.type == FinanceEntryType.expense)
        .toList();
    final incomeEntries = allUsableEntries
        .where((entry) => entry.type == FinanceEntryType.income)
        .toList();

    if (allUsableEntries.isEmpty) {
      return const _FinanceInsights(
        isEmpty: true,
        total: 0,
        todayTotal: 0,
        currentWeekTotal: 0,
        currentMonthTotal: 0,
        currentMonthProjected: 0,
        selectedMonthTotal: 0,
        previousMonthTotal: 0,
        averagePerDay: 0,
        averagePerActiveDay: 0,
        previousMonthDelta: 0,
        trackedDays: 0,
        activeDays: 0,
        currentMonthElapsedDays: 0,
        currentMonthNoSpendDays: 0,
        entryCount: 0,
        firstDate: null,
        mostSpentDayOverall: null,
        mostSpentDaySelectedMonth: null,
        mostSpentWeekOverall: null,
        mostSpentMonthOverall: null,
        largestEntry: null,
        topCategories: [],
        lastSevenDays: [],
        lastThirtyDays: [],
        yearlyActivity: [],
        yearlyMaxDailyTotal: 0,
        totalIncome: 0,
        savingsRolloverIncome: 0,
        currentMonthIncome: 0,
        selectedMonthIncome: 0,
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
    final nextCurrentMonthStart = DateTime(today.year, today.month + 1);
    final currentMonthDays = nextCurrentMonthStart
        .difference(currentMonthStart)
        .inDays;
    final currentMonthElapsedDays =
        today.difference(currentMonthStart).inDays + 1;

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

    var totalIncome = 0.0;
    var savingsRolloverIncome = 0.0;
    var currentMonthIncome = 0.0;
    var selectedMonthIncome = 0.0;
    for (final entry in incomeEntries) {
      final day = _dateOnly(entry.date);
      final month = DateTime(day.year, day.month);
      totalIncome += entry.amount;
      if (_isSavingsRollover(entry)) {
        savingsRolloverIncome += entry.amount;
      }
      if (month == currentMonthStart) currentMonthIncome += entry.amount;
      if (month == selectedMonthStart) selectedMonthIncome += entry.amount;
    }

    final firstDate = _dateOnly(allUsableEntries.first.date);
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
    final lastThirtyDays = List.generate(30, (index) {
      final day = today.subtract(Duration(days: 29 - index));
      return _DatedTotal(day, totalsByDay[day] ?? 0);
    });
    // Trailing 12-month window, but never earlier than the first tracked
    // entry — otherwise the grid renders empty squares for months before any
    // data existed, which reads as if spending was tracked back then.
    final yearlyWindowStart = today.subtract(const Duration(days: 364));
    final yearlyActivityStart = yearlyWindowStart.isBefore(firstDate)
        ? firstDate
        : yearlyWindowStart;
    final alignedYearlyActivityStart = yearlyActivityStart.subtract(
      Duration(days: yearlyActivityStart.weekday - 1),
    );
    final yearlyActivityEnd = today.add(Duration(days: 7 - today.weekday));
    final yearlyActivityDays =
        yearlyActivityEnd.difference(alignedYearlyActivityStart).inDays + 1;
    final yearlyActivity = List.generate(yearlyActivityDays, (index) {
      final day = alignedYearlyActivityStart.add(Duration(days: index));
      final total = day.isAfter(today) ? 0.0 : totalsByDay[day] ?? 0.0;
      return _DatedTotal(day, total);
    });
    final yearlyMaxDailyTotal = yearlyActivity.fold<double>(
      0,
      (max, day) => day.total > max ? day.total : max,
    );
    final currentMonthActiveDays = totalsByDay.keys
        .where(
          (day) =>
              day.year == currentMonthStart.year &&
              day.month == currentMonthStart.month &&
              !day.isAfter(today),
        )
        .length;
    final currentMonthNoSpendDays =
        currentMonthElapsedDays - currentMonthActiveDays;
    final currentMonthProjected = currentMonthElapsedDays == 0
        ? 0.0
        : (currentMonthTotal / currentMonthElapsedDays) * currentMonthDays;

    return _FinanceInsights(
      isEmpty: false,
      total: total,
      todayTotal: todayTotal,
      currentWeekTotal: currentWeekTotal,
      currentMonthTotal: currentMonthTotal,
      currentMonthProjected: currentMonthProjected,
      selectedMonthTotal: selectedMonthTotal,
      previousMonthTotal: previousMonthTotal,
      averagePerDay: trackedDays == 0 ? 0 : total / trackedDays,
      averagePerActiveDay: activeDays == 0 ? 0 : total / activeDays,
      previousMonthDelta: selectedMonthTotal - previousMonthTotal,
      trackedDays: trackedDays,
      activeDays: activeDays,
      currentMonthElapsedDays: currentMonthElapsedDays,
      currentMonthNoSpendDays: currentMonthNoSpendDays,
      entryCount: allUsableEntries.length,
      firstDate: firstDate,
      mostSpentDayOverall: _maxDatedTotal(totalsByDay),
      mostSpentDaySelectedMonth: _maxDatedTotal(selectedMonthDayTotals),
      mostSpentWeekOverall: _maxDatedTotal(totalsByWeek),
      mostSpentMonthOverall: _maxDatedTotal(totalsByMonth),
      largestEntry: largestEntry,
      topCategories: topCategories,
      lastSevenDays: lastSevenDays,
      lastThirtyDays: lastThirtyDays,
      yearlyActivity: yearlyActivity,
      yearlyMaxDailyTotal: yearlyMaxDailyTotal,
      totalIncome: totalIncome,
      savingsRolloverIncome: savingsRolloverIncome,
      currentMonthIncome: currentMonthIncome,
      selectedMonthIncome: selectedMonthIncome,
    );
  }

  static bool _isSavingsRollover(FinanceEntry entry) {
    return entry.type == FinanceEntryType.income &&
        entry.category == FinanceService.savingsCategory &&
        entry.description.toLowerCase().startsWith('savings from');
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

class _CategoryBreakdownCard extends StatefulWidget {
  const _CategoryBreakdownCard({required this.insights});

  final _FinanceInsights insights;

  @override
  State<_CategoryBreakdownCard> createState() => _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends State<_CategoryBreakdownCard> {
  static const int _initialCount = 6;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = widget.insights.topCategories;
    final maxTotal = categories.first.value;
    final visible = _expanded
        ? categories
        : categories.take(_initialCount).toList();
    final hiddenCount = categories.length - _initialCount;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _FinanceInsightsScreenState._cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _FinanceInsightsScreenState._sectionTitle(
            theme,
            'Category Breakdown',
          ),
          const SizedBox(height: 12),
          ...visible.map(
            (entry) => _FinanceInsightsScreenState._buildCategoryRow(
              theme,
              entry,
              total: widget.insights.total,
              maxTotal: maxTotal,
            ),
          ),
          if (hiddenCount > 0)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _expanded ? 'Show less' : 'Show $hiddenCount more',
                  style: AppTheme.bodySmall.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyTrendsCard extends StatefulWidget {
  const _DailyTrendsCard({required this.insights});

  final _FinanceInsights insights;

  @override
  State<_DailyTrendsCard> createState() => _DailyTrendsCardState();
}

class _DailyTrendsCardState extends State<_DailyTrendsCard> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _FinanceInsightsScreenState._cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _FinanceInsightsScreenState._sectionTitle(
                  theme,
                  _page == 0 ? 'Last 7 Days' : 'Last 30 Days',
                ),
              ),
              for (var i = 0; i < 2; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(left: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 154,
            child: PageView(
              controller: _pageController,
              onPageChanged: (page) => setState(() => _page = page),
              children: [
                _buildBars(theme, widget.insights.lastSevenDays),
                _SpendingActivityBars(
                  days: widget.insights.lastThirtyDays,
                  barColor: theme.colorScheme.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _page == 0 ? 'Swipe for last 30 days' : 'Swipe for last 7 days',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBars(ThemeData theme, List<_DatedTotal> days) {
    final maxTotal = days.fold<double>(
      0,
      (max, day) => day.total > max ? day.total : max,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    days[i].total == 0
                        ? '-'
                        : FinanceEntry.formatAmount(days[i].total),
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
                          maxTotal == 0 ? 0.0 : days[i].total / maxTotal,
                          days[i].total == 0 ? 0.06 : 0.12,
                        ),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxWidth: 28),
                          decoration: BoxDecoration(
                            color: days[i].total == 0
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
                    _FinanceInsightsScreenState._shortDayLabel(days[i].date),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Expense bars sized by amount, with no axis labels. Tapping or holding a
/// bar shows a transient overlay popup with that day's total and date, so the
/// numbers stay discoverable without cluttering the chart.
class _SpendingActivityBars extends StatefulWidget {
  const _SpendingActivityBars({required this.days, required this.barColor});

  final List<_DatedTotal> days;
  final Color barColor;

  @override
  State<_SpendingActivityBars> createState() => _SpendingActivityBarsState();
}

class _SpendingActivityBarsState extends State<_SpendingActivityBars> {
  OverlayEntry? _popup;
  Timer? _timer;
  int? _activeIndex;

  @override
  void dispose() {
    _timer?.cancel();
    _popup?.remove();
    _popup = null;
    super.dispose();
  }

  void _showPopup(Offset globalPosition, _DatedTotal day, int index) {
    _removePopup();
    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    const cardWidth = 140.0;
    final left = (globalPosition.dx - cardWidth / 2).clamp(
      8.0,
      screen.width - cardWidth - 8.0,
    );
    final top = (globalPosition.dy - 88.0).clamp(48.0, screen.height - 140.0);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        width: cardWidth,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 6),
                child: child,
              ),
            ),
            child: _popupCard(theme, day),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _timer = Timer(const Duration(milliseconds: 1600), _removePopup);
    setState(() {
      _popup = entry;
      _activeIndex = index;
    });
  }

  void _removePopup() {
    _timer?.cancel();
    _timer = null;
    _popup?.remove();
    _popup = null;
    if (mounted) setState(() => _activeIndex = null);
  }

  Widget _popupCard(ThemeData theme, _DatedTotal day) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              day.total == 0 ? 'No spending' : FinanceEntry.money(day.total),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyMedium.copyWith(
                color: theme.colorScheme.onInverseSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _popupDate(day.date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onInverseSurface.withValues(
                  alpha: 0.72,
                ),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _popupDate(DateTime date) {
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
    return '${names[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = widget.days;
    final maxTotal = days.fold<double>(
      0,
      (max, day) => day.total > max ? day.total : max,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _showPopup(details.globalPosition, days[i], i),
                onLongPressStart: (details) =>
                    _showPopup(details.globalPosition, days[i], i),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: math.max(
                      maxTotal == 0 ? 0.0 : days[i].total / maxTotal,
                      days[i].total == 0 ? 0.05 : 0.12,
                    ),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 18),
                      decoration: BoxDecoration(
                        color: days[i].total == 0
                            ? theme.colorScheme.outline.withValues(alpha: 0.18)
                            : i == _activeIndex
                            ? theme.colorScheme.primary
                            : widget.barColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
