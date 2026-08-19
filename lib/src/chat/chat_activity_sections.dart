import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart'
    show LinkBuilder;
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/tools/tool_name_formatter.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/chat/streaming_text_reveal.dart';
import 'package:budget_ai/src/helpers/themed_code_block.dart';

typedef MarkdownLinkTap = Future<void> Function(String url, String title);

class ChatActivitySection extends StatefulWidget {
  final String durationLabel;
  final bool initiallyExpanded;
  final bool isInProgress;
  final bool forceCollapsed;
  final WidgetBuilder detailsBuilder;

  const ChatActivitySection({
    super.key,
    required this.durationLabel,
    required this.initiallyExpanded,
    required this.isInProgress,
    this.forceCollapsed = false,
    required this.detailsBuilder,
  });

  @override
  State<ChatActivitySection> createState() => _ChatActivitySectionState();
}

class _ChatActivitySectionState extends State<ChatActivitySection> {
  static const double _horizontalInset = 12;

  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.forceCollapsed ? false : widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant ChatActivitySection oldWidget) {
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

class ChatThinkingSection extends StatelessWidget {
  final String text;
  final Color themeColor;
  final bool isComplete;

  const ChatThinkingSection({
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

class ChatProcessTextSection extends StatelessWidget {
  final String text;

  const ChatProcessTextSection({super.key, required this.text});

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

class ChatToolCallSection extends StatelessWidget {
  final ToolCall toolCall;
  final Color themeColor;
  final bool isInProgress;
  final double displayScale;
  final double horizontalPadding;
  final String Function(String text)? markdownNormalizer;
  final MarkdownLinkTap? onLinkTap;
  final LinkBuilder? linkBuilder;

  const ChatToolCallSection({
    super.key,
    required this.toolCall,
    required this.themeColor,
    required this.isInProgress,
    this.displayScale = 1,
    this.horizontalPadding = 12,
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
      displayScale: displayScale,
      horizontalPadding: horizontalPadding,
      markdownNormalizer: markdownNormalizer,
      onLinkTap: onLinkTap,
      linkBuilder: linkBuilder,
    );
  }
}

class ChatToolCallGroupSection extends StatefulWidget {
  final List<ToolCall> toolCalls;
  final Color themeColor;
  final bool isInProgress;
  final String Function(String text)? markdownNormalizer;
  final MarkdownLinkTap? onLinkTap;
  final LinkBuilder? linkBuilder;

  const ChatToolCallGroupSection({
    super.key,
    required this.toolCalls,
    required this.themeColor,
    required this.isInProgress,
    this.markdownNormalizer,
    this.onLinkTap,
    this.linkBuilder,
  });

  @override
  State<ChatToolCallGroupSection> createState() =>
      _ChatToolCallGroupSectionState();
}

class _ChatToolCallGroupSectionState extends State<ChatToolCallGroupSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
  }

  @override
  void didUpdateWidget(covariant ChatToolCallGroupSection oldWidget) {
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
                      fontSize: 14,
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
                    ChatToolCallSection(
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
                    size: 22,
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
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (failedCount > 0) ...[
                    Text(
                      '$failedCount failed',
                      style: AppTheme.bodySmall.copyWith(
                        color: Colors.red,
                        fontSize: 12,
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
              padding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
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

class _SingleToolCallSection extends StatefulWidget {
  final ToolCall toolCall;
  final Color themeColor;
  final bool isInProgress;
  final double displayScale;
  final double horizontalPadding;
  final String Function(String text)? markdownNormalizer;
  final MarkdownLinkTap? onLinkTap;
  final LinkBuilder? linkBuilder;

  const _SingleToolCallSection({
    required this.toolCall,
    required this.themeColor,
    this.isInProgress = false,
    this.displayScale = 1,
    this.horizontalPadding = 12,
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
    final addedEntry = _addedEntryResult();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.horizontalPadding * widget.displayScale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 4 * widget.displayScale),
              child: Row(
                spacing: 4 * widget.displayScale,
                children: [
                  Icon(
                    isSuccess
                        ? CupertinoIcons.check_mark_circled
                        : isFailed
                        ? CupertinoIcons.xmark_circle
                        : isRunning
                        ? Icons.pending_outlined
                        : CupertinoIcons.info_circle,
                    size: 20 * widget.displayScale,
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
                        fontSize: 14 * widget.displayScale,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),

                  if (widget.isInProgress) ...[
                    SizedBox(
                      width: 12 * widget.displayScale,
                      height: 12 * widget.displayScale,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5 * widget.displayScale,
                        valueColor: AlwaysStoppedAnimation(widget.themeColor),
                      ),
                    ),
                  ],
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 22 * widget.displayScale,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (addedEntry != null)
            Padding(
              padding: EdgeInsets.only(
                top: 4 * widget.displayScale,
                bottom: 8 * widget.displayScale,
              ),
              child: _AddedFinanceEntryCard(
                entry: addedEntry,
                displayScale: widget.displayScale,
              ),
            ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 8 * widget.displayScale),
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

  Map<String, dynamic>? _addedEntryResult() {
    final name = widget.toolCall.name.trim().toLowerCase();
    if (widget.toolCall.status != ToolCallStatus.completed ||
        (name != 'finance_add' && name != 'finance_income_add')) {
      return null;
    }
    final decoded = _tryDecodeJson(widget.toolCall.result);
    if (decoded is! Map || decoded['ok'] != true) return null;
    return Map<String, dynamic>.from(decoded);
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
    return arguments;
  }

  Widget _buildStructuredResult(
    BuildContext context,
    Map<String, dynamic> result,
  ) {
    final normalizedResult = _normalizeStructuredResult(result);
    final content = normalizedResult['content'];
    final metadata = Map<String, dynamic>.from(normalizedResult)
      ..remove('content')
      ..remove('image_base64')
      ..remove('image_url');
    final hasContent = content is String && content.trim().isNotEmpty;

    if (!hasContent) {
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
    final cleanContent = _stripMarkdownImages(content);
    final contentTitle = result.containsKey('content_preview')
        ? 'Content Preview'
        : 'Content';

    return _buildPlainTextContent(context, cleanContent, title: contentTitle);
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

class _AddedFinanceEntryCard extends StatelessWidget {
  const _AddedFinanceEntryCard({
    required this.entry,
    required this.displayScale,
  });

  final Map<String, dynamic> entry;
  final double displayScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = entry['type'] == 'income';
    final title = (entry['description'] ?? 'Entry').toString();
    final date = (entry['date'] ?? '').toString().split(' - ').first;
    final details = <(String, String)>[
      ('Amount', (entry['display_amount'] ?? entry['amount'] ?? '').toString()),
      ('Category', (entry['category'] ?? '').toString()),
      ('Date', date),
      ('Time', (entry['time'] ?? '').toString()),
    ].where((item) => item.$2.trim().isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12 * displayScale),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12 * displayScale),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isIncome
                    ? CupertinoIcons.arrow_down_circle
                    : CupertinoIcons.check_mark_circled,
                color: isIncome ? Colors.green : theme.colorScheme.primary,
                size: 18 * displayScale,
              ),
              SizedBox(width: 7 * displayScale),
              Text(
                isIncome ? 'Income added' : 'Expense added',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 12 * displayScale,
                ),
              ),
            ],
          ),
          SizedBox(height: 7 * displayScale),
          Text(
            title,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 16 * displayScale,
            ),
          ),
          SizedBox(height: 10 * displayScale),
          Wrap(
            spacing: 18 * displayScale,
            runSpacing: 9 * displayScale,
            children: [
              for (final detail in details)
                SizedBox(
                  width: 125 * displayScale,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.$1,
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11 * displayScale,
                        ),
                      ),
                      SizedBox(height: 2 * displayScale),
                      Text(
                        detail.$2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13 * displayScale,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
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
