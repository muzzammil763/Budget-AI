part of 'chat_provider.dart';

String _buildBehaviorPrompt() {
  final financeEnabled = ToolSettings.isToolEnabled('finance_add');

  return [
    _coreChatBehavior,
    if (financeEnabled) _financeGuidance,
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n\n');
}

String _buildDateTimeContextPrompt() {
  final now = DateTime.now();
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final weekday = weekdays[now.weekday - 1];
  final month = months[now.month - 1];
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final oh = offset.inHours.abs().toString().padLeft(2, '0');
  final om = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final hour = now.hour.toString().padLeft(2, '0');
  final min = now.minute.toString().padLeft(2, '0');
  return 'Now: $weekday, ${now.day} $month ${now.year}, $hour:$min '
      '(${now.timeZoneName}, UTC$sign$oh:$om).';
}

String _buildCurrencyContextPrompt() {
  final currency = CurrencySettingsService.instance.current;
  final sample = CurrencySettingsService.instance.formatAmount(1200);
  return 'Currency: "$currency" (example: $sample).';
}

String _buildUserNameContextPrompt() {
  final userName = UserNameSettingsService.instance.current;
  if (userName.isEmpty) return '';
  return 'User name: "$userName"; use naturally, not in every response.';
}

String _buildChatBaseSystemPrompt() {
  final segments = <String>[
    _buildBehaviorPrompt(),
    _buildUserNameContextPrompt(),
    _buildCurrencyContextPrompt(),
    _buildDateTimeContextPrompt(),
  ];

  return segments.map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n\n');
}

Future<String> _buildChatSystemPrompt() async {
  return _buildChatBaseSystemPrompt();
}

Future<String> buildChatSystemPromptSnapshotForDiagnostics() {
  return _buildChatSystemPrompt();
}

bool _isToolFailure(dynamic result) {
  return result is Map && result['error'] != null;
}

String? _terminalToolFailureResponse(String? toolName, dynamic result) {
  if (!_isToolFailure(result)) return null;
  final name = (toolName ?? '').trim();
  final error = result is Map ? result['error']?.toString().trim() ?? '' : '';
  final cleanError = error.isEmpty ? 'Unknown error.' : error;
  return '${formatToolNameForUiFallback(name)} failed: $cleanError';
}

String formatToolNameForUiFallback(String rawName) {
  final trimmed = rawName.trim();
  if (trimmed.isEmpty) return 'Tool call';
  return trimmed
      .split('_')
      .where((part) => part.trim().isNotEmpty)
      .map(
        (part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

ToolCallStatus _toolStatusForResult(dynamic result) {
  return _isToolFailure(result)
      ? ToolCallStatus.failed
      : ToolCallStatus.completed;
}

Map<String, dynamic>? _tryParseToolArguments(String? rawArguments) {
  final trimmed = rawArguments?.trim() ?? '';
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return null;
  }

  Map<String, dynamic>? parseObject(String candidate) {
    try {
      final parsed = jsonDecode(candidate);
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
    } catch (_) {}
    return null;
  }

  final parsed = parseObject(trimmed);
  if (parsed != null) return parsed;

  final escapedControlChars = _escapeUnescapedJsonStringControlChars(trimmed);
  if (escapedControlChars != trimmed) {
    final repaired = parseObject(escapedControlChars);
    if (repaired != null) return repaired;
  }

  return null;
}

String _escapeUnescapedJsonStringControlChars(String input) {
  final buffer = StringBuffer();
  var inString = false;
  var escaping = false;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];

    if (!inString) {
      buffer.write(char);
      if (char == '"') inString = true;
      continue;
    }

    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }

    if (char == r'\') {
      buffer.write(char);
      escaping = true;
      continue;
    }

    if (char == '"') {
      buffer.write(char);
      inString = false;
      continue;
    }

    if (char == '\n') {
      buffer.write(r'\n');
    } else if (char == '\r') {
      buffer.write(r'\r');
    } else if (char == '\t') {
      buffer.write(r'\t');
    } else if (char == '\b') {
      buffer.write(r'\b');
    } else if (char == '\f') {
      buffer.write(r'\f');
    } else {
      final codeUnit = char.codeUnitAt(0);
      if (codeUnit < 0x20) {
        buffer.write(r'\u' + codeUnit.toRadixString(16).padLeft(4, '0'));
      } else {
        buffer.write(char);
      }
    }
  }

  return buffer.toString();
}

Map<String, dynamic> _malformedToolCallResult(ToolCallChunk toolCall) {
  return {
    'error':
        'Tool arguments could not be parsed before execution. The tool call was ignored so the chat can continue.',
    'raw_arguments': toolCall.rawArguments ?? '',
  };
}

Stream<ChatStreamChunk> _executeToolAndStreamChunks({
  required ToolRegistry toolRegistry,
  required ToolCallChunk toolCall,
  required Map<String, dynamic> arguments,
  required bool Function() isCancelled,
  required void Function(dynamic result) onResult,
}) async* {
  await for (final event in toolRegistry.executeToolStream(
    toolCall.name!,
    arguments,
  )) {
    if (isCancelled()) {
      throw CancelledException();
    }

    onResult(event.result);
    yield ChatStreamChunk(
      content: '',
      toolCall: toolCall.copyWith(
        result: event.result,
        status: event.isComplete
            ? (event.isError
                  ? ToolCallStatus.failed
                  : _toolStatusForResult(event.result))
            : ToolCallStatus.calling,
      ),
      isToolCallComplete: event.isComplete,
    );
  }
}

String _toolResultContent(dynamic result) {
  if (result == null) return 'No result';
  return truncateToolPayloadForStorage(result);
}

List<Map<String, dynamic>> _sanitizeConversationStateForApi(
  List<Map<String, dynamic>> items,
) {
  final sanitized = <Map<String, dynamic>>[];
  var index = 0;
  while (index < items.length) {
    final item = items[index];
    final type = item['type']?.toString();
    final role = item['role']?.toString();

    if (type == 'function_call' ||
        type == 'function_call_output' ||
        type == 'message' ||
        type == 'reasoning') {
      sanitized.add(Map<String, dynamic>.from(item));
      index++;
      continue;
    }

    // Convert saved Chat Completions tool history into Responses API items so
    // conversations created before the OpenAI migration remain resumable.
    if (role == 'assistant' && item['tool_calls'] is List) {
      final content = item['content']?.toString().trim() ?? '';
      if (content.isNotEmpty) {
        sanitized.add({'role': 'assistant', 'content': content});
      }

      final toolResults = <String, String>{};
      var nextIndex = index + 1;
      while (nextIndex < items.length &&
          items[nextIndex]['role']?.toString() == 'tool') {
        final toolItem = items[nextIndex];
        final callId = toolItem['tool_call_id']?.toString() ?? '';
        if (callId.isNotEmpty) {
          toolResults[callId] = toolItem['content']?.toString() ?? 'No result';
        }
        nextIndex++;
      }

      for (final rawToolCall in item['tool_calls'] as List) {
        if (rawToolCall is! Map || rawToolCall['function'] is! Map) continue;
        final callId = rawToolCall['id']?.toString() ?? '';
        final function = rawToolCall['function'] as Map;
        final name = function['name']?.toString().trim() ?? '';
        final arguments = function['arguments']?.toString() ?? '';
        if (callId.isEmpty || name.isEmpty || arguments.isEmpty) continue;
        sanitized.add({
          'type': 'function_call',
          'call_id': callId,
          'name': name,
          'arguments': arguments,
        });
        sanitized.add({
          'type': 'function_call_output',
          'call_id': callId,
          'output':
              toolResults[callId] ??
              jsonEncode({
                'error': 'Tool call was interrupted before returning a result.',
              }),
        });
      }
      index = nextIndex;
      continue;
    }

    if (role == 'user' || role == 'assistant') {
      sanitized.add({
        'role': role,
        'content': item['content']?.toString() ?? '',
      });
    }
    index++;
  }
  return _compactCompletedConversationTurns(sanitized);
}

/// Keeps the current user turn intact because Responses tool calls, reasoning,
/// and outputs must be replayed together. Completed turns need only their
/// visible dialogue; their internal tool payloads are already represented by
/// the assistant's final answer.
List<Map<String, dynamic>> _compactCompletedConversationTurns(
  List<Map<String, dynamic>> items,
) {
  const maxPreviousDialogueItems = 16;
  var currentTurnStart = -1;
  for (var index = items.length - 1; index >= 0; index--) {
    if (items[index]['role']?.toString() == 'user') {
      currentTurnStart = index;
      break;
    }
  }
  if (currentTurnStart <= 0) return items;

  final previousDialogue = items.take(currentTurnStart).where((item) {
    final role = item['role']?.toString();
    final type = item['type']?.toString();
    return (role == 'user' || role == 'assistant') &&
        (type == null || type == 'message');
  }).toList();
  final windowStart = previousDialogue.length > maxPreviousDialogueItems
      ? previousDialogue.length - maxPreviousDialogueItems
      : 0;
  final recentDialogue = previousDialogue.sublist(windowStart);
  while (recentDialogue.isNotEmpty &&
      recentDialogue.first['role']?.toString() != 'user') {
    recentDialogue.removeAt(0);
  }

  return [...recentDialogue, ...items.sublist(currentTurnStart)];
}
