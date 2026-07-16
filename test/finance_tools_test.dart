import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/tools/finance_delete.dart';
import 'package:budget_ai/src/tools/finance_list.dart';
import 'package:budget_ai/src/tools/finance_update.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FinanceToolHarness
    with FinanceUpdateToolHandler, FinanceDeleteToolHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late _FinanceToolHarness tools;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('budget_ai_tools_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory.path);
    FinanceService.instance.invalidateCache();
    tools = _FinanceToolHarness();
  });

  tearDown(() async {
    FinanceService.instance.invalidateCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('finance_update can change an expense into income', () async {
    final entry = _entry(
      id: 'update_me',
      type: FinanceEntryType.expense,
      date: DateTime(2026, 7, 10),
      category: 'Work',
    );
    await _seed(directory, [entry]);

    final result = await tools.handleFinanceUpdateRequest({
      'id': entry.id,
      'type': 'income',
      'description': 'monthly salary and bonus',
      'category': 'salary',
      'amount': 4500,
    });
    final saved = (await FinanceService.instance.getAll()).single;

    expect(result['ok'], isTrue, reason: result.toString());
    expect(saved.type, FinanceEntryType.income);
    expect(saved.description, 'Monthly Salary & Bonus');
    expect(saved.category, 'Salary');
    expect(saved.amount, 4500);
  });

  test(
    'finance_delete removes only matching entries in a date range',
    () async {
      final entries = [
        _entry(
          id: 'food_expense',
          type: FinanceEntryType.expense,
          date: DateTime(2026, 7, 2),
          category: 'Food',
        ),
        _entry(
          id: 'travel_expense',
          type: FinanceEntryType.expense,
          date: DateTime(2026, 7, 3),
          category: 'Transportation',
        ),
        _entry(
          id: 'food_income',
          type: FinanceEntryType.income,
          date: DateTime(2026, 7, 4),
          category: 'Food',
        ),
        _entry(
          id: 'older_food_expense',
          type: FinanceEntryType.expense,
          date: DateTime(2026, 6, 30),
          category: 'Food',
        ),
      ];
      await _seed(directory, entries);

      final result = await tools.handleFinanceDeleteRequest({
        'from': '2026-07-01',
        'to': '2026-07-31',
        'type': 'expense',
        'category': 'food',
      });
      final remainingIds = (await FinanceService.instance.getAll())
          .map((entry) => entry.id)
          .toSet();

      expect(result['ok'], isTrue);
      expect(result['removed'], 1);
      expect(remainingIds, isNot(contains('food_expense')));
      expect(
        remainingIds,
        containsAll(<String>{
          'travel_expense',
          'food_income',
          'older_food_expense',
        }),
      );
    },
  );

  test(
    'finance_list filters above an amount and sorts largest first',
    () async {
      final entries = [
        _entry(
          id: 'small',
          type: FinanceEntryType.expense,
          date: DateTime(2026, 7, 12),
          category: 'Food',
          amount: 1000,
        ),
        _entry(
          id: 'medium',
          type: FinanceEntryType.expense,
          date: DateTime(2026, 7, 11),
          category: 'Bills',
          amount: 2500,
        ),
        _entry(
          id: 'large',
          type: FinanceEntryType.expense,
          date: DateTime(2026, 7, 10),
          category: 'Shopping',
          amount: 30000,
        ),
        _entry(
          id: 'income',
          type: FinanceEntryType.income,
          date: DateTime(2026, 7, 9),
          category: 'Salary',
          amount: 50000,
        ),
      ];
      final listed = filterFinanceEntriesForList(
        entries,
        type: FinanceEntryType.expense,
        amountGreaterThan: 1000,
        sortBy: 'amount_desc',
      );

      expect(listed.map((entry) => entry.id), ['large', 'medium']);
    },
  );
}

FinanceEntry _entry({
  required String id,
  required FinanceEntryType type,
  required DateTime date,
  required String category,
  double amount = 100,
}) {
  return FinanceEntry(
    id: id,
    type: type,
    date: date,
    hasTime: false,
    description: 'Test Entry',
    amount: amount,
    category: category,
    createdAt: date,
  );
}

Future<void> _seed(Directory directory, List<FinanceEntry> entries) async {
  await File(
    '${directory.path}/finances.json',
  ).writeAsString(jsonEncode(entries.map((entry) => entry.toJson()).toList()));
  FinanceService.instance.invalidateCache();
}
