import 'dart:convert';
import 'dart:io';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/tools/finance_summary.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _SummaryTool with FinanceSummaryToolHandler {}

FinanceEntry entry(
  String id,
  FinanceEntryType type,
  double amount,
  DateTime date, {
  String category = 'Salary',
  String description = 'Payment',
}) => FinanceEntry(
  id: id,
  type: type,
  amount: amount,
  date: date,
  hasTime: false,
  category: category,
  description: description,
  createdAt: date,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('January to September totals count actual expenses only', () {
    final records = <FinanceEntry>[];
    for (var month = 1; month <= 9; month++) {
      records.add(
        entry(
          'expense-$month',
          FinanceEntryType.expense,
          month * 100,
          DateTime(2026, month, 5),
          category: 'Food',
        ),
      );
      records.add(
        entry(
          'income-$month',
          FinanceEntryType.income,
          20000,
          DateTime(2026, month, 1),
        ),
      );
      records.add(
        FinanceService.buildRolloverEntry(
          sourceMonth: DateTime(2026, month - 1),
          closingBalance: -3000,
        )!,
      );
    }
    final actual = FinanceService.expenseEntries(records);
    expect(actual, hasLength(9));
    expect(FinanceService.instance.totalAmount(actual), 4500);
    for (var month = 1; month <= 9; month++) {
      expect(
        FinanceService.instance.totalAmount(
          actual.where((e) => e.date.month == month).toList(),
        ),
        month * 100,
      );
    }
    expect(records, hasLength(27));
  });
  final january = entry(
    'salary',
    FinanceEntryType.income,
    30000,
    DateTime(2026, 1, 5),
  );
  final carried = FinanceService.buildRolloverEntry(
    sourceMonth: DateTime(2026, 1),
    closingBalance: 30000,
  )!;
  test(
    'overall earnings count saved income once while monthly balance includes it',
    () {
      final all = [january, carried];
      expect(
        FinanceService.instance.totalAmount(
          FinanceService.reportingEntries(all, includeRollovers: false),
        ),
        30000,
      );
      expect(
        FinanceService.rolloverEntryForMonth(all, DateTime(2026, 1))?.amount,
        30000,
      );
      expect(
        FinanceService.instance.totalAmount(
          FinanceService.reportingEntries([carried], includeRollovers: true),
        ),
        30000,
      );
      expect(
        FinanceService.isRolloverEntry(
          entry(
            'real_savings',
            FinanceEntryType.income,
            700,
            DateTime(2026, 2),
            category: 'Savings',
          ),
        ),
        isFalse,
      );
    },
  );
  test(
    'deficits and legacy transfers are excluded from overall activity too',
    () {
      final deficit = FinanceService.buildRolloverEntry(
        sourceMonth: DateTime(2026, 1),
        closingBalance: -100,
      )!;
      final legacy = entry(
        'old',
        FinanceEntryType.income,
        30000,
        DateTime(2026, 2),
        category: 'Savings',
        description: 'Savings From January 2026',
      );
      final expense = entry(
        'food',
        FinanceEntryType.expense,
        100,
        DateTime(2026, 1),
        category: 'Food',
      );
      final actual = FinanceService.reportingEntries([
        deficit,
        legacy,
        expense,
      ], includeRollovers: false);
      expect(actual.map((e) => e.id), ['food']);
    },
  );
  test('summary tool excludes income and transfers in every scope', () async {
    final directory = await Directory.systemTemp.createTemp('reporting_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    try {
      await File(
        '${directory.path}/finances.json',
      ).writeAsString(jsonEncode([january.toJson(), carried.toJson()]));
      FinanceService.instance.invalidateCache();
      final tool = _SummaryTool();
      final overall = await tool.handleFinanceSummaryRequest({
        'from_date': '2026-01-01',
        'to_date': '2026-02-28',
      });
      expect(overall.containsKey('income_total'), isFalse);
      expect(overall['entry_count'], 0);
      expect(overall['expense_total'], FinanceEntry.money(0));
      final month = await tool.handleFinanceSummaryRequest({
        'from_date': '2026-02-01',
        'to_date': '2026-02-28',
      });
      expect(month.containsKey('income_total'), isFalse);
      expect(month['includes_month_rollovers'], isFalse);
    } finally {
      FinanceService.instance.invalidateCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  });
}
