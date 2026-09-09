import 'package:budget_ai/src/widgets/budget_home_widget_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarizeMonths groups income and expenses newest first', () {
    final entries = [
      _entry('expense', DateTime(2026, 8, 4), 40),
      _entry('income', DateTime(2026, 9, 1), 3000),
      _entry('expense', DateTime(2026, 9, 2), 125),
      _entry('expense', DateTime(2026, 9, 3), 75),
    ];

    expect(BudgetHomeWidgetSync.summarizeMonths(entries), [
      {'month': '2026-09', 'expense': 200.0, 'income': 3000.0},
      {'month': '2026-08', 'expense': 40.0, 'income': 0.0},
    ]);
  });

  test('summarizeMonths keeps an income-only month', () {
    final entries = [_entry('income', DateTime(2025, 12, 20), 900)];

    expect(BudgetHomeWidgetSync.summarizeMonths(entries), [
      {'month': '2025-12', 'expense': 0.0, 'income': 900.0},
    ]);
  });
}

BudgetWidgetFinanceEntry _entry(String type, DateTime date, double amount) {
  return BudgetWidgetFinanceEntry(
    id: '$type-$date-$amount',
    type: type,
    date: date,
    hasTime: false,
    description: type,
    amount: amount,
    category: type,
    createdAt: date,
  );
}
