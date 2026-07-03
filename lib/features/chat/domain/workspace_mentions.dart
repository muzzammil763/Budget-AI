import 'dart:math' as math;

import 'package:flutter/widgets.dart';

const Set<String> kIgnoredWorkspaceMentionDirectoryNames = {
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
  'Pods',
  '.symlinks',
  'ephemeral',
};

class WorkspaceMentionQuery {
  final int start;
  final int end;
  final String query;

  const WorkspaceMentionQuery({
    required this.start,
    required this.end,
    required this.query,
  });
}

class ResolvedWorkspaceMention {
  final String trigger;
  final WorkspaceMentionEntry entry;

  const ResolvedWorkspaceMention({required this.trigger, required this.entry});
}

class WorkspaceMentionEntry {
  final String relativePath;
  final bool isDirectory;
  final String workspaceRoot;
  final String workspaceLabel;
  final String workspaceSource;
  final String mentionToken;
  final String displayName;
  final String parentPath;
  final String relativePathLower;
  final String mentionTokenLower;
  final String displayNameLower;
  final String workspaceLabelLower;
  final List<String> pathSegmentsLower;
  final int depth;

  const WorkspaceMentionEntry({
    required this.relativePath,
    required this.isDirectory,
    required this.workspaceRoot,
    required this.workspaceLabel,
    required this.workspaceSource,
    required this.mentionToken,
    required this.displayName,
    required this.parentPath,
    required this.relativePathLower,
    required this.mentionTokenLower,
    required this.displayNameLower,
    required this.workspaceLabelLower,
    required this.pathSegmentsLower,
    required this.depth,
  });

  factory WorkspaceMentionEntry.fromRelativePath(
    String relativePath, {
    required bool isDirectory,
    String workspaceRoot = '',
    String workspaceLabel = '',
    String workspaceSource = '',
    bool includeWorkspaceInMention = false,
  }) {
    final normalized = relativePath.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    final displayName = segments.isEmpty ? normalized : segments.last;
    final parentSegments = segments.length <= 1
        ? const <String>[]
        : segments.sublist(0, segments.length - 1);
    final normalizedWorkspaceLabel = workspaceLabel.trim();
    final mentionPrefix = _sanitizeWorkspaceMentionPrefix(
      normalizedWorkspaceLabel.isEmpty
          ? workspaceRoot
          : normalizedWorkspaceLabel,
    );
    final mentionToken = includeWorkspaceInMention && mentionPrefix.isNotEmpty
        ? '$mentionPrefix/$normalized'
        : normalized;

    return WorkspaceMentionEntry(
      relativePath: normalized,
      isDirectory: isDirectory,
      workspaceRoot: workspaceRoot.trim(),
      workspaceLabel: normalizedWorkspaceLabel,
      workspaceSource: workspaceSource.trim(),
      mentionToken: mentionToken,
      displayName: displayName,
      parentPath: parentSegments.join('/'),
      relativePathLower: normalized.toLowerCase(),
      mentionTokenLower: mentionToken.toLowerCase(),
      displayNameLower: displayName.toLowerCase(),
      workspaceLabelLower: normalizedWorkspaceLabel.toLowerCase(),
      pathSegmentsLower: segments
          .map((segment) => segment.toLowerCase())
          .toList(),
      depth: math.max(0, segments.length - 1),
    );
  }

  String get subtitle {
    if (workspaceLabel.isNotEmpty) {
      if (parentPath.isEmpty) {
        return workspaceLabel;
      }
      return '$workspaceLabel / $relativePath';
    }
    if (parentPath.isEmpty) {
      return isDirectory ? 'workspace root' : 'root';
    }
    return relativePath;
  }
}

String _sanitizeWorkspaceMentionPrefix(String value) {
  final segments = value
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  if (segments.isEmpty) return '';
  return segments.last.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-');
}

bool shouldIgnoreWorkspaceMentionPath(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty);
  for (final segment in segments) {
    if (kIgnoredWorkspaceMentionDirectoryNames.contains(segment)) {
      return true;
    }
  }
  return false;
}

int compareWorkspaceMentionEntries(
  WorkspaceMentionEntry a,
  WorkspaceMentionEntry b,
) {
  if (a.isDirectory != b.isDirectory) {
    return a.isDirectory ? -1 : 1;
  }
  final workspaceCompare = a.workspaceLabelLower.compareTo(
    b.workspaceLabelLower,
  );
  if (workspaceCompare != 0) return workspaceCompare;
  final depthCompare = a.depth.compareTo(b.depth);
  if (depthCompare != 0) return depthCompare;
  final nameCompare = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  if (nameCompare != 0) return nameCompare;
  return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
}

WorkspaceMentionQuery? currentWorkspaceMentionQuery(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) {
    return null;
  }

  final cursor = selection.extentOffset;
  if (cursor < 0 || cursor > value.text.length) {
    return null;
  }

  var start = cursor - 1;
  while (start >= 0) {
    final char = value.text[start];
    if (char == '@' || _isWorkspaceMentionTokenChar(char)) {
      start--;
      continue;
    }
    break;
  }
  start += 1;

  if (start >= cursor || start >= value.text.length) {
    return null;
  }

  final token = value.text.substring(start, cursor);
  if (!token.startsWith('@') || token.substring(1).contains('@')) {
    return null;
  }

  if (start > 0) {
    final previous = value.text[start - 1];
    if (!_isWorkspaceMentionBoundary(previous)) {
      return null;
    }
  }

  return WorkspaceMentionQuery(
    start: start,
    end: cursor,
    query: token.substring(1),
  );
}

List<WorkspaceMentionEntry> findWorkspaceMentionSuggestions({
  required List<WorkspaceMentionEntry> entries,
  required String query,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final ranked = <_WorkspaceMentionCandidate>[];
  for (final entry in entries) {
    final score = _workspaceMentionScore(entry, normalizedQuery);
    if (score == null) {
      continue;
    }
    ranked.add(_WorkspaceMentionCandidate(entry: entry, score: score));
  }

  ranked.sort((a, b) {
    final scoreCompare = a.score.compareTo(b.score);
    if (scoreCompare != 0) return scoreCompare;
    return compareWorkspaceMentionEntries(a.entry, b.entry);
  });

  return ranked.take(20).map((item) => item.entry).toList();
}

bool sameWorkspaceSuggestionList(
  List<WorkspaceMentionEntry> current,
  List<WorkspaceMentionEntry> next,
) {
  if (identical(current, next)) return true;
  if (current.length != next.length) return false;
  for (var i = 0; i < current.length; i++) {
    if (current[i].relativePath != next[i].relativePath ||
        current[i].workspaceRoot != next[i].workspaceRoot ||
        current[i].isDirectory != next[i].isDirectory) {
      return false;
    }
  }
  return true;
}

String prepareWorkspaceMentionsForProvider({
  required String message,
  required List<WorkspaceMentionEntry> entries,
}) {
  final resolutions = resolveWorkspaceMentionTokens(
    text: message,
    entries: entries,
  );
  if (resolutions.isEmpty) {
    return message;
  }

  final buffer = StringBuffer(message);
  buffer.write(
    '\n\nTreat these @mentions as workspace paths inside connected projects:\n',
  );
  for (final resolution in resolutions) {
    final workspace = resolution.entry.workspaceRoot.trim();
    final label = resolution.entry.workspaceLabel.trim();
    final workspaceText = workspace.isEmpty
        ? ''
        : ' in ${label.isEmpty ? 'workspace' : label} at `$workspace`';
    buffer.writeln(
      '- ${resolution.trigger} -> ${resolution.entry.relativePath}$workspaceText (${resolution.entry.isDirectory ? 'directory' : 'file'})',
    );
  }
  return buffer.toString().trimRight();
}

List<ResolvedWorkspaceMention> resolveWorkspaceMentionTokens({
  required String text,
  required List<WorkspaceMentionEntry> entries,
}) {
  if (entries.isEmpty) {
    return const [];
  }

  final matches = RegExp(
    r"(^|[\s(\[{<'])@([A-Za-z0-9_./-]+)",
    multiLine: true,
  ).allMatches(text);

  final resolved = <ResolvedWorkspaceMention>[];
  final seenTriggers = <String>{};

  for (final match in matches) {
    final token = match.group(2)?.trim() ?? '';
    if (token.isEmpty) {
      continue;
    }
    final trigger = '@$token';
    if (!seenTriggers.add(trigger.toLowerCase())) {
      continue;
    }

    final entry = resolveWorkspaceMentionEntry(token: token, entries: entries);
    if (entry == null) {
      continue;
    }
    resolved.add(ResolvedWorkspaceMention(trigger: trigger, entry: entry));
  }

  return resolved;
}

WorkspaceMentionEntry? resolveWorkspaceMentionEntry({
  required String token,
  required List<WorkspaceMentionEntry> entries,
}) {
  final normalized = token.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }

  final exactPathMatches = entries
      .where(
        (entry) =>
            entry.relativePathLower == normalized ||
            entry.mentionTokenLower == normalized,
      )
      .toList();
  if (exactPathMatches.length == 1) {
    return exactPathMatches.first;
  }

  final exactNameMatches = entries
      .where((entry) => entry.displayNameLower == normalized)
      .toList();
  if (exactNameMatches.length == 1) {
    return exactNameMatches.first;
  }

  final suggestions = findWorkspaceMentionSuggestions(
    entries: entries,
    query: token,
  );
  if (suggestions.length == 1) {
    return suggestions.first;
  }

  return null;
}

bool _isWorkspaceMentionTokenChar(String value) {
  return RegExp(r'[A-Za-z0-9_./-]').hasMatch(value);
}

bool _isWorkspaceMentionBoundary(String value) {
  return RegExp(r'\s').hasMatch(value) || '([{"\'<'.contains(value);
}

int? _workspaceMentionScore(WorkspaceMentionEntry entry, String query) {
  if (query.isEmpty) {
    return entry.depth + (entry.isDirectory ? 0 : 2);
  }

  final basename = entry.displayNameLower;
  final fullPath = entry.relativePathLower;
  final mentionToken = entry.mentionTokenLower;
  final workspaceLabel = entry.workspaceLabelLower;
  final segments = entry.pathSegmentsLower;
  final compactQuery = _compactWorkspaceMentionText(query);
  final compactBasename = _compactWorkspaceMentionText(basename);
  final compactFullPath = _compactWorkspaceMentionText(fullPath);
  final compactMentionToken = _compactWorkspaceMentionText(mentionToken);
  final compactWorkspaceLabel = _compactWorkspaceMentionText(workspaceLabel);
  final compactSegments = segments.map(_compactWorkspaceMentionText);

  if (fullPath == query) return entry.isDirectory ? 0 : 1;
  if (mentionToken == query) return entry.isDirectory ? 0 : 1;
  if (workspaceLabel == query) return 1;
  if (basename == query) return 2;
  if (compactQuery.isNotEmpty && compactBasename == compactQuery) return 2;
  if (compactQuery.isNotEmpty && compactMentionToken == compactQuery) {
    return entry.isDirectory ? 2 : 3;
  }
  if (workspaceLabel.startsWith(query)) return 2;
  if (compactQuery.isNotEmpty &&
      compactWorkspaceLabel.startsWith(compactQuery)) {
    return 2;
  }
  if (basename.startsWith(query)) return 3;
  if (compactQuery.isNotEmpty && compactBasename.startsWith(compactQuery)) {
    return 3;
  }
  if (segments.any((segment) => segment.startsWith(query))) return 4;
  if (compactQuery.isNotEmpty &&
      compactSegments.any((segment) => segment.startsWith(compactQuery))) {
    return 4;
  }
  if (mentionToken.startsWith(query)) return 4;
  if (compactQuery.isNotEmpty && compactMentionToken.startsWith(compactQuery)) {
    return 4;
  }
  if (fullPath.startsWith(query)) return 5;
  if (compactQuery.isNotEmpty && compactFullPath.startsWith(compactQuery)) {
    return 5;
  }
  if (basename.contains(query)) return 6;
  if (compactQuery.isNotEmpty && compactBasename.contains(compactQuery)) {
    return 6;
  }
  if (workspaceLabel.contains(query)) return 6;
  if (compactQuery.isNotEmpty && compactWorkspaceLabel.contains(compactQuery)) {
    return 6;
  }
  if (mentionToken.contains(query)) return 7;
  if (compactQuery.isNotEmpty && compactMentionToken.contains(compactQuery)) {
    return 7;
  }
  if (fullPath.contains(query)) return 7;
  if (compactQuery.isNotEmpty && compactFullPath.contains(compactQuery)) {
    return 7;
  }
  return null;
}

String _compactWorkspaceMentionText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _WorkspaceMentionCandidate {
  final WorkspaceMentionEntry entry;
  final int score;

  const _WorkspaceMentionCandidate({required this.entry, required this.score});
}
