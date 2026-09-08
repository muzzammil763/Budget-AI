import 'package:budget_ai/src/finances/expense_summary_card.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card displays explicit current and overall dates', (
    tester,
  ) async {
    final entries = [
      FinanceEntry(
        id: 'one',
        type: FinanceEntryType.expense,
        date: DateTime(2026, 1, 1),
        hasTime: false,
        description: 'Food',
        amount: 10,
        category: 'Food',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
    Future<void> open(DateTime? month) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseSummaryCard(
            entries: entries,
            month: month,
            now: DateTime(2026, 9, 7),
          ),
        ),
      ),
    );
    await open(null);
    expect(find.text('From 1 Jan 2026 To 7 Sep 2026'), findsOneWidget);
    await open(DateTime(2026, 9));
    expect(
      find.text('Income and expenses in Sep 2026 · 1–7 Sep'),
      findsOneWidget,
    );
  });

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
    expect(find.text(FinanceEntry.money(9000)), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(FinanceEntry.money(300)), findsOneWidget);
    expect(find.text('Expense entries'), findsOneWidget);
    expect(find.text('Active days'), findsOneWidget);
    expect(find.text('Daily expense avg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
