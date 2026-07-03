import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';

ToolDefinition buildFinanceAddTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_add',
  description:
      'Add a new personal finance/expense entry. Use this when the user mentions spending money, buying something, or asks to log an expense. '
      'Infer the category from the description when not specified. '
      'Date defaults to today if not provided. Amount is in Pakistani Rupees (Rs).',
  parameters: {
    'type': 'object',
    'properties': {
      'description': {
        'type': 'string',
        'description':
            'What was purchased or spent on (e.g. "Lunch", "Petrol", "Electricity bill").',
      },
      'amount': {
        'type': 'number',
        'description':
            'Amount spent in Pakistani Rupees (numeric only, no currency symbol).',
      },
      'category': {
        'type': 'string',
        'description':
            'Expense category. One of: Food, Groceries, Household, Bills, Transportation, Healthcare, Personal Care, Clothing, Shopping, Entertainment, Sports, Mobile, Home, Kitchen, Bike, Vehicle, Baby Supplies, Wife, Family, Gift, Charity, Banking, Savings. Infer from description if not specified.',
      },
      'date': {
        'type': 'string',
        'description':
            'Date in ISO 8601 format (YYYY-MM-DD). Omit to use today\'s date.',
      },
      'time': {
        'type': 'string',
        'description':
            'Time in HH:MM 24-hour format (e.g. "14:30"). Include only when the user specifies a time.',
      },
    },
    'required': ['description', 'amount', 'category'],
  },
  handler: handler,
);

mixin FinanceAddToolHandler {
  Future<dynamic> handleFinanceAddRequest(Map<String, dynamic> args) async {
    final description = (args['description'] as String? ?? '').trim();
    final amount = (args['amount'] as num?)?.toDouble() ?? 0.0;
    final category = (args['category'] as String? ?? '').trim();
    final dateStr = (args['date'] as String? ?? '').trim();
    final timeStr = (args['time'] as String? ?? '').trim();

    if (description.isEmpty) return {'error': 'description is required'};
    if (amount <= 0) return {'error': 'amount must be greater than 0'};
    if (category.isEmpty) return {'error': 'category is required'};

    try {
      DateTime date;
      bool hasTime = false;

      if (dateStr.isNotEmpty) {
        date = DateTime.tryParse(dateStr) ?? DateTime.now();
      } else {
        final now = DateTime.now();
        date = DateTime(now.year, now.month, now.day);
      }

      if (timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;
          date = DateTime(date.year, date.month, date.day, hour, minute);
          hasTime = true;
        }
      }

      final entry = FinanceEntry.create(
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
        'description': entry.description,
        'amount': entry.amount,
        'display_amount': entry.displayAmount,
        'category': entry.category,
        'date': entry.displayDate,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
