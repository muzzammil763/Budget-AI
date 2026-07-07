import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';

ToolDefinition buildFinanceSummaryTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_summary',
  description:
      'Get a finance summary for a date range, including income, expenses, net balance, and category breakdowns. Use a type filter for income-only or expense-only questions. Loans are intentionally excluded.',
  parameters: {
    'type': 'object',
    'properties': {
      'from_date': {
        'type': 'string',
        'description':
            'Start date in YYYY-MM-DD format. Defaults to the first day of the current month.',
      },
      'to_date': {
        'type': 'string',
        'description': 'End date in YYYY-MM-DD format. Defaults to today.',
      },
      'type': {
        'type': 'string',
        'description':
            'Optional entry type filter: expense or income. Omit to summarize both.',
      },
    },
    'required': [],
  },
  handler: handler,
);

mixin FinanceSummaryToolHandler {
  Future<dynamic> handleFinanceSummaryRequest(Map<String, dynamic> args) async {
    final fromStr = (args['from_date'] as String? ?? '').trim();
    final toStr = (args['to_date'] as String? ?? '').trim();
    final typeRaw = (args['type'] as String? ?? '').trim();
    final type = typeRaw.isNotEmpty ? FinanceEntryType.fromJson(typeRaw) : null;

    try {
      final now = DateTime.now();
      final from = fromStr.isNotEmpty
          ? DateTime.tryParse(fromStr) ?? DateTime(now.year, now.month, 1)
          : DateTime(now.year, now.month, 1);
      final to = toStr.isNotEmpty ? DateTime.tryParse(toStr) ?? now : now;

      var entries = await FinanceService.instance.getByDateRange(from, to);
      if (type != null) {
        entries = entries.where((entry) => entry.type == type).toList();
      }
      final total = FinanceService.instance.totalAmount(entries);
      final incomeTotal = FinanceService.instance.totalAmount(
        entries,
        type: FinanceEntryType.income,
      );
      final expenseTotal = FinanceService.instance.totalAmount(
        entries,
        type: FinanceEntryType.expense,
      );
      final expenseByCat = FinanceService.instance.categorySummary(
        entries,
        type: FinanceEntryType.expense,
      );
      final incomeByCat = FinanceService.instance.categorySummary(
        entries,
        type: FinanceEntryType.income,
      );

      return {
        'ok': true,
        'from':
            '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        'to':
            '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}',
        'entry_count': entries.length,
        'total': '${FinanceEntry.formatAmount(total)} Rs',
        'income_total': '${FinanceEntry.formatAmount(incomeTotal)} Rs',
        'expense_total': '${FinanceEntry.formatAmount(expenseTotal)} Rs',
        'net_balance': _formatSignedAmount(incomeTotal - expenseTotal),
        'expense_by_category': expenseByCat.map(
          (cat, amount) =>
              MapEntry(cat, '${FinanceEntry.formatAmount(amount)} Rs'),
        ),
        'income_by_category': incomeByCat.map(
          (cat, amount) =>
              MapEntry(cat, '${FinanceEntry.formatAmount(amount)} Rs'),
        ),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  String _formatSignedAmount(double amount) {
    final prefix = amount < 0 ? '-' : '';
    return '$prefix${FinanceEntry.formatAmount(amount.abs())} Rs';
  }
}
