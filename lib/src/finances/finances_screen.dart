import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/pill_nav_bar.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/chat/chat_loading_widgets.dart';
import 'package:budget_ai/src/finances/finance_entry_edit_screen.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
import 'package:budget_ai/src/widgets/siri_finance_realtime_sync.dart';
import 'package:budget_ai/src/widgets/android_finance_app_actions.dart';
import 'package:toastification/toastification.dart';

class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key});

  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<FinanceEntry> _allEntries = [];
  List<FinanceEntry> _monthEntries = [];
  bool _isLoading = true;
  bool _isOverall = false;
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    SiriFinanceRealtimeSync.revision.addListener(_handleSiriFinanceChanged);
    AndroidFinanceAppActions.revision.addListener(_handleSiriFinanceChanged);
    LocalFinanceStore.instance.changes.addListener(_handleSiriFinanceChanged);
    EncryptedFinanceSyncService.instance.status.addListener(
      _handleSyncStatusChanged,
    );
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    SiriFinanceRealtimeSync.revision.removeListener(_handleSiriFinanceChanged);
    AndroidFinanceAppActions.revision.removeListener(_handleSiriFinanceChanged);
    LocalFinanceStore.instance.changes.removeListener(
      _handleSiriFinanceChanged,
    );
    EncryptedFinanceSyncService.instance.status.removeListener(
      _handleSyncStatusChanged,
    );
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSiriFinanceChanged() {
    _load(showLoading: false);
  }

  void _handleSyncStatusChanged() {
    // The sync status alone can flip the "still fetching" shimmer on/off
    // even when no local rows changed (e.g. syncing finished with 0 rows).
    if (mounted) setState(() {});
  }

  bool get _isInitialSyncPending =>
      _allEntries.isEmpty &&
      EncryptedFinanceSyncService.instance.status.value == 'Syncing…';

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
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
        month.month == _selectedMonth.month &&
        !_isOverall) {
      return;
    }
    if (month.year == _selectedMonth.year &&
        month.month == _selectedMonth.month) {
      setState(() => _isOverall = false);
      return;
    }
    setState(() {
      _selectedMonth = month;
      _isOverall = false;
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

  void _selectOverall() {
    if (_isOverall) return;
    setState(() => _isOverall = true);
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

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  bool get _isSearchFieldActive => _searchFocusNode.hasFocus || _isSearching;

  List<FinanceEntry> get _scopedEntries =>
      _isOverall ? _allEntries : _monthEntries;

  List<FinanceEntry> get _currentMonthEntries {
    final now = DateTime.now();
    return _allEntries
        .where(
          (entry) =>
              entry.date.year == now.year && entry.date.month == now.month,
        )
        .toList();
  }

  List<FinanceEntry> get _visibleEntries {
    final query = _searchController.text.trim();
    if (query.isEmpty) return _scopedEntries;

    final terms = _searchTerms(query);
    if (terms.isEmpty) return _scopedEntries;

    final normalizedQuery = _normalizeSearchText(query);
    final matches = <({FinanceEntry entry, int score})>[];
    for (final entry in _scopedEntries) {
      final score = _searchScore(entry, normalizedQuery, terms);
      if (score > 0) matches.add((entry: entry, score: score));
    }
    final primaryMatches = matches.where((match) => match.score > 120).toList();
    final results = primaryMatches.isEmpty ? matches : primaryMatches;
    results.sort((a, b) {
      final relevance = b.score.compareTo(a.score);
      return relevance != 0 ? relevance : b.entry.date.compareTo(a.entry.date);
    });
    return results.map((match) => match.entry).toList();
  }

  void _handleSearchFocusChanged() {
    if (mounted) setState(() {});
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
    final visibleEntries = _visibleEntries;
    final scopedEntries = _scopedEntries;
    final balanceEntries = _isOverall ? _currentMonthEntries : scopedEntries;
    final isSearching = _isSearching;
    final isSearchFieldActive = _isSearchFieldActive;
    final hasAnyEntries = _allEntries.isNotEmpty;
    final hasScopedEntries = scopedEntries.isNotEmpty;
    final isBusy = _isLoading || _isInitialSyncPending;
    final shouldShowSearchField =
        !isBusy && hasAnyEntries && (hasScopedEntries || isSearchFieldActive);
    final totalExpense = FinanceService.instance.totalAmount(
      scopedEntries,
      type: FinanceEntryType.expense,
    );
    final totalIncome = FinanceService.instance.totalAmount(
      scopedEntries,
      type: FinanceEntryType.income,
    );
    final currentBalance =
        FinanceService.instance.totalAmount(
          balanceEntries,
          type: FinanceEntryType.income,
        ) -
        FinanceService.instance.totalAmount(
          balanceEntries,
          type: FinanceEntryType.expense,
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Finances'),
        actions: [
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
            icon: const BudgetMarkIcon(size: 28),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PillNavBar(
                  items: ['Overall', ...months.map(_monthLabel)],
                  selectedIndex: _isOverall
                      ? 0
                      : months.indexWhere(
                              (m) =>
                                  m.year == _selectedMonth.year &&
                                  m.month == _selectedMonth.month,
                            ) +
                            1,
                  onSelected: (index) => index == 0
                      ? _selectOverall()
                      : _selectMonth(months[index - 1]),
                ),
                const SizedBox(height: 12),
                if (!isBusy)
                  _buildCurrentBalanceCard(
                    theme,
                    currentBalance,
                    totalIncome,
                    totalExpense,
                    isOverall: _isOverall,
                  ),
                if (!isBusy && isSearching)
                  _buildSearchResultsHeader(theme, visibleEntries.length),
                Expanded(
                  child: isBusy
                      ? const _FinanceListShimmer()
                      : scopedEntries.isEmpty
                      ? _buildEmpty(theme)
                      : visibleEntries.isEmpty
                      ? _buildNoSearchResults(theme)
                      : _buildList(theme, visibleEntries),
                ),
              ],
            ),
          ),
          if (shouldShowSearchField)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildFinanceSearchField(),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentBalanceCard(
    ThemeData theme,
    double balance,
    double totalIncome,
    double totalExpense, {
    required bool isOverall,
  }) {
    final cardColor = theme.colorScheme.primary;
    final onCard = AppTheme.readableOn(cardColor);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month);
    final isPreviousMonth = !isOverall && selectedMonth.isBefore(currentMonth);
    final isSaved = balance >= 0;
    final wasTransferred =
        isPreviousMonth &&
        balance != 0 &&
        FinanceService.hasRolloverForMonth(_allEntries, selectedMonth);
    final balanceColor = !isPreviousMonth
        ? onCard
        : isSaved
        ? Colors.green
        : Colors.red;
    final balanceText = !isPreviousMonth
        ? FinanceEntry.money(balance)
        : isSaved
        ? '${FinanceEntry.money(balance, forceSign: balance > 0)} Saved'
        : '${FinanceEntry.money(balance)} Overspent';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardColor,
              Color.lerp(cardColor, AppTheme.highlight, 0.28)!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? theme.colorScheme.primary.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.14),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPreviousMonth
                  ? isSaved
                        ? 'SAVED'
                        : 'OVERSPENT'
                  : 'CURRENT BALANCE',
              style: AppTheme.bodySmall.copyWith(
                color: onCard.withValues(alpha: 0.68),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              balanceText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.headingLarge.copyWith(
                color: balanceColor,
                fontSize: isSaved ? 20 : 28,
                fontWeight: FontWeight.w600,
                fontFamily: "Boldonse",
                letterSpacing: 1.2,
              ),
            ),
            if (wasTransferred) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: onCard.withValues(alpha: 0.82),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Transferred To Next Month',
                    style: AppTheme.bodySmall.copyWith(
                      color: onCard.withValues(alpha: 0.76),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildBalanceMetric(
                    onCard: onCard,
                    amountColor: Colors.green,
                    label: 'INCOME',
                    amount: FinanceEntry.money(totalIncome),
                    icon: CupertinoIcons.arrow_down_left,
                  ),
                ),
                Container(
                  width: 1,
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: onCard.withValues(alpha: 0.20),
                ),
                Expanded(
                  child: _buildBalanceMetric(
                    onCard: onCard,
                    amountColor: Colors.red,
                    label: 'EXPENSE',
                    amount: FinanceEntry.money(totalExpense),
                    icon: CupertinoIcons.arrow_up_right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceMetric({
    required Color onCard,
    required Color amountColor,
    required String label,
    required String amount,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, color: onCard, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.bodySmall.copyWith(
                  color: onCard,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyMedium.copyWith(
                  color: amountColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: "Boldonse",
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildSearchResultsHeader(ThemeData theme, int resultCount) {
    final label = resultCount == 1 ? 'result' : 'results';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.search,
            size: 17,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$resultCount $label in ${_isOverall ? 'overall finances' : _monthLabel(_selectedMonth)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
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
            _isOverall
                ? 'No finance entries yet'
                : 'No entries for ${_monthLabel(_selectedMonth)}',
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

  Widget _buildNoSearchResults(ThemeData theme) {
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
              CupertinoIcons.search,
              size: 32,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No finances found',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try another title, category, amount,\nor date.',
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

  Widget _buildList(ThemeData theme, List<FinanceEntry> entriesToShow) {
    final grouped = _groupByDate(entriesToShow);
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 112, top: 12),
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
                      FinanceEntry.money(dayIncome, forceSign: true),
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (dayExpense > 0 || dayIncome == 0)
                    Text(
                      FinanceEntry.money(-dayExpense),
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

  Widget _buildFinanceSearchField() {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final hintColor = theme.colorScheme.onSurfaceVariant;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    const kKeyboardHeightApprox = 280.0;
    final t = (bottomInset / kKeyboardHeightApprox).clamp(0.0, 1.0);

    final horizontalPadding = 32 - (32 - 8) * t;
    final safeAreaBottom = 32 - (32 - 12) * t;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: safeAreaBottom),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: ChatWorkingComposerFrame(
          isWorking: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 56, maxHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.brightness == Brightness.dark
                    ? theme.colorScheme.outline.withValues(alpha: 0.2)
                    : theme.colorScheme.outline.withValues(alpha: 0.06),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    tooltip: 'Search finances',
                    onPressed: () => _searchFocusNode.requestFocus(),
                    icon: Icon(
                      CupertinoIcons.search,
                      size: 26,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      focusNode: _searchFocusNode,
                      controller: _searchController,
                      cursorColor: theme.colorScheme.primary,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _searchFocusNode.unfocus(),
                      onTapOutside: (_) => _searchFocusNode.unfocus(),
                      decoration: InputDecoration(
                        hoverColor: Colors.transparent,
                        hintText: 'Search finances',
                        hintStyle: TextStyle(
                          color: hintColor.withValues(alpha: 0.72),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        fillColor: Colors.transparent,
                      ),
                      maxLines: 1,
                      minLines: 1,
                      textInputAction: TextInputAction.search,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(fontSize: 16, color: textColor),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _searchFocusNode.hasFocus
                      ? SizedBox(
                          key: const ValueKey('hide-search-keyboard'),
                          width: 44,
                          height: 44,
                          child: IconButton(
                            tooltip: 'Hide keyboard',
                            onPressed: _searchFocusNode.unfocus,
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : _isSearching
                      ? SizedBox(
                          key: const ValueKey('clear-search'),
                          width: 44,
                          height: 44,
                          child: IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: Icon(
                              CupertinoIcons.xmark_circle_fill,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('empty-search-action'),
                          width: 44,
                          height: 44,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDismissibleEntry(ThemeData theme, FinanceEntry entry) {
    return Dismissible(
      key: ValueKey('finance-${entry.id}'),
      direction: DismissDirection.horizontal,
      background: _buildEditBackground(),
      secondaryBackground: _buildDeleteBackground(theme),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _openEntryEditor(entry);
          return false;
        }
        return _confirmAndDeleteEntry(entry);
      },
      onDismissed: (_) => _removeDeletedEntry(entry),
      child: _buildEntryTile(theme, entry),
    );
  }

  Widget _buildEntryTile(ThemeData theme, FinanceEntry entry) {
    final timeStr = entry.hasTime ? _formatClockTime(entry.date) : null;
    final onSurface = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: () => _showEntryDetails(entry),
          borderRadius: BorderRadius.circular(100),
          child: Container(
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
          ),
        ),
      ),
    );
  }

  Future<void> _showEntryDetails(FinanceEntry entry) {
    final theme = Theme.of(context);
    final isIncome = entry.type == FinanceEntryType.income;
    final accent = isIncome ? Colors.green : theme.colorScheme.error;
    final readableAccent = AppTheme.readableOn(accent);

    return ResponsiveInfoSheet.show<void>(
      context,
      title: isIncome ? 'Income Details' : 'Expense Details',
      headerIcon: Icon(
        isIncome
            ? CupertinoIcons.arrow_down_left
            : CupertinoIcons.arrow_up_right,
        size: 32,
        color: readableAccent,
      ),
      gradientColors: [accent, accent.withValues(alpha: 0.78)],
      contentWidgets: [
        Center(
          child: Text(
            entry.displaySignedAmount,
            textAlign: TextAlign.center,
            style: AppTheme.headingLarge.copyWith(
              color: isIncome ? Colors.green : theme.colorScheme.error,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            entry.description,
            textAlign: TextAlign.center,
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEntryDetailRow(
          theme,
          icon: CupertinoIcons.tag,
          label: 'Category',
          value: entry.category,
        ),
        _buildEntryDetailRow(
          theme,
          icon: CupertinoIcons.calendar,
          label: 'Date',
          value: entry.displayDate,
        ),
        _buildEntryDetailRow(
          theme,
          icon: CupertinoIcons.time,
          label: 'Logged',
          value: _fullDateTime(entry.createdAt),
        ),
        _buildEntryDetailRow(
          theme,
          icon: isIncome
              ? CupertinoIcons.arrow_down_circle
              : CupertinoIcons.arrow_up_circle,
          label: 'Type',
          value: isIncome ? 'Income' : 'Expense',
        ),
      ],
    );
  }

  Widget _buildEntryDetailRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 12.5,
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

  Widget _buildEditBackground() {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: const Icon(CupertinoIcons.pencil, color: AppTheme.highlight),
    );
  }

  Future<void> _openEntryEditor(FinanceEntry entry) async {
    final updated = await Navigator.of(context).push<FinanceEntry>(
      MaterialPageRoute(builder: (_) => FinanceEntryEditScreen(entry: entry)),
    );
    if (!mounted || updated == null) return;

    final selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month);
    final updatedMonth = DateTime(updated.date.year, updated.date.month);
    setState(() {
      final allIndex = _allEntries.indexWhere((item) => item.id == updated.id);
      if (allIndex >= 0) {
        _allEntries[allIndex] = updated;
      } else {
        _allEntries.add(updated);
      }
      _allEntries.sort((a, b) => b.date.compareTo(a.date));

      _monthEntries.removeWhere((item) => item.id == updated.id);
      if (updatedMonth == selectedMonth) {
        _monthEntries.add(updated);
        _monthEntries.sort((a, b) => b.date.compareTo(a.date));
      }
    });
    showAppToast(
      context,
      message: 'Finance entry updated',
      type: ToastificationType.success,
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
              child: AppButton(
                text: 'Cancel',
                variant: AppButtonVariant.outlined,
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            Expanded(
              child: AppButton(
                text: 'Delete',
                isRed: true,
                onPressed: () => Navigator.pop(context, true),
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

  List<String> _searchTerms(String query) {
    return _normalizeSearchText(
      query,
    ).split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
  }

  int _searchScore(
    FinanceEntry entry,
    String normalizedQuery,
    List<String> terms,
  ) {
    final title = _normalizeSearchText(entry.description);
    final category = _normalizeSearchText(entry.category);

    final titleScore = _fieldSearchScore(
      title,
      normalizedQuery,
      terms,
      exact: 600,
      startsWith: 560,
      phrase: 520,
      allTerms: 480,
      eachTerm: 450,
    );
    if (titleScore > 0) return titleScore;

    final categoryScore = _fieldSearchScore(
      category,
      normalizedQuery,
      terms,
      exact: 400,
      startsWith: 370,
      phrase: 340,
      allTerms: 310,
      eachTerm: 280,
    );
    if (categoryScore > 0) return categoryScore;

    final amountText = _normalizeSearchText(
      [
        entry.amount.toString(),
        FinanceEntry.formatAmount(entry.amount),
        entry.displayAmount,
        entry.displaySignedAmount,
      ].join(' '),
    );
    final amountScore = _fieldSearchScore(
      amountText,
      normalizedQuery,
      terms,
      exact: 260,
      startsWith: 250,
      phrase: 240,
      allTerms: 230,
      eachTerm: 180,
    );
    if (amountScore > 0) return amountScore;

    final dateScore = _fieldSearchScore(
      _normalizeSearchText(_searchDateTextForEntry(entry)),
      normalizedQuery,
      terms,
      exact: 120,
      startsWith: 110,
      phrase: 100,
      allTerms: 90,
      eachTerm: 20,
    );
    if (dateScore > 0) return dateScore;

    final type = entry.type == FinanceEntryType.income ? 'income' : 'expense';
    return _fieldSearchScore(
      type,
      normalizedQuery,
      terms,
      exact: 60,
      startsWith: 55,
      phrase: 50,
      allTerms: 45,
      eachTerm: 30,
    );
  }

  int _fieldSearchScore(
    String field,
    String query,
    List<String> terms, {
    required int exact,
    required int startsWith,
    required int phrase,
    required int allTerms,
    required int eachTerm,
  }) {
    if (field == query) return exact;
    if (field.startsWith(query)) return startsWith;
    if (field.contains(query)) return phrase;
    final matchedTerms = terms.where(field.contains).length;
    if (matchedTerms == terms.length) return allTerms;
    if (matchedTerms == 0) return 0;
    final termScore = eachTerm + matchedTerms;
    return termScore < allTerms ? termScore : allTerms - 1;
  }

  String _searchDateTextForEntry(FinanceEntry entry) {
    return [
      entry.date.toIso8601String(),
      entry.displayDate,
      _dayLabel(entry.date),
      _monthLabel(DateTime(entry.date.year, entry.date.month)),
      if (entry.hasTime) _formatClockTime(entry.date),
    ].join(' ');
  }

  String _normalizeSearchText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
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

  String _fullDateTime(DateTime date) {
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
    return '${date.day.toString().padLeft(2, '0')} '
        '${months[date.month - 1]} ${date.year}, '
        '${_formatClockTime(date)}';
  }
}

/// Placeholder shown while entries are being read locally or backfilled by
/// the encrypted sync, so the finances screen never flashes an empty state
/// while data is still on its way in.
class _FinanceListShimmer extends StatelessWidget {
  const _FinanceListShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const ChatShimmerBlock(
              width: 44,
              height: 44,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChatShimmerBlock(
                    width: 120 + (index % 3) * 30,
                    height: 13,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 8),
                  const ChatShimmerBlock(
                    width: 80,
                    height: 11,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const ChatShimmerBlock(
              width: 56,
              height: 15,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          ],
        ),
      ),
    );
  }
}
