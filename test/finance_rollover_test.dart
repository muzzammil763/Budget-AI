import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('monthly finance rollover', () {
    test('saved balance becomes Savings income on the first of next month', () {
      final entry = FinanceService.buildRolloverEntry(
        sourceMonth: DateTime(2026, 6),
        closingBalance: 2300,
        createdAt: DateTime(2026, 7, 1),
      );

      expect(entry, isNotNull);
      expect(entry!.type, FinanceEntryType.income);
      expect(entry.category, 'Savings');
      expect(entry.amount, 2300);
      expect(entry.date, DateTime(2026, 7, 1));
      expect(entry.description, 'Savings From June 2026');
    });

    test('overspending becomes a Balance Rollover expense next month', () {
      final entry = FinanceService.buildRolloverEntry(
        sourceMonth: DateTime(2026, 6),
        closingBalance: -750,
      );

      expect(entry, isNotNull);
      expect(entry!.type, FinanceEntryType.expense);
      expect(entry.category, 'Balance Rollover');
      expect(entry.amount, 750);
      expect(entry.date, DateTime(2026, 7, 1));
      expect(entry.description, 'Deficit Carried From June 2026');
    });

    test('zero closing balance creates no transfer entry', () {
      expect(
        FinanceService.buildRolloverEntry(
          sourceMonth: DateTime(2026, 6),
          closingBalance: 0,
        ),
        isNull,
      );
    });

    test('each month transition has a different deterministic ID', () {
      final june = FinanceService.rolloverEntryIdForMonth(DateTime(2026, 6));
      final july = FinanceService.rolloverEntryIdForMonth(DateTime(2026, 7));

      expect(june, 'fin_rollover_2026_06_to_2026_07');
      expect(july, 'fin_rollover_2026_07_to_2026_08');
      expect(june, isNot(july));
    });

    test('completion detection is scoped to its source month', () {
      final juneTransfer = FinanceService.buildRolloverEntry(
        sourceMonth: DateTime(2026, 6),
        closingBalance: 2300,
      )!;

      expect(
        FinanceService.hasRolloverForMonth([juneTransfer], DateTime(2026, 6)),
        isTrue,
      );
      expect(
        FinanceService.hasRolloverForMonth([juneTransfer], DateTime(2026, 7)),
        isFalse,
      );
    });

    test('recognizes an existing legacy Savings transfer', () {
      final legacy = FinanceEntry(
        id: 'fin_old_random_id',
        type: FinanceEntryType.income,
        date: DateTime(2026, 7, 1, 1),
        hasTime: true,
        description: 'Savings from June 2026',
        amount: 2300,
        category: 'Savings',
        createdAt: DateTime(2026, 7, 1),
      );

      expect(
        FinanceService.hasRolloverForMonth([legacy], DateTime(2026, 6)),
        isTrue,
      );
    });

    test('recognizes an existing legacy overspending transfer', () {
      final legacy = FinanceEntry(
        id: 'fin_old_overspending_id',
        type: FinanceEntryType.expense,
        date: DateTime(2026, 7, 1),
        hasTime: true,
        description: 'Overspending From June 2026',
        amount: 750,
        category: 'Savings',
        createdAt: DateTime(2026, 7, 1),
      );

      expect(
        FinanceService.hasRolloverForMonth([legacy], DateTime(2026, 6)),
        isTrue,
      );
    });

    test('startup rollover persists once and does not duplicate', () async {
      final directory = await Directory.systemTemp.createTemp(
        'budget_ai_rollover_test_',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => directory.path);

      final juneIncome = FinanceEntry(
        id: 'june_income',
        type: FinanceEntryType.income,
        date: DateTime(2026, 6, 2),
        hasTime: false,
        description: 'Salary',
        amount: 3000,
        category: 'Salary',
        createdAt: DateTime(2026, 6, 2),
      );
      final juneExpense = FinanceEntry(
        id: 'june_expense',
        type: FinanceEntryType.expense,
        date: DateTime(2026, 6, 20),
        hasTime: false,
        description: 'Groceries',
        amount: 700,
        category: 'Groceries',
        createdAt: DateTime(2026, 6, 20),
      );
      await File(
        '${directory.path}/finances.json',
      ).writeAsString(jsonEncode([juneIncome.toJson(), juneExpense.toJson()]));

      FinanceService.instance.invalidateCache();
      final firstRun = await FinanceService.instance.applySavingsRollover(
        now: DateTime(2026, 7, 2),
      );
      final secondRun = await FinanceService.instance.applySavingsRollover(
        now: DateTime(2026, 7, 2),
      );
      final entries = await FinanceService.instance.getAll();
      final rollovers = entries
          .where(
            (entry) =>
                entry.id ==
                FinanceService.rolloverEntryIdForMonth(DateTime(2026, 6)),
          )
          .toList();

      expect(firstRun, 1);
      expect(secondRun, 0);
      expect(rollovers, hasLength(1));
      expect(rollovers.single.amount, 2300);
      expect(rollovers.single.type, FinanceEntryType.income);

      FinanceService.instance.invalidateCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
  });
}
