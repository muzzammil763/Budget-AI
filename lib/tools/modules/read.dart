import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/workspace_handler_base.dart';

ToolDefinition buildReadTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'read',
  description:
      'Read the contents of a file. Supports text files and images (jpg, png, gif, webp). Images are sent as attachments. For text files, the default output is 300 lines and explicit limit is capped at 2000 lines or 50KB (whichever is hit first). Use offset/limit for targeted reads of large files. When you need more context, continue with offset until complete.',
  parameters: {
    'type': 'object',
    'properties': {
      'filePath': {
        'type': 'string',
        'description': 'Path to the file to read (relative or absolute)',
      },
      'offset': {
        'type': 'integer',
        'description': 'Line number to start reading from (1-indexed)',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum number of lines to read',
      },
      'workspace_root': {
        'type': 'string',
        'description':
            'Optional explicit workspace root. Use an absolute macOS path when targeting a specific MacRemote project directory.',
      },
    },
    'required': ['filePath'],
  },
  handler: handler,
);

mixin ReadToolHandler on WorkspaceHandlerBase {
  Future<dynamic> handleReadRequest(Map<String, dynamic> args) async {
    final filePaths = args['filePaths'];
    if (filePaths is List && filePaths.isNotEmpty) {
      final paths = filePaths
          .whereType<String>()
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toList();

      if (paths.isEmpty) {
        return {
          'error': 'filePaths must include at least one non-empty path.',
          'tool': 'read',
        };
      }

      final results = <Map<String, dynamic>>[];
      for (final path in paths) {
        final result = await readSingleOpenCodePath(args, path);
        results.add(
          result is Map<String, dynamic>
              ? result
              : {'tool': 'read', 'filePath': path, 'result': result},
        );
      }

      final failedCount = results.where((result) {
        return result['error'] != null || result['file_error'] != null;
      }).length;

      return {
        'tool': 'read',
        'filePaths': paths,
        'count': results.length,
        'failed_count': failedCount,
        'results': results,
      };
    }

    final requestedPath =
        ((args['filePath'] as String?) ?? (args['path'] as String?) ?? '')
            .trim();
    if (requestedPath.isEmpty) {
      return {
        'error': 'A non-empty filePath or filePaths array is required.',
        'tool': 'read',
      };
    }

    return readSingleOpenCodePath(args, requestedPath);
  }

  Future<dynamic> readSingleOpenCodePath(
    Map<String, dynamic> args,
    String requestedPath,
  ) async {
    final target = openCodeWorkspaceTarget(
      filePath: requestedPath,
      explicitWorkspaceRoot: (args['workspace_root'] as String? ?? '').trim(),
    );
    if (target.error != null) return {'error': target.error, 'tool': 'read'};

    final offset = ((args['offset'] as num?) ?? 1).toInt().clamp(1, 1 << 30);
    final limit =
        ((args['limit'] as num?) ?? WorkspaceHandlerBase.defaultReadLineLimit)
            .toInt()
            .clamp(1, WorkspaceHandlerBase.maxReadLineLimit);
    final endLine = offset + limit - 1;

    final fileResult = await readWorkspaceFileData(
      workspaceRoot: target.workspaceRoot,
      path: target.path,
      startLine: offset,
      endLine: endLine,
    );

    if (fileResult is Map && fileResult['error'] == null) {
      return {
        ...fileResult,
        'tool': 'read',
        'filePath': target.originalFilePath,
      };
    }

    final directoryResult = await listWorkspaceFilesData(
      workspaceRoot: target.workspaceRoot,
      path: target.path,
      recursive: false,
      maxResults: limit,
    );
    return {
      if (directoryResult is Map) ...directoryResult,
      'tool': 'read',
      'filePath': target.originalFilePath,
      if (fileResult is Map && fileResult['error'] != null)
        'file_error': fileResult['error'],
    };
  }
}
