class CommandOptimization {
  const CommandOptimization({
    required this.commands,
    required this.originalCount,
    required this.optimizedCount,
    required this.changed,
  });

  final List<String> commands;
  final int originalCount;
  final int optimizedCount;
  final bool changed;

  String? get singleCommand => commands.length == 1 ? commands.first : null;

  Map<String, dynamic> toJson() => {
    'commands': commands,
    'original_count': originalCount,
    'optimized_count': optimizedCount,
    'changed': changed,
    if (originalCount > 0)
      'savings_percent':
          (((originalCount - optimizedCount) / originalCount) * 100).round(),
  };
}

class CommandOptimizer {
  const CommandOptimizer();

  CommandOptimization optimizeCommand(String command) {
    final parts = _splitSequentialShellCommands(command);
    if (parts.length < 2) {
      return CommandOptimization(
        commands: [command.trim()],
        originalCount: command.trim().isEmpty ? 0 : 1,
        optimizedCount: command.trim().isEmpty ? 0 : 1,
        changed: false,
      );
    }

    return optimizeCommands(parts);
  }

  CommandOptimization optimizeCommands(List<String> commands) {
    final normalized = commands
        .map((command) => command.trim())
        .where((command) => command.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return const CommandOptimization(
        commands: [],
        originalCount: 0,
        optimizedCount: 0,
        changed: false,
      );
    }

    final optimized = <String>[];
    var changed = false;
    var index = 0;
    while (index < normalized.length) {
      final command = normalized[index];
      final cdPath = _cdPath(command);
      if (cdPath == null || index + 1 >= normalized.length) {
        optimized.add(command);
        index += 1;
        continue;
      }

      final following = <String>[];
      var next = index + 1;
      while (next < normalized.length && _cdPath(normalized[next]) == null) {
        following.add(normalized[next]);
        next += 1;
      }

      if (following.isEmpty) {
        optimized.add(command);
        index += 1;
        continue;
      }

      final combined = _combineCdAndCommands(command, cdPath, following);
      optimized.add(combined);
      changed = true;
      index = next;
    }

    return CommandOptimization(
      commands: optimized,
      originalCount: normalized.length,
      optimizedCount: optimized.length,
      changed: changed || optimized.length != normalized.length,
    );
  }

  String _combineCdAndCommands(
    String cdCommand,
    String cdPath,
    List<String> following,
  ) {
    if (following.length == 1) {
      final command = following.single;
      final gitCommand = _optimizeGitCommand(cdPath, command);
      if (gitCommand != null) return gitCommand;

      final absolutePathCommand = _optimizeAbsolutePathCommand(cdPath, command);
      if (absolutePathCommand != null) return absolutePathCommand;
    }

    final catCommand = _optimizeCatCommands(cdPath, following);
    if (catCommand != null) return catCommand;

    return [cdCommand, ...following].join(' && ');
  }

  String? _optimizeGitCommand(String path, String command) {
    final words = _splitShellWords(command);
    if (words.length < 2 || words.first != 'git') return null;
    final subcommand = words[1];
    const supportedSubcommands = {
      'status',
      'log',
      'diff',
      'add',
      'commit',
      'push',
      'pull',
      'branch',
      'checkout',
    };
    if (!supportedSubcommands.contains(subcommand)) return null;
    return 'git -C ${_shellQuote(path)} ${command.substring(3).trim()}';
  }

  String? _optimizeAbsolutePathCommand(String basePath, String command) {
    final words = _splitShellWords(command);
    if (words.isEmpty) return null;
    final executable = words.first;
    if (executable == 'ls') {
      return '$command ${_shellQuote(_joinPath(basePath, ''))}';
    }

    const pathAwareCommands = {'cat', 'less', 'head', 'tail'};
    if (pathAwareCommands.contains(executable)) {
      final rewritten = _rewriteRelativeArguments(basePath, command, words);
      return rewritten == command ? null : rewritten;
    }

    const scriptRunners = {'python', 'python3', 'node', 'bash', 'sh'};
    if (scriptRunners.contains(executable) && words.length >= 2) {
      final script = words[1];
      if (!_isRelativePath(script)) return null;
      final rest = words.skip(2).map(_shellQuote).join(' ');
      final rewritten =
          '$executable ${_shellQuote(_joinPath(basePath, script))}';
      return rest.isEmpty ? rewritten : '$rewritten $rest';
    }

    return null;
  }

  String? _optimizeCatCommands(String basePath, List<String> commands) {
    if (commands.length < 2) return null;
    final paths = <String>[];
    for (final command in commands) {
      final words = _splitShellWords(command);
      if (words.length != 2 || words.first != 'cat') return null;
      final filePath = words[1];
      if (!_isRelativePath(filePath)) return null;
      paths.add(_shellQuote(_joinPath(basePath, filePath)));
    }
    return 'cat ${paths.join(' ')}';
  }

  String? _cdPath(String command) {
    final words = _splitShellWords(command);
    if (words.length != 2 || words.first != 'cd' || words[1] == '-') {
      return null;
    }
    return words[1];
  }

  String? _rewriteRelativeArguments(
    String basePath,
    String command,
    List<String> words,
  ) {
    if (words.length < 2) return null;
    final rewritten = <String>[words.first];
    var changed = false;
    for (final word in words.skip(1)) {
      if (word.startsWith('-') || !_isRelativePath(word)) {
        rewritten.add(_shellQuote(word));
        continue;
      }
      rewritten.add(_shellQuote(_joinPath(basePath, word)));
      changed = true;
    }
    return changed ? rewritten.join(' ') : command;
  }

  bool _isRelativePath(String value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.startsWith('~') ||
        value.startsWith('-') ||
        value.contains('*') ||
        value.contains('?') ||
        value.contains('[') ||
        value.contains(']') ||
        value.contains(r'$')) {
      return false;
    }
    return true;
  }

  String _joinPath(String basePath, String relativePath) {
    final trimmedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    if (relativePath.isEmpty) return '$trimmedBase/';
    return '$trimmedBase/$relativePath';
  }

  List<String> _splitSequentialShellCommands(String command) {
    final parts = <String>[];
    final buffer = StringBuffer();
    String? quote;

    for (var index = 0; index < command.length; index += 1) {
      final char = command[index];
      final next = index + 1 < command.length ? command[index + 1] : '';
      if (char == r'\' && quote != "'") {
        buffer.write(char);
        if (next.isNotEmpty) {
          index += 1;
          buffer.write(next);
        }
        continue;
      }
      if ((char == "'" || char == '"')) {
        quote = quote == char ? null : (quote ?? char);
        buffer.write(char);
        continue;
      }
      if (quote == null && char == '&' && next == '&') {
        _addPart(parts, buffer);
        index += 1;
        continue;
      }
      if (quote == null && char == '\n') {
        _addPart(parts, buffer);
        continue;
      }
      if (quote == null && (char == ';' || char == '|' || char == '`')) {
        return [command.trim()];
      }
      buffer.write(char);
    }
    _addPart(parts, buffer);
    return parts;
  }

  void _addPart(List<String> parts, StringBuffer buffer) {
    final part = buffer.toString().trim();
    if (part.isNotEmpty) parts.add(part);
    buffer.clear();
  }

  List<String> _splitShellWords(String command) {
    final words = <String>[];
    final buffer = StringBuffer();
    String? quote;

    for (var index = 0; index < command.length; index += 1) {
      final char = command[index];
      final next = index + 1 < command.length ? command[index + 1] : '';
      if (char == r'\' && quote != "'") {
        if (next.isNotEmpty) {
          index += 1;
          buffer.write(next);
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = quote == char ? null : (quote ?? char);
        continue;
      }
      if (quote == null && char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) words.add(buffer.toString());
    return words;
  }

  String _shellQuote(String value) {
    if (RegExp(r'^[A-Za-z0-9_./~:=@%+-]+$').hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}
