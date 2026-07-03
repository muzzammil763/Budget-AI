import 'package:budget_ai/core/logging/open_gate_log_service.dart';
import 'package:budget_ai/core/utils/project_automation_service.dart';
import 'package:budget_ai/features/chat/data/services/smart_file_edit_service.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/workspace_handler_base.dart';

ToolDefinition buildEditTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'edit',
  description:
      'Make precise file edits using exact text replacement. Edits are applied sequentially — each oldText is matched against the file as it looks after previous edits in the same call. Every oldText must identify a unique region; if two edits touch the same block or adjacent lines, merge them into one edit.',
  parameters: {
    'type': 'object',
    'properties': {
      'filePath': {
        'type': 'string',
        'description': 'Path to the file to edit (relative or absolute)',
      },
      'edits': {
        'type': 'array',
        'description':
            'One or more targeted replacements applied sequentially. Each oldText must uniquely identify a region of the file (as it exists after all prior edits in this call). Do not emit overlapping or adjacent edits — merge them instead.',
        'items': {
          'type': 'object',
          'properties': {
            'oldText': {
              'type': 'string',
              'description':
                  'The exact text to find and replace. Must be non-empty and must uniquely match one region in the current file content. Smart matching (whitespace normalisation and fuzzy) is applied when an exact match is not found.',
            },
            'newText': {
              'type': 'string',
              'description':
                  'Replacement text. May be empty to delete the matched region.',
            },
          },
          'required': ['oldText', 'newText'],
        },
      },
      'workspace_root': {
        'type': 'string',
        'description':
            'Optional explicit workspace root. Use an absolute macOS path when targeting a specific MacRemote project directory.',
      },
    },
    'required': ['filePath', 'edits'],
  },
  handler: handler,
);

mixin EditToolHandler on WorkspaceHandlerBase {
  Future<dynamic> handleEditRequest(Map<String, dynamic> args) async {
    final requestedPath =
        ((args['filePath'] as String?) ?? (args['path'] as String?) ?? '')
            .trim();
    final target = openCodeWorkspaceTarget(
      filePath: requestedPath,
      explicitWorkspaceRoot: (args['workspace_root'] as String? ?? '').trim(),
    );
    if (target.error != null) return {'error': target.error, 'tool': 'edit'};

    final editsList = args['edits'] as List<dynamic>?;
    OpenGateLogService.log(
      'Edit tool start path=${target.path} multi_edit_count=${editsList?.length ?? 0}',
      area: 'ToolEdit',
    );
    if (editsList != null && editsList.isNotEmpty) {
      final resolvedRoot = resolveWorkspaceRoot(target.workspaceRoot);
      final useRemote = shouldUseRemoteWorkspace(
        target.workspaceRoot,
        resolvedRoot,
      );
      final readResult = await readWorkspaceText(
        workspaceRoot: target.workspaceRoot,
        resolvedWorkspaceRoot: resolvedRoot,
        useRemote: useRemote,
        path: target.path,
      );
      if (readResult['error'] != null) return {...readResult, 'tool': 'edit'};

      final originalContent = readResult['content'] as String? ?? '';
      var updatedContent = originalContent;
      var editsChanged = 0;
      var editsAlreadyApplied = 0;
      final alreadyAppliedEdits = <Map<String, dynamic>>[];
      OpenGateLogService.log(
        'Edit tool read path=${target.path} chars=${originalContent.length} remote=$useRemote',
        area: 'ToolEdit',
      );

      for (var i = 0; i < editsList.length; i++) {
        final item = editsList[i] as Map<String, dynamic>? ?? {};
        final old =
            item['oldText'] as String? ??
            item['old_text'] as String? ??
            item['oldString'] as String? ??
            item['old_string'] as String? ??
            '';
        final neo =
            item['newText'] as String? ??
            item['new_text'] as String? ??
            item['newString'] as String? ??
            item['new_string'] as String? ??
            '';
        if (old.isEmpty) {
          return {
            'error': 'edits[$i].oldText is required and must not be empty.',
            'tool': 'edit',
          };
        }
        try {
          OpenGateLogService.log(
            'Applying edit ${i + 1}/${editsList.length} old_chars=${old.length} new_chars=${neo.length}',
            area: 'ToolEdit',
          );
          final editResult = const SmartFileEditService().editContent(
            content: updatedContent,
            request: SmartFileEditRequest(
              command: 'str_replace',
              oldText: old,
              newText: neo,
            ),
          );
          updatedContent = editResult.updatedContent;
          editsChanged++;
        } on SmartFileEditException catch (e) {
          if (isAlreadyAppliedReplacement(updatedContent, old, neo)) {
            editsAlreadyApplied++;
            alreadyAppliedEdits.add({
              'index': i,
              'old_text': old,
              'new_text': neo,
              'line': lineNumberForText(updatedContent, neo),
            });
            OpenGateLogService.log(
              'Edit ${i + 1}/${editsList.length} already applied.',
              area: 'ToolEdit',
            );
            continue;
          }
          OpenGateLogService.log(
            'Edit ${i + 1}/${editsList.length} failed: ${e.message}',
            area: 'ToolEdit',
          );
          return {
            'error': 'edits[$i]: ${e.message}',
            if (e.suggestions.isNotEmpty) 'suggestions': e.suggestions,
            'tool': 'edit',
          };
        }
      }

      if (editsChanged == 0 && editsAlreadyApplied > 0) {
        return {
          'success': true,
          'tool': 'edit',
          'command': 'multi_edit',
          'path': target.path,
          'edits_applied': editsList.length,
          'edits_changed': 0,
          'edits_already_applied': editsAlreadyApplied,
          if (alreadyAppliedEdits.isNotEmpty)
            'already_applied_edits': alreadyAppliedEdits,
          'already_applied': true,
          'diff': '',
          'bytes_before': originalContent.length,
          'bytes_after': originalContent.length,
        };
      }

      final writeResult = await writeWorkspaceText(
        workspaceRoot: target.workspaceRoot,
        resolvedWorkspaceRoot: resolvedRoot,
        useRemote: useRemote,
        path: target.path,
        content: updatedContent,
        mode: 'overwrite',
        toolName: 'edit',
        command: 'multi_edit',
      );
      OpenGateLogService.log(
        'Edit tool write completed path=${target.path} success=${writeResult['error'] == null}',
        area: 'ToolEdit',
      );
      return {
        ...writeResult,
        'tool': 'edit',
        'edits_applied': editsList.length,
        'edits_changed': editsChanged,
        if (editsAlreadyApplied > 0)
          'edits_already_applied': editsAlreadyApplied,
        if (alreadyAppliedEdits.isNotEmpty)
          'already_applied_edits': alreadyAppliedEdits,
        if (editsChanged == 0 && editsAlreadyApplied > 0)
          'already_applied': true,
        'diff': buildSimpleUnifiedDiff(
          path: target.path,
          before: originalContent,
          after: updatedContent,
        ),
      };
    }

    final oldString = args['oldString'] as String? ?? '';
    final newString = args['newString'] as String? ?? '';
    if (oldString == newString) {
      return {
        'error': 'No changes to apply: oldString and newString are identical.',
        'tool': 'edit',
      };
    }

    final replaceAll = args['replaceAll'] as bool? ?? false;
    if (!replaceAll) {
      OpenGateLogService.log(
        'Edit tool single replace path=${target.path} old_chars=${oldString.length} new_chars=${newString.length}',
        area: 'ToolEdit',
      );
      return _editWorkspaceFileData(
        workspaceRoot: target.workspaceRoot,
        path: target.path,
        command: oldString.isEmpty ? 'create' : 'str_replace',
        oldText: oldString,
        newText: newString,
        expectedOccurrences: 1,
        toolName: 'edit',
      );
    }

    final readResult = await readWorkspaceText(
      workspaceRoot: target.workspaceRoot,
      resolvedWorkspaceRoot: resolveWorkspaceRoot(target.workspaceRoot),
      useRemote: shouldUseRemoteWorkspace(
        target.workspaceRoot,
        resolveWorkspaceRoot(target.workspaceRoot),
      ),
      path: target.path,
    );
    if (readResult['error'] != null) return {...readResult, 'tool': 'edit'};

    final originalContent = readResult['content'] as String? ?? '';
    if (!originalContent.contains(oldString)) {
      return {'error': 'Could not find oldString in the file.', 'tool': 'edit'};
    }

    final updatedContent = originalContent.replaceAll(oldString, newString);
    final writeResult = await writeWorkspaceText(
      workspaceRoot: target.workspaceRoot,
      resolvedWorkspaceRoot: resolveWorkspaceRoot(target.workspaceRoot),
      useRemote: shouldUseRemoteWorkspace(
        target.workspaceRoot,
        resolveWorkspaceRoot(target.workspaceRoot),
      ),
      path: target.path,
      content: updatedContent,
      mode: 'overwrite',
      toolName: 'edit',
      command: 'str_replace_all',
    );
    return {
      ...writeResult,
      'tool': 'edit',
      'diff': buildSimpleUnifiedDiff(
        path: target.path,
        before: originalContent,
        after: updatedContent,
      ),
    };
  }

  Future<dynamic> _editWorkspaceFileData({
    required String workspaceRoot,
    required String path,
    required String command,
    required String toolName,
    String oldText = '',
    String newText = '',
    String anchorText = '',
    int? lineNumber,
    int? startLine,
    int? endLine,
    String contextText = '',
    int expectedOccurrences = 1,
  }) async {
    if (!canUseWorkspaceTools) {
      return {'error': noWorkspaceError()};
    }

    var normalizedWorkspaceRoot = normalizeExplicitMacPath(
      workspaceRoot.trim(),
    );
    var normalizedPath = normalizeExplicitMacPath(path.trim());
    var resolvedWorkspaceRoot = resolveWorkspaceRoot(normalizedWorkspaceRoot);

    if (normalizedPath.isEmpty) {
      return {'error': 'A file path is required for $toolName.'};
    }
    if (command.isEmpty) {
      return {'error': 'A command is required for $toolName.'};
    }

    if (shouldUseGithubModeLocalAbsolutePath(
      normalizedWorkspaceRoot,
      normalizedPath,
    )) {
      final split = splitAbsolutePathForWorkspace(normalizedPath);
      normalizedWorkspaceRoot = split.workspaceRoot;
      normalizedPath = split.path;
      resolvedWorkspaceRoot = normalizedWorkspaceRoot;
    } else if (normalizedWorkspaceRoot.isEmpty &&
        shouldUseRemoteAbsolutePath(normalizedPath)) {
      final split = splitAbsolutePathForWorkspace(normalizedPath);
      normalizedWorkspaceRoot = split.workspaceRoot;
      normalizedPath = split.path;
      resolvedWorkspaceRoot = null;
    }
    final useRemote = shouldUseRemoteWorkspace(
      normalizedWorkspaceRoot,
      resolvedWorkspaceRoot,
    );
    final isGithubModeLocalClone = isGithubModeLocalWorkspace(
      normalizedWorkspaceRoot,
      resolvedWorkspaceRoot,
    );

    if (command == 'create') {
      return writeWorkspaceText(
        workspaceRoot: normalizedWorkspaceRoot,
        resolvedWorkspaceRoot: resolvedWorkspaceRoot,
        useRemote: useRemote,
        path: normalizedPath,
        content: newText,
        mode: 'create',
        toolName: toolName,
        command: command,
      );
    }

    final readResult = await readWorkspaceText(
      workspaceRoot: normalizedWorkspaceRoot,
      resolvedWorkspaceRoot: resolvedWorkspaceRoot,
      useRemote: useRemote,
      path: normalizedPath,
    );
    if (readResult['error'] != null) {
      return {...readResult, 'tool': toolName, 'command': command};
    }

    final originalContent = readResult['content'] as String? ?? '';
    OpenGateLogService.log(
      '$toolName read path=$normalizedPath command=$command chars=${originalContent.length} remote=$useRemote',
      area: 'ToolEdit',
    );
    final editService = const SmartFileEditService();
    late SmartFileEditResult editResult;

    try {
      editResult = editService.editContent(
        content: originalContent,
        request: SmartFileEditRequest(
          command: command,
          oldText: oldText,
          newText: newText,
          anchorText: anchorText,
          expectedOccurrences: expectedOccurrences.clamp(1, 100),
          lineNumber: lineNumber,
          startLine: startLine,
          endLine: endLine,
          contextText: contextText,
        ),
      );
    } on SmartFileEditException catch (error) {
      if (command == 'str_replace' &&
          isAlreadyAppliedReplacement(originalContent, oldText, newText)) {
        OpenGateLogService.log(
          '$toolName already applied path=$normalizedPath command=$command',
          area: 'ToolEdit',
        );
        return {
          'success': true,
          'tool': toolName,
          'command': command,
          'path': normalizedPath,
          'already_applied': true,
          'details': {
            'old_text': oldText,
            'new_text': newText,
            'match_count': 0,
            'strategy': 'alreadyApplied',
            'line': lineNumberForText(originalContent, newText),
          },
          'diff': '',
          'bytes_before': originalContent.length,
          'bytes_after': originalContent.length,
        };
      }
      OpenGateLogService.log(
        '$toolName failed path=$normalizedPath command=$command: ${error.message}',
        area: 'ToolEdit',
      );
      return {
        ...error.toJson(),
        'tool': toolName,
        'command': command,
        'path': normalizedPath,
      };
    }

    final writeResult = await writeWorkspaceText(
      workspaceRoot: normalizedWorkspaceRoot,
      resolvedWorkspaceRoot: resolvedWorkspaceRoot,
      useRemote: useRemote,
      path: normalizedPath,
      content: editResult.updatedContent,
      mode: 'overwrite',
      toolName: toolName,
      command: command,
    );
    if (writeResult['error'] != null) {
      OpenGateLogService.log(
        '$toolName write failed path=$normalizedPath command=$command: ${writeResult['error']}',
        area: 'ToolEdit',
      );
      return writeResult;
    }
    OpenGateLogService.log(
      '$toolName write completed path=$normalizedPath command=$command strategy=${editResult.strategy.name}',
      area: 'ToolEdit',
    );

    final automationResults = <Map<String, dynamic>>[];
    if (!useRemote &&
        resolvedWorkspaceRoot != null &&
        !isGithubModeLocalClone) {
      final automationService = const ProjectAutomationService();

      if (normalizedPath.endsWith('.dart')) {
        final packageResults = await automationService
            .processDartFileForNewPackages(
              projectRoot: resolvedWorkspaceRoot,
              fileContent: editResult.updatedContent,
            );
        for (final result in packageResults) {
          automationResults.add(result.toJson());
        }
      }

      final analysisResult = await automationService.runPostEditAnalysis(
        resolvedWorkspaceRoot,
      );
      automationResults.add(analysisResult.toJson());
    }

    return {
      ...writeResult,
      'details': editResult.toDetails(
        command: command,
        requestedText: command == 'str_replace' ? oldText : anchorText,
        newText: newText,
      ),
      'diff': buildSimpleUnifiedDiff(
        path: normalizedPath,
        before: originalContent,
        after: editResult.updatedContent,
      ),
      'bytes_before': originalContent.length,
      'bytes_after': editResult.updatedContent.length,
      if (automationResults.isNotEmpty) 'automation': automationResults,
      if (isGithubModeLocalClone) 'verification': githubModeVerificationInfo(),
    };
  }
}
