import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';

ToolDefinition buildMemoryListTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'memory_list',
  description:
      'List all saved memories with their IDs, keys, titles, content, types and timestamps.',
  parameters: {'type': 'object', 'properties': {}, 'required': []},
  handler: handler,
);

mixin MemoryListToolHandler {
  Future<dynamic> handleMemoryListRequest(Map<String, dynamic> args) async {
    try {
      final memories = await MemoryService.instance.getAll();
      return {
        'ok': true,
        'count': memories.length,
        'memories': memories.map((m) => m.toJson()).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
