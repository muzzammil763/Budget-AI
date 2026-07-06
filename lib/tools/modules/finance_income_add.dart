import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';

ToolDefinition buildFinanceIncomeAddTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_income_add',
  description:
      'Add an income entry. Use this only when the user clearly says they received money, salary, freelance income, refund, gift money, or other income. If unclear, ask whether it is income or expense.',
  parameters: {
    'type': 'object',
    'properties': {
      'description': {
        'type': 'string',
        'description': 'Income source, e.g. "Salary", "Freelance project".',
      },
      'amount': {
        'type': 'number',
        'description': 'Income amount in Pakistani Rupees.',
      },
      'category': {
        'type': 'string',
        'description':
            'Income category/source. Examples: Salary, Freelance, Business, Refund, Gift, Bonus, Other.',
      },
      'date': {
        'type': 'string',
        'description': 'Date in ISO 8601 format (YYYY-MM-DD).',
      },
      'time': {
        'type': 'string',
        'description': 'Time in HH:MM 24-hour format if specified.',
      },
    },
    'required': ['description', 'amount', 'category'],
  },
  handler: handler,
);

mixin FinanceIncomeAddToolHandler {
  Future<dynamic> handleFinanceIncomeAddRequest(
    Map<String, dynamic> args,
  ) async {
    final description = (args['description'] as String? ?? '').trim();
    final amount = (args['amount'] as num?)?.toDouble() ?? 0.0;
    final category = (args['category'] as String? ?? '').trim();
    final dateStr = (args['date'] as String? ?? '').trim();
    final timeStr = (args['time'] as String? ?? '').trim();

    if (description.isEmpty) return {'error': 'description is required'};
    if (amount <= 0) return {'error': 'amount must be greater than 0'};
    if (category.isEmpty) return {'error': 'category is required'};

    try {
      var date = dateStr.isNotEmpty
          ? DateTime.tryParse(dateStr) ?? DateTime.now()
          : DateTime.now();
      var hasTime = true;
      if (timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;
          date = DateTime(date.year, date.month, date.day, hour, minute);
        }
      } else {
        final now = DateTime.now();
        date = DateTime(date.year, date.month, date.day, now.hour, now.minute);
      }

      final entry = FinanceEntry.create(
        type: FinanceEntryType.income,
        date: date,
        hasTime: hasTime,
        description: description,
        amount: amount,
        category: category,
      );
      await FinanceService.instance.add(entry);

      return {
        'ok': true,
        'id': entry.id,
        'type': entry.type.storageValue,
        'description': entry.description,
        'amount': entry.amount,
        'display_amount': entry.displaySignedAmount,
        'category': entry.category,
        'date': entry.displayDate,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
