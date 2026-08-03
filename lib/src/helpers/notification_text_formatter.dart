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
