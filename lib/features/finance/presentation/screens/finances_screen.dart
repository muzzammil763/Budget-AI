import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/pill_nav_bar.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/features/finance/presentation/screens/finance_insights_screen.dart';
import 'package:budget_ai/features/finance/presentation/screens/loans_screen.dart';
import 'package:toastification/toastification.dart';

class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key});

  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  List<FinanceEntry> _allEntries = [];
  List<FinanceEntry> _monthEntries = [];
  bool _isLoading = true;
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    FinanceService.instance.invalidateCache();
    await FinanceService.instance.applySavingsRollover();
    final allEntries = await FinanceService.instance.getAll();
    final month = await FinanceService.instance.getByMonth(
      _selectedMonth.year,
      _selectedMonth.month,
    );
    if (mounted) {
      setState(() {
        _allEntries = List.from(allEntries);
        _monthEntries = List.from(month);
        _isLoading = false;
      });
    }
  }

  Future<void> _selectMonth(DateTime month) async {
    if (month.year == _selectedMonth.year &&
        month.month == _selectedMonth.month) {
      return;
    }
    setState(() {
      _selectedMonth = month;
      _isLoading = true;
    });
    final entries = await FinanceService.instance.getByMonth(
      month.year,
      month.month,
    );
    if (mounted) {
      setState(() {
        _monthEntries = List.from(entries);
        _isLoading = false;
      });
    }
  }

  List<DateTime> _availableMonths() {
    final months = <DateTime>{};
    for (final e in _allEntries) {
      months.add(DateTime(e.date.year, e.date.month));
    }
    final now = DateTime.now();
    months.add(DateTime(now.year, now.month));
    return months.toList()..sort((a, b) => b.compareTo(a));
  }

  Map<String, List<FinanceEntry>> _groupByDate(List<FinanceEntry> entries) {
    final groups = <String, List<FinanceEntry>>{};
    for (final e in entries) {
      final key =
          '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}';
      (groups[key] ??= []).add(e);
    }
    // Sort entries within each group by time (latest first)
    for (final group in groups.values) {
      group.sort((a, b) => b.date.compareTo(a.date));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = _availableMonths();
    final totalExpense = FinanceService.instance.totalAmount(
      _monthEntries,
      type: FinanceEntryType.expense,
    );
    final totalIncome = FinanceService.instance.totalAmount(
      _monthEntries,
      type: FinanceEntryType.income,
    );
    final byCat = FinanceService.instance.categorySummary(_monthEntries);
    final topCats = byCat.entries.take(8).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Finances'),
        actions: [
          IconButton(
            tooltip: 'Loans',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoansScreen()));
            },
            icon: const Icon(Icons.handshake_outlined),
          ),
          IconButton(
            tooltip: 'Finance insights',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FinanceInsightsScreen(
                    entries: _allEntries,
                    selectedMonth: _selectedMonth,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.insights_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PillNavBar(
            items: months.map((m) => _monthLabel(m)).toList(),
            selectedIndex: months.indexWhere(
              (m) =>
                  m.year == _selectedMonth.year &&
                  m.month == _selectedMonth.month,
            ),
            onSelected: (index) => _selectMonth(months[index]),
          ),
          if (!_isLoading && _monthEntries.isNotEmpty)
            _buildSummaryCard(theme, totalExpense, totalIncome, topCats),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _monthEntries.isEmpty
                ? _buildEmpty(theme)
                : _buildList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    double totalExpense,
    double totalIncome,
    List<MapEntry<String, double>> topCats,
  ) {
    final cardColor = theme.colorScheme.primary;
    final onCard = AppTheme.readableOn(cardColor);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cardColor,
            Color.lerp(cardColor, theme.colorScheme.primary, 0.28)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL · ${_monthLabel(_selectedMonth).toUpperCase()}',
                  style: AppTheme.bodySmall.copyWith(
                    color: onCard.withValues(alpha: 0.65),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '-${FinanceEntry.formatAmount(totalExpense)} Rs',
                  style: AppTheme.headingLarge.copyWith(
                    color: Colors.red,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '+${FinanceEntry.formatAmount(totalIncome)} Rs',
                  style: AppTheme.headingLarge.copyWith(
                    color: Colors.green,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (totalIncome > totalExpense) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      'SAVED ${FinanceEntry.formatAmount(totalIncome - totalExpense)} Rs',
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.green,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _monthEntries.length == 1
                      ? '1 ENTRY'
                      : '${_monthEntries.length} ENTRIES',
                  style: AppTheme.bodySmall.copyWith(
                    color: onCard.withValues(alpha: 0.6),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (topCats.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: topCats.take(3).map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${e.key} · ${FinanceEntry.formatAmount(e.value)} Rs',
                    style: TextStyle(
                      color: onCard.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
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

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 32,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No entries for ${_monthLabel(_selectedMonth)}',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Log an expense from the chat\nand it will show up here.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    final grouped = _groupByDate(_monthEntries);
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 12),
      itemCount: keys.length,
      itemBuilder: (ctx, i) {
        final key = keys[i];
        final entries = grouped[key]!;
        final dayExpense = FinanceService.instance.totalAmount(
          entries,
          type: FinanceEntryType.expense,
        );
        final dayIncome = FinanceService.instance.totalAmount(
          entries,
          type: FinanceEntryType.income,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Row(
                spacing: 12,
                children: [
                  Text(
                    _dayLabel(entries.first.date).toUpperCase(),
                    style: AppTheme.headingSmall.copyWith(
                      color: theme.colorScheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      height: 1,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  if (dayIncome > 0) ...[
                    Text(
                      '+${FinanceEntry.formatAmount(dayIncome)} Rs',
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (dayExpense > 0 || dayIncome == 0)
                    Text(
                      '-${FinanceEntry.formatAmount(dayExpense)} Rs',
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
            ...entries.map((entry) => _buildDismissibleEntry(theme, entry)),
          ],
        );
      },
    );
  }

  Widget _buildDismissibleEntry(ThemeData theme, FinanceEntry entry) {
    return Dismissible(
      key: ValueKey('finance-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: _buildDeleteBackground(theme),
      confirmDismiss: (_) => _confirmAndDeleteEntry(entry),
      onDismissed: (_) => _removeDeletedEntry(entry),
      child: _buildEntryTile(theme, entry),
    );
  }

  Widget _buildEntryTile(ThemeData theme, FinanceEntry entry) {
    final timeStr = entry.hasTime ? _formatClockTime(entry.date) : null;
    final onSurface = theme.colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: onSurface.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Center(
              child: Text(
                entry.category.isNotEmpty ? entry.category[0] : '?',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,

                  entry.description,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      entry.category,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (timeStr != null) ...[
                      Text(
                        ' · $timeStr',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.displaySignedAmount,
            style: AppTheme.headingSmall.copyWith(
              color: entry.type == FinanceEntryType.income
                  ? Colors.green
                  : Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteBackground(ThemeData theme) {
    return Container(
      alignment: Alignment.centerRight,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: Icon(CupertinoIcons.trash, color: theme.colorScheme.error),
    );
  }

  Future<bool> _confirmAndDeleteEntry(FinanceEntry entry) async {
    final theme = Theme.of(context);
    final confirmed = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Delete Finance Entry?',
      headerIcon: Icon(
        CupertinoIcons.trash,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.error),
      ),
      gradientColors: [
        theme.colorScheme.error,
        theme.colorScheme.error.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Delete "${entry.description}" (${entry.displayAmount})?',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 0,
                    side: BorderSide(color: theme.colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    if (confirmed != true) return false;

    final deleted = await FinanceService.instance.delete(entry.id);
    if (!mounted) return false;
    if (!deleted) {
      showAppToast(
        context,
        message: 'Finance entry could not be deleted',
        type: ToastificationType.error,
      );
      return false;
    }

    return true;
  }

  void _removeDeletedEntry(FinanceEntry entry) {
    if (!mounted) return;
    setState(() {
      _allEntries.removeWhere((item) => item.id == entry.id);
      _monthEntries.removeWhere((item) => item.id == entry.id);
    });
    showAppToast(
      context,
      message: 'Finance entry deleted',
      type: ToastificationType.success,
    );
  }

  String _dayLabel(DateTime date) {
    const months = [
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
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final entryDay = DateTime(date.year, date.month, date.day);
    if (entryDay == today) return 'Today';
    if (entryDay == yesterday) return 'Yesterday';
    return '${days[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}';
  }

  String _formatClockTime(DateTime date) {
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
