class ToolCollectionDefinition {
  const ToolCollectionDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.tools,
  });

  final String id;
  final String title;
  final String description;
  final List<ToolItemDefinition> tools;

  bool matchesTool(String name) {
    return tools.any((tool) => tool.name == name);
  }
}

class ToolItemDefinition {
  const ToolItemDefinition({
    required this.name,
    required this.title,
    required this.description,
  });

  final String name;
  final String title;
  final String description;
}

class ToolSettings {
  const ToolSettings._();

  static const finance = 'finance';

  static const collections = <ToolCollectionDefinition>[
    ToolCollectionDefinition(
      id: finance,
      title: 'Finance Tools',
      description:
          'Add, list, edit, summarize, and delete finance and loan records',
      tools: [
        ToolItemDefinition(
          name: 'finance_add',
          title: 'Add Finance',
          description: 'Add a finance entry for spending',
        ),
        ToolItemDefinition(
          name: 'finance_income_add',
          title: 'Add Income',
          description: 'Add an income entry',
        ),
        ToolItemDefinition(
          name: 'finance_list',
          title: 'List Finances',
          description: 'List income and expense entries with filters',
        ),
        ToolItemDefinition(
          name: 'finance_summary',
          title: 'Finance Summary',
          description: 'Summarize income and spending by date range',
        ),
        ToolItemDefinition(
          name: 'finance_update',
          title: 'Edit Finances',
          description: 'Update an existing income or expense entry',
        ),
        ToolItemDefinition(
          name: 'finance_delete',
          title: 'Delete Finances',
          description: 'Delete one or more income or expense entries',
        ),
        ToolItemDefinition(
          name: 'loan_add',
          title: 'Add Loan',
          description: 'Record a borrowed or lent loan',
        ),
        ToolItemDefinition(
          name: 'loan_payment_add',
          title: 'Add Loan Payment',
          description: 'Record a repayment against a loan',
        ),
        ToolItemDefinition(
          name: 'loan_update',
          title: 'Edit Loan',
          description: 'Update an existing loan',
        ),
        ToolItemDefinition(
          name: 'loan_payment_update',
          title: 'Edit Loan Payment',
          description: 'Update an existing loan repayment',
        ),
        ToolItemDefinition(
          name: 'loan_payment_delete',
          title: 'Delete Loan Payment',
          description: 'Delete a repayment from a loan',
        ),
        ToolItemDefinition(
          name: 'loan_delete',
          title: 'Delete Loan',
          description: 'Delete an existing loan',
        ),
        ToolItemDefinition(
          name: 'loan_list',
          title: 'List Loans',
          description: 'List loans and their repayments',
        ),
      ],
    ),
  ];

  static List<ToolItemDefinition> get tools {
    return [for (final collection in collections) ...collection.tools];
  }

  static ToolCollectionDefinition? collectionForToolName(String name) {
    for (final collection in collections) {
      if (collection.matchesTool(name)) return collection;
    }
    return null;
  }

  static ToolItemDefinition? toolForName(String name) {
    for (final tool in tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  static bool isToolEnabled(String name) => true;
}
