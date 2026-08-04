import 'package:budget_ai/src/finances/finance_service.dart';

class BankTransactionMapper {
  const BankTransactionMapper._();

  static FinanceEntry fromPlaid(
    Map<String, dynamic> transaction, {
    required String connectionId,
  }) {
    final transactionId = transaction['transaction_id'] as String;
    final category = _category(transaction);
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final isIncome = amount < 0 || category == 'Income';
    final pending = transaction['pending'] as bool? ?? false;
    final merchant = (transaction['merchant_name'] as String?)?.trim();
    final name = (transaction['name'] as String?)?.trim();

    return FinanceEntry(
      id: 'bank:plaid:$transactionId',
      type: isIncome ? FinanceEntryType.income : FinanceEntryType.expense,
      date:
          DateTime.tryParse(transaction['authorized_date'] as String? ?? '') ??
          DateTime.tryParse(transaction['date'] as String? ?? '') ??
          DateTime.now(),
      hasTime: false,
      description: merchant?.isNotEmpty == true
          ? merchant!
          : name?.isNotEmpty == true
          ? name!
          : 'Bank transaction',
      amount: amount.abs(),
      category: category,
      createdAt: DateTime.now(),
      source: FinanceEntrySource.bank,
      provider: 'plaid',
      connectionId: connectionId,
      accountId: transaction['account_id'] as String?,
      externalTransactionId: transactionId,
      pendingTransactionId: transaction['pending_transaction_id'] as String?,
      merchantName: merchant,
      currencyCode: transaction['iso_currency_code'] as String?,
      bankState: pending
          ? BankTransactionState.pending
          : BankTransactionState.posted,
      excludedFromBudget: category == 'Transfer',
    );
  }

  static FinanceEntry mergeProviderUpdate(
    FinanceEntry incoming,
    FinanceEntry? existing,
  ) {
    if (existing == null) return incoming;
    return incoming.copyWith(
      description: existing.userModified
          ? existing.description
          : incoming.description,
      category: existing.userModified ? existing.category : incoming.category,
      excludedFromBudget: existing.excludedFromBudget,
      userModified: existing.userModified,
    );
  }

  static String _category(Map<String, dynamic> transaction) {
    final category = transaction['personal_finance_category'];
    final primary = category is Map
        ? (category['primary'] as String? ?? '').toUpperCase()
        : '';
    final detailed = category is Map
        ? (category['detailed'] as String? ?? '').toUpperCase()
        : '';
    if (primary == 'INCOME') return 'Income';
    if (primary == 'REFUND' || detailed.contains('REFUND')) return 'Refund';
    if (primary == 'TRANSFER_IN' || primary == 'TRANSFER_OUT') {
      return 'Transfer';
    }
    if (detailed.contains('GAS') || primary == 'TRANSPORTATION') {
      return 'Transportation';
    }
    if (detailed.contains('GROCER')) return 'Groceries';
    if (primary == 'FOOD_AND_DRINK') return 'Food';
    if (primary == 'RENT_AND_UTILITIES') return 'Bills';
    if (primary == 'MEDICAL') return 'Healthcare';
    if (primary == 'ENTERTAINMENT') return 'Entertainment';
    if (primary == 'GENERAL_MERCHANDISE') return 'Shopping';
    return 'Other';
  }
}
