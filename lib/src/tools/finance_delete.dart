import 'package:budget_ai/src/tools/tools.dart';
import 'package:budget_ai/src/finances/finance_service.dart';

ToolDefinition buildFinanceDeleteTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_delete',
  description:
      'Delete finance entries by a single ID, an IDs array, or an inclusive date range. Range deletion can optionally filter by income/expense type and category. Use finance_list first when deleting by ID.',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': 'Single entry ID to delete.'},
      'ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Multiple entry IDs to delete in one call.',
      },
      'from': {
        'type': 'string',
        'description':
            'Inclusive range start in YYYY-MM-DD format. Must be used with to.',
      },
      'to': {
        'type': 'string',
        'description':
            'Inclusive range end in YYYY-MM-DD format. Must be used with from.',
      },
      'type': {
        'type': 'string',
        'enum': ['income', 'expense'],
        'description': 'Optional entry type filter for range deletion.',
      },
      'category': {
        'type': 'string',
        'description':
            'Optional case-insensitive category filter for range deletion.',
      },
    },
  },
  handler: handler,
);

mixin FinanceDeleteToolHandler {
  Future<dynamic> handleFinanceDeleteRequest(Map<String, dynamic> args) async {
    final singleId = (args['id'] as String? ?? '').trim();
    final rawIds = args['ids'];
    final ids = singleId.isNotEmpty
        ? [singleId]
        : (rawIds is List ? rawIds : [])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();

    final fromRaw = (args['from'] as String? ?? '').trim();
    final toRaw = (args['to'] as String? ?? '').trim();

    if (ids.isEmpty && fromRaw.isEmpty && toRaw.isEmpty) {
      return {'error': 'id, ids, or a from/to date range is required'};
    }

    try {
      if (ids.isEmpty) {
        if (fromRaw.isEmpty || toRaw.isEmpty) {
          return {'error': 'both from and to are required for range deletion'};
        }
        final from = DateTime.tryParse(fromRaw);
        final to = DateTime.tryParse(toRaw);
        if (from == null || to == null) {
          return {'error': 'from and to must use YYYY-MM-DD format'};
        }
        if (from.isAfter(to)) {
          return {'error': 'from must be before or equal to to'};
        }

        final typeRaw = (args['type'] as String? ?? '').trim().toLowerCase();
        if (typeRaw.isNotEmpty && typeRaw != 'income' && typeRaw != 'expense') {
          return {'error': 'type must be income or expense'};
        }
        final category = (args['category'] as String? ?? '').trim();
        var matches = await FinanceService.instance.getByDateRange(from, to);
        if (typeRaw.isNotEmpty) {
          final type = FinanceEntryType.fromJson(typeRaw);
          matches = matches.where((entry) => entry.type == type).toList();
        }
        if (category.isNotEmpty) {
          matches = matches
              .where(
                (entry) =>
                    entry.category.toLowerCase() == category.toLowerCase(),
              )
              .toList();
        }
        final removed = await FinanceService.instance.deleteMany(
          matches.map((entry) => entry.id).toList(),
        );
        return {
          'ok': true,
          'removed': removed,
          'from': fromRaw,
          'to': toRaw,
          if (typeRaw.isNotEmpty) 'type': typeRaw,
          if (category.isNotEmpty) 'category': category,
        };
      }

      if (ids.length == 1) {
        final deleted = await FinanceService.instance.delete(ids.first);
        return {'ok': deleted, 'id': ids.first};
      }
      final removed = await FinanceService.instance.deleteMany(ids);
      return {'ok': true, 'removed': removed, 'requested': ids.length};
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
