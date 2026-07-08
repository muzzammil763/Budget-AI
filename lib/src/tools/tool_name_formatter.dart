import 'package:budget_ai/src/tools/tool_settings.dart';

/// Returns a human-readable display name for any tool name string.
///
/// Priority:
/// 1. Exact match in [ToolSettings.tools] -> returns that tool's title.
/// 2. Snake_case fallback → each segment title-cased, joined with spaces.
String formatToolNameForUi(String rawName) {
  final trimmed = rawName.trim();
  if (trimmed.isEmpty) return 'Tool Call';

  for (final tool in ToolSettings.tools) {
    if (tool.name == trimmed) return tool.title;
  }

  if (!trimmed.contains('_')) {
    return trimmed.isEmpty
        ? 'Tool Call'
        : '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  return trimmed
      .split('_')
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}
