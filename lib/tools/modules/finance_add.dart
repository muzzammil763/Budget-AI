import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/finance_entry_tool_helpers.dart';

ToolDefinition buildFinanceAddTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_add',
  description:
      'Add a new expense entry. Use this by default for short entries like "200 fuel", and when the user mentions spending money, buying something, paying a bill, or asks to log an expense. '
      'Do not use for salary/income, borrowed/lent money, or loan repayments. Use income or loan tools for those. '
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
    return addFinanceEntryFromToolArgs(args, type: FinanceEntryType.expense);
  }
}
