import 'dart:async';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/monthly_summary_card.dart';
import 'package:budget_ai/src/finances/monthly_summary_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final month = DateTime(2026, 1);
  FinanceEntry income(double amount) => FinanceEntry(
    id: 'salary',
    type: FinanceEntryType.expense,
    date: month,
    hasTime: false,
    description: 'Salary',
    amount: amount,
    category: 'Salary',
    createdAt: month,
  );
  test('summary prompt never includes legacy income or transfer amounts', () {
    final prompt = MonthlySummaryService.buildPrompt(month, [
      income(100),
      income(987654).copyWith(type: FinanceEntryType.income),
      FinanceService.buildRolloverEntry(
        sourceMonth: DateTime(2025, 12),
        closingBalance: -876543,
      )!,
    ]);
    expect(prompt, contains('"expenses":100.0'));
    expect(prompt, isNot(contains('987654')));
    expect(prompt, isNot(contains('876543')));
    expect(prompt, isNot(contains('"closing_balance"')));
  });
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
    'cache is per account/month and regeneration reads fresh data',
    () async {
      var user = 'first';
      var amount = 30000.0;
      var calls = 0;
      final service = MonthlySummaryService(
        userId: () => user,
        loadEntries: (_) async => [income(amount)],
        generateText: (prompt) async {
          calls++;
          expect(prompt, contains('"expenses":$amount'));
          return 'Saved $amount this month.';
        },
      );
      expect(await service.load(month), isNull);
      await service.generate(month);
      expect((await service.load(month))!.text, 'Saved 30000.0 this month.');
      expect(calls, 1);
      amount = 40000;
      await service.generate(month);
      expect((await service.load(month))!.text, 'Saved 40000.0 this month.');
      expect(await service.load(DateTime(2026, 2)), isNull);
      user = 'second';
      expect(await service.load(month), isNull);
    },
  );
  test('failed regeneration preserves the prior saved result', () async {
    var response = 'A meaningful summary.';
    final service = MonthlySummaryService(
      userId: () => 'user',
      loadEntries: (_) async => [income(10)],
      generateText: (_) async => response,
    );
    await service.generate(month);
    response = '';
    await expectLater(service.generate(month), throwsStateError);
    expect((await service.load(month))!.text, 'A meaningful summary.');
  });
  test(
    'account exit prevents an in-flight response from restoring cached data',
    () async {
      final response = Completer<String>();
      final started = Completer<void>();
      final service = MonthlySummaryService(
        userId: () => 'user',
        loadEntries: (_) async => [income(10)],
        generateText: (_) {
          started.complete();
          return response.future;
        },
      );
      final pending = service.generate(month);
      await started.future;
      MonthlySummaryService.invalidatePendingRequests();
      final rejected = expectLater(pending, throwsStateError);
      response.complete('Private financial summary');
      await rejected;
      expect(await service.load(month), isNull);
    },
  );
  testWidgets(
    'card generates on tap and offers regeneration without automatic API calls',
    (tester) async {
      var calls = 0;
      final service = MonthlySummaryService(
        userId: () => 'user',
        loadEntries: (_) async => [income(10)],
        generateText: (_) async {
          calls++;
          return 'You saved 10.';
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthlySummaryCard(month: month, service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Generate Summary'));
      await tester.pumpAndSettle();
      expect(find.text('You saved 10.'), findsOneWidget);
      expect(find.text('Regenerate Summary'), findsOneWidget);
      await tester.tap(find.text('Regenerate Summary'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}
