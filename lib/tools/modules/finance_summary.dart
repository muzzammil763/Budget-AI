import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';

ToolDefinition buildFinanceSummaryTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_summary',
  description:
      'Get an expense/spending summary (total + breakdown by category) for a date range. Use for questions like "how much did I spend this month?", "what are my top expenses?", or "show me a summary for April". Income and loans are intentionally excluded.',
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
    },
    'required': [],
  },
  handler: handler,
);

mixin FinanceSummaryToolHandler {
  Future<dynamic> handleFinanceSummaryRequest(Map<String, dynamic> args) async {
    final fromStr = (args['from_date'] as String? ?? '').trim();
    final toStr = (args['to_date'] as String? ?? '').trim();

    try {
      final now = DateTime.now();
      final from = fromStr.isNotEmpty
          ? DateTime.tryParse(fromStr) ?? DateTime(now.year, now.month, 1)
          : DateTime(now.year, now.month, 1);
      final to = toStr.isNotEmpty ? DateTime.tryParse(toStr) ?? now : now;

      final entries = await FinanceService.instance.getByDateRange(from, to);
      final total = FinanceService.instance.totalAmount(entries);
      final byCat = FinanceService.instance.categorySummary(entries);

      return {
        'ok': true,
        'from':
            '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        'to':
            '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}',
        'entry_count': entries.length,
        'total': '${FinanceEntry.formatAmount(total)} Rs',
        'by_category': byCat.map(
          (cat, amount) =>
              MapEntry(cat, '${FinanceEntry.formatAmount(amount)} Rs'),
        ),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
