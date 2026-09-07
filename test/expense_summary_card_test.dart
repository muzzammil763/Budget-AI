import 'package:budget_ai/src/finances/expense_summary_card.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('summary scopes expenses and averages over calendar days', (
    tester,
  ) async {
    FinanceEntry expense(String id, int day, double amount) => FinanceEntry(
      id: id,
      type: FinanceEntryType.expense,
      date: DateTime(2026, 1, day),
      hasTime: false,
      description: 'Food',
      amount: amount,
      category: 'Food',
      createdAt: DateTime(2026, 1, day),
    );
    final entries = [
      expense('a', 30, 100),
      expense('b', 30, 200),
      expense('c', 31, 300),
      expense('income', 30, 9000).copyWith(type: FinanceEntryType.income),
      FinanceService.buildRolloverEntry(
        sourceMonth: DateTime(2025, 12),
        closingBalance: -8000,
      )!,
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseSummaryCard(
            entries: entries,
            month: DateTime(2026, 1),
            now: DateTime(2026, 2, 10),
          ),
        ),
      ),
    );
    expect(find.text(FinanceEntry.money(600)), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(FinanceEntry.money(300)), findsOneWidget);
    expect(find.text('Entries'), findsOneWidget);
    expect(find.text('Active days'), findsOneWidget);
    expect(find.text('Daily avg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
