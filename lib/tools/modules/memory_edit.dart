import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';

ToolDefinition buildMemoryEditTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'memory_edit',
  description:
      'Edit an existing memory by its ID. Use memory_list first to get the ID. Only provided fields are changed.',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': 'The memory ID to edit (from memory_list).',
      },
      'title': {'type': 'string'},
      'content': {'type': 'string'},
      'type': {
        'type': 'string',
        'enum': ['preference', 'fact', 'name', 'project', 'instruction'],
      },
    },
    'required': ['id'],
  },
  handler: handler,
);

mixin MemoryEditToolHandler {
  Future<dynamic> handleMemoryEditRequest(Map<String, dynamic> args) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return {'error': 'id is required'};

    try {
      final memories = await MemoryService.instance.getAll();
      final existingIndex = memories.indexWhere((m) => m.id == id);
      if (existingIndex < 0) return {'ok': false, 'error': 'Memory not found'};
      final existing = memories[existingIndex];

      final result = await MemoryService.instance.write(
        key: existing.key,
        title: (args['title'] as String? ?? existing.title).trim(),
        content: (args['content'] as String? ?? existing.content).trim(),
        type: (args['type'] as String? ?? existing.type).trim(),
      );
      return {
        'ok': true,
        'id': result.item.id,
        'key': result.item.key,
        'title': result.item.title,
        'updated_at': result.item.updatedAt.toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
