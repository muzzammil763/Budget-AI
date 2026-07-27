import 'package:budget_ai/src/finances/finance_entry_edit_screen.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('create form exposes save in AppBar and body without delete', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FinanceEntryEditScreen()));

    expect(find.text('Add Finance Entry'), findsOneWidget);
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text('Save Entry'), findsOneWidget);
    expect(find.text('Delete Entry'), findsNothing);
  });

  testWidgets('edit form exposes save in AppBar and body plus body delete', (
    tester,
  ) async {
    final entry = FinanceEntry(
      id: 'entry-1',
      date: DateTime(2026, 7, 27, 14, 30),
      hasTime: true,
      description: 'Groceries',
      amount: 250,
      category: 'Food',
      createdAt: DateTime(2026, 7, 27),
    );

    await tester.pumpWidget(
      MaterialApp(home: FinanceEntryEditScreen(entry: entry)),
    );

    expect(find.text('Edit Finance Entry'), findsOneWidget);
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Delete Entry'), findsOneWidget);
  });
}
