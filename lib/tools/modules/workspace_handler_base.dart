import 'dart:io';
import 'dart:math' as math;

import 'package:budget_ai/core/storage/shared_prefs_service.dart';
import 'package:budget_ai/features/mac_companion/data/mac_companion_service.dart';

// Public workspace target class (renamed from _OpenCodeWorkspaceTarget).
class WorkspaceTarget {
  const WorkspaceTarget({
    required this.originalFilePath,
    required this.workspaceRoot,
    required this.path,
    this.error,
  });

  final String originalFilePath;
  final String workspaceRoot;
  final String path;
  final String? error;
}

mixin WorkspaceHandlerBase {
  String? _lastRemoteWorkingDirectory;

  // ── abstract ─────────────────────────────────────────────
  bool get githubModeActive;

  // ── string constants ─────────────────────────────────────
  static const connectMacRemoteMessage =
      'Connect to MacRemote first to run terminal, git, filesystem, or Makefile actions. Open Settings > MacRemote Backend, then save and test your backend host, port, and API key.';

  static const selectOrProvideRemoteWorkspaceMessage =
      'MacRemote is connected, but this file path is relative and no remote working directory is available yet. Run bash with a workdir first or provide an absolute path such as /Users/name/Projects/app/file.txt.';

  // ── read-line limits ─────────────────────────────────────
  static const defaultReadLineLimit = 300;
  static const maxReadLineLimit = 2000;

  // ── computed getters ─────────────────────────────────────
  bool get hasRemoteWorkspaceConnection =>
      MacCompanionService.instance.stateNotifier.value.hasRemoteConnection;

  String? get activeWorkspaceSource => SharedPrefsService.getWorkspaceSource();

  bool get canUseWorkspaceTools =>
      hasRemoteWorkspaceConnection || githubModeActive;

  void rememberRemoteWorkingDirectory(String? workingDirectory) {
    final normalized = normalizeExplicitMacPath(
      (workingDirectory ?? '').trim(),
    );
    if (normalized.isEmpty || !looksLikeMacAbsolutePath(normalized)) {
      return;
    }
    _lastRemoteWorkingDirectory = normalized;
  }

  // ── workspace I/O helpers ────────────────────────────────

  Future<dynamic> readWorkspaceFileData({
    required String workspaceRoot,
    required String path,
    int? startLine,
    int? endLine,
  }) async {
    if (!canUseWorkspaceTools) {
      return {'error': noWorkspaceError()};
    }

    var normalizedWorkspaceRoot = normalizeExplicitMacPath(
      workspaceRoot.trim(),
    );
    var normalizedPath = normalizeExplicitMacPath(path.trim());
    final effectiveStartLine = startLine ?? 1;
    final maxEndLine = effectiveStartLine + maxReadLineLimit - 1;
    final effectiveEndLine = math.min(
      endLine ?? (effectiveStartLine + defaultReadLineLimit - 1),
      maxEndLine,
    );
    var resolvedWorkspaceRoot = resolveWorkspaceRoot(normalizedWorkspaceRoot);

    if (normalizedPath.isEmpty) {
      return {'error': noWorkspaceError()};
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

    if (shouldUseRemoteWorkspace(
      normalizedWorkspaceRoot,
      resolvedWorkspaceRoot,
    )) {
      return MacCompanionService.instance.readRemoteFile(
        normalizedPath,
        workspaceRoot: normalizedWorkspaceRoot.isEmpty
            ? null
            : normalizedWorkspaceRoot,
        startLine: effectiveStartLine,
        endLine: effectiveEndLine,
      );
    }

    return readLocalWorkspaceFile(
      workspaceRoot: normalizedWorkspaceRoot,
      resolvedWorkspaceRoot: resolvedWorkspaceRoot,
      path: normalizedPath,
      startLine: effectiveStartLine,
      endLine: effectiveEndLine,
    );
  }

  Future<dynamic> writeWorkspaceFileData({
    required String workspaceRoot,
    required String path,
    required String content,
    required String mode,
    required String toolName,
    required String command,
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
      return {'error': noWorkspaceError(), 'tool': toolName};
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

    // Capture pre-edit content for undo support (overwrite mode only, cap at 200 KB).
    String? preContent;
    String? writeDiff;
    if (mode == 'overwrite') {
      final readResult = await readWorkspaceText(
        workspaceRoot: normalizedWorkspaceRoot,
        resolvedWorkspaceRoot: resolvedWorkspaceRoot,
        useRemote: useRemote,
        path: normalizedPath,
      );
      if (readResult['error'] == null) {
        final original = readResult['content'] as String? ?? '';
        if (original.isNotEmpty &&
            original != content &&
            original.length <= 200000) {
          preContent = original;
          final raw = buildSimpleUnifiedDiff(
            path: normalizedPath,
            before: original,
            after: content,
          );
          writeDiff = raw.isEmpty ? null : raw;
        }
      }
    }

    if (useRemote) {
      final writeResult = await writeWorkspaceText(
        workspaceRoot: normalizedWorkspaceRoot,
        resolvedWorkspaceRoot: resolvedWorkspaceRoot,
        useRemote: true,
        path: normalizedPath,
        content: content,
        mode: mode,
        toolName: toolName,
        command: command,
      );
      return {...writeResult, 'pre_content': preContent, 'diff': writeDiff};
    }

    final writeResult = await writeWorkspaceText(
      workspaceRoot: normalizedWorkspaceRoot,
      resolvedWorkspaceRoot: resolvedWorkspaceRoot,
      useRemote: false,
      path: normalizedPath,
      content: content,
      mode: mode,
      toolName: toolName,
      command: command,
    );
    return {
      ...writeResult,
      'pre_content': preContent,
      'diff': writeDiff,
      if (isGithubModeLocalClone) 'verification': githubModeVerificationInfo(),
    };
  }

  Future<dynamic> listWorkspaceFilesData({
    required String workspaceRoot,
    required String path,
    required bool recursive,
    required int maxResults,
  }) async {
    if (!canUseWorkspaceTools) {
      return {'error': noWorkspaceError()};
    }

    var normalizedWorkspaceRoot = normalizeExplicitMacPath(
      workspaceRoot.trim(),
    );
    var normalizedPath = normalizeExplicitMacPath(path.trim());
    var resolvedWorkspaceRoot = resolveWorkspaceRoot(normalizedWorkspaceRoot);

    if (shouldUseGithubModeLocalAbsolutePath(
      normalizedWorkspaceRoot,
      normalizedPath,
    )) {
      normalizedWorkspaceRoot = normalizedPath;
      normalizedPath = '.';
      resolvedWorkspaceRoot = normalizedWorkspaceRoot;
    } else if (normalizedWorkspaceRoot.isEmpty &&
        shouldUseRemoteAbsolutePath(normalizedPath)) {
      normalizedWorkspaceRoot = normalizedPath;
      normalizedPath = '.';
      resolvedWorkspaceRoot = null;
    }

    if (shouldUseRemoteWorkspace(
      normalizedWorkspaceRoot,
      resolvedWorkspaceRoot,
    )) {
      return MacCompanionService.instance.listRemoteFiles(
        workspaceRoot: normalizedWorkspaceRoot.isEmpty
            ? null
            : normalizedWorkspaceRoot,
        path: normalizedPath,
        recursive: recursive,
        maxResults: maxResults,
      );
    }

    return listLocalWorkspaceFiles(
      workspaceRoot: normalizedWorkspaceRoot,
      resolvedWorkspaceRoot: resolvedWorkspaceRoot,
      path: normalizedPath,
      recursive: recursive,
      maxResults: maxResults,
    );
  }

  Future<Map<String, dynamic>> readWorkspaceText({
    required String workspaceRoot,
    required String? resolvedWorkspaceRoot,
    required bool useRemote,
    required String path,
  }) async {
    if (useRemote) {
      final result = await MacCompanionService.instance.readRemoteFile(
        path,
        workspaceRoot: workspaceRoot.isEmpty ? null : workspaceRoot,
      );
      if (result['file'] is Map) {
        return {
          ...Map<String, dynamic>.from(result['file'] as Map),
          'ok': result['ok'],
        };
      }
      return result;
    }

    final result = await readLocalWorkspaceFile(
      workspaceRoot: workspaceRoot,
      resolvedWorkspaceRoot: resolvedWorkspaceRoot,
      path: path,
    );
    if (result['file'] is Map) {
      return {
        ...Map<String, dynamic>.from(result['file'] as Map),
        'ok': result['ok'],
      };
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> writeWorkspaceText({
    required String workspaceRoot,
    required String? resolvedWorkspaceRoot,
    required bool useRemote,
    required String path,
    required String content,
    required String mode,
    required String toolName,
    required String command,
  }) async {
    Map<String, dynamic> result;
    if (useRemote) {
      result = await MacCompanionService.instance.writeRemoteFile(
        workspaceRoot: workspaceRoot.isEmpty ? null : workspaceRoot,
        path: path,
        content: content,
        mode: mode,
      );
    } else {
      result = await writeLocalWorkspaceFile(
        workspaceRoot: workspaceRoot,
        resolvedWorkspaceRoot: resolvedWorkspaceRoot,
        path: path,
        content: content,
        mode: mode,
      );
    }

    return {...result, 'tool': toolName, 'command': command, 'path': path};
  }

  Future<Map<String, dynamic>> readLocalWorkspaceFile({
    required String workspaceRoot,
    required String? resolvedWorkspaceRoot,
    required String path,
    int? startLine,
    int? endLine,
  }) async {
    final root = resolvedWorkspaceRoot ?? workspaceRoot;
    if (root.trim().isEmpty) return {'ok': false, 'error': noWorkspaceError()};
    final absolutePath = joinLocalWorkspacePath(root, path);
    final file = File(absolutePath);
    if (!await file.exists()) {
      return {'ok': false, 'error': 'File not found: $absolutePath'};
    }

    try {
      final content = await file.readAsString();
      final lines = content.split('\n');
      final safeStart = (startLine ?? 1).clamp(
        1,
        lines.isEmpty ? 1 : lines.length,
      );
      final safeEnd = (endLine ?? lines.length).clamp(
        safeStart,
        lines.isEmpty ? safeStart : lines.length,
      );
      final selectedLines = lines.sublist(safeStart - 1, safeEnd);
      return {
        'ok': true,
        'file': {
          'workspace_root': root,
          'path': path,
          'absolute_path': absolutePath,
          'start_line': safeStart,
          'end_line': safeEnd,
          'line_count': lines.length,
          'content': selectedLines.join('\n'),
          'size_bytes': await file.length(),
        },
      };
    } catch (error) {
      return {'ok': false, 'error': 'Could not read file: $error'};
    }
  }

  Future<Map<String, dynamic>> writeLocalWorkspaceFile({
    required String workspaceRoot,
    required String? resolvedWorkspaceRoot,
    required String path,
    required String content,
    required String mode,
  }) async {
    final root = resolvedWorkspaceRoot ?? workspaceRoot;
    if (root.trim().isEmpty) return {'ok': false, 'error': noWorkspaceError()};
    final absolutePath = joinLocalWorkspacePath(root, path);
    final file = File(absolutePath);
    if (mode == 'create' && await file.exists()) {
      return {'ok': false, 'error': 'File already exists: $absolutePath'};
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return {
      'ok': true,
      'workspace_root': root,
      'path': path,
      'absolute_path': absolutePath,
      'size_bytes': await file.length(),
    };
  }

  Future<Map<String, dynamic>> listLocalWorkspaceFiles({
    required String workspaceRoot,
    required String? resolvedWorkspaceRoot,
    required String path,
    required bool recursive,
    required int maxResults,
  }) async {
    final root = resolvedWorkspaceRoot ?? workspaceRoot;
    if (root.trim().isEmpty) return {'ok': false, 'error': noWorkspaceError()};
    final absolutePath = joinLocalWorkspacePath(root, path);
    final file = File(absolutePath);
    if (await file.exists()) {
      final name = basename(file.path);
      if (name == '.opengate_github.json') {
        return {'ok': true, 'results': <Map<String, dynamic>>[]};
      }
      return {
        'ok': true,
        'results': [
          {
            'path': relativeLocalPath(root, file.path),
            'absolute_path': file.path,
            'type': 'file',
            'name': name,
          },
        ],
      };
    }
    final start = Directory(absolutePath);
    if (!await start.exists()) {
      return {'ok': false, 'error': 'Directory not found: $absolutePath'};
    }
    final results = <Map<String, dynamic>>[];
    await for (final entity in start.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (results.length >= maxResults) break;
      final name = basename(entity.path);
      if (name == '.opengate_github.json' || name == '.git') continue;
      results.add({
        'path': relativeLocalPath(root, entity.path),
        'absolute_path': entity.path,
        'type': entity is Directory ? 'directory' : 'file',
        'name': name,
      });
    }
    return {'ok': true, 'results': results};
  }

  String buildSimpleUnifiedDiff({
    required String path,
    required String before,
    required String after,
  }) {
    if (before == after) {
      return '';
    }
    const maxDiffInputChars = 200000;
    const maxDiffChangedLines = 400;
    if (before.length > maxDiffInputChars || after.length > maxDiffInputChars) {
      return 'Diff omitted for $path because the edited file is too large '
          '(${before.length} -> ${after.length} chars).';
    }

    final beforeLines = before.split('\n');
    final afterLines = after.split('\n');
    var prefix = 0;
    while (prefix < beforeLines.length &&
        prefix < afterLines.length &&
        beforeLines[prefix] == afterLines[prefix]) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < beforeLines.length - prefix &&
        suffix < afterLines.length - prefix &&
        beforeLines[beforeLines.length - suffix - 1] ==
            afterLines[afterLines.length - suffix - 1]) {
      suffix++;
    }

    final contextBeforeStart = (prefix - 3).clamp(0, beforeLines.length);
    final contextBeforeEnd = (beforeLines.length - suffix + 3).clamp(
      contextBeforeStart,
      beforeLines.length,
    );
    final contextAfterStart = (prefix - 3).clamp(0, afterLines.length);
    final contextAfterEnd = (afterLines.length - suffix + 3).clamp(
      contextAfterStart,
      afterLines.length,
    );
    final removedLineCount = beforeLines.length - suffix - prefix;
    final addedLineCount = afterLines.length - suffix - prefix;
    if (removedLineCount + addedLineCount > maxDiffChangedLines) {
      return 'Diff omitted for $path because the edit changed '
          '${removedLineCount + addedLineCount} lines.';
    }

    final buffer = StringBuffer()
      ..writeln('--- a/$path')
      ..writeln('+++ b/$path')
      ..writeln(
        '@@ -${contextBeforeStart + 1},${contextBeforeEnd - contextBeforeStart} +${contextAfterStart + 1},${contextAfterEnd - contextAfterStart} @@',
      );

    for (var i = contextBeforeStart; i < prefix; i++) {
      buffer.writeln(' ${beforeLines[i]}');
    }
    for (var i = prefix; i < beforeLines.length - suffix; i++) {
      buffer.writeln('-${beforeLines[i]}');
    }
    for (var i = prefix; i < afterLines.length - suffix; i++) {
      buffer.writeln('+${afterLines[i]}');
    }
    for (var i = beforeLines.length - suffix; i < contextBeforeEnd; i++) {
      buffer.writeln(' ${beforeLines[i]}');
    }

    return buffer.toString().trimRight();
  }

  // ── workspace path utilities ─────────────────────────────

  String? resolveWorkspaceRoot(String explicitWorkspaceRoot) {
    explicitWorkspaceRoot = normalizeExplicitMacPath(explicitWorkspaceRoot);
    if (explicitWorkspaceRoot.isNotEmpty) {
      if (isKnownRemoteWorkspaceRoot(explicitWorkspaceRoot)) {
        return null;
      }
      return explicitWorkspaceRoot;
    }
    if (activeWorkspaceSource == 'remote_mac') {
      return null;
    }
    return SharedPrefsService.getWorkspaceRoot();
  }

  WorkspaceTarget openCodeWorkspaceTarget({
    required String filePath,
    String explicitWorkspaceRoot = '',
  }) {
    final original = normalizeExplicitMacPath(filePath.trim());
    if (original.isEmpty) {
      return const WorkspaceTarget(
        originalFilePath: '',
        workspaceRoot: '',
        path: '',
        error: 'A filePath is required.',
      );
    }

    final explicit = normalizeExplicitMacPath(explicitWorkspaceRoot.trim());
    if (explicit.isEmpty &&
        githubModeActive &&
        looksLikeLocalAbsolutePath(original)) {
      final split = splitAbsolutePathForWorkspace(original);
      return WorkspaceTarget(
        originalFilePath: original,
        workspaceRoot: split.workspaceRoot,
        path: split.path,
      );
    }

    final remoteState = MacCompanionService.instance.stateNotifier.value;
    final selectedRemoteRoot =
        remoteState.remoteWorkspaceRoot?.trim().isNotEmpty == true
        ? remoteState.remoteWorkspaceRoot!.trim()
        : (SharedPrefsService.getWorkspaceSource() == 'remote_mac'
              ? SharedPrefsService.getWorkspaceRoot()?.trim() ?? ''
              : '');
    final selectedLocalRoot =
        SharedPrefsService.getWorkspaceRoot()?.trim() ?? '';
    final rememberedRemoteRoot = (_lastRemoteWorkingDirectory ?? '').trim();
    if (explicit.isEmpty && shouldUseRemoteAbsolutePath(original)) {
      final split = splitAbsolutePathForWorkspace(original);
      return WorkspaceTarget(
        originalFilePath: original,
        workspaceRoot: split.workspaceRoot,
        path: split.path,
      );
    }

    final inferredRoot = explicit.isNotEmpty
        ? explicit
        : (activeWorkspaceSource == 'remote_mac'
              ? selectedRemoteRoot
              : selectedLocalRoot);
    final fallbackRoot = inferredRoot.isEmpty && hasRemoteWorkspaceConnection
        ? rememberedRemoteRoot
        : inferredRoot;

    if (fallbackRoot.isEmpty) {
      return WorkspaceTarget(
        originalFilePath: original,
        workspaceRoot: '',
        path: original,
        error: noWorkspaceError(),
      );
    }

    return WorkspaceTarget(
      originalFilePath: original,
      workspaceRoot: fallbackRoot,
      path: relativeToRootIfPossible(fallbackRoot, original),
    );
  }

  bool shouldUseRemoteWorkspace(
    String explicitWorkspaceRoot,
    String? resolvedWorkspaceRoot,
  ) {
    if (!hasRemoteWorkspaceConnection) {
      return false;
    }

    if (activeWorkspaceSource == 'remote_mac') {
      return true;
    }

    if (isKnownRemoteWorkspaceRoot(explicitWorkspaceRoot)) {
      return true;
    }

    return resolvedWorkspaceRoot == null || resolvedWorkspaceRoot.isEmpty;
  }

  bool isKnownRemoteWorkspaceRoot(String workspaceRoot) {
    final candidate = normalizeExplicitMacPath(workspaceRoot);
    if (candidate.isEmpty || !hasRemoteWorkspaceConnection) {
      return false;
    }

    final remoteState = MacCompanionService.instance.stateNotifier.value;
    final remoteRoots = <String>[
      remoteState.remoteWorkspaceRoot?.trim() ?? '',
      ...remoteState.remoteAllowedRoots.map(
        (item) => item['path']?.toString().trim() ?? '',
      ),
    ].where((path) => path.isNotEmpty);

    for (final remoteRoot in remoteRoots) {
      if (pathMatchesOrContains(candidate, remoteRoot)) {
        return true;
      }
    }

    // If a remote backend is connected and the model explicitly uses a
    // canonical macOS home path, prefer the remote backend over treating that
    // path as local device storage.
    return candidate.startsWith('/Users/');
  }

  bool pathMatchesOrContains(String candidate, String root) {
    final normalizedCandidate = candidate.trim().replaceAll('\\', '/');
    final normalizedRoot = root.trim().replaceAll('\\', '/');
    if (normalizedCandidate == normalizedRoot) {
      return true;
    }
    return normalizedCandidate.startsWith('$normalizedRoot/');
  }

  bool shouldUseRemoteAbsolutePath(String path) {
    return hasRemoteWorkspaceConnection && looksLikeMacAbsolutePath(path);
  }

  bool looksLikeMacAbsolutePath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    return normalized.startsWith('/Users/') || normalized.startsWith('Users/');
  }

  bool looksLikeLocalAbsolutePath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    return normalized.startsWith('/');
  }

  bool shouldUseGithubModeLocalAbsolutePath(String workspaceRoot, String path) {
    return githubModeActive &&
        workspaceRoot.trim().isEmpty &&
        looksLikeLocalAbsolutePath(path);
  }

  bool isGithubModeLocalWorkspace(
    String workspaceRoot,
    String? resolvedWorkspaceRoot,
  ) {
    final root = (resolvedWorkspaceRoot ?? workspaceRoot).trim().replaceAll(
      '\\',
      '/',
    );
    return root.contains('/app_flutter/github_repos/');
  }

  Map<String, dynamic> githubModeVerificationInfo() {
    return {
      'available': false,
      'reason':
          'Command validation is unavailable for local GitHub mode app-storage clones because bash/flutter/dart tools are not exposed in this mode.',
      'recommended_next_step':
          'Use read/grep to inspect the changed code and github_repo_status before commit/push.',
    };
  }

  String normalizeExplicitMacPath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (normalized.startsWith('Users/')) {
      return '/$normalized';
    }
    return normalized;
  }

  ({String workspaceRoot, String path}) splitAbsolutePathForWorkspace(
    String absolutePath,
  ) {
    final normalized = normalizeExplicitMacPath(absolutePath);
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0 || lastSlash == normalized.length - 1) {
      return (workspaceRoot: normalized, path: '.');
    }
    return (
      workspaceRoot: normalized.substring(0, lastSlash),
      path: normalized.substring(lastSlash + 1),
    );
  }

  String relativeToRootIfPossible(String root, String path) {
    final normalizedRoot = normalizeExplicitMacPath(root);
    final normalizedPath = normalizeExplicitMacPath(path);
    if (normalizedPath == normalizedRoot) return '.';
    if (normalizedPath.startsWith('$normalizedRoot/')) {
      return normalizedPath.substring(normalizedRoot.length + 1);
    }
    return path;
  }

  String joinLocalWorkspacePath(String root, String childPath) {
    final normalizedRoot = root.trim().replaceAll('\\', '/');
    final normalizedChild = childPath.trim().replaceAll('\\', '/');
    if (normalizedChild.isEmpty || normalizedChild == '.') {
      return normalizedRoot;
    }
    if (normalizedChild.startsWith('/')) {
      return normalizedChild;
    }
    return '$normalizedRoot/$normalizedChild';
  }

  String relativeLocalPath(String root, String absolutePath) {
    final normalizedRoot = root.trim().replaceAll('\\', '/');
    final normalizedPath = absolutePath.trim().replaceAll('\\', '/');
    if (normalizedPath == normalizedRoot) return '.';
    if (normalizedPath.startsWith('$normalizedRoot/')) {
      return normalizedPath.substring(normalizedRoot.length + 1);
    }
    return normalizedPath;
  }

  String basename(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  bool isAlreadyAppliedReplacement(
    String content,
    String oldText,
    String newText,
  ) {
    if (oldText.isEmpty || newText.isEmpty) {
      return false;
    }
    return !content.contains(oldText) && content.contains(newText);
  }

  int? lineNumberForText(String content, String text) {
    if (text.isEmpty) return null;
    final index = content.indexOf(text);
    if (index < 0) return null;

    var line = 1;
    for (var i = 0; i < index; i++) {
      if (content.codeUnitAt(i) == 10) line++;
    }
    return line;
  }

  dynamic withToolName(dynamic result, String toolName) {
    if (result is Map) {
      return {...result, 'tool': toolName};
    }
    return {'tool': toolName, 'result': result};
  }

  Future<String?> ensureLocalCommandWorkspace(String workspaceRoot) async {
    final directory = Directory(workspaceRoot);
    if (!await directory.exists()) {
      return 'Workspace root not found: $workspaceRoot';
    }
    return null;
  }

  String noWorkspaceError() {
    if (hasRemoteWorkspaceConnection) {
      return selectOrProvideRemoteWorkspaceMessage;
    }
    return 'No workspace is connected. Connect a local project folder in chat, connect to MacRemote in Settings > MacRemote Backend, or pass workspace_root explicitly.';
  }
}
