import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart'
    show LinkBuilder;
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/tools/settings/tool_name_formatter.dart';
import 'package:budget_ai/features/chat/data/services/chat_provider.dart';
import 'package:budget_ai/features/chat/presentation/widgets/markdown_table_view.dart';
import 'package:budget_ai/features/chat/presentation/widgets/streaming_text_reveal.dart';
import 'package:budget_ai/core/widgets/themed_code_block.dart';

typedef MarkdownLinkTap = Future<void> Function(String url, String title);

class AgenticActivitySection extends StatefulWidget {
  final String durationLabel;
  final bool initiallyExpanded;
  final bool isInProgress;
  final bool forceCollapsed;
  final WidgetBuilder detailsBuilder;

  const AgenticActivitySection({
    super.key,
    required this.durationLabel,
    required this.initiallyExpanded,
    required this.isInProgress,
    this.forceCollapsed = false,
    required this.detailsBuilder,
  });

  @override
  State<AgenticActivitySection> createState() => _AgenticActivitySectionState();
}

class _AgenticActivitySectionState extends State<AgenticActivitySection> {
  static const double _horizontalInset = 12;

  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.forceCollapsed ? false : widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant AgenticActivitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceCollapsed) {
      if (_isExpanded) setState(() => _isExpanded = false);
      return;
    }
    if (oldWidget.isInProgress != widget.isInProgress) {
      setState(() => _isExpanded = widget.isInProgress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final railColor = theme.colorScheme.primary.withValues(alpha: 0.75);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          radius: 48,
          splashColor: AppTheme.highlight.withValues(alpha: 0.25),
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _horizontalInset,
              vertical: 8,
            ),
            child: Row(
              children: [
                Text(
                  widget.durationLabel,
                  style: AppTheme.bodyMedium.copyWith(
                    color: hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.isInProgress) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(hintColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: hintColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _isExpanded
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _horizontalInset,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: railColor,
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: widget.detailsBuilder(context),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class AgenticThinkingSection extends StatelessWidget {
  final String text;
  final Color themeColor;
  final bool isComplete;

  const AgenticThinkingSection({
    super.key,
    required this.text,
    required this.themeColor,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = AppTheme.bodyMedium.copyWith(
      color: theme.colorScheme.onSurface,
    );

    return Text(text, style: style);
  }
}

class AgenticProcessTextSection extends StatelessWidget {
  final String text;

  const AgenticProcessTextSection({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.primary;
    return Text(
      text,
      style: AppTheme.bodyMedium.copyWith(
        color: baseColor,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class AgenticToolCallSection extends StatelessWidget {
  final ToolCall toolCall;
  final Color themeColor;
  final bool isInProgress;
  final String Function(String text)? markdownNormalizer;
  final MarkdownLinkTap? onLinkTap;
  final LinkBuilder? linkBuilder;

  const AgenticToolCallSection({
    super.key,
    required this.toolCall,
    required this.themeColor,
    required this.isInProgress,
    this.markdownNormalizer,
    this.onLinkTap,
    this.linkBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return _SingleToolCallSection(
      toolCall: toolCall,
      themeColor: themeColor,
      isInProgress: isInProgress,
      markdownNormalizer: markdownNormalizer,
      onLinkTap: onLinkTap,
      linkBuilder: linkBuilder,
    );
  }
}

class AgenticToolCallGroupSection extends StatefulWidget {
  final List<ToolCall> toolCalls;
  final Color themeColor;
  final bool isInProgress;
  final String Function(String text)? markdownNormalizer;
  final MarkdownLinkTap? onLinkTap;
  final LinkBuilder? linkBuilder;

  const AgenticToolCallGroupSection({
    super.key,
    required this.toolCalls,
    required this.themeColor,
    required this.isInProgress,
    this.markdownNormalizer,
    this.onLinkTap,
    this.linkBuilder,
  });

  @override
  State<AgenticToolCallGroupSection> createState() =>
      _AgenticToolCallGroupSectionState();
}

class _AgenticToolCallGroupSectionState
    extends State<AgenticToolCallGroupSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
  }

  @override
  void didUpdateWidget(covariant AgenticToolCallGroupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final failedCount = widget.toolCalls
        .where((tool) => tool.status == ToolCallStatus.failed)
        .length;
    final completedCount = widget.toolCalls
        .where((tool) => tool.status == ToolCallStatus.completed)
        .length;
    final hasFailure = failedCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          radius: 48,
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  hasFailure
                      ? CupertinoIcons.info_circle
                      : widget.isInProgress
                      ? Icons.pending_outlined
                      : Icons.check_circle_outline,
                  size: 16,
                  color: hasFailure
                      ? Colors.red
                      : widget.isInProgress
                      ? widget.themeColor
                      : hintColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _buildGroupSummary(),
                    style: AppTheme.bodySmall.copyWith(
                      color: hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$completedCount/${widget.toolCalls.length}',
                  style: AppTheme.bodySmall.copyWith(
                    color: hintColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: hintColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final entry in _buildDisplayEntries())
                  if (entry.batch != null)
                    _CompactToolCallBatchSection(
                      toolCalls: entry.batch!,
                      themeColor: widget.themeColor,
                    )
                  else
                    AgenticToolCallSection(
                      toolCall: entry.toolCall!,
                      themeColor: widget.themeColor,
                      isInProgress: !entry.toolCall!.isComplete,
                      markdownNormalizer: widget.markdownNormalizer,
                      onLinkTap: widget.onLinkTap,
                      linkBuilder: widget.linkBuilder,
                    ),
              ],
            ),
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }

  String _buildGroupSummary() {
    final counts = <String, int>{};
    for (final toolCall in widget.toolCalls) {
      final label = formatToolNameForUi(toolCall.name);
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pieces = entries.take(3).map((entry) {
      return entry.value == 1 ? entry.key : '${entry.key} x${entry.value}';
    }).toList();
    final remaining = entries.length - pieces.length;
    final suffix = remaining > 0 ? ', +$remaining more' : '';
    return 'Ran ${widget.toolCalls.length} tool calls: ${pieces.join(', ')}$suffix';
  }

  List<_ToolCallBatchEntry> _buildDisplayEntries() {
    final entries = <_ToolCallBatchEntry>[];
    var index = 0;

    while (index < widget.toolCalls.length) {
      final toolCall = widget.toolCalls[index];
      final run = <ToolCall>[toolCall];
      var cursor = index + 1;
      while (cursor < widget.toolCalls.length &&
          _canCompactTogether(toolCall, widget.toolCalls[cursor])) {
        run.add(widget.toolCalls[cursor]);
        cursor++;
      }

      if (_shouldCompactRun(run)) {
        entries.add(_ToolCallBatchEntry.batch(run));
      } else {
        for (final item in run) {
          entries.add(_ToolCallBatchEntry.single(item));
        }
      }

      index = cursor;
    }

    return entries;
  }

  bool _canCompactTogether(ToolCall first, ToolCall next) {
    return first.name.trim().toLowerCase() == next.name.trim().toLowerCase();
  }

  bool _shouldCompactRun(List<ToolCall> run) {
    final name = run.first.name.trim().toLowerCase();
    if (name != 'read') return false;
    if (run.length < 2) return false;

    final signatures = run.map(_toolCallReadSignature).toSet();
    if (signatures.length == 1) return true;
    if (run.length < 5) return false;

    final paths = run
        .map(_toolCallPath)
        .where((path) => path != null && path.trim().isNotEmpty)
        .cast<String>()
        .toList();
    if (paths.length != run.length) return true;

    return paths.every((path) => path.toLowerCase().endsWith('.csv'));
  }
}

class _ToolCallBatchEntry {
  const _ToolCallBatchEntry.single(this.toolCall) : batch = null;
  const _ToolCallBatchEntry.batch(this.batch) : toolCall = null;

  final ToolCall? toolCall;
  final List<ToolCall>? batch;
}

class _CompactToolCallBatchSection extends StatefulWidget {
  final List<ToolCall> toolCalls;
  final Color themeColor;

  const _CompactToolCallBatchSection({
    required this.toolCalls,
    required this.themeColor,
  });

  @override
  State<_CompactToolCallBatchSection> createState() =>
      _CompactToolCallBatchSectionState();
}

class _CompactToolCallBatchSectionState
    extends State<_CompactToolCallBatchSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final failedCount = widget.toolCalls
        .where((tool) => tool.status == ToolCallStatus.failed)
        .length;
    final isInProgress = widget.toolCalls.any((tool) => !tool.isComplete);
    final pathCounts = <String, int>{};
    for (final toolCall in widget.toolCalls) {
      final path = _toolCallPath(toolCall);
      if (path == null || path.trim().isEmpty) continue;
      pathCounts[path] = (pathCounts[path] ?? 0) + 1;
    }
    final paths = pathCounts.keys.toList();
    final csvCount = paths
        .where((path) => path.toLowerCase().endsWith('.csv'))
        .length;
    final fileLabel = csvCount == widget.toolCalls.length
        ? 'CSV files'
        : 'files';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            radius: 48,
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    failedCount > 0
                        ? CupertinoIcons.xmark_circle
                        : isInProgress
                        ? Icons.pending_outlined
                        : CupertinoIcons.check_mark_circled,
                    size: 16,
                    color: failedCount > 0
                        ? Colors.red
                        : isInProgress
                        ? widget.themeColor
                        : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _buildReadBatchTitle(fileLabel),
                      style: AppTheme.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (failedCount > 0) ...[
                    Text(
                      '$failedCount failed',
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: hintColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 0, 8),
              child: Text(
                paths.isEmpty
                    ? '${widget.toolCalls.length} read calls'
                    : paths
                          .map((path) {
                            final count = pathCounts[path] ?? 1;
                            final suffix = count > 1 ? ' x$count' : '';
                            return '${_basename(path)}$suffix';
                          })
                          .join('\n'),
                style: AppTheme.bodySmall.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.45,
                  color: hintColor,
                ),
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  String _buildReadBatchTitle(String fileLabel) {
    final firstPath = _toolCallPath(widget.toolCalls.first);
    final sameTarget =
        widget.toolCalls.map(_toolCallReadSignature).toSet().length == 1;
    if (sameTarget && firstPath != null && firstPath.trim().isNotEmpty) {
      return 'Read ${_basename(firstPath)} x${widget.toolCalls.length}';
    }
    return 'Read ${widget.toolCalls.length} $fileLabel';
  }
}

class _ChangedFilesReview extends StatefulWidget {
  final String diff;

  const _ChangedFilesReview({required this.diff});

  @override
  State<_ChangedFilesReview> createState() => _ChangedFilesReviewState();
}

class _ChangedFilesReviewState extends State<_ChangedFilesReview> {
  bool _isExpanded = false;
  bool _isSplitView = false;
  late final List<_DiffFileSummary> _files = _parseUnifiedDiff(widget.diff);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = _files.isEmpty
        ? [
            _DiffFileSummary(
              path: 'Changes',
              added: _countAddedLines(widget.diff),
              removed: _countRemovedLines(widget.diff),
              lines: widget.diff.split('\n'),
            ),
          ]
        : _files;
    final fileLabel = files.length == 1 ? 'file changed' : 'files changed';
    final added = files.fold(0, (sum, file) => sum + file.added);
    final removed = files.fold(0, (sum, file) => sum + file.removed);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          InkWell(
            radius: 48,
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${files.length} $fileLabel',
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodySmall.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+$added',
                          style: AppTheme.bodySmall.copyWith(
                            color: Colors.green.shade400,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '-$removed',
                          style: AppTheme.bodySmall.copyWith(
                            color: Colors.red.shade400,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _isExpanded = true),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Review'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: theme.colorScheme.onSurface,
                      textStyle: AppTheme.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Row(
                    children: [
                      const Spacer(),
                      _DiffViewToggleButton(
                        selected: !_isSplitView,
                        tooltip: 'Switch to unified diff',
                        icon: Icons.view_stream_rounded,
                        onPressed: () => setState(() => _isSplitView = false),
                      ),
                      const SizedBox(width: 6),
                      _DiffViewToggleButton(
                        selected: _isSplitView,
                        tooltip: 'Switch to split diff',
                        icon: Icons.splitscreen_rounded,
                        onPressed: () => setState(() => _isSplitView = true),
                      ),
                    ],
                  ),
                ),
                for (var index = 0; index < files.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      color: theme.dividerColor.withValues(alpha: 0.16),
                    ),
                  _DiffFileSection(file: files[index], splitView: _isSplitView),
                ],
              ],
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _DiffViewToggleButton extends StatelessWidget {
  final bool selected;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _DiffViewToggleButton({
    required this.selected,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          color: theme.colorScheme.onSurfaceVariant,
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.65,
                  )
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiffFileSection extends StatefulWidget {
  final _DiffFileSummary file;
  final bool splitView;

  const _DiffFileSection({required this.file, required this.splitView});

  @override
  State<_DiffFileSection> createState() => _DiffFileSectionState();
}

class _DiffFileSectionState extends State<_DiffFileSection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          radius: 48,
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.file.path,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '+${widget.file.added}',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.green.shade400,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '-${widget.file.removed}',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: widget.splitView
                ? _SplitDiffView(file: widget.file)
                : _UnifiedDiffView(lines: widget.file.lines),
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}

class _UnifiedDiffView extends StatelessWidget {
  final List<String> lines;

  const _UnifiedDiffView({required this.lines});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleLines = _condenseDiffLines(lines);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in visibleLines)
              _DiffLine(
                line: line,
                width: 720,
                color: _diffLineColor(theme, line),
              ),
          ],
        ),
      ),
    );
  }
}

class _SplitDiffView extends StatelessWidget {
  final _DiffFileSummary file;

  const _SplitDiffView({required this.file});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _splitDiffRows(file.lines);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectionArea(
        child: Column(
          children: [
            for (final row in rows)
              Row(
                children: [
                  _DiffLine(
                    line: row.left,
                    width: 360,
                    color: row.left.startsWith('-')
                        ? Colors.red.withValues(alpha: 0.12)
                        : theme.colorScheme.surface.withValues(alpha: 0.2),
                  ),
                  _DiffLine(
                    line: row.right,
                    width: 360,
                    color: row.right.startsWith('+')
                        ? Colors.green.withValues(alpha: 0.12)
                        : theme.colorScheme.surface.withValues(alpha: 0.2),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  final String line;
  final double width;
  final Color color;

  const _DiffLine({
    required this.line,
    required this.width,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = line.startsWith('+')
        ? Colors.green.shade300
        : line.startsWith('-')
        ? Colors.red.shade300
        : theme.colorScheme.onSurface;
    return Container(
      width: width,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.visible,
        softWrap: false,
        style: AppTheme.bodySmall.copyWith(
          fontFamily: 'monospace',
          fontSize: 10.5,
          height: 1.35,
          color: textColor,
        ),
      ),
    );
  }
}

class _SingleToolCallSection extends StatefulWidget {
  final ToolCall toolCall;
  final Color themeColor;
  final bool isInProgress;
  final String Function(String text)? markdownNormalizer;
  final MarkdownLinkTap? onLinkTap;
  final LinkBuilder? linkBuilder;

  const _SingleToolCallSection({
    required this.toolCall,
    required this.themeColor,
    this.isInProgress = false,
    this.markdownNormalizer,
    this.onLinkTap,
    this.linkBuilder,
  });

  @override
  State<_SingleToolCallSection> createState() => _SingleToolCallSectionState();
}

class _SingleToolCallSectionState extends State<_SingleToolCallSection> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
  }

  @override
  void didUpdateWidget(covariant _SingleToolCallSection oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuccess = widget.toolCall.status == ToolCallStatus.completed;
    final isFailed = widget.toolCall.status == ToolCallStatus.failed;
    final isRunning = widget.isInProgress;
    final shouldRenderResult = _shouldRenderInlineResult();
    final shouldRenderArguments = _shouldRenderArguments();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            radius: 48,
            splashColor: AppTheme.highlight.withValues(alpha: 0.25),
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                spacing: 4,
                children: [
                  Icon(
                    isSuccess
                        ? CupertinoIcons.check_mark_circled
                        : isFailed
                        ? CupertinoIcons.xmark_circle
                        : isRunning
                        ? Icons.pending_outlined
                        : CupertinoIcons.info_circle,
                    size: 20,
                    color: isSuccess
                        ? Colors.green
                        : isFailed
                        ? Colors.red
                        : isRunning
                        ? widget.themeColor
                        : widget.themeColor,
                  ),
                  Expanded(
                    child: Text(
                      formatToolNameForUi(widget.toolCall.name),
                      style: AppTheme.bodySmall.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),

                  if (widget.isInProgress) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(widget.themeColor),
                      ),
                    ),
                  ],
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 22,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (shouldRenderArguments)
                    _buildToolDetailSection(
                      context,
                      child: _buildToolArgumentsContent(context),
                    ),
                  if (shouldRenderResult) ...[
                    if (shouldRenderArguments) const SizedBox(height: 8),
                    _buildToolDetailSection(
                      context,
                      child: _buildToolResultContent(context),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildToolDetailSection(
    BuildContext context, {
    required Widget child,
  }) {
    return SizedBox(width: double.infinity, child: child);
  }

  Widget _buildToolResultContent(BuildContext context) {
    final parsedResult = _tryDecodeJson(widget.toolCall.result);
    if (parsedResult is Map<String, dynamic>) {
      return _buildStructuredResult(context, parsedResult);
    }

    if (parsedResult is List) {
      return _buildJsonCodeBlock(
        context,
        parsedResult,
        title: 'Response',
        fontSize: 10,
      );
    }

    return _buildPlainTextContent(
      context,
      _formatToolResultText(widget.toolCall.result),
      title: 'Response',
    );
  }

  bool _shouldRenderInlineResult() {
    if (widget.toolCall.result == null) return false;
    return true;
  }

  bool _shouldRenderArguments() {
    if (_displayArguments(widget.toolCall.arguments).isNotEmpty) return true;
    return _hasNonEmptyRawArguments(widget.toolCall.rawArguments);
  }

  Widget _buildToolArgumentsContent(BuildContext context) {
    final arguments = _displayArguments(widget.toolCall.arguments);
    final rawArguments = widget.toolCall.rawArguments;

    if (arguments.isEmpty &&
        rawArguments != null &&
        _hasNonEmptyRawArguments(rawArguments)) {
      return _buildStreamingArgumentsText(context, _capIfCalling(rawArguments));
    }

    return _buildJsonCodeBlock(
      context,
      arguments,
      title: 'Arguments',
      fontSize: 12,
    );
  }

  bool _hasNonEmptyRawArguments(String? rawArguments) {
    final trimmed = rawArguments?.trim() ?? '';
    if (trimmed.isEmpty) return false;
    final decoded = _tryDecodeJson(trimmed);
    if (decoded is Map && decoded.isEmpty) return false;
    if (decoded is List && decoded.isEmpty) return false;
    return true;
  }

  Widget _buildStreamingArgumentsText(BuildContext context, String text) {
    final codeLike = _looksLikeCodeOrStructuredText(text);
    if (codeLike) {
      return _buildCodeContent(context, text, title: 'Arguments');
    }

    final theme = Theme.of(context);
    final isStreaming = widget.isInProgress && !widget.toolCall.isComplete;

    return StreamingTextReveal(
      text: text,
      isStreaming: isStreaming,
      style: AppTheme.bodyMedium.copyWith(
        color: theme.colorScheme.onSurface,
        fontSize: 14,
        fontStyle: FontStyle.italic,
        height: 1.5,
      ),
      cursorColor: theme.colorScheme.primary,
    );
  }

  // Truncates large text to 500 chars while the tool is still streaming its
  // arguments (status == calling). Once complete the full text is shown.
  String _capIfCalling(String text) {
    const int maxChars = 500;
    if (widget.toolCall.status != ToolCallStatus.calling) return text;
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n…';
  }

  Map<String, dynamic> _displayArguments(Map<String, dynamic> arguments) {
    final toolName = widget.toolCall.name.trim().toLowerCase();
    if (toolName != 'bash' || !arguments.containsKey('timeout')) {
      return arguments;
    }

    final displayArguments = Map<String, dynamic>.from(arguments);
    displayArguments['timeout'] = _estimatedBashTimeoutMs(displayArguments);
    return displayArguments;
  }

  int _estimatedBashTimeoutMs(Map<String, dynamic> arguments) {
    final command = (arguments['command'] as String? ?? '')
        .trim()
        .toLowerCase();
    final description = (arguments['description'] as String? ?? '')
        .trim()
        .toLowerCase();
    final combined = '$command $description';
    final requested = (arguments['timeout'] as num?)?.toInt();
    final estimate = _bashTimeoutEstimateForText(combined);
    if (requested == null) return estimate;

    final safeRequested = requested.clamp(1000, 120000);
    return safeRequested > estimate ? estimate : safeRequested;
  }

  int _bashTimeoutEstimateForText(String text) {
    if (RegExp(
      r'\b(deploy|release|archive|xcodebuild|docker\s+build|flutter\s+build|gradle\s+(assemble|build)|make\s+.*deploy|make\s+.*all)\b',
    ).hasMatch(text)) {
      return 120000;
    }

    if (RegExp(
      r'\b(npm|pnpm|yarn|bun|pip|bundle|pod|flutter\s+pub|dart\s+pub)\s+(install|get|add)\b',
    ).hasMatch(text)) {
      return 90000;
    }

    if (RegExp(
      r'\b(test|analyze|lint|check|build|make|cargo\s+test|go\s+test)\b',
    ).hasMatch(text)) {
      return 60000;
    }

    if (RegExp(r'\bgit\s+(clone|pull|push|fetch)\b').hasMatch(text)) {
      return 45000;
    }

    if (RegExp(
      r'\b(pwd|ls|cat|head|tail|rg|grep|find|git\s+status|git\s+diff|git\s+log)\b',
    ).hasMatch(text)) {
      return 10000;
    }

    return 30000;
  }

  bool _looksLikeCodeOrStructuredText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed.contains(r'\n') ||
        trimmed.contains('\n')) {
      return true;
    }
    return _isLikelyCodeFile('', trimmed);
  }

  Widget _buildStructuredResult(
    BuildContext context,
    Map<String, dynamic> result,
  ) {
    final normalizedResult = _normalizeStructuredResult(result);
    final content = normalizedResult['content'];
    final diff = result['diff'];
    final metadata = Map<String, dynamic>.from(normalizedResult)
      ..remove('content')
      ..remove('diff')
      ..remove('image_base64')
      ..remove('image_url');
    final hasContent = content is String && content.trim().isNotEmpty;
    final hasDiff = diff is String && diff.trim().isNotEmpty;

    if (!hasContent && !hasDiff) {
      return _buildJsonCodeBlock(
        context,
        metadata,
        title: 'Response',
        fontSize: 10,
      );
    }

    final children = <Widget>[];

    if (metadata.isNotEmpty) {
      children.add(
        _buildJsonCodeBlock(context, metadata, title: 'Response', fontSize: 10),
      );
      children.add(const SizedBox(height: 8));
    }

    if (hasContent) {
      children.add(_buildToolContentBody(context, normalizedResult, content));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Map<String, dynamic> _normalizeStructuredResult(Map<String, dynamic> result) {
    final normalized = Map<String, dynamic>.from(result);
    final file = result['file'];
    if (normalized['content'] == null && file is Map) {
      final fileMap = Map<String, dynamic>.from(file);
      final fileContent = fileMap['content'];
      if (fileContent is String && fileContent.isNotEmpty) {
        normalized['content'] = fileContent;
        for (final key in const [
          'path',
          'absolute_path',
          'start_line',
          'end_line',
          'line_count',
          'size_bytes',
        ]) {
          if (!normalized.containsKey(key) && fileMap.containsKey(key)) {
            normalized[key] = fileMap[key];
          }
        }
        normalized.remove('file');
      }
    }

    final preview = normalized['content_preview'];
    if (normalized['content'] == null && preview is String) {
      normalized['content'] = preview;
      normalized.remove('content_preview');
    }

    return normalized;
  }

  String _stripMarkdownImages(String text) {
    return text
        .replaceAll(RegExp(r'!\[[^\]]*\]\(https?:\/\/[^\s\)]+\)'), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\(data:image\/[^\n)]*\)?'), '');
  }

  Widget _buildToolContentBody(
    BuildContext context,
    Map<String, dynamic> result,
    String content,
  ) {
    final normalizedPath =
        (result['path'] ?? widget.toolCall.arguments['path'] ?? '')
            .toString()
            .toLowerCase();
    final isMarkdownFile =
        normalizedPath.endsWith('.md') || normalizedPath.endsWith('.markdown');
    final isCodeFile = _isLikelyCodeFile(normalizedPath, content);
    final cleanContent = _stripMarkdownImages(content);

    final contentTitle = isMarkdownFile
        ? 'Content Preview'
        : isCodeFile
        ? 'Code Content'
        : 'Content';
    Widget contentWidget;
    if (isMarkdownFile) {
      contentWidget = _buildToolMarkdown(context, cleanContent);
    } else if (isCodeFile) {
      contentWidget = _buildCodeContent(
        context,
        cleanContent,
        title: contentTitle,
      );
    } else {
      contentWidget = _buildPlainTextContent(
        context,
        cleanContent,
        title: contentTitle,
      );
    }

    if (!isMarkdownFile) return contentWidget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isMarkdownFile
              ? 'Content Preview'
              : isCodeFile
              ? 'Code Content'
              : 'Content',
          style: AppTheme.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        contentWidget,
      ],
    );
  }

  bool _isLikelyCodeFile(String path, String content) {
    final codeExtensions = [
      '.dart',
      '.py',
      '.js',
      '.ts',
      '.tsx',
      '.jsx',
      '.java',
      '.kt',
      '.swift',
      '.c',
      '.cpp',
      '.h',
      '.hpp',
      '.cs',
      '.go',
      '.rs',
      '.rb',
      '.php',
      '.html',
      '.css',
      '.scss',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.sql',
      '.sh',
      '.bash',
      '.md',
      '.markdown',
      '.txt',
      '.log',
      '.env',
      '.gitignore',
      '.dockerfile',
    ];

    final pathLower = path.toLowerCase();
    for (final ext in codeExtensions) {
      if (pathLower.endsWith(ext)) return true;
    }

    // Also detect code patterns in content
    final codePatterns = [
      RegExp(r'^\s*(import|export|from|require|use|include|namespace)\s'),
      RegExp(
        r'^\s*(class|struct|interface|enum|fn|def|function|const|let|var)\s',
      ),
      RegExp(
        r'^\s*(if|else|for|while|switch|match|return|throw|try|catch)\s*[\(\{]',
      ),
      RegExp(r'^\s*(public|private|protected|static|async|await)\s'),
      RegExp(r'\{[\s\S]*\}:[\s\S]*;'),
      RegExp(r'=>'),
      RegExp(r'^\s*///\s', multiLine: true),
      RegExp(r'^\s*//\s', multiLine: true),
      RegExp(r'^\s*#\s', multiLine: true),
    ];

    final lines = content.split('\n');
    int patternMatches = 0;
    for (final line in lines.take(10)) {
      for (final pattern in codePatterns) {
        if (pattern.hasMatch(line)) patternMatches++;
      }
    }

    return patternMatches >= 2 ||
        content.contains('\n\n') && content.length > 100;
  }

  Widget _buildCodeContent(
    BuildContext context,
    String content, {
    String title = 'Code Content',
  }) {
    final language = _detectLanguage(content, _targetPathForToolCall());

    return ThemedCodeBlock(
      name: language.toLowerCase(),
      code: content,
      closed: true,
      fontSize: 12,
      contentPadding: 8,
      borderRadius: 8,
      headerHeight: 34,
      showHeader: true,
      headerTitle: title,
      showHeaderIcon: false,
      showCopyAction: false,
      showLineNumbers: false,
      selectable: false,
      showZoom: false,
    );
  }

  String _detectLanguage(String content, String path) {
    final pathLower = path.toLowerCase();
    if (pathLower.endsWith('.dart')) return 'Dart';
    if (pathLower.endsWith('.py')) return 'Python';
    if (pathLower.endsWith('.js')) return 'JavaScript';
    if (pathLower.endsWith('.ts') || pathLower.endsWith('.tsx')) {
      return 'TypeScript';
    }
    if (pathLower.endsWith('.java')) return 'Java';
    if (pathLower.endsWith('.kt')) return 'Kotlin';
    if (pathLower.endsWith('.swift')) return 'Swift';
    if (pathLower.endsWith('.go')) return 'Go';
    if (pathLower.endsWith('.rs')) return 'Rust';
    if (pathLower.endsWith('.rb')) return 'Ruby';
    if (pathLower.endsWith('.php')) return 'PHP';
    if (pathLower.endsWith('.cs')) return 'C#';
    if (pathLower.endsWith('.cpp') || pathLower.endsWith('.cc')) return 'C++';
    if (pathLower.endsWith('.c')) return 'C';
    if (pathLower.endsWith('.html')) return 'HTML';
    if (pathLower.endsWith('.css')) return 'CSS';
    if (pathLower.endsWith('.scss')) return 'SCSS';
    if (pathLower.endsWith('.json')) return 'JSON';
    if (pathLower.endsWith('.yaml') || pathLower.endsWith('.yml')) {
      return 'YAML';
    }
    if (pathLower.endsWith('.xml')) return 'XML';
    if (pathLower.endsWith('.sql')) return 'SQL';
    if (pathLower.endsWith('.sh') || pathLower.endsWith('.bash')) {
      return 'Shell';
    }
    if (pathLower.endsWith('.md')) return 'Markdown';

    // Try to detect from content patterns
    if (content.contains("import 'package:")) return 'Dart';
    if (content.contains('def ') && content.contains(':')) return 'Python';
    if (content.contains('function ') || content.contains('const ')) {
      return 'JavaScript';
    }
    if (content.contains('func ') && content.contains('->')) return 'Go';
    if (content.contains('fn ') && content.contains('->')) return 'Rust';

    return 'Text';
  }

  String _targetPathForToolCall() {
    final arguments = widget.toolCall.arguments;
    return (arguments['path'] ??
                arguments['filePath'] ??
                arguments['file_path'])
            ?.toString() ??
        '';
  }

  Widget _buildPlainTextContent(
    BuildContext context,
    String content, {
    String title = 'Content',
  }) {
    return ThemedCodeBlock(
      name: 'text',
      code: content,
      closed: false,
      fontSize: 12,
      contentPadding: 8,
      borderRadius: 8,
      headerHeight: 34,
      showHeader: true,
      headerTitle: title,
      showHeaderIcon: false,
      showCopyAction: false,
      showLineNumbers: false,
      selectable: false,
      showZoom: false,
    );
  }

  Widget _buildToolMarkdown(BuildContext context, String text) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final normalizedText = widget.markdownNormalizer?.call(text) ?? text;

    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          headlineLarge: AppTheme.headingLarge.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          headlineMedium: AppTheme.headingMedium.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          headlineSmall: AppTheme.headingSmall.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          bodyMedium: AppTheme.bodyMedium.copyWith(
            fontSize: 14,
            color: textColor,
            height: 1.5,
          ),
        ),
      ),
      child: GptMarkdown(
        normalizedText,
        textAlign: TextAlign.start,
        style: AppTheme.bodyMedium.copyWith(
          color: textColor,
          fontSize: 14,
          height: 1.5,
        ),
        codeBuilder: (context, name, code, closed) {
          return ThemedCodeBlock(name: name, code: code);
        },
        onLinkTap: widget.onLinkTap,
        linkBuilder: widget.linkBuilder,
        tableBuilder: buildStyledMarkdownTable,
      ),
    );
  }

  Widget _buildJsonCodeBlock(
    BuildContext context,
    Object? jsonValue, {
    String title = 'JSON',
    double fontSize = 12,
    double? maxHeight,
  }) {
    final code = const JsonEncoder.withIndent(
      '  ',
    ).convert(_normalizeJsonValue(jsonValue));

    return ThemedCodeBlock(
      name: 'json',
      code: code,
      closed: false,
      fontSize: fontSize,
      headerHeight: 32,
      contentPadding: 8,
      borderRadius: 8,
      maxHeight: maxHeight,
      showHeader: true,
      headerTitle: title,
      showHeaderIcon: false,
      showCopyAction: false,
      showLineNumbers: false,
      selectable: false,
      showZoom: false,
    );
  }

  Object? _normalizeJsonValue(Object? value) {
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), _normalizeJsonValue(val)),
      );
    }
    if (value is List) {
      return value.map(_normalizeJsonValue).toList();
    }
    return value;
  }

  dynamic _tryDecodeJson(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return null;
    if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;

    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  String _formatToolResultText(dynamic result) {
    if (result == null) return 'No result';

    if (result is String) {
      final trimmed = result.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          const encoder = JsonEncoder.withIndent('  ');
          return encoder.convert(jsonDecode(trimmed));
        } catch (_) {
          return _compactFallbackToolText(trimmed);
        }
      }
      return _compactFallbackToolText(trimmed);
    }

    if (result is Map || result is List) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(result);
    }

    return result.toString();
  }

  String _compactFallbackToolText(String text) {
    return text;
  }
}

String? _toolCallPath(ToolCall toolCall) {
  final arguments = toolCall.arguments;
  for (final key in ['filePath', 'path']) {
    final value = arguments[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String _toolCallReadSignature(ToolCall toolCall) {
  final arguments = toolCall.arguments;
  final path = (_toolCallPath(toolCall) ?? '').trim();
  final offset = arguments['offset']?.toString().trim() ?? '';
  final limit = arguments['limit']?.toString().trim() ?? '';
  return '$path|$offset|$limit';
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/').where((part) => part.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}

class _DiffFileSummary {
  const _DiffFileSummary({
    required this.path,
    required this.added,
    required this.removed,
    required this.lines,
  });

  final String path;
  final int added;
  final int removed;
  final List<String> lines;
}

class _SplitDiffRow {
  const _SplitDiffRow({required this.left, required this.right});

  final String left;
  final String right;
}

List<_DiffFileSummary> _parseUnifiedDiff(String diff) {
  final lines = diff.split('\n');
  final files = <_DiffFileSummary>[];
  String? path;
  final buffer = <String>[];
  var hasGitHeaderForCurrentFile = false;

  void flush() {
    if (path == null && buffer.isEmpty) return;
    final fileLines = List<String>.from(buffer);
    files.add(
      _DiffFileSummary(
        path: path ?? 'Changes',
        added: _countAddedLines(fileLines.join('\n')),
        removed: _countRemovedLines(fileLines.join('\n')),
        lines: fileLines,
      ),
    );
    buffer.clear();
    hasGitHeaderForCurrentFile = false;
  }

  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      flush();
      path = _pathFromGitDiffHeader(line) ?? 'Changes';
      hasGitHeaderForCurrentFile = true;
      buffer.add(line);
      continue;
    }

    if (line.startsWith('--- ')) {
      if (!hasGitHeaderForCurrentFile) {
        flush();
        path = null;
      }
      buffer.add(line);
      continue;
    }

    if (line.startsWith('+++ ')) {
      path = _normalizeDiffPath(line.substring(4).trim());
      buffer.add(line);
      continue;
    }

    buffer.add(line);
  }

  flush();
  return files
      .where((file) => file.lines.any((line) => line.trim().isNotEmpty))
      .toList();
}

String _normalizeDiffPath(String rawPath) {
  if (rawPath == '/dev/null') return 'New file';
  return rawPath.replaceFirst(RegExp(r'^[ab]/'), '');
}

String? _pathFromGitDiffHeader(String line) {
  final match = RegExp(r'^diff --git a/(.+?) b/(.+)$').firstMatch(line);
  return match?.group(2);
}

int _countAddedLines(String diff) {
  return diff
      .split('\n')
      .where((line) => line.startsWith('+') && !line.startsWith('+++'))
      .length;
}

int _countRemovedLines(String diff) {
  return diff
      .split('\n')
      .where((line) => line.startsWith('-') && !line.startsWith('---'))
      .length;
}

List<String> _condenseDiffLines(List<String> lines) {
  final output = <String>[];
  var unchangedRun = 0;

  void flushRun() {
    if (unchangedRun <= 0) return;
    if (unchangedRun > 6) {
      output.add('  ... $unchangedRun unmodified lines');
    }
    unchangedRun = 0;
  }

  for (final line in lines) {
    final isHeader =
        line.startsWith('---') ||
        line.startsWith('+++') ||
        line.startsWith('@@');
    final isChange = line.startsWith('+') || line.startsWith('-');
    if (!isHeader && !isChange && line.trim().isNotEmpty) {
      unchangedRun++;
      if (unchangedRun <= 3) output.add(' $line');
      continue;
    }

    flushRun();
    output.add(line);
  }

  flushRun();
  return output;
}

Color _diffLineColor(ThemeData theme, String line) {
  if (line.startsWith('+') && !line.startsWith('+++')) {
    return Colors.green.withValues(alpha: 0.12);
  }
  if (line.startsWith('-') && !line.startsWith('---')) {
    return Colors.red.withValues(alpha: 0.12);
  }
  if (line.startsWith('@@')) {
    return theme.colorScheme.primary.withValues(alpha: 0.08);
  }
  return theme.colorScheme.surface.withValues(alpha: 0.2);
}

List<_SplitDiffRow> _splitDiffRows(List<String> lines) {
  final rows = <_SplitDiffRow>[];
  for (final line in _condenseDiffLines(lines)) {
    if (line.startsWith('---') || line.startsWith('+++')) continue;
    if (line.startsWith('-')) {
      rows.add(_SplitDiffRow(left: line, right: ''));
    } else if (line.startsWith('+')) {
      rows.add(_SplitDiffRow(left: '', right: line));
    } else {
      rows.add(_SplitDiffRow(left: line, right: line));
    }
  }
  return rows;
}
