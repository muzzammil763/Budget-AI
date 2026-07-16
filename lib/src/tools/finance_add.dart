import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/tools/tools.dart';
import 'package:budget_ai/src/tools/finance_entry_tool_helpers.dart';

ToolDefinition buildFinanceAddTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_add',
  description:
      'Add a new expense entry. Use this by default for short entries like "200 fuel", and when the user mentions spending money, buying something, paying a bill, or asks to log an expense. '
      'Use this for money lent to someone and loan repayments paid, with category "Loan". Do not use for money received. '
      'Generate a concise, specific category from the description. Never use Other or Others; create a suitable new category when needed. '
      'Format the entry title in title case and use "&" instead of the word "and". '
      'Date defaults to today if not provided. Amount is in ${CurrencySettingsService.instance.promptDescription} (numeric only, no currency token).',
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
            'Amount spent in ${CurrencySettingsService.instance.promptDescription} (numeric only, no currency token).',
      },
      'category': {
        'type': 'string',
        'description':
            'A concise, title-cased expense type generated from the description, such as Groceries, Fuel, Bills, Healthcare, Shopping, or Loan. Never return Other or Others; create a specific type.',
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
