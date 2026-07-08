import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/finance_entry_tool_helpers.dart';

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
    return addFinanceEntryFromToolArgs(args, type: FinanceEntryType.income);
  }
}
