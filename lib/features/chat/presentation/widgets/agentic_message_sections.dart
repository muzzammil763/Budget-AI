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
typedef CommandApprovalResolved =
    Future<void> Function(ToolCall toolCall, Map<String, dynamic> result);

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
  static const double _horizontalInset = 8;

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
    final baseColor = Theme.of(context).colorScheme.primary;
    final style = AppTheme.bodyMedium.copyWith(
      color: baseColor,
      fontStyle: FontStyle.italic,
    );

    if (isComplete) {
      // Show completed thinking as plain text so it remains visible
      return Text(text, style: style);
    }

    // While streaming, show the actual reasoning text live
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
  final CommandApprovalResolved? onCommandApprovalResolved;
  final bool approvalOnly;

  const AgenticToolCallSection({
    super.key,
    required this.toolCall,
    required this.themeColor,
    required this.isInProgress,
    this.markdownNormalizer,
    this.onLinkTap,
    this.linkBuilder,
    this.onCommandApprovalResolved,
    this.approvalOnly = false,
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
      onCommandApprovalResolved: onCommandApprovalResolved,
      approvalOnly: approvalOnly,
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
  final CommandApprovalResolved? onCommandApprovalResolved;
  final bool approvalOnly;

  const AgenticToolCallGroupSection({
    super.key,
    required this.toolCalls,
    required this.themeColor,
    required this.isInProgress,
    this.markdownNormalizer,
    this.onLinkTap,
    this.linkBuilder,
    this.onCommandApprovalResolved,
    this.approvalOnly = false,
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
            padding: const EdgeInsets.symmetric(vertical: 8),
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
                      onCommandApprovalResolved:
                          widget.onCommandApprovalResolved,
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

    return SizedBox(
      width: double.infinity,
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
  final CommandApprovalResolved? onCommandApprovalResolved;
  final bool approvalOnly;

  const _SingleToolCallSection({
    required this.toolCall,
    required this.themeColor,
    this.isInProgress = false,
    this.markdownNormalizer,
    this.onLinkTap,
    this.linkBuilder,
    this.onCommandApprovalResolved,
    this.approvalOnly = false,
  });

  @override
  State<_SingleToolCallSection> createState() => _SingleToolCallSectionState();
}

class _SingleToolCallSectionState extends State<_SingleToolCallSection> {
  bool _isExpanded = false;

  bool get _isAwaitingApproval =>
      widget.toolCall.status == ToolCallStatus.awaitingApproval;

  bool get _isWorkspaceMutationTool {
    final name = widget.toolCall.name.trim().toLowerCase();
    return name == 'write' || name == 'edit';
  }

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
  }

  @override
  void didUpdateWidget(covariant _SingleToolCallSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Approval state is reflected by the row icon/status. Keep expansion under
    // direct user control so approval sheets do not reshape the timeline.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final isSuccess = widget.toolCall.status == ToolCallStatus.completed;
    final isFailed = widget.toolCall.status == ToolCallStatus.failed;
    final isAwaitingApproval = _isAwaitingApproval;
    final isRunning = widget.isInProgress && !isAwaitingApproval;
    final shouldRenderResult = _shouldRenderInlineResult();
    final shouldRenderArguments = _shouldRenderArguments();
    if (widget.approvalOnly) {
      return _buildToolResultContent(context);
    }

    return SizedBox(
      width: double.infinity,
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                spacing: 6,
                children: [
                  Icon(
                    isSuccess
                        ? CupertinoIcons.check_mark_circled
                        : isFailed
                        ? CupertinoIcons.xmark_circle
                        : isAwaitingApproval
                        ? Icons.pending_outlined
                        : isRunning
                        ? Icons.pending_outlined
                        : CupertinoIcons.info_circle,
                    size: 18,
                    color: isSuccess
                        ? Colors.green
                        : isFailed
                        ? Colors.red
                        : isAwaitingApproval
                        ? Colors.orange
                        : isRunning
                        ? widget.themeColor
                        : widget.themeColor,
                  ),
                  Expanded(
                    child: Text(
                      formatToolNameForUi(widget.toolCall.name),
                      style: AppTheme.bodySmall.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),

                  if (widget.isInProgress && !isAwaitingApproval) ...[
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
      if (parsedResult['approval_required'] == true &&
          parsedResult['approval_request'] is Map) {
        final hasDecision =
            parsedResult['approval_decision'] == 'approved' ||
            parsedResult['approval_decision'] == 'denied';
        if (!widget.approvalOnly && !hasDecision) {
          return const SizedBox.shrink();
        }
        if (widget.approvalOnly && hasDecision) {
          return const SizedBox.shrink();
        }
        return _buildApprovalRequiredResult(context, parsedResult);
      }
      if (parsedResult['status'] == 'awaiting_preflight_approval') {
        return _buildAgentPreflightApproval(context, parsedResult);
      }
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
    if (widget.approvalOnly) return true;

    final parsedResult = _tryDecodeJson(widget.toolCall.result);
    if (parsedResult is Map<String, dynamic> &&
        parsedResult['approval_required'] == true &&
        parsedResult['approval_request'] is Map) {
      final decision = parsedResult['approval_decision']?.toString();
      return decision == 'approved' || decision == 'denied';
    }

    return true;
  }

  bool _shouldRenderArguments() {
    if (_displayArguments(widget.toolCall.arguments).isNotEmpty) return true;
    return _hasNonEmptyRawArguments(widget.toolCall.rawArguments);
  }

  Widget _buildToolArgumentsContent(BuildContext context) {
    final arguments = _displayArguments(widget.toolCall.arguments);
    final content = arguments['content'];
    final newText = arguments['new_text'];
    final oldText = arguments['old_text'];
    final contextText = arguments['context_text'];
    final anchorText = arguments['anchor_text'];
    final edits = arguments['edits'];
    final rawArguments = widget.toolCall.rawArguments;
    final hasWritableContent = content is String && content.isNotEmpty;
    final hasNewText = newText is String && newText.isNotEmpty;
    final hasOldText = oldText is String && oldText.isNotEmpty;
    final hasContextText = contextText is String && contextText.isNotEmpty;
    final hasAnchorText = anchorText is String && anchorText.isNotEmpty;
    final hasStructuredEdits = edits is List && edits.isNotEmpty;

    if (_isWorkspaceMutationTool &&
        (hasWritableContent ||
            hasNewText ||
            hasOldText ||
            hasContextText ||
            hasAnchorText ||
            hasStructuredEdits)) {
      final metadata = Map<String, dynamic>.from(arguments)
        ..remove('content')
        ..remove('new_text')
        ..remove('old_text')
        ..remove('context_text')
        ..remove('anchor_text')
        ..remove('edits');
      final children = <Widget>[];

      if (metadata.isNotEmpty) {
        children.add(
          _buildJsonCodeBlock(
            context,
            metadata,
            title: 'Arguments',
            fontSize: 12,
          ),
        );
      }

      if (hasWritableContent) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        children.add(
          _buildCodeTextBlock(
            context,
            title: 'Content Being Written',
            text: _capIfCalling(content),
          ),
        );
      }

      if (hasOldText) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        children.add(
          _buildCodeTextBlock(
            context,
            title: 'Text Being Replaced',
            text: _capIfCalling(oldText),
          ),
        );
      }

      if (hasNewText) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        children.add(
          _buildCodeTextBlock(
            context,
            title: 'Text Being Written',
            text: _capIfCalling(newText),
          ),
        );
      }

      if (hasContextText) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        children.add(
          _buildCodeTextBlock(context, title: 'Context', text: contextText),
        );
      }

      if (hasAnchorText) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        children.add(
          _buildCodeTextBlock(context, title: 'Anchor Text', text: anchorText),
        );
      }

      if (hasStructuredEdits) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        children.add(_buildEditOperationsBlock(context, edits));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    if (arguments.isEmpty &&
        rawArguments != null &&
        _hasNonEmptyRawArguments(rawArguments)) {
      final partialContent = _partialStringValueFromJsonArguments(
        rawArguments,
        'content',
      );
      if (_isWorkspaceMutationTool &&
          partialContent != null &&
          partialContent.isNotEmpty) {
        return _buildCodeTextBlock(
          context,
          title: 'Content Being Written',
          text: _capIfCalling(partialContent),
        );
      }
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

  String? _partialStringValueFromJsonArguments(String raw, String key) {
    final keyPattern = RegExp('"${RegExp.escape(key)}"\\s*:\\s*"');
    final match = keyPattern.firstMatch(raw);
    if (match == null) return null;

    final buffer = StringBuffer();
    var escaped = false;
    for (var index = match.end; index < raw.length; index++) {
      final char = raw[index];
      if (escaped) {
        buffer.write(_decodeJsonEscapedChar(char));
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') break;
      buffer.write(char);
    }
    return buffer.toString();
  }

  String _decodeJsonEscapedChar(String char) {
    return switch (char) {
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      '"' => '"',
      '\\' => '\\',
      '/' => '/',
      _ => char,
    };
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
    if ((result['tool'] == 'github_clone_repo' ||
            result['tool'] == 'github_switch_branch' ||
            result['tool'] == 'github_create_branch' ||
            result['tool'] == 'github_commit_push' ||
            ((result['tool'] == 'github_create_pull_request' ||
                    result['tool'] == 'github_repo_status') &&
                result['in_progress'] == true)) &&
        (result['progress'] is num || result['total_files'] is num)) {
      return _buildGithubCloneProgressResult(context, result);
    }

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

  Widget _buildGithubCloneProgressResult(
    BuildContext context,
    Map<String, dynamic> result,
  ) {
    final theme = Theme.of(context);
    final progress = ((result['progress'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      1.0,
    );
    final message = result['message']?.toString().trim();
    final currentFile = result['current_file']?.toString().trim();
    final path = result['path']?.toString().trim();
    final downloadedFiles = (result['downloaded_files'] as num?)?.toInt();
    final totalFiles = (result['total_files'] as num?)?.toInt();
    final uploadedFiles = (result['uploaded_files'] as num?)?.toInt();
    final totalChangedFiles = (result['total_changed_files'] as num?)?.toInt();
    final downloadedBytes = (result['downloaded_bytes'] as num?)?.toInt();
    final activeDownloads = (result['active_downloads'] as num?)?.toInt();
    final maxConcurrency = (result['max_concurrency'] as num?)?.toInt();
    final activeFiles = _cloneActiveFiles(result['current_files']);
    final inProgress = result['in_progress'] == true;
    final toolName = result['tool']?.toString() ?? '';
    final defaultProgressMessage = switch (toolName) {
      'github_commit_push' => 'Uploading changes ...',
      'github_switch_branch' => 'Switching branch ...',
      'github_create_branch' => 'Creating branch ...',
      'github_create_pull_request' => 'Creating pull request ...',
      'github_repo_status' => 'Checking repository status ...',
      _ => 'Cloning repository ...',
    };
    final defaultDoneMessage = switch (toolName) {
      'github_commit_push' => 'Commit pushed',
      'github_switch_branch' => 'Branch switched',
      'github_create_branch' => 'Branch ready',
      'github_create_pull_request' => 'Pull request created',
      'github_repo_status' => 'Repository status checked',
      _ => 'Clone complete',
    };

    String fileCountLabel() {
      if (uploadedFiles != null && totalChangedFiles != null) {
        return '$uploadedFiles / $totalChangedFiles files uploaded';
      }
      if (downloadedFiles == null || totalFiles == null) return '';
      return '$downloadedFiles / $totalFiles files';
    }

    if (!inProgress) {
      final doneMessage = message?.isNotEmpty == true
          ? message!
          : defaultDoneMessage;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: widget.themeColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doneMessage,
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (path != null && path.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
                if (result['tree_truncated'] == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'GitHub marked this repository tree as truncated; very large repos may need a narrower checkout later.',
                    style: AppTheme.bodySmall.copyWith(
                      color: Colors.orange,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final rows = <Widget>[
      TweenAnimationBuilder<double>(
        tween: Tween<double>(end: progress),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, _) {
          final visibleProgress = animatedProgress.clamp(0.0, progress);
          final percentLabel = _formatCloneProgressPercent(visibleProgress);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      message?.isNotEmpty == true
                          ? message!
                          : defaultProgressMessage,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    percentLabel,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(100),
                  value: visibleProgress == 0 ? null : visibleProgress,
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(widget.themeColor),
                ),
              ),
            ],
          );
        },
      ),
    ];

    if (activeFiles.isNotEmpty) {
      rows.add(const SizedBox(height: 10));
      rows.add(_buildCloneActiveFileGrid(context, activeFiles));
    }

    final details = <String>[
      fileCountLabel(),
      if (downloadedBytes != null) _formatBytes(downloadedBytes),
      if (activeDownloads != null &&
          activeDownloads > 1 &&
          maxConcurrency != null &&
          maxConcurrency > 1)
        '$activeDownloads active, concurrency $maxConcurrency',
      if (currentFile != null && currentFile.isNotEmpty) currentFile,
    ].where((item) => item.trim().isNotEmpty).toList();

    if (details.isNotEmpty) {
      rows.add(const SizedBox(height: 8));
      rows.add(
        Text(
          details.join('  |  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
            height: 1.25,
          ),
        ),
      );
    }

    if (result['tree_truncated'] == true) {
      rows.add(const SizedBox(height: 6));
      rows.add(
        Text(
          'GitHub marked this repository tree as truncated; very large repos may need a narrower checkout later.',
          style: AppTheme.bodySmall.copyWith(
            color: Colors.orange,
            fontSize: 11,
            height: 1.25,
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  List<Map<String, dynamic>> _cloneActiveFiles(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['path']?.toString().trim() ?? '').isNotEmpty)
        .take(12)
        .toList();
  }

  Widget _buildCloneActiveFileGrid(
    BuildContext context,
    List<Map<String, dynamic>> activeFiles,
  ) {
    final rows = <Widget>[];
    for (var index = 0; index < activeFiles.length; index += 2) {
      final rowFiles = activeFiles.skip(index).take(2).toList();
      rows.add(
        Row(
          children: [
            Expanded(child: _buildCloneActiveFileTile(context, rowFiles[0])),
            if (rowFiles.length == 2) ...[
              const SizedBox(width: 8),
              Expanded(child: _buildCloneActiveFileTile(context, rowFiles[1])),
            ],
          ],
        ),
      );
      if (index + 2 < activeFiles.length) {
        rows.add(const SizedBox(height: 8));
      }
    }
    return Column(children: rows);
  }

  Widget _buildCloneActiveFileTile(
    BuildContext context,
    Map<String, dynamic> file,
  ) {
    final theme = Theme.of(context);
    final filePath = file['path']?.toString().trim() ?? '';
    final progress = ((file['progress'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      1.0,
    );
    final fileName = _basename(filePath);

    return TweenAnimationBuilder<double>(
      key: ValueKey('clone-active-file-$filePath'),
      tween: Tween<double>(begin: 0, end: progress),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, _) {
        final visibleProgress = animatedProgress.clamp(0.0, progress);
        return Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName.isEmpty ? filePath : fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(100),
                  value: visibleProgress == 0 ? null : visibleProgress,
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(widget.themeColor),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatCloneProgressPercent(double progress) {
    final percent = (progress * 100).clamp(0.0, 100.0);
    if (percent >= 99.995) return '100%';
    return '${percent.toStringAsFixed(2)}%';
  }

  String _basename(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
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
          'workspace_root',
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

  Widget _buildApprovalRequiredResult(
    BuildContext context,
    Map<String, dynamic> result,
  ) {
    final decision = result['approval_decision']?.toString();
    final hasDecision = decision == 'approved' || decision == 'denied';
    final commandResult = result['command_result'];
    if (!hasDecision) {
      return const SizedBox.shrink();
    }

    final responseText = (result['content'] ?? '').toString().trim();
    final commandOutput = commandResult is Map
        ? _commandResultOutput(commandResult)
        : '';
    final children = <Widget>[];

    if (responseText.isNotEmpty && responseText != commandOutput) {
      children.add(
        _buildPlainTextContent(context, responseText, title: 'Response'),
      );
    }
    if (commandOutput.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        _buildPlainTextContent(context, commandOutput, title: 'Command Output'),
      );
    }

    if (children.isEmpty) {
      return _buildPlainTextContent(
        context,
        decision == 'approved' ? 'Command approved.' : 'Command denied.',
        title: 'Response',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _commandResultOutput(Map<dynamic, dynamic> commandResult) {
    for (final key in const [
      'content',
      'stdout',
      'stderr',
      'stdout_tail',
      'stderr_tail',
      'output_sample',
    ]) {
      final value = commandResult[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Widget _buildAgentPreflightApproval(
    BuildContext context,
    Map<String, dynamic> result,
  ) {
    final theme = Theme.of(context);
    final agent = result['agent']?.toString() ?? 'agent';
    return Row(
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Waiting for approval to run $agent agent…',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildCodeTextBlock(
    BuildContext context, {
    required String title,
    required String text,
  }) {
    return _buildCodeContent(context, text, title: title);
  }

  Widget _buildJsonDetailBlock(
    BuildContext context, {
    required String title,
    required Object? jsonValue,
    double fontSize = 12,
    double? maxHeight,
  }) {
    return _buildJsonCodeBlock(
      context,
      jsonValue,
      title: title,
      fontSize: fontSize,
      maxHeight: maxHeight,
    );
  }

  Widget _buildEditOperationsBlock(BuildContext context, List<dynamic> edits) {
    final operations = edits
        .map(_editOperationFromValue)
        .whereType<_EditOperationPreview>()
        .toList(growable: false);

    if (operations.isEmpty) {
      return _buildJsonDetailBlock(
        context,
        title: 'Edit Operations',
        jsonValue: edits,
        maxHeight: 280,
      );
    }

    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Edit Operations',
          style: AppTheme.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: foreground.withValues(alpha: 0.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${operations.length} replacement${operations.length == 1 ? '' : 's'}',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (var index = 0; index < operations.length; index++) ...[
                if (index > 0)
                  Divider(height: 1, color: foreground.withValues(alpha: 0.08)),
                _buildEditOperationTile(context, index, operations[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditOperationTile(
    BuildContext context,
    int index,
    _EditOperationPreview operation,
  ) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        splashColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        visualDensity: VisualDensity.compact,
        title: Text(
          'Replacement ${index + 1}',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          operation.preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.35,
          ),
        ),
        children: [
          _buildEditOperationText(
            context,
            label: 'Text Being Replaced',
            text: operation.oldText,
          ),
          const SizedBox(height: 8),
          _buildEditOperationText(
            context,
            label: 'Text Being Written',
            text: operation.newText,
          ),
        ],
      ),
    );
  }

  Widget _buildEditOperationText(
    BuildContext context, {
    required String label,
    required String text,
  }) {
    return _buildCodeContent(context, text, title: label);
  }

  _EditOperationPreview? _editOperationFromValue(Object? value) {
    if (value is! Map) return null;
    final oldText = (value['oldText'] ?? value['old_text'])?.toString() ?? '';
    final newText = (value['newText'] ?? value['new_text'])?.toString() ?? '';
    if (oldText.trim().isEmpty && newText.trim().isEmpty) return null;
    return _EditOperationPreview(
      oldText: oldText,
      newText: newText,
      preview: _compactEditPreview(newText.trim().isEmpty ? oldText : newText),
    );
  }

  String _compactEditPreview(String text) {
    final preview = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ');
    if (preview.length <= 180) return preview;
    return '${preview.substring(0, 180).trimRight()}...';
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
  final workspaceRoot = arguments['workspace_root']?.toString().trim() ?? '';
  return '$workspaceRoot|$path|$offset|$limit';
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

class _EditOperationPreview {
  const _EditOperationPreview({
    required this.oldText,
    required this.newText,
    required this.preview,
  });

  final String oldText;
  final String newText;
  final String preview;
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

class AgenticFileChange {
  final String filePath;
  final String diff;
  final String toolName;
  final String? oldString;
  final String? newString;
  final String? preContent;
  final String workspaceRoot;

  const AgenticFileChange({
    required this.filePath,
    required this.diff,
    required this.toolName,
    this.oldString,
    this.newString,
    this.preContent,
    required this.workspaceRoot,
  });
}

class AgenticFileChangesSummary extends StatefulWidget {
  final List<AgenticFileChange> changes;

  const AgenticFileChangesSummary({super.key, required this.changes});

  @override
  State<AgenticFileChangesSummary> createState() =>
      _AgenticFileChangesSummaryState();
}

class _AgenticFileChangesSummaryState extends State<AgenticFileChangesSummary> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDiffs = widget.changes.map((c) => c.diff).join('\n');
    final parsedFiles = _parseUnifiedDiff(allDiffs);
    final files = parsedFiles.isEmpty
        ? [
            _DiffFileSummary(
              path: 'Changes',
              added: _countAddedLines(allDiffs),
              removed: _countRemovedLines(allDiffs),
              lines: allDiffs.split('\n'),
            ),
          ]
        : parsedFiles;
    final added = _countAddedLines(allDiffs);
    final removed = _countRemovedLines(allDiffs);
    final fileCount = files.length;
    final fileLabel = fileCount == 1 ? 'file changed' : 'files changed';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '$fileCount $fileLabel',
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

                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
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
                for (var index = 0; index < files.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      color: theme.dividerColor.withValues(alpha: 0.16),
                    ),
                  _DiffFileSection(file: files[index], splitView: false),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
}
