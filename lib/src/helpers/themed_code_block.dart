import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_syntax_view/flutter_syntax_view.dart';

const _ghGreen = Color(0xFF3fb950);

// LRU cache of built SyntaxView widgets so that repeated rebuilds of an
// unchanged closed code block (common while a later part of the message is
// still streaming) reuse the same widget instance and Flutter skips the
// subtree update instead of re-tokenizing.
const int _kSyntaxCacheCapacity = 64;
final LinkedHashMap<String, Widget> _syntaxViewCache =
    LinkedHashMap<String, Widget>();
final LinkedHashMap<String, Widget> _jsonSyntaxViewCache =
    LinkedHashMap<String, Widget>();

Widget _cachedSyntaxView({
  required String code,
  required Syntax syntax,
  required SyntaxTheme syntaxTheme,
  required bool isDark,
  required double fontSize,
  required double contentPadding,
  required bool showLineNumbers,
  required bool selectable,
  required bool showZoom,
}) {
  final key =
      '${isDark ? 'd' : 'l'}|${syntax.index}|$fontSize|$contentPadding|$showLineNumbers|$selectable|$showZoom|${code.length}|$code';
  final existing = _syntaxViewCache.remove(key);
  if (existing != null) {
    _syntaxViewCache[key] = existing;
    return existing;
  }
  final built = _InlineSyntaxCodeView(
    code: code,
    syntax: syntax,
    syntaxTheme: syntaxTheme,
    fontSize: fontSize,
    contentPadding: contentPadding,
    showLineNumbers: showLineNumbers,
    selectable: selectable,
    showZoom: showZoom,
  );
  _syntaxViewCache[key] = built;
  if (_syntaxViewCache.length > _kSyntaxCacheCapacity) {
    _syntaxViewCache.remove(_syntaxViewCache.keys.first);
  }
  return built;
}

Widget _cachedJsonSyntaxView({
  required String code,
  required SyntaxTheme syntaxTheme,
  required bool isDark,
  required double fontSize,
  required double contentPadding,
  required bool showLineNumbers,
  required bool selectable,
  required bool showZoom,
}) {
  final key =
      '${isDark ? 'd' : 'l'}|json|$fontSize|$contentPadding|$showLineNumbers|$selectable|$showZoom|${code.length}|$code';
  final existing = _jsonSyntaxViewCache.remove(key);
  if (existing != null) {
    _jsonSyntaxViewCache[key] = existing;
    return existing;
  }
  final built = _InlineJsonCodeView(
    code: code,
    syntaxTheme: syntaxTheme,
    fontSize: fontSize,
    contentPadding: contentPadding,
    showLineNumbers: showLineNumbers,
    selectable: selectable,
    showZoom: showZoom,
  );
  _jsonSyntaxViewCache[key] = built;
  if (_jsonSyntaxViewCache.length > _kSyntaxCacheCapacity) {
    _jsonSyntaxViewCache.remove(_jsonSyntaxViewCache.keys.first);
  }
  return built;
}

class ThemedCodeBlock extends StatefulWidget {
  final String name;
  final String code;
  final bool closed;
  final double fontSize;
  final double headerHeight;
  final double contentPadding;
  final double borderRadius;
  final double? maxHeight;
  final bool showLineNumbers;
  final bool selectable;
  final bool showZoom;
  final bool showHeader;
  final String? headerTitle;
  final bool showHeaderIcon;
  final bool showCopyAction;

  const ThemedCodeBlock({
    super.key,
    required this.name,
    required this.code,
    this.closed = true,
    this.fontSize = 14,
    this.headerHeight = 44,
    this.contentPadding = 8,
    this.borderRadius = 12,
    this.maxHeight,
    this.showLineNumbers = true,
    this.selectable = true,
    this.showZoom = true,
    this.showHeader = true,
    this.headerTitle,
    this.showHeaderIcon = true,
    this.showCopyAction = true,
  });

  @override
  State<ThemedCodeBlock> createState() => _ThemedCodeBlockState();
}

class _ThemedCodeBlockState extends State<ThemedCodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final language = widget.name.trim().isEmpty ? 'text' : widget.name.trim();
    final headerText = widget.headerTitle?.trim().isNotEmpty == true
        ? widget.headerTitle!.trim()
        : language;
    final displayCode = _trimTrailingCodeWhitespace(widget.code);
    final syntax = _syntaxFor(widget.name);
    final isJson = _isJsonLanguage(widget.name);
    final syntaxTheme = isDark ? codeDarkSyntaxTheme() : codeLightSyntaxTheme();

    final codeFg = isDark
        ? const Color(0xFFe6edf3)
        : theme.colorScheme.onSurface;
    final codeView = _buildCodeView(
      displayCode: displayCode,
      syntax: syntax,
      isJson: isJson,
      syntaxTheme: syntaxTheme,
      isDark: isDark,
      codeFg: codeFg,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: Theme.of(context).colorScheme.primary),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHeader)
              // Header — same layout as gh_file_viewer_screen
              Container(
                height: widget.headerHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      (widget.borderRadius - 2).clamp(0, 100).toDouble(),
                    ),
                    topRight: Radius.circular(
                      (widget.borderRadius - 2).clamp(0, 100).toDouble(),
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(left: 8, right: 8),
                child: Row(
                  children: [
                    Text(
                      headerText,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    if (widget.showCopyAction) ...[
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _copied
                            ? const Row(
                                key: ValueKey('copied'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: 15, color: _ghGreen),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copied',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _ghGreen,
                                    ),
                                  ),
                                ],
                              )
                            : InkWell(
                                key: const ValueKey('copy'),
                                onTap: _copyCode,
                                borderRadius: BorderRadius.circular(6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      CupertinoIcons.doc_on_doc,
                                      size: 15,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Copy',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
              ),
            codeView,
          ],
        ),
      ),
    );
  }

  Widget _buildCodeView({
    required String displayCode,
    required Syntax? syntax,
    required bool isJson,
    required SyntaxTheme syntaxTheme,
    required bool isDark,
    required Color codeFg,
  }) {
    if (syntax != null && widget.closed) {
      return _cachedSyntaxView(
        code: displayCode,
        syntax: syntax,
        syntaxTheme: syntaxTheme,
        isDark: isDark,
        fontSize: widget.fontSize,
        contentPadding: widget.contentPadding,
        showLineNumbers: widget.showLineNumbers,
        selectable: widget.selectable,
        showZoom: widget.showZoom,
      );
    }

    if (isJson && widget.closed) {
      return _cachedJsonSyntaxView(
        code: displayCode,
        syntaxTheme: syntaxTheme,
        isDark: isDark,
        fontSize: widget.fontSize,
        contentPadding: widget.contentPadding,
        showLineNumbers: widget.showLineNumbers,
        selectable: widget.selectable,
        showZoom: widget.showZoom,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.maxHeight ?? double.infinity,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minCodeWidth =
              (constraints.maxWidth - widget.contentPadding * 2).clamp(
                0.0,
                double.infinity,
              );
          final codeText = widget.selectable
              ? SelectableText(
                  displayCode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: widget.fontSize,
                    height: 1.55,
                    color: codeFg,
                  ),
                )
              : Text(
                  displayCode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: widget.fontSize,
                    height: 1.55,
                    color: codeFg,
                  ),
                );

          final body = Padding(
            padding: EdgeInsets.all(widget.contentPadding),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minCodeWidth),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: codeText,
                ),
              ),
            ),
          );

          if (widget.maxHeight == null) {
            return body;
          }

          return SingleChildScrollView(child: body);
        },
      ),
    );
  }

  Syntax? _syntaxFor(String name) {
    final ext = name.trim().toLowerCase();
    return switch (ext) {
      'dart' => Syntax.DART,
      'js' || 'javascript' || 'jsx' => Syntax.JAVASCRIPT,
      'ts' || 'typescript' || 'tsx' => Syntax.JAVASCRIPT,
      'py' || 'python' => Syntax.PYTHON,
      'java' => Syntax.JAVA,
      'kt' || 'kotlin' => Syntax.KOTLIN,
      'swift' => Syntax.SWIFT,
      'c' || 'h' => Syntax.C,
      'cpp' || 'c++' || 'cxx' || 'hpp' => Syntax.CPP,
      'yaml' || 'yml' => Syntax.YAML,
      'rs' || 'rust' => Syntax.RUST,
      'lua' => Syntax.LUA,
      _ => null,
    };
  }

  bool _isJsonLanguage(String name) {
    final ext = name.trim().toLowerCase();
    return switch (ext) {
      'json' || 'jsonc' || 'application/json' => true,
      _ => false,
    };
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(
      ClipboardData(text: _trimTrailingCodeWhitespace(widget.code)),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  String _trimTrailingCodeWhitespace(String code) {
    final trimmed = code.replaceFirst(RegExp(r'[ \t\r\n]+$'), '');
    return trimmed.isEmpty && code.isNotEmpty ? code : trimmed;
  }
}

class _InlineSyntaxCodeView extends StatefulWidget {
  const _InlineSyntaxCodeView({
    required this.code,
    required this.syntax,
    required this.syntaxTheme,
    required this.fontSize,
    required this.contentPadding,
    required this.showLineNumbers,
    required this.selectable,
    required this.showZoom,
  });

  final String code;
  final Syntax syntax;
  final SyntaxTheme syntaxTheme;
  final double fontSize;
  final double contentPadding;
  final bool showLineNumbers;
  final bool selectable;
  final bool showZoom;

  @override
  State<_InlineSyntaxCodeView> createState() => _InlineSyntaxCodeViewState();
}

class _InlineSyntaxCodeViewState extends State<_InlineSyntaxCodeView> {
  static const double _maxFontScaleFactor = 3.0;
  static const double _minFontScaleFactor = 0.5;

  final ScrollController _verticalScrollController = ScrollController();
  double _fontScaleFactor = 1.0;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(widget.code).length + 1;
    final scaledFontSize = widget.fontSize * _fontScaleFactor;
    final lineNumberWidth =
        (lineCount.toString().length * scaledFontSize * 0.8 + 8).clamp(
          28.0,
          64.0,
        );
    final codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: widget.fontSize,
      height: 1.45,
    );
    final lineStyle = codeStyle.copyWith(
      color: widget.syntaxTheme.linesCountColor,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final minCodeWidth = (constraints.maxWidth - widget.contentPadding * 2)
            .clamp(0.0, double.infinity);

        return Stack(
          alignment: AlignmentDirectional.bottomEnd,
          children: [
            Scrollbar(
              controller: _verticalScrollController,
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                padding: EdgeInsets.fromLTRB(
                  widget.contentPadding,
                  widget.contentPadding,
                  widget.contentPadding,
                  widget.showZoom ? 8 : widget.contentPadding,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minCodeWidth),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.showLineNumbers) ...[
                            SizedBox(
                              width: lineNumberWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 1; i <= lineCount; i++)
                                    Text(
                                      '$i',
                                      style: lineStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.visible,
                                      softWrap: false,
                                      textAlign: TextAlign.right,
                                      textScaler: TextScaler.linear(
                                        _fontScaleFactor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              constraints: const BoxConstraints(minHeight: 1),
                              color: widget.syntaxTheme.linesCountColor!
                                  .withValues(alpha: 0.28),
                            ),
                            const SizedBox(width: 10),
                          ],
                          _buildCodeText(codeStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showZoom)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.zoom_out,
                          color: widget.syntaxTheme.zoomIconColor,
                        ),
                        onPressed: () => setState(() {
                          _fontScaleFactor = (_fontScaleFactor - 0.1).clamp(
                            _minFontScaleFactor,
                            _maxFontScaleFactor,
                          );
                        }),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.zoom_in,
                          color: widget.syntaxTheme.zoomIconColor,
                        ),
                        onPressed: () => setState(() {
                          _fontScaleFactor = (_fontScaleFactor + 0.1).clamp(
                            _minFontScaleFactor,
                            _maxFontScaleFactor,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCodeText(TextStyle codeStyle) {
    final span = TextSpan(
      style: codeStyle,
      children: [
        getSyntax(widget.syntax, widget.syntaxTheme).format(widget.code),
      ],
    );
    if (widget.selectable) {
      return SelectableText.rich(
        span,
        textScaler: TextScaler.linear(_fontScaleFactor),
      );
    }
    return RichText(
      textScaler: TextScaler.linear(_fontScaleFactor),
      text: span,
    );
  }
}

class _InlineJsonCodeView extends StatefulWidget {
  const _InlineJsonCodeView({
    required this.code,
    required this.syntaxTheme,
    required this.fontSize,
    required this.contentPadding,
    required this.showLineNumbers,
    required this.selectable,
    required this.showZoom,
  });

  final String code;
  final SyntaxTheme syntaxTheme;
  final double fontSize;
  final double contentPadding;
  final bool showLineNumbers;
  final bool selectable;
  final bool showZoom;

  @override
  State<_InlineJsonCodeView> createState() => _InlineJsonCodeViewState();
}

class _InlineJsonCodeViewState extends State<_InlineJsonCodeView> {
  static const double _maxFontScaleFactor = 3.0;
  static const double _minFontScaleFactor = 0.5;
  static final RegExp _numberPattern = RegExp(
    r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?',
  );

  final ScrollController _verticalScrollController = ScrollController();
  double _fontScaleFactor = 1.0;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(widget.code).length + 1;
    final scaledFontSize = widget.fontSize * _fontScaleFactor;
    final lineNumberWidth =
        (lineCount.toString().length * scaledFontSize * 0.8 + 8).clamp(
          28.0,
          64.0,
        );
    final codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: widget.fontSize,
      height: 1.45,
    );
    final lineStyle = codeStyle.copyWith(
      color: widget.syntaxTheme.linesCountColor,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final minCodeWidth = (constraints.maxWidth - widget.contentPadding * 2)
            .clamp(0.0, double.infinity);

        return Stack(
          alignment: AlignmentDirectional.bottomEnd,
          children: [
            Scrollbar(
              controller: _verticalScrollController,
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                padding: EdgeInsets.fromLTRB(
                  widget.contentPadding,
                  widget.contentPadding,
                  widget.contentPadding,
                  widget.showZoom ? 42 : widget.contentPadding,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minCodeWidth),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.showLineNumbers) ...[
                            SizedBox(
                              width: lineNumberWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 1; i <= lineCount; i++)
                                    Text(
                                      '$i',
                                      style: lineStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.visible,
                                      softWrap: false,
                                      textAlign: TextAlign.right,
                                      textScaler: TextScaler.linear(
                                        _fontScaleFactor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              constraints: const BoxConstraints(minHeight: 1),
                              color: widget.syntaxTheme.linesCountColor!
                                  .withValues(alpha: 0.28),
                            ),
                            const SizedBox(width: 10),
                          ],
                          _buildCodeText(codeStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showZoom)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.zoom_out,
                          color: widget.syntaxTheme.zoomIconColor,
                        ),
                        onPressed: () => setState(() {
                          _fontScaleFactor = (_fontScaleFactor - 0.1).clamp(
                            _minFontScaleFactor,
                            _maxFontScaleFactor,
                          );
                        }),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.zoom_in,
                          color: widget.syntaxTheme.zoomIconColor,
                        ),
                        onPressed: () => setState(() {
                          _fontScaleFactor = (_fontScaleFactor + 0.1).clamp(
                            _minFontScaleFactor,
                            _maxFontScaleFactor,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCodeText(TextStyle codeStyle) {
    final span = TextSpan(
      style: codeStyle.merge(widget.syntaxTheme.baseStyle),
      children: _jsonSpans(widget.code, widget.syntaxTheme),
    );
    if (widget.selectable) {
      return SelectableText.rich(
        span,
        textScaler: TextScaler.linear(_fontScaleFactor),
      );
    }
    return RichText(
      textScaler: TextScaler.linear(_fontScaleFactor),
      text: span,
    );
  }

  List<TextSpan> _jsonSpans(String src, SyntaxTheme theme) {
    final spans = <TextSpan>[];
    var index = 0;

    while (index < src.length) {
      final char = src[index];

      if (char == '"') {
        final end = _stringEnd(src, index);
        final text = src.substring(index, end);
        spans.add(
          TextSpan(
            text: text,
            style: _isObjectKey(src, end)
                ? theme.classStyle
                : theme.stringStyle,
          ),
        );
        index = end;
        continue;
      }

      final numberMatch = _numberPattern.matchAsPrefix(src, index);
      if (numberMatch != null) {
        spans.add(
          TextSpan(text: numberMatch.group(0)!, style: theme.numberStyle),
        );
        index = numberMatch.end;
        continue;
      }

      if (_startsWithToken(src, index, 'true') ||
          _startsWithToken(src, index, 'false')) {
        final token = src.startsWith('true', index) ? 'true' : 'false';
        spans.add(TextSpan(text: token, style: theme.keywordStyle));
        index += token.length;
        continue;
      }

      if (_startsWithToken(src, index, 'null')) {
        spans.add(TextSpan(text: 'null', style: theme.constantStyle));
        index += 4;
        continue;
      }

      if ('{}[]:,'.contains(char)) {
        spans.add(TextSpan(text: char, style: theme.punctuationStyle));
        index += 1;
        continue;
      }

      spans.add(TextSpan(text: char));
      index += 1;
    }

    return spans;
  }

  int _stringEnd(String src, int start) {
    var index = start + 1;
    var escaped = false;
    while (index < src.length) {
      final char = src[index];
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        return index + 1;
      }
      index += 1;
    }
    return src.length;
  }

  bool _isObjectKey(String src, int stringEnd) {
    var index = stringEnd;
    while (index < src.length) {
      final unit = src.codeUnitAt(index);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) {
        return src[index] == ':';
      }
      index += 1;
    }
    return false;
  }

  bool _startsWithToken(String src, int index, String token) {
    if (!src.startsWith(token, index)) return false;
    final end = index + token.length;
    if (end >= src.length) return true;
    final next = src[end];
    return !RegExp(r'[A-Za-z0-9_]').hasMatch(next);
  }
}

// ── Shared syntax themes ─────────────────────────────────────────────────────

SyntaxTheme codeDarkSyntaxTheme() => SyntaxTheme(
  linesCountColor: const Color(0xFF6e7681),
  backgroundColor: Colors.transparent,
  baseStyle: const TextStyle(color: Color(0xFFe6edf3)),
  numberStyle: const TextStyle(color: Color(0xFF93d0ff)),
  commentStyle: const TextStyle(
    color: Color(0xFF8b949e),
    fontStyle: FontStyle.italic,
  ),
  keywordStyle: const TextStyle(color: Color.fromRGBO(247, 114, 112, 1)),
  stringStyle: const TextStyle(color: Color.fromARGB(255, 101, 172, 248)),
  punctuationStyle: const TextStyle(color: Color(0xFFe6edf3)),
  classStyle: const TextStyle(color: Color.fromARGB(255, 167, 135, 247)),
  constantStyle: const TextStyle(color: Color.fromARGB(255, 131, 199, 251)),
  zoomIconColor: const Color(0xFF6e7681),
);

SyntaxTheme codeLightSyntaxTheme() => SyntaxTheme(
  linesCountColor: const Color(0xFF6e7781),
  backgroundColor: Colors.transparent,
  baseStyle: const TextStyle(color: Color(0xFF1f2328)),
  numberStyle: const TextStyle(color: Color(0xFF0550ae)),
  commentStyle: const TextStyle(
    color: Color(0xFF6e7781),
    fontStyle: FontStyle.italic,
  ),
  keywordStyle: const TextStyle(color: Color(0xFFcf222e)),
  stringStyle: const TextStyle(color: Color(0xFF0a3069)),
  punctuationStyle: const TextStyle(color: Color(0xFF1f2328)),
  classStyle: const TextStyle(color: Color(0xFF953800)),
  constantStyle: const TextStyle(color: Color(0xFF0550ae)),
  zoomIconColor: const Color(0xFF6e7781),
);
