import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/monthly_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();
  final month = DateTime(now.year, now.month - 1);
  FinanceEntry entry(FinanceEntryType type, double amount) => FinanceEntry(
    id: type.name,
    type: type,
    amount: amount,
    date: month,
    hasTime: false,
    category: type == FinanceEntryType.income ? 'Salary' : 'Food',
    description: 'Entry',
    createdAt: month,
  );
  Future<void> open(WidgetTester tester, double income, double expense) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceInsightsScreen(
          entries: [
            entry(FinanceEntryType.income, income),
            entry(FinanceEntryType.expense, expense),
          ],
          selectedMonth: month,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'past positive and negative months show Saved or Overused instead of Net',
    (tester) async {
      await open(tester, 1000, 300);
      expect(find.text('Saved'), findsWidgets);
      expect(find.text('Net'), findsNothing);
      expect(find.text('Net balance'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, 100, 300);
      expect(find.text('Overused'), findsWidgets);
      expect(find.text('Net'), findsNothing);
    },
  );
  testWidgets('zero past-month balance has no Saved or Overused metric', (
    tester,
  ) async {
    await open(tester, 300, 300);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Overused'), findsNothing);
    expect(find.text('Net'), findsNothing);
    expect(find.text('Income'), findsWidgets);
    expect(find.text('Expenses'), findsWidgets);
  });
  testWidgets(
    'month includes income categories and a summary action at the end',
    (tester) async {
      await open(tester, 1000, 300);
      final list = find.byType(ListView).last;
      for (
        var i = 0;
        i < 5 && find.byType(MonthlySummaryCard).evaluate().isEmpty;
        i++
      ) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      expect(find.text('TOP INCOME CATEGORIES'), findsOneWidget);
      expect(find.text('INCOME CATEGORY BREAKDOWN'), findsOneWidget);
      expect(find.byType(MonthlySummaryCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('past month moves saved income into the following month', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rollover = FinanceService.buildRolloverEntry(
      sourceMonth: month,
      closingBalance: 3000,
    )!;
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceInsightsScreen(
          entries: [
            entry(FinanceEntryType.income, 20000),
            entry(FinanceEntryType.expense, 17000),
            rollover,
          ],
          selectedMonth: month,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+${FinanceEntry.money(17000)}'), findsOneWidget);
    expect(find.text('+${FinanceEntry.money(20000)}'), findsNothing);
    expect(find.text(FinanceEntry.money(3000)), findsWidgets);
    expect(find.text('Saved'), findsWidgets);
  });

  testWidgets('overall Net uses the current carried balance', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final current = DateTime(now.year, now.month);
    final prior = DateTime(now.year, now.month - 1);
    FinanceEntry datedEntry(
      String id,
      FinanceEntryType type,
      double amount,
      DateTime date,
    ) => FinanceEntry(
      id: id,
      type: type,
      amount: amount,
      date: date,
      hasTime: false,
      category: type == FinanceEntryType.income ? 'Salary' : 'Food',
      description: 'Entry',
      createdAt: date,
    );
    final rollover = FinanceService.buildRolloverEntry(
      sourceMonth: prior,
      closingBalance: 100,
    )!;
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceInsightsScreen(
          entries: [
            datedEntry('old-income', FinanceEntryType.income, 1000, prior),
            datedEntry('old-expense', FinanceEntryType.expense, 100, prior),
            rollover,
            datedEntry('new-income', FinanceEntryType.income, 20, current),
            datedEntry('new-expense', FinanceEntryType.expense, 30, current),
          ],
          selectedMonth: current,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overall'));
    await tester.pumpAndSettle();

    expect(find.text('+${FinanceEntry.money(90)}'), findsWidgets);
    expect(find.text('+${FinanceEntry.money(890)}'), findsNothing);
    expect(find.text('ALL TIME'), findsOneWidget);
  });
}
