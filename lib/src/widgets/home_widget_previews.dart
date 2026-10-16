import 'dart:math' as math;

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/widgets/home_widget_catalog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The numbers the native widgets compute, derived from finance entries the
/// same way (`BudgetSnapshot` on iOS, `BudgetWidgetData` on Android).
class WidgetPreviewSnapshot {
  WidgetPreviewSnapshot({
    required List<FinanceEntry> entries,
    required this.currency,
    required this.now,
    this.isSample = false,
  }) : entries = List.unmodifiable(
         FinanceService.reportingEntries(entries, includeRollovers: false)
           ..sort((a, b) => b.date.compareTo(a.date)),
       );

  /// Believable numbers for people who have not logged anything yet.
  factory WidgetPreviewSnapshot.sample({
    required String currency,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final lastMonth = DateTime(now.year, now.month - 1, 12);
    FinanceEntry entry(
      String id,
      DateTime date,
      String description,
      double amount,
      String category, {
      bool income = false,
      bool hasTime = false,
    }) {
      return FinanceEntry(
        id: 'sample_$id',
        type: income ? FinanceEntryType.income : FinanceEntryType.expense,
        date: date,
        hasTime: hasTime,
        description: description,
        amount: amount,
        category: category,
        createdAt: date,
      );
    }

    final earlier = today.day > 3
        ? today.subtract(const Duration(days: 2))
        : today;
    return WidgetPreviewSnapshot(
      currency: currency,
      now: now,
      isSample: true,
      entries: [
        entry(
          'coffee',
          today.add(const Duration(hours: 9, minutes: 10)),
          'Morning coffee',
          4.5,
          'Food',
          hasTime: true,
        ),
        entry(
          'lunch',
          today.add(const Duration(hours: 13, minutes: 30)),
          'Lunch with Sam',
          18,
          'Food',
          hasTime: true,
        ),
        entry('fuel', today, 'Fuel', 42, 'Transport'),
        entry('groceries', earlier, 'Groceries', 86.4, 'Groceries'),
        entry('internet', earlier, 'Internet bill', 35, 'Bills'),
        entry('gym', earlier, 'Gym membership', 25, 'Health'),
        entry(
          'salary',
          DateTime(now.year, now.month, 1),
          'Salary',
          2400,
          'Salary',
          income: true,
        ),
        entry('rent', DateTime(now.year, now.month, 1), 'Rent', 650, 'Bills'),
        entry('last_rent', lastMonth, 'Rent', 650, 'Bills'),
        entry('last_shop', lastMonth, 'Shopping', 210, 'Shopping'),
        entry('last_food', lastMonth, 'Groceries', 190, 'Groceries'),
      ],
    );
  }

  final List<FinanceEntry> entries;
  final String currency;
  final DateTime now;
  final bool isSample;

  DateTime monthStart(int offset) => DateTime(now.year, now.month + offset);

  WidgetMonthSummary summary(int offset) {
    final month = monthStart(offset);
    var expense = 0.0;
    var income = 0.0;
    var expenseCount = 0;
    var incomeCount = 0;
    for (final entry in entries) {
      if (entry.date.year != month.year || entry.date.month != month.month) {
        continue;
      }
      if (entry.type == FinanceEntryType.income) {
        income += entry.amount;
        incomeCount++;
      } else {
        expense += entry.amount;
        expenseCount++;
      }
    }
    return WidgetMonthSummary(
      month: month,
      expense: expense,
      income: income,
      expenseCount: expenseCount,
      incomeCount: incomeCount,
    );
  }

  List<FinanceEntry> recentExpenses(int limit) => entries
      .where((entry) => entry.type == FinanceEntryType.expense)
      .take(limit)
      .toList(growable: false);

  List<FinanceEntry> get todayExpenses => entries
      .where(
        (entry) =>
            entry.type == FinanceEntryType.expense &&
            entry.date.year == now.year &&
            entry.date.month == now.month &&
            entry.date.day == now.day,
      )
      .toList(growable: false);

  /// Expense totals per category this month, largest first.
  List<MapEntry<String, double>> categories(int offset) {
    final month = monthStart(offset);
    final totals = <String, double>{};
    for (final entry in entries) {
      if (entry.type != FinanceEntryType.expense ||
          entry.date.year != month.year ||
          entry.date.month != month.month) {
        continue;
      }
      totals[entry.category] = (totals[entry.category] ?? 0) + entry.amount;
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Matches the widgets' `WidgetFormat.amount`.
  String amount(double value, {String sign = ''}) {
    final whole = value.roundToDouble() == value;
    final fixed = value.abs().toStringAsFixed(whole ? 0 : 2);
    final parts = fixed.split('.');
    final digits = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final number = parts.length > 1 ? '$digits.${parts[1]}' : digits;
    if (const ['\$', '€', '£', '₹', '¥'].contains(currency)) {
      return '$sign$currency$number';
    }
    return '$sign$number $currency';
  }
}

class WidgetMonthSummary {
  const WidgetMonthSummary({
    required this.month,
    required this.expense,
    required this.income,
    required this.expenseCount,
    required this.incomeCount,
  });

  final DateTime month;
  final double expense;
  final double income;
  final int expenseCount;
  final int incomeCount;
}

const _monthNames = [
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
const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _shortMonth(DateTime date) =>
    _monthNames[date.month - 1].substring(0, 3);

String _entriesLabel(int count) => '$count ${count == 1 ? 'entry' : 'entries'}';

/// The widgets' monochrome palette with red expense and green income.
class _Palette {
  _Palette(Brightness brightness)
    : primary = brightness == Brightness.dark ? Colors.white : Colors.black,
      surface = brightness == Brightness.dark
          ? const Color(0xFF1C1C1E)
          : Colors.white;

  final Color primary;
  final Color surface;
  Color get secondary => primary.withValues(alpha: 0.58);
  Color get hairline => primary.withValues(alpha: 0.09);
  Color get chip => primary.withValues(alpha: 0.06);
  static const expense = Color.fromRGBO(237, 69, 69, 1);
  static const income = Color.fromRGBO(33, 179, 102, 1);
}

TextStyle _body(double size, Color color, [FontWeight? weight]) => TextStyle(
  fontFamily: 'Google Sans',
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.2,
);

TextStyle _display(double size, Color color) => TextStyle(
  fontFamily: 'Boldonse',
  fontSize: size,
  color: color,
  height: 1.5,
);

/// A native widget redrawn in Flutter at its Home Screen proportions.
class HomeWidgetPreview extends StatelessWidget {
  const HomeWidgetPreview({
    super.key,
    required this.definition,
    required this.snapshot,
  });

  final HomeWidgetDefinition definition;
  final WidgetPreviewSnapshot snapshot;

  /// The widget's size on a typical phone, in logical pixels.
  static Size baseSize(HomeWidgetSize size) => switch (size) {
    HomeWidgetSize.small => const Size(158, 158),
    HomeWidgetSize.medium => const Size(338, 158),
    HomeWidgetSize.large => const Size(338, 354),
    HomeWidgetSize.lockScreen => const Size(338, 150),
  };

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(Theme.of(context).brightness);
    final base = baseSize(definition.size);
    if (definition.size == HomeWidgetSize.lockScreen) {
      return _frame(base, child: _LockScreen(snapshot: snapshot));
    }
    final content = switch (definition.id) {
      'summary' => _Summary(snapshot: snapshot, palette: palette),
      'expenses' => _MonthTotal(
        snapshot: snapshot,
        palette: palette,
        isIncome: false,
      ),
      'income' => _MonthTotal(
        snapshot: snapshot,
        palette: palette,
        isIncome: true,
      ),
      'balance' => _MonthBalance(snapshot: snapshot, palette: palette),
      'comparison' => _Comparison(snapshot: snapshot, palette: palette),
      'recent' => _Recent(snapshot: snapshot, palette: palette),
      'categories' => _Categories(snapshot: snapshot, palette: palette),
      _ => _Today(snapshot: snapshot, palette: palette),
    };
    return _frame(
      base,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: content,
      ),
    );
  }

  Widget _frame(Size base, {required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = HomeWidgetPreview.baseSize(HomeWidgetSize.medium).width;
        final scale = math.min(1.15, constraints.maxWidth / wide);
        return SizedBox(
          width: base.width * scale,
          height: base.height * scale,
          child: FittedBox(
            child: SizedBox.fromSize(size: base, child: child),
          ),
        );
      },
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.label, required this.palette});

  final String label;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, bool enabled) => SizedBox(
      width: 18,
      height: 22,
      child: Icon(
        icon,
        size: 9,
        color: enabled
            ? palette.primary
            : palette.primary.withValues(alpha: 0.2),
      ),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: palette.chip,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(CupertinoIcons.chevron_left, true),
          Text(label, style: _body(11, palette.primary, FontWeight.w600)),
          arrow(CupertinoIcons.chevron_right, false),
        ],
      ),
    );
  }
}

class _FlowBadge extends StatelessWidget {
  const _FlowBadge({required this.isIncome});

  final bool isIncome;
  static const size = 24.0;

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? _Palette.income : _Palette.expense;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: Icon(
        isIncome
            ? CupertinoIcons.arrow_down_left
            : CupertinoIcons.arrow_up_right,
        size: size * 0.46,
        color: color,
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.12),
        shape: const StadiumBorder(),
      ),
      child: Text(text, style: _body(11, color, FontWeight.w500)),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.text, {required this.style, this.alignLeft = false});

  final String text;
  final TextStyle style;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(text, maxLines: 1, style: style),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Container(
            height: 4,
            decoration: ShapeDecoration(
              color: track,
              shape: const StadiumBorder(),
            ),
          ),
          Container(
            height: 4,
            width: math.max(4, constraints.maxWidth * fraction.clamp(0, 1)),
            decoration: ShapeDecoration(
              color: color,
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.trailing,
    required this.palette,
  });

  final String title;
  final Widget trailing;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BudgetMarkIcon(size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _body(14, palette.primary, FontWeight.w600),
          ),
        ),
        trailing,
      ],
    );
  }
}

// ── Budget AI (wide summary) ──────────────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({required this.snapshot, required this.palette});

  final WidgetPreviewSnapshot snapshot;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final month = snapshot.summary(0);
    final recent = snapshot.recentExpenses(2);
    Widget metric(String label, String value, Color dot) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _body(9, palette.secondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        _Amount(value, alignLeft: true, style: _body(13, palette.primary)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BudgetMarkIcon(size: 30),
              const SizedBox(width: 10),
              Text('Budget AI', style: _display(12, palette.primary)),
              const Spacer(),
              Text(
                _monthNames[snapshot.now.month - 1],
                style: _body(12, palette.primary, FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Expenses this month',
                        style: _body(9, palette.secondary),
                      ),
                      _Amount(
                        snapshot.amount(month.expense),
                        alignLeft: true,
                        style: _display(20, palette.primary),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: palette.hairline),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: metric(
                          'Income',
                          snapshot.amount(month.income),
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: metric(
                          'Entries',
                          '${month.expenseCount + month.incomeCount}',
                          palette.primary.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (recent.isEmpty)
            Text('No entries yet', style: _body(10, palette.primary))
          else
            for (final expense in recent)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.description.isEmpty
                            ? expense.category
                            : expense.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _body(10, palette.primary),
                      ),
                    ),
                    Text(
                      snapshot.amount(expense.amount, sign: '−'),
                      style: _body(10, Colors.red),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ── Expenses / Income totals ──────────────────────────────────

class _MonthTotal extends StatelessWidget {
  const _MonthTotal({
    required this.snapshot,
    required this.palette,
    required this.isIncome,
  });

  final WidgetPreviewSnapshot snapshot;
  final _Palette palette;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final summary = snapshot.summary(0);
    final total = isIncome ? summary.income : summary.expense;
    final count = isIncome ? summary.incomeCount : summary.expenseCount;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              _FlowBadge(isIncome: isIncome),
              const Spacer(),
              _MonthChip(label: _shortMonth(summary.month), palette: palette),
            ],
          ),
          const Spacer(),
          Text(
            isIncome ? 'Income' : 'Expenses',
            style: _body(12, palette.secondary, FontWeight.w500),
          ),
          const SizedBox(height: 4),
          _Amount(snapshot.amount(total), style: _display(24, palette.primary)),
          const Spacer(),
          _CountChip(
            text: _entriesLabel(count),
            color: isIncome ? _Palette.income : _Palette.expense,
          ),
        ],
      ),
    );
  }
}

// ── Income & Expenses ─────────────────────────────────────────

class _MonthBalance extends StatelessWidget {
  const _MonthBalance({required this.snapshot, required this.palette});

  final WidgetPreviewSnapshot snapshot;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final summary = snapshot.summary(0);
    final largest = math.max(math.max(summary.income, summary.expense), 1);
    Widget row(String label, double value, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label, style: _body(11, palette.secondary, FontWeight.w500)),
          ],
        ),
        _Amount(
          snapshot.amount(value),
          alignLeft: true,
          style: _display(15, palette.primary),
        ),
        _Bar(fraction: value / largest, color: color, track: palette.hairline),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BudgetMarkIcon(size: 24),
              const Spacer(),
              _MonthChip(label: _shortMonth(summary.month), palette: palette),
            ],
          ),
          const Spacer(),
          row('Income', summary.income, _Palette.income),
          const SizedBox(height: 6),
          row('Expenses', summary.expense, _Palette.expense),
        ],
      ),
    );
  }
}

// ── This Month vs Last ────────────────────────────────────────

class _Comparison extends StatelessWidget {
  const _Comparison({required this.snapshot, required this.palette});

  final WidgetPreviewSnapshot snapshot;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final current = snapshot.summary(0);
    final previous = snapshot.summary(-1);
    final largest = math.max(math.max(current.expense, previous.expense), 1);
    Widget bar(WidgetMonthSummary summary, bool isCurrent) => Expanded(
      child: Column(
        children: [
          _Amount(
            snapshot.amount(summary.expense),
            style: _body(11, palette.primary, FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: math.max(
                    8,
                    constraints.maxHeight * summary.expense / largest,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? palette.primary
                        : palette.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _shortMonth(summary.month),
            style: _body(
              11,
              isCurrent ? palette.primary : palette.secondary,
              FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    Widget? badge;
    if (previous.expense > 0) {
      final change = (current.expense - previous.expense) / previous.expense;
      final color = change > 0 ? _Palette.expense : _Palette.income;
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: ShapeDecoration(
          color: color.withValues(alpha: 0.12),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              change > 0 ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down,
              size: 8,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              '${(change.abs() * 100).round()}%',
              style: _body(10, color, FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Amount(
                  'vs last month',
                  alignLeft: true,
                  style: _body(12, palette.primary, FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
              ?badge,
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                bar(previous, false),
                const SizedBox(width: 12),
                bar(current, true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recent Expenses ───────────────────────────────────────────

class _Recent extends StatelessWidget {
  const _Recent({required this.snapshot, required this.palette});

  final WidgetPreviewSnapshot snapshot;
  final _Palette palette;

  String _day(DateTime date) {
    final now = snapshot.now;
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return '${date.day} ${_shortMonth(date)}';
  }

  @override
  Widget build(BuildContext context) {
    final recent = snapshot.recentExpenses(5);
    return Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          _Header(
            title: 'Recent expenses',
            palette: palette,
            trailing: Text(
              'Last 5',
              style: _body(11, palette.secondary, FontWeight.w500),
            ),
          ),
          const SizedBox(height: 6),
          if (recent.isEmpty)
            Expanded(
              child: _Empty(
                icon: CupertinoIcons.tray,
                text: 'No expenses yet',
                palette: palette,
              ),
            )
          else
            for (final expense in recent)
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.description.isEmpty
                            ? expense.category
                            : expense.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _body(12, palette.primary, FontWeight.w500),
                      ),
                    ),
                    Text(
                      _day(expense.date),
                      style: _body(10, palette.secondary),
                    ),
                    SizedBox(
                      width: 76,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _Amount(
                          snapshot.amount(expense.amount, sign: '−'),
                          style: _body(12, _Palette.expense, FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ── Top Categories ────────────────────────────────────────────

class _Categories extends StatelessWidget {
  const _Categories({required this.snapshot, required this.palette});

  final WidgetPreviewSnapshot snapshot;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final categories = snapshot.categories(0);
    final total = categories.fold<double>(0, (sum, entry) => sum + entry.value);
    final largest = categories.isEmpty ? 1.0 : categories.first.value;
    return Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          _Header(
            title: 'Top categories',
            palette: palette,
            trailing: _MonthChip(
              label: _shortMonth(snapshot.now),
              palette: palette,
            ),
          ),
          const SizedBox(height: 8),
          if (categories.isEmpty)
            Expanded(
              child: _Empty(
                icon: CupertinoIcons.chart_bar,
                text: 'No expenses this month',
                palette: palette,
              ),
            )
          else
            for (final category in categories.take(4))
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _body(12, palette.primary, FontWeight.w500),
                          ),
                        ),
                        Text(
                          snapshot.amount(category.value),
                          style: _body(12, palette.primary, FontWeight.w600),
                        ),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${(category.value / math.max(total, 1) * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: _body(
                              10,
                              palette.secondary,
                              FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    _Bar(
                      fraction: category.value / largest,
                      color: _Palette.expense,
                      track: palette.hairline,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ── Today's Expenses ──────────────────────────────────────────

class _Today extends StatelessWidget {
  const _Today({required this.snapshot, required this.palette});

  final WidgetPreviewSnapshot snapshot;
  final _Palette palette;

  static const _maxRows = 6;

  String _time(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final now = snapshot.now;
    final today = snapshot.todayExpenses;
    final total = today.fold<double>(0, (sum, entry) => sum + entry.amount);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            title: 'Today',
            palette: palette,
            trailing: Text(
              '${_weekdayNames[now.weekday - 1]}, ${now.day} '
              '${_shortMonth(now)}',
              style: _body(11, palette.secondary, FontWeight.w500),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Spent today',
            style: _body(12, palette.secondary, FontWeight.w500),
          ),
          _Amount(
            snapshot.amount(total),
            alignLeft: true,
            style: _display(30, palette.primary),
          ),
          const SizedBox(height: 2),
          _CountChip(
            text: _entriesLabel(today.length),
            color: _Palette.expense,
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: palette.hairline),
          if (today.isEmpty)
            Expanded(
              child: _Empty(
                icon: CupertinoIcons.checkmark_seal,
                text: 'No expenses today',
                palette: palette,
              ),
            )
          else ...[
            const SizedBox(height: 12),
            for (final expense in today.take(_maxRows))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.description.isEmpty
                                ? expense.category
                                : expense.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _body(13, palette.primary, FontWeight.w500),
                          ),
                          Text(
                            expense.hasTime
                                ? _time(expense.date)
                                : expense.category,
                            style: _body(10, palette.secondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      snapshot.amount(expense.amount, sign: '−'),
                      style: _body(13, _Palette.expense, FontWeight.w600),
                    ),
                  ],
                ),
              ),
            if (today.length > _maxRows)
              Text(
                '+${today.length - _maxRows} more',
                style: _body(11, palette.secondary, FontWeight.w500),
              ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, required this.palette});

  final IconData icon;
  final String text;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: palette.primary.withValues(alpha: 0.25)),
        const SizedBox(height: 6),
        Text(text, style: _body(12, palette.secondary, FontWeight.w500)),
      ],
    );
  }
}

// ── Lock Screen (iPhone) ──────────────────────────────────────

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.snapshot});

  final WidgetPreviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final current = snapshot.summary(0);
    final previous = snapshot.summary(-1);
    final limit = math.max(math.max(previous.expense, current.expense), 1);
    final today = snapshot.todayExpenses.fold<double>(
      0,
      (sum, entry) => sum + entry.amount,
    );
    const white = Colors.white;
    final dim = white.withValues(alpha: 0.7);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2A4A), Color(0xFF4A3B6B), Color(0xFF7A4E6E)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            Text(
              'Today ${snapshot.amount(today)} spent',
              style: _body(13, white, FontWeight.w600),
            ),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: current.expense / limit,
                        strokeWidth: 5,
                        backgroundColor: white.withValues(alpha: 0.25),
                        color: white,
                        constraints: const BoxConstraints.tightFor(
                          width: 64,
                          height: 64,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: _Amount(
                          _compact(current.expense),
                          style: _body(13, white, FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _monthNames[current.month.month - 1],
                        style: _body(13, white, FontWeight.w700),
                      ),
                      _line(
                        CupertinoIcons.arrow_up_right,
                        snapshot.amount(current.expense),
                        white,
                      ),
                      _line(
                        CupertinoIcons.arrow_down_left,
                        snapshot.amount(current.income),
                        dim,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, Color color) => Row(
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _body(13, color, FontWeight.w500),
        ),
      ),
    ],
  );

  /// Short amounts for the small ring, e.g. 42.5K or 1.2M.
  static String _compact(double value) {
    String trim(double number) {
      final text = number.toStringAsFixed(1);
      return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
    }

    if (value >= 1000000) return '${trim(value / 1000000)}M';
    if (value >= 1000) return '${trim(value / 1000)}K';
    return trim(value);
  }
}
