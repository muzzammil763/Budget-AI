import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';

ToolDefinition buildMemoryDeleteTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'memory_delete',
  description:
      'Delete a memory by its ID. Use memory_list first to get the ID of the memory to remove.',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': 'The memory ID to delete (from memory_list).',
      },
    },
    'required': ['id'],
  },
  handler: handler,
);

mixin MemoryDeleteToolHandler {
  Future<dynamic> handleMemoryDeleteRequest(Map<String, dynamic> args) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return {'error': 'id is required'};
    try {
      final deleted = await MemoryService.instance.delete(id);
      return {'ok': deleted, 'id': id};
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
