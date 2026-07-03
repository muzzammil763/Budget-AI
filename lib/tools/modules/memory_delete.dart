import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';
import 'package:budget_ai/tools/core/tool_approval.dart';
import 'package:budget_ai/tools/settings/tool_settings.dart';

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
    if (ToolSettings.accessModeForTool('memory_delete') ==
        ToolAccessMode.approvalRequired) {
      return localToolApprovalRequired(
        tool: 'memory_delete',
        title: 'Delete Memory',
        command: 'Delete memory $id',
        consequence: 'This removes the saved memory from this device.',
        arguments: {'id': id},
      );
    }
    try {
      final deleted = await MemoryService.instance.delete(id);
      return {'ok': deleted, 'id': id};
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
