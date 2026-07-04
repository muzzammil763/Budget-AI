import 'package:budget_ai/core/storage/shared_prefs_service.dart';

enum ToolPermissionLevel { safe, approvalRequired, fullAccess }

enum ToolAccessMode { approvalRequired, fullAccess }

extension ToolAccessModeLabel on ToolAccessMode {
  String get label {
    switch (this) {
      case ToolAccessMode.approvalRequired:
        return 'Approval required';
      case ToolAccessMode.fullAccess:
        return 'Full access';
    }
  }

  String get storageValue {
    switch (this) {
      case ToolAccessMode.approvalRequired:
        return 'approval_required';
      case ToolAccessMode.fullAccess:
        return 'full_access';
    }
  }
}

extension ToolPermissionLevelLabel on ToolPermissionLevel {
  String get label {
    switch (this) {
      case ToolPermissionLevel.safe:
        return 'Safe';
      case ToolPermissionLevel.approvalRequired:
        return 'Approval required';
      case ToolPermissionLevel.fullAccess:
        return 'Full access';
    }
  }
}

class ToolCollectionDefinition {
  const ToolCollectionDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.permissionLevel,
    required this.tools,
  });

  final String id;
  final String title;
  final String description;
  final ToolPermissionLevel permissionLevel;
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
    this.defaultAccessMode = ToolAccessMode.fullAccess,
  });

  final String name;
  final String title;
  final String description;
  final ToolAccessMode defaultAccessMode;
}

class ToolSettings {
  const ToolSettings._();

  static const filesystem = 'filesystem';
  static const browser = 'browser';
  static const finance = 'finance';
  static const memory = 'memory';

  static const collections = <ToolCollectionDefinition>[
    ToolCollectionDefinition(
      id: filesystem,
      title: 'Filesystem Tools',
      description: 'Read, write, and edit workspace files',
      permissionLevel: ToolPermissionLevel.approvalRequired,
      tools: [
        ToolItemDefinition(
          name: 'read',
          title: 'Read',
          description: 'Read text files and image attachments',
        ),
        ToolItemDefinition(
          name: 'write',
          title: 'Write',
          description: 'Create or overwrite workspace files',
        ),
        ToolItemDefinition(
          name: 'edit',
          title: 'Edit',
          description: 'Apply exact text replacements to files',
        ),
      ],
    ),
    ToolCollectionDefinition(
      id: browser,
      title: 'Web Tools',
      description: 'Search the web and fetch pages',
      permissionLevel: ToolPermissionLevel.approvalRequired,
      tools: [
        ToolItemDefinition(
          name: 'web_search',
          title: 'Web Search',
          description: 'Search the web for current information',
        ),
        ToolItemDefinition(
          name: 'web_page_fetch',
          title: 'Fetch Web Page',
          description: 'Fetch and summarize a web page',
        ),
      ],
    ),
    ToolCollectionDefinition(
      id: finance,
      title: 'Finance Tools',
      description: 'Add, list, summarize, and delete expense records',
      permissionLevel: ToolPermissionLevel.safe,
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
      permissionLevel: ToolPermissionLevel.safe,
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

  static bool isIndividualToolEnabled(String name) {
    return SharedPrefsService.getToolEnabled(name);
  }

  static Future<void> setIndividualToolEnabled(String name, bool enabled) {
    return SharedPrefsService.setToolEnabled(name, enabled);
  }

  static ToolItemDefinition? toolForName(String name) {
    for (final tool in tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  static ToolAccessMode defaultAccessModeForTool(String name) {
    return toolForName(name)?.defaultAccessMode ?? ToolAccessMode.fullAccess;
  }

  static ToolAccessMode accessModeForTool(String name) {
    final stored = SharedPrefsService.getToolAccessMode(name);
    if (stored == 'full_access') return ToolAccessMode.fullAccess;
    if (stored == 'approval_required') return ToolAccessMode.approvalRequired;
    return defaultAccessModeForTool(name);
  }

  static Future<void> setToolAccessMode(
    String name,
    ToolAccessMode mode,
  ) async {
    await SharedPrefsService.setToolAccessMode(name, mode.storageValue);
  }

  static bool isToolAtDefault(String name) {
    final enabledDefault = true;
    final enabled = isIndividualToolEnabled(name);
    if (enabled != enabledDefault) return false;

    final stored = SharedPrefsService.getToolAccessMode(name);
    if (stored == null) return true;
    return accessModeForTool(name) == defaultAccessModeForTool(name);
  }

  static Future<void> resetToolToDefault(String name) async {
    await SharedPrefsService.clearToolEnabled(name);
    await SharedPrefsService.clearToolAccessMode(name);
  }

  static bool isToolEnabled(String name) {
    return toolForName(name) == null || isIndividualToolEnabled(name);
  }

  static List<ToolItemDefinition> disabledToolsForPrompt() {
    return [
      for (final tool in tools)
        if (!isToolEnabled(tool.name)) tool,
    ];
  }
}
