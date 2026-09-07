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
}
