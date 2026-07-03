import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/presentation/widgets/delayed_marquee_text.dart';
import 'package:budget_ai/features/chat/domain/workspace_mentions.dart';

class WorkspaceMentionSuggestionsCard extends StatelessWidget {
  static const double itemExtent = 46;

  final List<WorkspaceMentionEntry> suggestions;
  final int activeIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onHoverSuggestion;
  final ValueChanged<int> onTapDownSuggestion;
  final ValueChanged<WorkspaceMentionEntry> onSuggestionSelected;

  const WorkspaceMentionSuggestionsCard({
    super.key,
    required this.suggestions,
    required this.activeIndex,
    required this.scrollController,
    required this.onHoverSuggestion,
    required this.onTapDownSuggestion,
    required this.onSuggestionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFieldTapRegion(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: Platform.isMacOS ? 240 : 140),
          child: ListView.builder(
            controller: scrollController,
            shrinkWrap: true,
            itemExtent: itemExtent,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final entry = suggestions[index];
              final isActive = index == activeIndex;
              return Material(
                color: isActive
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.transparent,
                child: InkWell(
                  radius: 48,
                  splashColor: AppTheme.highlight.withValues(alpha: 0.25),
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onTap: () => onSuggestionSelected(entry),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      spacing: 8,
                      children: [
                        _WorkspaceMentionIcon(entry: entry, isActive: isActive),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DelayedMarqueeText(
                                key: ValueKey(
                                  '${entry.workspaceRoot}:${entry.relativePath}',
                                ),
                                text: entry.relativePath,
                                style: AppTheme.bodyMedium.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                startDelay: const Duration(seconds: 2),
                                endPause: const Duration(milliseconds: 500),
                                pixelsPerSecond: 34,
                                endPadding: 0,
                              ),
                              if (entry.workspaceLabel.isNotEmpty)
                                Text(
                                  entry.workspaceLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodySmall.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkspaceMentionIcon extends StatelessWidget {
  final WorkspaceMentionEntry entry;
  final bool isActive;

  const _WorkspaceMentionIcon({required this.entry, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entry.isDirectory) {
      return Icon(
        CupertinoIcons.folder,
        size: 18,
        color: isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      );
    }

    final assetPath = _fileIconAssetPath(entry.relativePath);
    if (assetPath == null) {
      return Icon(
        CupertinoIcons.doc_text,
        size: 18,
        color: isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      );
    }

    return SizedBox(
      width: 18,
      height: 18,
      child: SvgPicture.asset(assetPath, fit: BoxFit.contain),
    );
  }

  String? _fileIconAssetPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    final iconName = switch (extension) {
      'css' => 'file_css',
      'dart' => 'file_dart',
      'go' => 'file_go',
      'html' || 'htm' => 'file_html',
      'java' => 'file_java',
      'js' || 'mjs' || 'cjs' => 'file_javascript',
      'json' => 'file_json',
      'kt' || 'kts' => 'file_kotlin',
      'py' => 'file_python',
      'swift' => 'file_swift',
      'ts' || 'tsx' => 'file_typescript',
      'yaml' || 'yml' => 'file_yaml',
      _ => null,
    };
    if (iconName == null) {
      return null;
    }
    return 'assets/icons/$iconName.svg';
  }
}
