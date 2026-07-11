import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/pill_nav_bar.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/loan/loans_screen.dart';
import 'package:toastification/toastification.dart';

class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key});

  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<FinanceEntry> _allEntries = [];
  List<FinanceEntry> _monthEntries = [];
  bool _isLoading = true;
  bool _isBalanceVisible = false;
  bool _isAuthenticatingBalance = false;
  Timer? _balanceHideTimer;
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _balanceHideTimer?.cancel();
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _hideBalance();
    }
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
    _hideBalance();
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

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  bool get _isSearchFieldActive => _searchFocusNode.hasFocus || _isSearching;

  List<FinanceEntry> get _visibleEntries {
    final query = _searchController.text.trim();
    if (query.isEmpty) return _monthEntries;

    final terms = _searchTerms(query);
    if (terms.isEmpty) return _monthEntries;

    return _monthEntries.where((entry) {
      final searchable = _searchTextForEntry(entry);
      final normalized = _normalizeSearchText(searchable);
      final normalizedQuery = _normalizeSearchText(query);
      return normalized.contains(normalizedQuery) ||
          terms.any(normalized.contains);
    }).toList();
  }

  void _hideBalance() {
    _balanceHideTimer?.cancel();
    _balanceHideTimer = null;
    if (_isBalanceVisible && mounted) {
      setState(() => _isBalanceVisible = false);
    }
  }

  void _handleSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleBalanceHide() {
    _balanceHideTimer?.cancel();
    _balanceHideTimer = Timer(const Duration(seconds: 10), _hideBalance);
  }

  Future<void> _toggleBalanceVisibility() async {
    if (_isBalanceVisible) {
      _hideBalance();
      return;
    }
    if (_isAuthenticatingBalance) return;

    setState(() => _isAuthenticatingBalance = true);
    final localAuth = LocalAuthentication();

    try {
      final canCheckBiometrics = await localAuth.canCheckBiometrics;
      final isDeviceSupported = await localAuth.isDeviceSupported();
      final availableBiometrics = await localAuth.getAvailableBiometrics();

      if (!canCheckBiometrics ||
          !isDeviceSupported ||
          availableBiometrics.isEmpty) {
        if (!mounted) return;
        showAppToast(
          context,
          message: 'Biometrics are not set up on this device',
          type: ToastificationType.error,
        );
        return;
      }

      final authenticated = await localAuth.authenticate(
        localizedReason: 'Authenticate to view your current balance',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;
      if (!authenticated) {
        showAppToast(
          context,
          message: 'Authentication failed. Balance is still hidden.',
          type: ToastificationType.error,
        );
        return;
      }

      setState(() => _isBalanceVisible = true);
      _scheduleBalanceHide();
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Authentication error: ${e.toString()}',
        type: ToastificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isAuthenticatingBalance = false);
    }
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
    final isSearching = _isSearching;
    final isSearchFieldActive = _isSearchFieldActive;
    final hasAnyEntries = _allEntries.isNotEmpty;
    final hasMonthEntries = _monthEntries.isNotEmpty;
    final shouldShowSearchField =
        !_isLoading &&
        hasAnyEntries &&
        (hasMonthEntries || isSearchFieldActive);
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
    final currentBalance = totalIncome - totalExpense;

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
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
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
                const SizedBox(height: 12),
                if (!_isLoading && isSearching)
                  _buildSearchResultsHeader(theme, visibleEntries.length),
                if (!_isLoading &&
                    !isSearchFieldActive &&
                    _isCurrentMonth &&
                    hasMonthEntries)
                  _buildCurrentBalanceCard(theme, currentBalance),
                if (!_isLoading && !isSearchFieldActive && hasMonthEntries)
                  _buildSummaryCard(
                    theme,
                    totalExpense,
                    totalIncome,
                    topCats,
                    currentBalance,
                  ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _monthEntries.isEmpty
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

  Widget _buildSummaryCard(
    ThemeData theme,
    double totalExpense,
    double totalIncome,
    List<MapEntry<String, double>> topCats,
    double currentBalance,
  ) {
    final cardColor = theme.colorScheme.primary;
    final onCard = AppTheme.readableOn(cardColor);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
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
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FinanceEntry.money(totalExpense),
                      style: AppTheme.headingLarge.copyWith(
                        color: Colors.red,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      FinanceEntry.money(totalIncome),
                      style: AppTheme.headingLarge.copyWith(
                        color: Colors.green,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
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
                        '${e.key} · ${FinanceEntry.money(e.value)}',
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
          if (!_isCurrentMonth && currentBalance > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${FinanceEntry.money(currentBalance)} will be moved to the next month balance automatically.',
              style: AppTheme.bodySmall.copyWith(
                color: onCard.withValues(alpha: 0.82),
                fontSize: 12,
                fontStyle: FontStyle.italic,

                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentBalanceCard(ThemeData theme, double balance) {
    final cardColor = theme.colorScheme.primary;
    final onCard = AppTheme.readableOn(cardColor);
    final isDark = theme.brightness == Brightness.dark;
    final amount = FinanceEntry.money(balance);

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
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardColor,
              Color.lerp(cardColor, theme.colorScheme.secondary, 0.28)!,
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT BALANCE',
                    style: AppTheme.bodySmall.copyWith(
                      color: onCard.withValues(alpha: 0.68),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.14),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      _isBalanceVisible ? amount : '######',
                      key: ValueKey(_isBalanceVisible),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.headingLarge.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: _isBalanceVisible ? 'Hide balance' : 'Show balance',
              onPressed: _isAuthenticatingBalance
                  ? null
                  : _toggleBalanceVisibility,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _isAuthenticatingBalance
                    ? SizedBox(
                        key: const ValueKey('authenticating'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: onCard,
                        ),
                      )
                    : Icon(
                        _isBalanceVisible
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        key: ValueKey(_isBalanceVisible),
                        color: onCard,
                        size: 32,
                      ),
              ),
            ),
          ],
        ),
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
              '$resultCount $label in ${_monthLabel(_selectedMonth)}',
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
            'Try another word, category, amount,\nor transaction type.',
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
                child: _isSearching
                    ? SizedBox(
                        key: const ValueKey('clear-search'),
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                            _searchFocusNode.requestFocus();
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
            ? CupertinoIcons.arrow_down_circle_fill
            : CupertinoIcons.arrow_up_circle_fill,
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

  List<String> _searchTerms(String query) {
    return _normalizeSearchText(
      query,
    ).split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
  }

  String _searchTextForEntry(FinanceEntry entry) {
    final type = entry.type == FinanceEntryType.income ? 'income' : 'expense';
    return [
      entry.description,
      entry.category,
      type,
      entry.displayAmount,
      entry.displaySignedAmount,
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
