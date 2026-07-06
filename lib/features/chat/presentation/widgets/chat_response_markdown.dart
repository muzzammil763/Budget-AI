import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/presentation/widgets/markdown_table_view.dart';
import 'package:budget_ai/core/widgets/themed_code_block.dart';

typedef ChatResponseLinkTap = Future<void> Function(String url, String title);
typedef ChatResponseTokenTap = Future<void> Function(String token);

class ChatResponseMarkdown extends StatefulWidget {
  const ChatResponseMarkdown({
    super.key,
    required this.text,
    required this.isStreaming,
    required this.onLinkTap,
    this.onTokenTap,
  });

  final String text;
  final bool isStreaming;
  final ChatResponseLinkTap onLinkTap;
  final ChatResponseTokenTap? onTokenTap;

  @override
  State<ChatResponseMarkdown> createState() => _ChatResponseMarkdownState();
}

class _ChatResponseMarkdownState extends State<ChatResponseMarkdown> {
  static const int _largeResponsePreviewChars = 20000;

  bool _showFullResponse = false;
  String? _cachedSourceText;
  String? _cachedNormalizedText;

  // Cached to avoid rebuilding the entire GptMarkdown subtree on every parent
  // setState. Theme.updateShouldNotify uses object identity, so creating a new
  // ThemeData each build forces all descendants to rebuild unnecessarily.
  ThemeData? _inputTheme;
  ThemeData? _markdownTheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    if (!identical(theme, _inputTheme)) {
      _inputTheme = theme;
      _markdownTheme = _buildMarkdownTheme(theme);
    }
  }

  ThemeData _buildMarkdownTheme(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;
    return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        headlineLarge: AppTheme.headingLarge.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        headlineMedium: AppTheme.headingMedium.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        headlineSmall: AppTheme.headingSmall.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        titleLarge: AppTheme.bodyLarge.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        titleMedium: AppTheme.bodyMedium.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        titleSmall: AppTheme.bodySmall.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        bodyMedium: AppTheme.bodyMedium.copyWith(
          fontSize: 16,
          color: textColor,
          height: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shouldPreview =
        widget.text.length > _largeResponsePreviewChars && !_showFullResponse;
    final sourceText = shouldPreview
        ? widget.text.substring(0, _largeResponsePreviewChars)
        : widget.text;
    final normalizedText = _normalizeCached(sourceText);

    return Theme(
      data: _markdownTheme!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            // Same ValueKey while streaming so per-chunk rebuilds don't
            // re-trigger the transition; only the streaming→formatted flip
            // changes the key and animates the swap.
            child: KeyedSubtree(
              key: ValueKey<bool>(widget.isStreaming),
              child: _StandardChatResponseMarkdown(
                text: normalizedText,
                isStreaming: widget.isStreaming,
                onLinkTap: widget.onLinkTap,
                onTokenTap: widget.onTokenTap,
              ),
            ),
          ),
          if (shouldPreview)
            _LargeResponsePreviewFooter(
              hiddenCharacters: widget.text.length - sourceText.length,
              isStreaming: widget.isStreaming,
              onShowFull: widget.isStreaming
                  ? null
                  : () => setState(() => _showFullResponse = true),
            ),
        ],
      ),
    );
  }

  String _normalizeCached(String sourceText) {
    if (_cachedSourceText == sourceText && _cachedNormalizedText != null) {
      return _cachedNormalizedText!;
    }
    final normalizedText = normalizeChatResponseMarkdown(sourceText);
    _cachedSourceText = sourceText;
    _cachedNormalizedText = normalizedText;
    return normalizedText;
  }
}

class _LargeResponsePreviewFooter extends StatelessWidget {
  const _LargeResponsePreviewFooter({
    required this.hiddenCharacters,
    required this.isStreaming,
    required this.onShowFull,
  });

  final int hiddenCharacters;
  final bool isStreaming;
  final VoidCallback? onShowFull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurfaceVariant;
    final label = isStreaming
        ? 'Showing preview while the response is still streaming'
        : 'Showing preview, ${_formatCompactCount(hiddenCharacters)} more characters hidden';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onShowFull != null)
            TextButton(
              onPressed: onShowFull,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Show full response'),
            ),
        ],
      ),
    );
  }
}

class _StandardChatResponseMarkdown extends StatelessWidget {
  const _StandardChatResponseMarkdown({
    required this.text,
    required this.isStreaming,
    required this.onLinkTap,
    this.onTokenTap,
  });

  static const double _horizontalInset = 12.0;

  final String text;
  final bool isStreaming;
  final ChatResponseLinkTap onLinkTap;
  final ChatResponseTokenTap? onTokenTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    final style = AppTheme.bodyMedium.copyWith(
      color: textColor,
      fontSize: 16,
      height: 1.5,
    );

    final segments = _splitMarkdownTables(text);

    Widget buildMarkdown(String source) {
      return GptMarkdown(
        source,
        textAlign: TextAlign.start,
        style: style,
        codeBuilder: (context, name, code, closed) {
          return _buildResponseCodeBlock(
            name: name,
            code: code,
            closed: closed,
          );
        },
        onLinkTap: onLinkTap,
        linkBuilder: (context, linkText, url, style) =>
            buildChatResponseMarkdownLink(
              context,
              linkText: linkText,
              url: url,
              style: style,
              onLinkTap: onLinkTap,
            ),
        highlightBuilder: (context, text, style) {
          final tokenStyle = const TextStyle(
            color: AppTheme.highlight,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            height: 1.5,
          );
          final onTap = onTokenTap;
          if (onTap == null || text.trim().isEmpty) {
            return Text(text, style: tokenStyle);
          }
          return InkWell(
            radius: 24,
            borderRadius: BorderRadius.circular(4),
            onTap: () => onTap(text),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(text, style: tokenStyle),
            ),
          );
        },
        tableBuilder: buildStyledMarkdownTable,
      );
    }

    final content = segments.length == 1 && !segments.first.isTable
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: _horizontalInset),
            child: buildMarkdown(segments.first.text),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final segment in segments)
                if (segment.isTable)
                  buildMarkdown(segment.text)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _horizontalInset,
                    ),
                    child: buildMarkdown(segment.text),
                  ),
            ],
          );

    return AnimatedSize(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: content,
    );
  }

  List<_MarkdownSegment> _splitMarkdownTables(String source) {
    final lines = source.split('\n');
    final segments = <_MarkdownSegment>[];
    final textLines = <String>[];
    var inFence = false;
    var index = 0;

    void flushText() {
      final text = textLines.join('\n');
      if (text.trim().isNotEmpty) {
        segments.add(_MarkdownSegment.text(text));
      }
      textLines.clear();
    }

    while (index < lines.length) {
      final line = lines[index];
      if (_isFenceLine(line)) {
        inFence = !inFence;
      }

      if (!inFence && _isTableStart(lines, index)) {
        flushText();
        final tableLines = <String>[];
        while (index < lines.length && _isTableRow(lines[index])) {
          tableLines.add(lines[index]);
          index++;
        }
        segments.add(_MarkdownSegment.table(tableLines.join('\n')));
        continue;
      }

      textLines.add(line);
      index++;
    }

    flushText();
    return segments.isEmpty ? [_MarkdownSegment.text(source)] : segments;
  }

  bool _isFenceLine(String line) {
    final trimmed = line.trimLeft();
    return trimmed.startsWith('```') || trimmed.startsWith('~~~');
  }

  bool _isTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) {
      return false;
    }
    return _isTableRow(lines[index]) && _isTableDelimiter(lines[index + 1]);
  }

  bool _isTableRow(String line) {
    final trimmed = line.trim();
    return trimmed.contains('|') && trimmed.isNotEmpty;
  }

  bool _isTableDelimiter(String line) {
    final trimmed = line.trim();
    if (!trimmed.contains('|')) {
      return false;
    }
    final cells = trimmed
        .replaceAll(RegExp(r'^\|'), '')
        .replaceAll(RegExp(r'\|$'), '')
        .split('|')
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();
    if (cells.length < 2) {
      return false;
    }
    return cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell));
  }

  Widget _buildResponseCodeBlock({
    required String name,
    required String code,
    required bool closed,
  }) {
    return ThemedCodeBlock(
      name: name,
      code: code,
      closed: closed,
      fontSize: 14,
      headerHeight: 40,
      contentPadding: 8,
      borderRadius: 12,
      showHeader: true,
      showHeaderIcon: true,
      showCopyAction: true,
      showLineNumbers: false,
      selectable: false,
      showZoom: false,
    );
  }
}

class _MarkdownSegment {
  const _MarkdownSegment._({required this.text, required this.isTable});

  factory _MarkdownSegment.text(String text) {
    return _MarkdownSegment._(text: text, isTable: false);
  }

  factory _MarkdownSegment.table(String text) {
    return _MarkdownSegment._(text: text, isTable: true);
  }

  final String text;
  final bool isTable;
}

Widget buildChatResponseMarkdownLink(
  BuildContext context, {
  required InlineSpan linkText,
  required String url,
  required TextStyle style,
  required ChatResponseLinkTap onLinkTap,
}) {
  final emphasisStyle = style.copyWith(
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationThickness: 1.5,
    decorationColor: AppTheme.highlight,
    color: AppTheme.highlight,
  );

  return InkWell(
    radius: 32,
    onTap: () => onLinkTap(url, _plainTextFromInlineSpan(linkText)),
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(text: _copyInlineSpanWithStyle(linkText, emphasisStyle)),
    ),
  );
}

String _formatCompactCount(int value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    final thousands = value / 1000;
    return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K';
  }
  return value.toString();
}

String normalizeChatResponseMarkdown(String text) {
  return _normalizeMarkdownSpacing(
    _autoLinkBareUrls(
      _normalizeMarkdownLinks(_stripInlineDataImageMarkdown(text)),
    ),
  );
}

String _normalizeMarkdownLinks(String text) {
  // Fix trailing bold/italic/code markers that leaked into link URLs.
  // e.g. **[url](url)** → GptMarkdown gets [url](url**) and renders it raw.
  var result = text.replaceAllMapped(RegExp(r'\[([^\]]*)\]\(([^)]+)\)'), (
    match,
  ) {
    final linkText = match.group(1)!;
    final rawUrl = match.group(2)!;
    final cleanUrl = rawUrl.replaceAll(RegExp(r'[*`]+$'), '').trim();
    if (cleanUrl == rawUrl || !cleanUrl.startsWith('http')) {
      return match.group(0)!;
    }
    return '[$linkText]($cleanUrl)';
  });
  // Fix code-span backticks wrapping link text: [`url`](url) → [url](url)
  result = result.replaceAllMapped(
    RegExp(r'\[`([^`\]]*)`\]\(([^)]+)\)'),
    (match) => '[${match.group(1)!.trim()}](${match.group(2)})',
  );
  return result;
}

String _stripInlineDataImageMarkdown(String text) {
  var cleaned = text;
  cleaned = cleaned.replaceAll(RegExp(r'!\[[^\]]*\]\([^\)]+\)'), '');
  cleaned = cleaned.replaceAll(RegExp(r'<img[^>]+>'), '');
  cleaned = cleaned.replaceAll(RegExp(r'<img[^>]*>'), '');
  return cleaned;
}

String _normalizeMarkdownSpacing(String text) {
  if (text.trim().isEmpty) {
    return text;
  }

  var normalized = text.replaceAll('\r\n', '\n');

  normalized = normalized.replaceAllMapped(
    RegExp(r'([^\n])\n(```)'),
    (match) => '${match.group(1)}\n\n${match.group(2)}',
  );

  normalized = normalized.replaceAllMapped(
    RegExp(r'(```[\s\S]*?```)(\n)([^\n])'),
    (match) => '${match.group(1)}\n\n${match.group(3)}',
  );

  normalized = normalized.replaceAllMapped(
    RegExp(r'(^|\n)(#{1,6}[^\n]+)\n([^\n])'),
    (match) => '${match.group(1)}${match.group(2)}\n\n${match.group(3)}',
  );

  normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return normalized.trimRight();
}

String _autoLinkBareUrls(String text) {
  if (text.trim().isEmpty) {
    return text;
  }

  final urlPattern = RegExp(
    r'(?<!\()(?<!\[)(https?:\/\/[^\s<]+[^\s<\).,;:!?])',
  );
  final codeBlocks = _extractInlineFencedCodeBlocks(text);
  if (codeBlocks.isEmpty) {
    return text.replaceAllMapped(urlPattern, (match) {
      final url = match.group(1)!;
      return '[$url]($url)';
    });
  }

  final buffer = StringBuffer();
  var cursor = 0;

  for (final block in codeBlocks) {
    final nonCodeSegment = text.substring(cursor, block.start);
    buffer.write(
      nonCodeSegment.replaceAllMapped(urlPattern, (match) {
        final url = match.group(1)!;
        return '[$url]($url)';
      }),
    );
    buffer.write(text.substring(block.start, block.end));
    cursor = block.end;
  }

  if (cursor < text.length) {
    final trailingSegment = text.substring(cursor);
    buffer.write(
      trailingSegment.replaceAllMapped(urlPattern, (match) {
        final url = match.group(1)!;
        return '[$url]($url)';
      }),
    );
  }

  return buffer.toString();
}

List<_InlineFencedCodeBlock> _extractInlineFencedCodeBlocks(String text) {
  if (text.isEmpty) {
    return const [];
  }

  final blocks = <_InlineFencedCodeBlock>[];
  final lines = text.split('\n');
  var offset = 0;
  int? openStart;
  String openFence = '';

  bool isFenceLine(String line, String fence) {
    final trimmed = line.trimLeft();
    return trimmed.startsWith(fence) &&
        trimmed.substring(fence.length).trim().isEmpty;
  }

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lineWithBreak = i < lines.length - 1 ? '$line\n' : line;
    final trimmed = line.trimLeft();

    if (openStart == null) {
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        openStart = offset;
        openFence = trimmed.startsWith('```') ? '```' : '~~~';
      }
    } else if (isFenceLine(line, openFence)) {
      blocks.add(
        _InlineFencedCodeBlock(
          start: openStart,
          end: offset + lineWithBreak.length,
        ),
      );
      openStart = null;
      openFence = '';
    }

    offset += lineWithBreak.length;
  }

  return blocks;
}

InlineSpan _copyInlineSpanWithStyle(InlineSpan span, TextStyle style) {
  if (span is TextSpan) {
    return TextSpan(
      text: span.text,
      style: span.style?.merge(style) ?? style,
      children: span.children
          ?.map((child) => _copyInlineSpanWithStyle(child, style))
          .toList(),
    );
  }

  return TextSpan(text: _plainTextFromInlineSpan(span), style: style);
}

String _plainTextFromInlineSpan(InlineSpan span) {
  if (span is TextSpan) {
    final buffer = StringBuffer();
    if (span.text != null) {
      buffer.write(span.text);
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      buffer.write(_plainTextFromInlineSpan(child));
    }
    return buffer.toString();
  }
  return '';
}

class _InlineFencedCodeBlock {
  const _InlineFencedCodeBlock({required this.start, required this.end});

  final int start;
  final int end;
}
