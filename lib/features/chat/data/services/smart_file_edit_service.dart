typedef SmartFileReader = Future<String> Function();
typedef SmartFileWriter = Future<void> Function(String content);

enum SmartEditStrategy {
  exact,
  lineExact,
  lineWhitespaceNormalized,
  contextExact,
  contextWhitespaceNormalized,
  whitespaceNormalized,
  fuzzy,
}

class SmartFileEditRequest {
  const SmartFileEditRequest({
    required this.command,
    required this.newText,
    this.oldText = '',
    this.anchorText = '',
    this.expectedOccurrences = 1,
    this.lineNumber,
    this.startLine,
    this.endLine,
    this.contextText = '',
  });

  final String command;
  final String oldText;
  final String newText;
  final String anchorText;
  final int expectedOccurrences;
  final int? lineNumber;
  final int? startLine;
  final int? endLine;
  final String contextText;

  String get targetText =>
      command.trim().toLowerCase() == 'str_replace' ? oldText : anchorText;
}

class SmartFileEditResult {
  const SmartFileEditResult({
    required this.updatedContent,
    required this.strategy,
    required this.matchedText,
    required this.matchCount,
    required this.line,
    required this.column,
  });

  final String updatedContent;
  final SmartEditStrategy strategy;
  final String matchedText;
  final int matchCount;
  final int line;
  final int column;

  Map<String, dynamic> toDetails({
    required String command,
    required String requestedText,
    required String newText,
  }) {
    return {
      if (command == 'str_replace') 'old_text': requestedText,
      if (command != 'str_replace') 'anchor_text': requestedText,
      'new_text': newText,
      'match_count': matchCount,
      'matched_text': matchedText,
      'strategy': strategy.name,
      'line': line,
      'column': column,
    };
  }
}

class SmartFileEditException implements Exception {
  const SmartFileEditException(this.message, {this.suggestions = const []});

  final String message;
  final List<String> suggestions;

  Map<String, dynamic> toJson() {
    return {
      'error': message,
      if (suggestions.isNotEmpty) 'suggestions': suggestions,
    };
  }

  @override
  String toString() => message;
}

class SmartFileEditService {
  const SmartFileEditService();

  static const int _maxFuzzyContentLength = 50000;
  static const int _maxFuzzyPatternLength = 2000;
  static const int _maxFuzzyComparisons = 20000;

  Future<SmartFileEditResult> editFile({
    required SmartFileReader read,
    required SmartFileWriter write,
    required SmartFileEditRequest request,
  }) async {
    final content = await read();
    final result = editContent(content: content, request: request);
    await write(result.updatedContent);
    return result;
  }

  SmartFileEditResult editContent({
    required String content,
    required SmartFileEditRequest request,
  }) {
    final command = request.command.trim().toLowerCase();
    if (command != 'str_replace' &&
        command != 'insert_before' &&
        command != 'insert_after' &&
        command != 'replace_lines') {
      throw SmartFileEditException('Unsupported edit command: $command');
    }

    if (command == 'replace_lines') {
      return _replaceLines(content: content, request: request);
    }

    final targetText = request.targetText;
    if (targetText.isEmpty) {
      throw SmartFileEditException(
        command == 'str_replace'
            ? 'old_text is required for str_replace.'
            : 'anchor_text is required for $command.',
      );
    }

    final match = _findBestMatch(content: content, request: request);
    final insertStart = match.start;
    final insertEnd = match.end;
    final editIndex = switch (command) {
      'insert_before' => insertStart,
      'insert_after' => insertEnd,
      _ => insertStart,
    };

    final updatedContent = switch (command) {
      'str_replace' =>
        content.substring(0, insertStart) +
            request.newText +
            content.substring(insertEnd),
      'insert_before' || 'insert_after' =>
        content.substring(0, editIndex) +
            request.newText +
            content.substring(editIndex),
      _ => content,
    };

    final position = _lineColumnForIndex(content, match.start);
    return SmartFileEditResult(
      updatedContent: updatedContent,
      strategy: match.strategy,
      matchedText: content.substring(match.start, match.end),
      matchCount: match.totalMatches,
      line: position.line,
      column: position.column,
    );
  }

  SmartFileEditResult _replaceLines({
    required String content,
    required SmartFileEditRequest request,
  }) {
    final requestedStart = request.startLine ?? request.lineNumber;
    final requestedEnd = request.endLine ?? request.lineNumber;
    if (requestedStart == null || requestedEnd == null) {
      throw const SmartFileEditException(
        'replace_lines requires start_line and end_line, or line_number for a single line.',
        suggestions: [
          'Read the file again and pass the exact 1-based line range to replace.',
        ],
      );
    }

    final lines = _lineSpans(content);
    if (lines.isEmpty) {
      throw const SmartFileEditException(
        'Cannot replace lines in an empty file.',
      );
    }

    final startLine = requestedStart.clamp(1, lines.length);
    final endLine = requestedEnd.clamp(startLine, lines.length);
    final start = lines[startLine - 1].start;
    final end = lines[endLine - 1].end;
    final updatedContent =
        content.substring(0, start) + request.newText + content.substring(end);
    final position = _lineColumnForIndex(content, start);

    return SmartFileEditResult(
      updatedContent: updatedContent,
      strategy: SmartEditStrategy.lineExact,
      matchedText: content.substring(start, end),
      matchCount: 1,
      line: position.line,
      column: position.column,
    );
  }

  _SmartMatch _findBestMatch({
    required String content,
    required SmartFileEditRequest request,
  }) {
    final targetText = request.targetText;
    final expectedOccurrences = request.expectedOccurrences.clamp(1, 100);

    final exactMatches = _findExactMatches(content, targetText);
    if (exactMatches.length == expectedOccurrences) {
      return exactMatches.first.copyWith(
        strategy: SmartEditStrategy.exact,
        totalMatches: exactMatches.length,
      );
    }

    final lineRange = _lineRangeForRequest(content, request);
    if (lineRange != null) {
      final lineExactMatches = _findExactMatches(
        lineRange.text,
        targetText,
        offset: lineRange.startOffset,
      );
      if (lineExactMatches.length == expectedOccurrences) {
        return lineExactMatches.first.copyWith(
          strategy: SmartEditStrategy.lineExact,
          totalMatches: lineExactMatches.length,
        );
      }

      final lineNormalizedMatches = _findWhitespaceNormalizedMatches(
        lineRange.text,
        targetText,
        offset: lineRange.startOffset,
      );
      if (lineNormalizedMatches.length == expectedOccurrences) {
        return lineNormalizedMatches.first.copyWith(
          strategy: SmartEditStrategy.lineWhitespaceNormalized,
          totalMatches: lineNormalizedMatches.length,
        );
      }
    }

    final contextRange = _contextRangeForRequest(content, request);
    if (contextRange != null) {
      final contextExactMatches = _findExactMatches(
        contextRange.text,
        targetText,
        offset: contextRange.startOffset,
      );
      final nearestContextExact = _nearestUniqueMatch(
        matches: contextExactMatches,
        context: contextRange.context,
      );
      if (nearestContextExact != null && expectedOccurrences == 1) {
        return nearestContextExact.copyWith(
          strategy: SmartEditStrategy.contextExact,
          totalMatches: 1,
        );
      }

      final contextNormalizedMatches = _findWhitespaceNormalizedMatches(
        contextRange.text,
        targetText,
        offset: contextRange.startOffset,
      );
      final nearestContextNormalized = _nearestUniqueMatch(
        matches: contextNormalizedMatches,
        context: contextRange.context,
      );
      if (nearestContextNormalized != null && expectedOccurrences == 1) {
        return nearestContextNormalized.copyWith(
          strategy: SmartEditStrategy.contextWhitespaceNormalized,
          totalMatches: 1,
        );
      }
    }

    final normalizedMatches = _findWhitespaceNormalizedMatches(
      content,
      targetText,
    );
    if (normalizedMatches.length == expectedOccurrences) {
      return normalizedMatches.first.copyWith(
        strategy: SmartEditStrategy.whitespaceNormalized,
        totalMatches: normalizedMatches.length,
      );
    }

    // Fuzzy matching as last resort for str_replace
    if (request.command.trim().toLowerCase() == 'str_replace' &&
        expectedOccurrences == 1) {
      final fuzzyMatch = _findFuzzyMatch(
        content,
        targetText,
        threshold: 0.60, // 60% similarity threshold - more lenient
      );
      if (fuzzyMatch != null) {
        return fuzzyMatch.copyWith(
          strategy: SmartEditStrategy.fuzzy,
          totalMatches: 1,
        );
      }
    }

    throw _buildNotFoundException(
      targetText: targetText,
      exactCount: exactMatches.length,
      normalizedCount: normalizedMatches.length,
      expectedOccurrences: expectedOccurrences,
      hasLineHint: lineRange != null,
      hasContextHint: request.contextText.trim().isNotEmpty,
    );
  }

  SmartFileEditException _buildNotFoundException({
    required String targetText,
    required int exactCount,
    required int normalizedCount,
    required int expectedOccurrences,
    required bool hasLineHint,
    required bool hasContextHint,
  }) {
    final label = targetText.length > 80
        ? '${targetText.substring(0, 77)}...'
        : targetText;
    final suggestions = <String>[
      'Read the file again and copy the current anchor text from the latest content.',
      'Provide line_number or start_line/end_line when the anchor appears near a known location.',
      'Provide context_text with a unique nearby snippet to disambiguate repeated anchors.',
    ];

    if (exactCount != expectedOccurrences && exactCount > 0) {
      suggestions.insert(
        0,
        'Set expected_occurrences to $exactCount if all exact matches should be considered valid.',
      );
    }
    if (normalizedCount != expectedOccurrences && normalizedCount > 0) {
      suggestions.insert(
        0,
        'Whitespace-normalized matching found $normalizedCount candidate(s); add context_text or a line hint.',
      );
    }
    if (exactCount == 0 && normalizedCount == 0) {
      suggestions.insert(
        0,
        'The text was not found at all. Check for typos or verify the file content with read.',
      );
    }
    if (hasLineHint) {
      suggestions.add(
        'The line hint was used, but the target was not unique inside that range.',
      );
    }
    if (hasContextHint) {
      suggestions.add(
        'The context_text was used, but it did not produce a unique target match.',
      );
    }

    return SmartFileEditException(
      'Could not find a unique edit target for "$label". Expected '
      '$expectedOccurrences match(es), found $exactCount exact and '
      '$normalizedCount whitespace-normalized match(es).',
      suggestions: suggestions,
    );
  }

  List<_SmartMatch> _findExactMatches(
    String content,
    String pattern, {
    int offset = 0,
  }) {
    if (pattern.isEmpty) {
      return const [];
    }

    final matches = <_SmartMatch>[];
    var start = 0;
    while (true) {
      final index = content.indexOf(pattern, start);
      if (index == -1) {
        break;
      }
      matches.add(
        _SmartMatch(
          start: offset + index,
          end: offset + index + pattern.length,
          strategy: SmartEditStrategy.exact,
          totalMatches: 0,
        ),
      );
      start = index + pattern.length;
    }
    return matches;
  }

  List<_SmartMatch> _findWhitespaceNormalizedMatches(
    String content,
    String pattern, {
    int offset = 0,
  }) {
    final normalizedContent = _NormalizedText.from(content);
    final normalizedPattern = _NormalizedText.from(pattern).text;
    if (normalizedPattern.isEmpty) {
      return const [];
    }

    final matches = <_SmartMatch>[];
    var start = 0;
    while (true) {
      final index = normalizedContent.text.indexOf(normalizedPattern, start);
      if (index == -1) {
        break;
      }

      final endIndex = index + normalizedPattern.length - 1;
      matches.add(
        _SmartMatch(
          start: offset + normalizedContent.ranges[index].start,
          end: offset + normalizedContent.ranges[endIndex].end,
          strategy: SmartEditStrategy.whitespaceNormalized,
          totalMatches: 0,
        ),
      );
      start = index + normalizedPattern.length;
    }

    return matches;
  }

  /// Find the best fuzzy match for a pattern in content.
  /// Uses sliding window with levenshtein similarity.
  _SmartMatch? _findFuzzyMatch(
    String content,
    String pattern, {
    required double threshold,
  }) {
    if (pattern.isEmpty || content.isEmpty) {
      return null;
    }
    if (content.length > _maxFuzzyContentLength ||
        pattern.length > _maxFuzzyPatternLength) {
      return null;
    }

    // Build character index map for the content
    final contentIndexMap = _buildFuzzyIndexMap(content);

    // Normalize pattern for comparison
    final normalizedPattern = _normalizeForFuzzy(pattern);

    // For short patterns, require higher threshold
    final effectiveThreshold = normalizedPattern.length < 20
        ? threshold + 0.15
        : threshold;

    _FuzzyMatchCandidate? bestMatch;
    var bestScore = 0.0;

    // Try different window sizes around the pattern length
    final patternLen = normalizedPattern.length;
    final normalizedContent = contentIndexMap.normalizedText;
    if (normalizedContent.isEmpty || patternLen == 0) {
      return null;
    }
    if (patternLen > normalizedContent.length) {
      return null;
    }
    final minWindow = (patternLen * 0.5).floor().clamp(1, patternLen);
    final maxWindow = (patternLen * 1.5).ceil().clamp(
      patternLen,
      normalizedContent.length,
    );
    final totalComparisons =
        (maxWindow - minWindow + 1) *
        (normalizedContent.length - minWindow + 1);
    if (totalComparisons > _maxFuzzyComparisons) {
      return null;
    }

    for (var windowSize = minWindow; windowSize <= maxWindow; windowSize++) {
      for (var i = 0; i <= normalizedContent.length - windowSize; i++) {
        final window = normalizedContent.substring(i, i + windowSize);
        final similarity = _levenshteinSimilarity(normalizedPattern, window);

        if (similarity > bestScore && similarity >= effectiveThreshold) {
          bestScore = similarity;

          // Map back to original content positions
          final originalStart = contentIndexMap.mapToOriginal(i);
          final originalEnd =
              contentIndexMap.mapToOriginal(i + windowSize - 1) + 1;

          bestMatch = _FuzzyMatchCandidate(
            start: originalStart,
            end: originalEnd,
            score: similarity,
          );
        }
      }
    }

    if (bestMatch == null) return null;

    return _SmartMatch(
      start: bestMatch.start,
      end: bestMatch.end,
      strategy: SmartEditStrategy.fuzzy,
      totalMatches: 0,
    );
  }

  /// Build an index map from normalized text back to original positions
  _FuzzyIndexMap _buildFuzzyIndexMap(String original) {
    final normalizedBuffer = StringBuffer();
    final originalPositions = <int>[];
    var lastWasSpace = false;

    for (var i = 0; i < original.length; i++) {
      final char = original[i];
      final lowerChar = char.toLowerCase();

      // Skip whitespace normalization - we'll include spaces but normalize multiple spaces
      if (_isWhitespaceFuzzy(char.codeUnitAt(0))) {
        // Only add a single space for any whitespace sequence
        if (!lastWasSpace && normalizedBuffer.isNotEmpty) {
          normalizedBuffer.write(' ');
          originalPositions.add(i);
          lastWasSpace = true;
        }
      } else {
        normalizedBuffer.write(lowerChar);
        originalPositions.add(i);
        lastWasSpace = false;
      }
    }

    return _FuzzyIndexMap(
      normalizedText: normalizedBuffer.toString().trim(),
      originalPositions: originalPositions,
    );
  }

  static bool _isWhitespaceFuzzy(int codeUnit) {
    return codeUnit == 9 ||
        codeUnit == 10 ||
        codeUnit == 11 ||
        codeUnit == 12 ||
        codeUnit == 13 ||
        codeUnit == 32;
  }

  /// Normalize text for fuzzy matching (lowercase, normalize whitespace)
  String _normalizeForFuzzy(String text) {
    final buffer = StringBuffer();
    var lastWasSpace = false;

    for (var i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      if (_isWhitespaceFuzzy(codeUnit)) {
        if (!lastWasSpace && buffer.isNotEmpty) {
          buffer.write(' ');
          lastWasSpace = true;
        }
      } else {
        buffer.write(String.fromCharCode(codeUnit).toLowerCase());
        lastWasSpace = false;
      }
    }

    return buffer.toString().trim();
  }

  /// Calculate levenshtein similarity (0.0 to 1.0)
  double _levenshteinSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final distance = _levenshteinDistance(s1, s2);
    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    return 1.0 - (distance / maxLen);
  }

  /// Calculate levenshtein distance between two strings
  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    // Use two rows for space efficiency
    final prevRow = List<int>.filled(s2.length + 1, 0);
    final currRow = List<int>.filled(s2.length + 1, 0);

    for (var j = 0; j <= s2.length; j++) {
      prevRow[j] = j;
    }

    for (var i = 1; i <= s1.length; i++) {
      currRow[0] = i;
      for (var j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        currRow[j] = [
          currRow[j - 1] + 1, // insertion
          prevRow[j] + 1, // deletion
          prevRow[j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      // Copy current row to previous row
      for (var j = 0; j <= s2.length; j++) {
        prevRow[j] = currRow[j];
      }
    }

    return currRow[s2.length];
  }

  _TextRange? _lineRangeForRequest(
    String content,
    SmartFileEditRequest request,
  ) {
    final lineNumber = request.lineNumber;
    final requestedStart = request.startLine ?? lineNumber;
    final requestedEnd = request.endLine ?? lineNumber;
    if (requestedStart == null && requestedEnd == null) {
      return null;
    }

    final lines = _lineSpans(content);
    if (lines.isEmpty) {
      return null;
    }

    final startLine = (requestedStart ?? 1).clamp(1, lines.length);
    final endLine = (requestedEnd ?? startLine).clamp(startLine, lines.length);
    final start = lines[startLine - 1].start;
    final end = lines[endLine - 1].end;
    return _TextRange(startOffset: start, text: content.substring(start, end));
  }

  _ContextRange? _contextRangeForRequest(
    String content,
    SmartFileEditRequest request,
  ) {
    final contextText = request.contextText.trim();
    if (contextText.isEmpty) {
      return null;
    }

    final exactContexts = _findExactMatches(content, contextText);
    final normalizedContexts = exactContexts.isNotEmpty
        ? exactContexts
        : _findWhitespaceNormalizedMatches(content, contextText);
    if (normalizedContexts.length != 1) {
      return null;
    }

    final lines = _lineSpans(content);
    if (lines.isEmpty) {
      return null;
    }

    final context = normalizedContexts.single;
    final startLineIndex = _lineIndexForOffset(lines, context.start);
    final endLineIndex = _lineIndexForOffset(lines, context.end);
    final windowStart = (startLineIndex - 20).clamp(0, lines.length - 1);
    final windowEnd = (endLineIndex + 20).clamp(windowStart, lines.length - 1);
    final start = lines[windowStart].start;
    final end = lines[windowEnd].end;
    return _ContextRange(
      startOffset: start,
      text: content.substring(start, end),
      context: context,
    );
  }

  _SmartMatch? _nearestUniqueMatch({
    required List<_SmartMatch> matches,
    required _SmartMatch context,
  }) {
    if (matches.isEmpty) {
      return null;
    }

    var nearestDistance = 1 << 62;
    final nearest = <_SmartMatch>[];
    for (final match in matches) {
      final distance = _distanceBetween(match, context);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest
          ..clear()
          ..add(match);
      } else if (distance == nearestDistance) {
        nearest.add(match);
      }
    }

    return nearest.length == 1 ? nearest.single : null;
  }

  int _distanceBetween(_SmartMatch match, _SmartMatch context) {
    if (match.end <= context.start) {
      return context.start - match.end;
    }
    if (match.start >= context.end) {
      return match.start - context.end;
    }
    return 0;
  }

  List<_LineSpan> _lineSpans(String content) {
    if (content.isEmpty) {
      return const [];
    }

    final spans = <_LineSpan>[];
    var start = 0;
    for (var i = 0; i < content.length; i++) {
      if (content.codeUnitAt(i) == 10) {
        spans.add(_LineSpan(start: start, end: i + 1));
        start = i + 1;
      }
    }
    if (start < content.length) {
      spans.add(_LineSpan(start: start, end: content.length));
    }
    return spans;
  }

  int _lineIndexForOffset(List<_LineSpan> lines, int offset) {
    for (var i = 0; i < lines.length; i++) {
      if (offset >= lines[i].start && offset <= lines[i].end) {
        return i;
      }
    }
    return lines.length - 1;
  }

  _Position _lineColumnForIndex(String content, int index) {
    var line = 1;
    var column = 1;
    for (var i = 0; i < index && i < content.length; i++) {
      if (content.codeUnitAt(i) == 10) {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    return _Position(line: line, column: column);
  }
}

class _NormalizedText {
  const _NormalizedText({required this.text, required this.ranges});

  final String text;
  final List<_SourceRange> ranges;

  static _NormalizedText from(String source) {
    final buffer = StringBuffer();
    final ranges = <_SourceRange>[];
    var i = 0;
    var hasPendingSpace = false;
    var pendingStart = 0;
    var pendingEnd = 0;

    while (i < source.length) {
      final codeUnit = source.codeUnitAt(i);
      if (_isWhitespace(codeUnit)) {
        final start = i;
        while (i < source.length && _isWhitespace(source.codeUnitAt(i))) {
          i++;
        }
        if (buffer.isNotEmpty) {
          hasPendingSpace = true;
          pendingStart = start;
          pendingEnd = i;
        }
        continue;
      }

      if (hasPendingSpace) {
        buffer.write(' ');
        ranges.add(_SourceRange(start: pendingStart, end: pendingEnd));
        hasPendingSpace = false;
      }

      buffer.writeCharCode(codeUnit);
      ranges.add(_SourceRange(start: i, end: i + 1));
      i++;
    }

    return _NormalizedText(text: buffer.toString(), ranges: ranges);
  }

  static bool _isWhitespace(int codeUnit) {
    return codeUnit == 9 ||
        codeUnit == 10 ||
        codeUnit == 11 ||
        codeUnit == 12 ||
        codeUnit == 13 ||
        codeUnit == 32;
  }
}

class _SmartMatch {
  const _SmartMatch({
    required this.start,
    required this.end,
    required this.strategy,
    required this.totalMatches,
  });

  final int start;
  final int end;
  final SmartEditStrategy strategy;
  final int totalMatches;

  _SmartMatch copyWith({SmartEditStrategy? strategy, int? totalMatches}) {
    return _SmartMatch(
      start: start,
      end: end,
      strategy: strategy ?? this.strategy,
      totalMatches: totalMatches ?? this.totalMatches,
    );
  }
}

class _TextRange {
  const _TextRange({required this.startOffset, required this.text});

  final int startOffset;
  final String text;
}

class _ContextRange extends _TextRange {
  const _ContextRange({
    required super.startOffset,
    required super.text,
    required this.context,
  });

  final _SmartMatch context;
}

class _LineSpan {
  const _LineSpan({required this.start, required this.end});

  final int start;
  final int end;
}

class _SourceRange {
  const _SourceRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _Position {
  const _Position({required this.line, required this.column});

  final int line;
  final int column;
}

/// Helper class to map normalized fuzzy text positions back to original
class _FuzzyIndexMap {
  _FuzzyIndexMap({
    required this.normalizedText,
    required this.originalPositions,
  });

  final String normalizedText;
  final List<int> originalPositions;

  /// Map a position in normalized text to original text
  int mapToOriginal(int normalizedPos) {
    if (normalizedPos < 0) return 0;
    if (normalizedPos >= originalPositions.length) {
      return originalPositions.isEmpty ? 0 : originalPositions.last + 1;
    }
    return originalPositions[normalizedPos];
  }
}

/// Candidate for fuzzy matching with position and score
class _FuzzyMatchCandidate {
  _FuzzyMatchCandidate({
    required this.start,
    required this.end,
    required this.score,
  });

  final int start;
  final int end;
  final double score;
}
