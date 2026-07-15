import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/pill_nav_bar.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  static const _filters = ['All', 'Borrowed', 'Lent'];

  List<LoanRecord> _loans = [];
  bool _isLoading = true;
  int _filterIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    LoanService.instance.invalidateCache();
    final loans = await LoanService.instance.getAll();
    if (mounted) {
      setState(() {
        _loans = List.from(loans);
        _isLoading = false;
      });
    }
  }

  List<LoanRecord> get _visibleLoans {
    return switch (_filterIndex) {
      1 =>
        _loans
            .where((loan) => loan.direction == LoanDirection.borrowed)
            .toList(),
      2 =>
        _loans.where((loan) => loan.direction == LoanDirection.lent).toList(),
      _ => _loans,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visibleLoans;
    final borrowedRemaining = LoanService.instance.totalRemaining(
      _loans,
      LoanDirection.borrowed,
    );
    final lentRemaining = LoanService.instance.totalRemaining(
      _loans,
      LoanDirection.lent,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Loans'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PillNavBar(
            items: _filters,
            selectedIndex: _filterIndex,
            onSelected: (index) => setState(() => _filterIndex = index),
          ),
          if (!_isLoading && _loans.isNotEmpty)
            _buildSummaryCard(theme, borrowedRemaining, lentRemaining),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? _buildEmpty(theme)
                : _buildList(theme, visible),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    double borrowedRemaining,
    double lentRemaining,
  ) {
    final cardColor = theme.colorScheme.primary;
    final onCard = AppTheme.readableOn(cardColor);
    final isDark = theme.brightness == Brightness.dark;
    final openLoans = _loans.where((loan) => loan.remainingAmount > 0).length;
    final borrowedLoans = _loans
        .where((loan) => loan.direction == LoanDirection.borrowed)
        .toList();
    final lentLoans = _loans
        .where((loan) => loan.direction == LoanDirection.lent)
        .toList();
    final borrowedPrincipal = borrowedLoans.fold(
      0.0,
      (sum, loan) => sum + loan.principal,
    );
    final borrowedPaid = borrowedLoans.fold(
      0.0,
      (sum, loan) => sum + loan.paidAmount,
    );
    final lentPrincipal = lentLoans.fold(
      0.0,
      (sum, loan) => sum + loan.principal,
    );
    final lentPaid = lentLoans.fold(0.0, (sum, loan) => sum + loan.paidAmount);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryColumn(
                  theme,
                  label: 'I BORROWED',
                  primaryAmount: borrowedPrincipal,
                  primaryColor: Colors.red,
                  rows: [_LoanSummaryRow('I paid', borrowedPaid)],
                ),
              ),
              Expanded(
                child: _buildSummaryColumn(
                  theme,
                  label: 'I LENT',
                  primaryAmount: lentPrincipal,
                  primaryColor: Colors.green,
                  rows: [_LoanSummaryRow('I got back', lentPaid)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryFooterItem(
                  theme,
                  value: '$openLoans',
                  label: openLoans == 1 ? 'Open loan' : 'Open loans',
                ),
              ),
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: onCard.withValues(alpha: 0.16),
              ),
              Expanded(
                child: _buildSummaryFooterItem(
                  theme,
                  value: FinanceEntry.money(borrowedRemaining),
                  label: 'To pay back',
                  valueColor: Colors.red,
                ),
              ),
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: onCard.withValues(alpha: 0.16),
              ),
              Expanded(
                child: _buildSummaryFooterItem(
                  theme,
                  value: FinanceEntry.money(lentRemaining),
                  label: 'To receive',
                  valueColor: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryColumn(
    ThemeData theme, {
    required String label,
    required double primaryAmount,
    required Color primaryColor,
    required List<_LoanSummaryRow> rows,
  }) {
    final onCard = AppTheme.readableOn(theme.colorScheme.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTheme.bodySmall.copyWith(
            color: onCard.withValues(alpha: 0.65),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          FinanceEntry.money(primaryAmount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.headingLarge.copyWith(
            color: primaryColor,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              '${row.label}: ${FinanceEntry.money(row.amount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall.copyWith(
                color: onCard.withValues(alpha: 0.76),
                fontSize: row.isEmphasis ? 12.5 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryFooterItem(
    ThemeData theme, {
    required String value,
    required String label,
    Color? valueColor,
  }) {
    final onCard = AppTheme.readableOn(theme.colorScheme.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.headingSmall.copyWith(
            color: valueColor ?? onCard,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodySmall.copyWith(
            color: onCard.withValues(alpha: 0.68),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
              CupertinoIcons.arrow_right_arrow_left_circle,
              size: 32,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No loans recorded',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a loan from the chat when you\nborrow or lend money and track\nrepayments here.',
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

  Widget _buildList(ThemeData theme, List<LoanRecord> loans) {
    return ListView.builder(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 12),
      itemCount: loans.length,
      itemBuilder: (ctx, i) => _buildDismissibleLoan(theme, loans[i]),
    );
  }

  Widget _buildDismissibleLoan(ThemeData theme, LoanRecord loan) {
    return Dismissible(
      key: ValueKey('loan-${loan.id}'),
      direction: DismissDirection.endToStart,
      background: _buildDeleteBackground(theme),
      confirmDismiss: (_) => _confirmAndDeleteLoan(loan),
      onDismissed: (_) => _removeDeletedLoan(loan),
      child: _buildLoanCard(theme, loan),
    );
  }

  Widget _buildLoanCard(ThemeData theme, LoanRecord loan) {
    final onSurface = theme.colorScheme.onSurface;
    final isBorrowed = loan.direction == LoanDirection.borrowed;
    final directionColor = isBorrowed ? Colors.red : Colors.green;
    final paidProgress = loan.principal == 0
        ? 0.0
        : (loan.paidAmount / loan.principal).clamp(0.0, 1.0);
    final isSettled = loan.remainingAmount <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: onSurface.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: directionColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Icon(
                  isBorrowed
                      ? CupertinoIcons.arrow_down_left
                      : CupertinoIcons.arrow_up_right,
                  size: 18,
                  color: directionColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.person,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${isBorrowed ? 'Borrowed' : 'Lent'} · ${_dateLabel(loan.date)}'
                      '${loan.description.isEmpty ? '' : ' · ${loan.description}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isSettled
                        ? 'SETTLED'
                        : FinanceEntry.money(
                            isBorrowed
                                ? -loan.remainingAmount
                                : loan.remainingAmount,
                            forceSign: !isBorrowed,
                          ),
                    style: AppTheme.headingSmall.copyWith(
                      color: isSettled
                          ? theme.colorScheme.onSurfaceVariant
                          : directionColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSettled ? 'of ${loan.displayPrincipal}' : 'remaining',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: paidProgress,
              backgroundColor: directionColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(directionColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  isBorrowed
                      ? 'I paid ${loan.displayPaid} of ${loan.displayPrincipal}'
                      : '${loan.person} paid ${loan.displayPaid} of ${loan.displayPrincipal}',
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(paidProgress * 100).round()}%',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (loan.payments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              height: 1,
              color: onSurface.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 8),
            Text(
              'TIMELINE',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            ..._buildTimelineRows(theme, loan),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTimelineRows(ThemeData theme, LoanRecord loan) {
    final isBorrowed = loan.direction == LoanDirection.borrowed;
    final directionColor = isBorrowed ? Colors.red : Colors.green;
    final ascending = [...loan.payments]
      ..sort((a, b) => a.date.compareTo(b.date));

    var remaining = loan.principal;
    final rows = <Widget>[
      _buildTimelineRow(
        theme,
        dotColor: directionColor,
        isFirst: true,
        isLast: ascending.isEmpty,
        title: isBorrowed
            ? 'Took ${loan.displayPrincipal} from ${loan.person}'
            : 'Gave ${loan.displayPrincipal} to ${loan.person}',
        caption: _dateLabel(loan.date),
      ),
    ];
    for (var i = 0; i < ascending.length; i++) {
      final payment = ascending[i];
      remaining = (remaining - payment.amount).clamp(0.0, loan.principal);
      rows.add(
        _buildTimelineRow(
          theme,
          dotColor: remaining <= 0 ? Colors.green : theme.colorScheme.primary,
          isFirst: false,
          isLast: i == ascending.length - 1,
          title:
              '${isBorrowed ? 'I paid' : '${loan.person} paid'} ${FinanceEntry.money(payment.amount)}${payment.note.isEmpty ? '' : ' · ${payment.note}'}',
          caption:
              '${_dateLabel(payment.date)} · '
              '${remaining <= 0 ? 'Settled' : '${FinanceEntry.money(remaining)} remaining'}',
        ),
      );
    }
    return rows;
  }

  Widget _buildTimelineRow(
    ThemeData theme, {
    required Color dotColor,
    required bool isFirst,
    required bool isLast,
    required String title,
    required String caption,
  }) {
    final lineColor = theme.colorScheme.onSurface.withValues(alpha: 0.14);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 3,
                  color: isFirst ? Colors.transparent : lineColor,
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : lineColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteBackground(ThemeData theme) {
    return Container(
      alignment: Alignment.centerRight,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: Icon(CupertinoIcons.trash, color: theme.colorScheme.error),
    );
  }

  Future<bool> _confirmAndDeleteLoan(LoanRecord loan) async {
    final theme = Theme.of(context);
    final confirmed = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Delete Loan?',
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
          'Delete the ${loan.direction == LoanDirection.borrowed ? 'borrowed' : 'lent'} '
          'loan of ${loan.displayPrincipal} with ${loan.person}? '
          'Its repayment history${loan.direction == LoanDirection.lent ? ' and linked Finance entries' : ''} will also be removed.',
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

    final deleted = await LoanService.instance.delete(loan.id);
    if (!mounted) return false;
    if (!deleted) {
      showAppToast(
        context,
        message: 'Loan could not be deleted',
        type: ToastificationType.error,
      );
      return false;
    }
    return true;
  }

  void _removeDeletedLoan(LoanRecord loan) {
    if (!mounted) return;
    setState(() {
      _loans.removeWhere((item) => item.id == loan.id);
    });
    showAppToast(
      context,
      message: 'Loan deleted',
      type: ToastificationType.success,
    );
  }

  String _dateLabel(DateTime date) {
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
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}, ${date.year}';
  }
}

class _LoanSummaryRow {
  const _LoanSummaryRow(this.label, this.amount) : isEmphasis = false;

  final String label;
  final double amount;
  final bool isEmphasis;
}
