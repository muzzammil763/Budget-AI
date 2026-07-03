import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/workspace_handler_base.dart';

ToolDefinition buildWriteTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'write',
  description:
      "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.",
  parameters: {
    'type': 'object',
    'properties': {
      'filePath': {
        'type': 'string',
        'description': 'Path to the file to write (relative or absolute)',
      },
      'content': {
        'type': 'string',
        'description': 'Content to write to the file',
      },
      'workspace_root': {
        'type': 'string',
        'description':
            'Optional explicit workspace root. Use an absolute macOS path when targeting a specific MacRemote project directory.',
      },
    },
    'required': ['filePath', 'content'],
  },
  handler: handler,
);

mixin WriteToolHandler on WorkspaceHandlerBase {
  Future<dynamic> handleWriteRequest(Map<String, dynamic> args) async {
    final requestedPath =
        ((args['filePath'] as String?) ?? (args['path'] as String?) ?? '')
            .trim();
    final target = openCodeWorkspaceTarget(
      filePath: requestedPath,
      explicitWorkspaceRoot: (args['workspace_root'] as String? ?? '').trim(),
    );
    if (target.error != null) return {'error': target.error, 'tool': 'write'};

    return writeWorkspaceFileData(
      workspaceRoot: target.workspaceRoot,
      path: target.path,
      content: args['content'] as String? ?? '',
      mode: 'overwrite',
      toolName: 'write',
      command: 'overwrite',
    );
  }
}
