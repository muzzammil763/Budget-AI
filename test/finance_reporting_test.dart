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
  test(
    'summary tool excludes transfers across months and keeps single-month carry-in',
    () async {
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
        expect(overall['income_total'], FinanceEntry.money(30000));
        expect(overall['entry_count'], 1);
        expect(overall['income_by_category'], {
          'Salary': FinanceEntry.money(30000),
        });
        final month = await tool.handleFinanceSummaryRequest({
          'from_date': '2026-02-01',
          'to_date': '2026-02-28',
        });
        expect(month['income_total'], FinanceEntry.money(30000));
        expect(month['includes_month_rollovers'], isTrue);
      } finally {
        FinanceService.instance.invalidateCache();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}
