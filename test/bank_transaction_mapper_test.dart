import 'package:budget_ai/src/banking/bank_transaction_mapper.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a Plaid expense into an immutable bank entry', () {
    final entry = BankTransactionMapper.fromPlaid({
      'transaction_id': 'posted-1',
      'account_id': 'account-1',
      'amount': 42.6,
      'date': '2026-08-04',
      'merchant_name': 'Shell',
      'pending': false,
      'iso_currency_code': 'GBP',
      'personal_finance_category': {
        'primary': 'TRANSPORTATION',
        'detailed': 'TRANSPORTATION_GAS',
      },
    }, connectionId: 'connection-1');

    expect(entry.id, 'bank:plaid:posted-1');
    expect(entry.type, FinanceEntryType.expense);
    expect(entry.amount, 42.6);
    expect(entry.category, 'Transportation');
    expect(entry.description, 'Shell');
    expect(entry.source, FinanceEntrySource.bank);
    expect(entry.bankState, BankTransactionState.posted);
  });

  test('maps negative Plaid amounts to positive Budget AI income', () {
    final entry = BankTransactionMapper.fromPlaid({
      'transaction_id': 'income-1',
      'account_id': 'account-1',
      'amount': -2500,
      'date': '2026-08-01',
      'name': 'Salary',
      'pending': false,
      'personal_finance_category': {
        'primary': 'INCOME',
        'detailed': 'INCOME_WAGES',
      },
    }, connectionId: 'connection-1');

    expect(entry.type, FinanceEntryType.income);
    expect(entry.amount, 2500);
    expect(entry.category, 'Income');
  });

  test('provider updates preserve user note and category overrides', () {
    final current =
        BankTransactionMapper.fromPlaid({
          'transaction_id': 'transaction-1',
          'amount': 10,
          'date': '2026-08-01',
          'name': 'Original merchant',
          'pending': true,
        }, connectionId: 'connection-1').copyWith(
          description: 'My note',
          category: 'Work',
          userModified: true,
          excludedFromBudget: true,
        );
    final update = BankTransactionMapper.fromPlaid({
      'transaction_id': 'transaction-1',
      'amount': 12,
      'date': '2026-08-02',
      'name': 'Posted merchant',
      'pending': false,
    }, connectionId: 'connection-1');

    final merged = BankTransactionMapper.mergeProviderUpdate(update, current);

    expect(merged.amount, 12);
    expect(merged.date, DateTime(2026, 8, 2));
    expect(merged.description, 'My note');
    expect(merged.category, 'Work');
    expect(merged.excludedFromBudget, isTrue);
  });

  test('bank metadata survives JSON round trip', () {
    final original = BankTransactionMapper.fromPlaid({
      'transaction_id': 'pending-1',
      'amount': 5,
      'date': '2026-08-04',
      'name': 'Coffee',
      'pending': true,
    }, connectionId: 'connection-1');

    final decoded = FinanceEntry.fromJson(original.toJson());

    expect(decoded.externalTransactionId, 'pending-1');
    expect(decoded.connectionId, 'connection-1');
    expect(decoded.bankState, BankTransactionState.pending);
    expect(decoded.isBankImported, isTrue);
  });
}
