/// Converts chat Markdown into readable text for system notifications.
///
/// Notification surfaces do not render Markdown. This keeps the response's
/// full textual content while removing formatting syntax that would otherwise
/// be displayed literally.
String notificationPlainText(String markdown) {
  var text = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  text = text.replaceAllMapped(
    RegExp(r'^[ \t]*```[^\n]*\n([\s\S]*?)^[ \t]*```[ \t]*$', multiLine: true),
    (match) => match.group(1)?.trimRight() ?? '',
  );
  text = text.replaceAll(RegExp(r'^[ \t]*```[^\n]*$', multiLine: true), '');

  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'<((?:https?://|mailto:)[^>]+)>'),
    (match) => match.group(1) ?? '',
  );

  final output = <String>[];
  for (final sourceLine in text.split('\n')) {
    var line = sourceLine;
    if (_isTableSeparator(line)) continue;

    if (_looksLikeTableRow(line)) {
      line = _plainTableRow(line);
    } else {
      line = line.replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s+'), '');
      line = line.replaceFirst(RegExp(r'^\s*>\s?'), '');
      line = line.replaceFirstMapped(RegExp(r'^\s*[-+*]\s+'), (_) => '• ');
      line = line.replaceFirstMapped(
        RegExp(r'^\s*(\d+)[.)]\s+'),
        (match) => '${match.group(1)}. ',
      );
    }

    output.add(_stripInlineMarkdown(line).trimRight());
  }

  return output
      .join('\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Produces spoken prose while omitting visual Markdown table contents.
///
/// The assistant prompt normally introduces tables in the response language.
/// This fallback cue covers responses that contain a table without doing so.
String speechPlainText(String markdown, {String? languageCode}) {
  final lines = markdown
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final output = <String>[];
  var removedTable = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final nextIsSeparator =
        index + 1 < lines.length && _isTableSeparator(lines[index + 1]);
    if (_looksLikeTableRow(line) && (nextIsSeparator || removedTable)) {
      removedTable = true;
      continue;
    }
    if (_isTableSeparator(line)) {
      removedTable = true;
      continue;
    }
    if (removedTable && line.trim().isEmpty) {
      removedTable = false;
      continue;
    }
    output.add(line);
  }

  var plain = notificationPlainText(output.join('\n'));
  if (!markdown.split('\n').any(_isTableSeparator)) return plain;
  final lower = plain.toLowerCase();
  final alreadyIntroduced =
      lower.contains('table below') ||
      lower.contains('neeche') ||
      plain.contains('جدول') ||
      plain.contains('نیچے');
  if (alreadyIntroduced) return plain;

  final isUrduScript = RegExp(r'[\u0600-\u06FF]').hasMatch(markdown);
  final isUrdu = languageCode?.toLowerCase().startsWith('ur') ?? false;
  final cue = isUrduScript
      ? 'تفصیل نیچے جدول میں دکھائی گئی ہے۔'
      : isUrdu
      ? 'Tafseel neeche table mein dikhai gayi hai, aap dekh sakte hain.'
      : 'You can see the details in the table below.';
  plain = plain.isEmpty ? cue : '$plain\n$cue';
  return plain;
}

bool _looksLikeTableRow(String line) {
  final trimmed = line.trim();
  return trimmed.contains('|') &&
      (trimmed.startsWith('|') || trimmed.endsWith('|'));
}

bool _isTableSeparator(String line) {
  if (!_looksLikeTableRow(line)) return false;
  final cells = line
      .trim()
      .replaceFirst(RegExp(r'^\|'), '')
      .replaceFirst(RegExp(r'\|$'), '')
      .split('|');
  return cells.isNotEmpty &&
      cells.every((cell) => RegExp(r'^\s*:?-{3,}:?\s*$').hasMatch(cell));
}

String _plainTableRow(String line) {
  return line
      .trim()
      .replaceFirst(RegExp(r'^\|'), '')
      .replaceFirst(RegExp(r'\|$'), '')
      .split('|')
      .map((cell) => _stripInlineMarkdown(cell.trim()))
      .where((cell) => cell.isNotEmpty)
      .join(' • ');
}

String _stripInlineMarkdown(String text) {
  var result = text;
  result = result.replaceAllMapped(
    RegExp(r'(`{1,2})(.*?)\1'),
    (match) => match.group(2) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'\*\*(.*?)\*\*'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'(?<!\w)__([^_\n]+)__(?!\w)'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'\*([^*\n]+)\*'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'(?<!\w)_([^_\n]+)_(?!\w)'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'~~(.*?)~~'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAll(RegExp(r'<[^>]+>'), '');
  result = result.replaceAllMapped(
    RegExp(r'\\([\\`*_{}\[\]()#+\-.!>])'),
    (match) => match.group(1) ?? '',
  );
  return result;
}
