import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/pill_nav_bar.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';
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
    final all = await FinanceService.instance.getAll();
    final month = await FinanceService.instance.getByMonth(
      _selectedMonth.year,
      _selectedMonth.month,
    );
    if (mounted) {
      setState(() {
        _allEntries = List.from(all);
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
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = _availableMonths();
    final total = FinanceService.instance.totalAmount(_monthEntries);
    final byCat = FinanceService.instance.categorySummary(_monthEntries);
    final topCats = byCat.entries.take(8).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Finances'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PillNavBar(
            items: months.map((m) => _monthLabel(m)).toList(),
            selectedIndex: months.indexWhere(
              (m) => m.year == _selectedMonth.year && m.month == _selectedMonth.month,
            ),
            onSelected: (index) => _selectMonth(months[index]),
          ),
          if (!_isLoading && _monthEntries.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Total',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${FinanceEntry.formatAmount(total)} Rs',
                        style: AppTheme.headingSmall.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: topCats.map((e) {
                      return Text(
                        '${e.key}: ${FinanceEntry.formatAmount(e.value)} Rs',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
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
          Icon(
            CupertinoIcons.money_dollar_circle,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No entries for ${_monthLabel(_selectedMonth)}',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
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
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
      itemCount: keys.length,
      itemBuilder: (ctx, i) {
        final key = keys[i];
        final entries = grouped[key]!;
        final dayTotal = FinanceService.instance.totalAmount(entries);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Row(
                spacing: 12,
                children: [
                  Text(
                    "${_dayLabel(entries.first.date)} Total",
                    style: AppTheme.headingSmall.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      height: 1,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '${FinanceEntry.formatAmount(dayTotal)} Rs',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                entry.category.isNotEmpty ? entry.category[0] : '?',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.category,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.displayAmount,
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteBackground(ThemeData theme) {
    return Container(
      alignment: Alignment.centerRight,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(CupertinoIcons.trash, color: theme.colorScheme.onError),
    );
  }

  Future<bool> _confirmAndDeleteEntry(FinanceEntry entry) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Entry?'),
        content: Text(
          'Delete "${entry.description}" (${entry.displayAmount})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
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
}
