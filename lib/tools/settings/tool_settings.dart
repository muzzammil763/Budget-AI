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
  static const memory = 'memory';

  static const collections = <ToolCollectionDefinition>[
    ToolCollectionDefinition(
      id: finance,
      title: 'Finance Tools',
      description: 'Add, list, summarize, and delete expense records',
      tools: [
        ToolItemDefinition(
          name: 'finance_add',
          title: 'Add Expense',
          description: 'Add a personal expense entry',
        ),
        ToolItemDefinition(
          name: 'finance_list',
          title: 'List Expenses',
          description: 'List expense entries with filters',
        ),
        ToolItemDefinition(
          name: 'finance_summary',
          title: 'Expense Summary',
          description: 'Summarize spending by date range',
        ),
        ToolItemDefinition(
          name: 'finance_update',
          title: 'Edit Expense',
          description: 'Update an existing expense entry',
        ),
        ToolItemDefinition(
          name: 'finance_delete',
          title: 'Delete Expense',
          description: 'Delete one or more expense entries',
        ),
      ],
    ),
    ToolCollectionDefinition(
      id: memory,
      title: 'Memory Tools',
      description: 'Save, list, and remove assistant memories',
      tools: [
        ToolItemDefinition(
          name: 'memory_write',
          title: 'Write Memory',
          description: 'Save or update a memory',
        ),
        ToolItemDefinition(
          name: 'memory_edit',
          title: 'Edit Memory',
          description: 'Edit an existing memory by ID',
        ),
        ToolItemDefinition(
          name: 'memory_delete',
          title: 'Delete Memory',
          description: 'Delete a memory',
        ),
        ToolItemDefinition(
          name: 'memory_list',
          title: 'List Memories',
          description: 'List saved memories',
        ),
        ToolItemDefinition(
          name: 'memory_search',
          title: 'Search Memories',
          description:
              'Search memories by keyword in title, content, key, or type',
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
