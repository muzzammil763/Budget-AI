import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/monthly_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all scopes show actual expenses without income or carryovers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final month = DateTime(now.year, now.month - 1);
    final entries = [
      FinanceEntry(
        id: 'expense',
        type: FinanceEntryType.expense,
        amount: 17000,
        date: month,
        hasTime: false,
        category: 'Food',
        description: 'Food',
        createdAt: month,
      ),
      FinanceEntry(
        id: 'income',
        type: FinanceEntryType.income,
        amount: 20000,
        date: month,
        hasTime: false,
        category: 'Salary',
        description: 'Salary',
        createdAt: month,
      ),
      FinanceService.buildRolloverEntry(
        sourceMonth: DateTime(month.year, month.month - 1),
        closingBalance: -9000,
      )!,
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceInsightsScreen(entries: entries, selectedMonth: month),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(FinanceEntry.money(17000)), findsWidgets);
    expect(find.text('Income vs Expenses'), findsNothing);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Overused'), findsNothing);
    expect(find.text('Net balance'), findsNothing);
    final list = find.byType(ListView).last;
    for (
      var i = 0;
      i < 8 && find.byType(MonthlySummaryCard).evaluate().isEmpty;
      i++
    ) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(find.byType(MonthlySummaryCard), findsOneWidget);
    expect(find.text('INCOME CATEGORY BREAKDOWN'), findsNothing);
    await tester.tap(find.text('Overall'));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(find.text(FinanceEntry.money(17000)), findsWidgets);
    expect(find.text('ALL TIME'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
