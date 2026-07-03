import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';

ToolDefinition buildFinanceListTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_list',
  description:
      'List finance/expense entries with optional filters. Use to answer questions like "what did I spend today?", "show my expenses this week", or "how much did I spend on food?".',
  parameters: {
    'type': 'object',
    'properties': {
      'from_date': {
        'type': 'string',
        'description': 'Start date filter in YYYY-MM-DD format (inclusive).',
      },
      'to_date': {
        'type': 'string',
        'description':
            'End date filter in YYYY-MM-DD format (inclusive). Defaults to today.',
      },
      'category': {
        'type': 'string',
        'description':
            'Filter by category name (case-insensitive). Omit to include all categories.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum number of entries to return. Defaults to 50.',
      },
    },
    'required': [],
  },
  handler: handler,
);

mixin FinanceListToolHandler {
  Future<dynamic> handleFinanceListRequest(Map<String, dynamic> args) async {
    final fromStr = (args['from_date'] as String? ?? '').trim();
    final toStr = (args['to_date'] as String? ?? '').trim();
    final category = (args['category'] as String? ?? '').trim().toLowerCase();
    final limit = (args['limit'] as int?) ?? 50;

    try {
      List<FinanceEntry> entries;

      if (fromStr.isNotEmpty) {
        final from = DateTime.tryParse(fromStr) ?? DateTime.now();
        final to = toStr.isNotEmpty
            ? DateTime.tryParse(toStr) ?? DateTime.now()
            : DateTime.now();
        entries = await FinanceService.instance.getByDateRange(from, to);
      } else {
        entries = List.from(await FinanceService.instance.getAll());
      }

      if (category.isNotEmpty) {
        entries = entries
            .where((e) => e.category.toLowerCase() == category)
            .toList();
      }

      final limited = entries.take(limit).toList();
      final total = FinanceService.instance.totalAmount(limited);

      return {
        'ok': true,
        'count': limited.length,
        'total': '${FinanceEntry.formatAmount(total)} Rs',
        'entries': limited
            .map(
              (e) => {
                'id': e.id,
                'date': e.displayDate,
                'description': e.description,
                'amount': e.displayAmount,
                'category': e.category,
              },
            )
            .toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
