import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/tools/tools.dart';
import 'package:budget_ai/src/tools/finance_entry_tool_helpers.dart';

ToolDefinition buildFinanceIncomeAddTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_income_add',
  description:
      'Add money received, including salary, freelance income, refunds, gifts, money borrowed, and loan repayments received. Generate a concise income type such as Salary, Freelance, Refund, Gift, or Loan; create a new specific type when needed and never use Other or Others. Format the entry title in title case and use "&" instead of the word "and". If unclear whether money was received or paid, ask one short question.',
  parameters: {
    'type': 'object',
    'properties': {
      'description': {
        'type': 'string',
        'description': 'Income source, e.g. "Salary", "Freelance project".',
      },
      'amount': {
        'type': 'number',
        'description':
            'Income amount in ${CurrencySettingsService.instance.promptDescription} (numeric only, no currency token).',
      },
      'category': {
        'type': 'string',
        'description':
            'A concise, title-cased income type generated from the source, such as Salary, Freelance, Business, Refund, Gift, Bonus, or Loan. Never return Other or Others.',
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
    return addFinanceEntryFromToolArgs(args, type: FinanceEntryType.income);
  }
}
