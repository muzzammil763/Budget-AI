import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/src/finances/finance_service.dart';

ToolDefinition buildFinanceDeleteTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_delete',
  description:
      'Delete one or more finance entries. Pass a single id string to delete one entry, or an ids array to delete multiple at once. Use finance_list first to find IDs.',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': 'Single entry ID to delete.'},
      'ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Multiple entry IDs to delete in one call.',
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

    if (ids.isEmpty) return {'error': 'id or ids is required'};

    try {
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
