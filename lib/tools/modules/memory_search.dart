import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';

ToolDefinition buildMemorySearchTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'memory_search',
  description:
      'Search saved memories by keyword. Returns matching memories from the title, content, key, or type. Use this instead of memory_list when you only need memories relevant to a specific topic or query.',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'The search keyword or phrase to look for in memories. Matches against title, content, key, and type.',
      },
    },
    'required': ['query'],
  },
  handler: handler,
);

mixin MemorySearchToolHandler {
  Future<dynamic> handleMemorySearchRequest(Map<String, dynamic> args) async {
    try {
      final query = (args['query'] as String? ?? '').trim().toLowerCase();
      if (query.isEmpty) {
        return {'error': 'query is required'};
      }

      final memories = await MemoryService.instance.getAll();
      final matches = memories
          .where(
            (m) =>
                m.title.toLowerCase().contains(query) ||
                m.content.toLowerCase().contains(query) ||
                m.key.toLowerCase().contains(query) ||
                m.type.toLowerCase().contains(query),
          )
          .toList(growable: false);

      return {
        'ok': true,
        'query': query,
        'count': matches.length,
        'memories': matches.map((m) => m.toJson()).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
