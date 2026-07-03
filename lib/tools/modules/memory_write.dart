import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';

ToolDefinition buildMemoryWriteTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'memory_write',
  description:
      'Save or update a memory about the user. If a memory with the same key already exists it is updated in place — never creates duplicates. Use descriptive keys like "user_name", "preferred_language", "timezone". Types: preference, fact, name, project, instruction. Batch multiple memories using the "facts" array.',
  parameters: {
    'type': 'object',
    'properties': {
      'key': {
        'type': 'string',
        'description':
            'Unique stable key identifying this memory (e.g. "user_name", "preferred_editor"). Used for deduplication.',
      },
      'title': {
        'type': 'string',
        'description': 'Short human-readable title (e.g. "User Name")',
      },
      'content': {
        'type': 'string',
        'description': 'The memory content to save.',
      },
      'type': {
        'type': 'string',
        'enum': ['preference', 'fact', 'name', 'project', 'instruction'],
        'description': 'Category of the memory.',
      },
      'facts': {
        'type': 'array',
        'description':
            'Batch of memories to save/update at once. Use this for multiple memories instead of calling the tool multiple times.',
        'items': {
          'type': 'object',
          'properties': {
            'key': {
              'type': 'string',
              'description': 'Unique stable key for this memory',
            },
            'title': {
              'type': 'string',
              'description': 'Short human-readable title',
            },
            'content': {
              'type': 'string',
              'description': 'The memory content to save',
            },
            'type': {
              'type': 'string',
              'enum': ['preference', 'fact', 'name', 'project', 'instruction'],
              'description': 'Category of the memory',
            },
          },
          'required': ['key', 'content'],
        },
      },
    },
    'required': [],
  },
  handler: handler,
);

mixin MemoryWriteToolHandler {
  Future<dynamic> handleMemoryWriteRequest(Map<String, dynamic> args) async {
    // Support batch writes via 'facts' array
    final facts = args['facts'] as List<dynamic>?;
    if (facts != null && facts.isNotEmpty) {
      final results = <Map<String, dynamic>>[];
      for (final item in facts) {
        final fact = item as Map<String, dynamic>? ?? {};
        final key = (fact['key'] as String? ?? '').trim();
        final content = (fact['content'] as String? ?? '').trim();
        if (key.isEmpty || content.isEmpty) continue;

        final title = (fact['title'] as String? ?? '').trim();
        final type = (fact['type'] as String? ?? 'fact').trim();

        try {
          final result = await MemoryService.instance.write(
            key: key,
            title: title.isEmpty ? key : title,
            content: content,
            type: type.isEmpty ? 'fact' : type,
          );
          results.add({
            'action': result.wasUpdated ? 'updated' : 'created',
            'id': result.item.id,
            'key': result.item.key,
            'title': result.item.title,
          });
        } catch (e) {
          results.add({'error': e.toString(), 'key': key});
        }
      }
      return {
        'ok': true,
        'batch': true,
        'count': results.length,
        'results': results,
      };
    }

    // Single memory write
    final key = (args['key'] as String? ?? '').trim();
    final title = (args['title'] as String? ?? '').trim();
    final content = (args['content'] as String? ?? '').trim();
    final type = (args['type'] as String? ?? 'fact').trim();

    if (key.isEmpty) return {'error': 'key is required'};
    if (content.isEmpty) return {'error': 'content is required'};

    try {
      final result = await MemoryService.instance.write(
        key: key,
        title: title.isEmpty ? key : title,
        content: content,
        type: type.isEmpty ? 'fact' : type,
      );
      return {
        'ok': true,
        'action': result.wasUpdated ? 'updated' : 'created',
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
