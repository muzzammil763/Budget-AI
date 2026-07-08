part of 'chat_provider.dart';

bool _isSvgPath(String path) => path.toLowerCase().endsWith('.svg');

String _fileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? path : segments.last;
}

Future<String> _buildMessageTextWithSvgAttachments(
  String message,
  List<String>? imagePaths,
) async {
  if (imagePaths == null || imagePaths.isEmpty) {
    return message;
  }

  final svgSections = <String>[];

  for (final path in imagePaths) {
    if (!_isSvgPath(path)) {
      continue;
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }

      final svgText = await file.readAsString();
      if (svgText.trim().isEmpty) {
        continue;
      }

      final fileName = _fileNameFromPath(path);
      svgSections.add(
        'Attached SVG file: `$fileName`\n```svg\n${svgText.trim()}\n```',
      );
    } catch (e) {
      debugPrint('[ChatProvider] Error reading SVG $path: $e');
    }
  }

  if (svgSections.isEmpty) {
    return message;
  }

  final baseText = message.trim();
  final prefix = baseText.isEmpty
      ? 'Please use the attached SVG source below as input.'
      : baseText;

  return '$prefix\n\n${svgSections.join('\n\n')}';
}

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
  return 'Current date: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}\n'
      'Current date and time: $weekday, ${now.day} $month ${now.year} at $hour:$min (${now.timeZoneName}, UTC$sign$oh:$om).';
}

String _buildChatBaseSystemPrompt() {
  final segments = <String>[
    _buildBehaviorPrompt(),
    _buildDateTimeContextPrompt(),
  ];

  return segments.map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n\n');
}

Future<String> _buildChatSystemPrompt() async {
  final basePrompt = _buildChatBaseSystemPrompt();
  final contextSections = await _buildSystemContextSections();

  return [basePrompt, ...contextSections].join('\n\n');
}

Future<String> buildChatSystemPromptSnapshotForDiagnostics() {
  return _buildChatSystemPrompt();
}

Future<List<String>> _buildSystemContextSections() async {
  final sections = <String>[];
  try {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month);
    final todayEntries = await FinanceService.instance.getByDateRange(
      today,
      now,
    );
    final monthEntries = await FinanceService.instance.getByDateRange(
      monthStart,
      now,
    );
    final financeContext = FinanceService.instance.buildContextText(
      todayEntries,
      monthEntries,
    );
    if (financeContext.trim().isNotEmpty) {
      sections.add('Current finance snapshot:\n$financeContext');
    }

    final loans = await LoanService.instance.getAll();
    final loanContext = LoanService.instance.buildContextText(loans);
    if (loanContext.trim().isNotEmpty) {
      sections.add('Current loan snapshot:\n$loanContext');
    }
  } catch (e) {
    debugPrint('[ChatProvider] Failed to build finance context: $e');
  }
  return sections;
}

Future<List<Map<String, dynamic>>> _buildMessagesWithContext(
  List<Map<String, dynamic>> chatHistory, {
  bool preserveReasoningContent = false,
}) async {
  final contextSections = await _buildSystemContextSections();
  if (contextSections.isEmpty) {
    return _sanitizeConversationStateForApi(
      chatHistory,
      preserveReasoningContent: preserveReasoningContent,
    );
  }

  return [
    {'role': 'system', 'content': contextSections.join('\n\n')},
    ..._sanitizeConversationStateForApi(
      chatHistory,
      preserveReasoningContent: preserveReasoningContent,
    ),
  ];
}

Future<List<Map<String, dynamic>>> _buildToolEnabledMessages(
  List<Map<String, dynamic>> chatHistory, {
  bool preserveReasoningContent = false,
}) async {
  return [
    {'role': 'system', 'content': await _buildChatSystemPrompt()},
    ..._sanitizeConversationStateForApi(
      chatHistory,
      preserveReasoningContent: preserveReasoningContent,
    ),
  ];
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

Map<String, dynamic> _skippedToolAfterFailureResult(String failedToolName) {
  final failedName = formatToolNameForUiFallback(failedToolName);
  return {
    'ok': false,
    'skipped': true,
    'error': 'Skipped because $failedName failed earlier in this tool batch.',
  };
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

Map<String, dynamic>? _toolCallPayloadForHistory(ToolCallChunk toolCall) {
  final name = toolCall.name?.trim();
  final arguments =
      toolCall.arguments ?? _tryParseToolArguments(toolCall.rawArguments);
  if (name == null || name.isEmpty || arguments == null) {
    return null;
  }

  return {
    'id': toolCall.id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };
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

String _assistantContentForHistory({
  required String finalAssistantResponse,
  required String fullResponse,
}) {
  final content = finalAssistantResponse.isEmpty
      ? fullResponse
      : finalAssistantResponse;
  if (content.trim().isNotEmpty) {
    return content;
  }

  return 'Tool execution completed.';
}

List<Map<String, dynamic>> _sanitizeConversationStateForApi(
  List<Map<String, dynamic>> items, {
  bool preserveReasoningContent = false,
}) {
  final sanitized = <Map<String, dynamic>>[];

  var index = 0;
  while (index < items.length) {
    final item = items[index];
    final role = item['role']?.toString();

    if (role == 'assistant' && item['tool_calls'] is List) {
      final validToolCalls = <Map<String, dynamic>>[];
      final validToolCallIds = <String>{};
      for (final rawToolCall in item['tool_calls'] as List) {
        if (rawToolCall is! Map) {
          continue;
        }
        final toolCall = Map<String, dynamic>.from(rawToolCall);
        final id = toolCall['id']?.toString() ?? '';
        final function = toolCall['function'];
        if (id.isEmpty || function is! Map) {
          continue;
        }

        final functionMap = Map<String, dynamic>.from(function);
        final name = functionMap['name']?.toString().trim() ?? '';
        final arguments = _tryParseToolArguments(
          functionMap['arguments']?.toString(),
        );
        if (name.isEmpty || arguments == null) {
          continue;
        }

        validToolCallIds.add(id);
        validToolCalls.add({
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': jsonEncode(arguments)},
        });
      }

      if (validToolCalls.isEmpty) {
        final content = item['content']?.toString().trim() ?? '';
        if (content.isNotEmpty) {
          sanitized.add({'role': 'assistant', 'content': content});
        }
        index++;
        continue;
      }

      final sanitizedAssistant = <String, dynamic>{
        'role': 'assistant',
        'content': item['content'],
        'tool_calls': validToolCalls,
      };
      if (preserveReasoningContent) {
        final reasoningContent = item['reasoning_content']?.toString();
        if (reasoningContent != null && reasoningContent.trim().isNotEmpty) {
          sanitizedAssistant['reasoning_content'] = reasoningContent;
        }
      }
      sanitized.add(sanitizedAssistant);

      final pendingToolCallIds = validToolCallIds.toSet();
      var nextIndex = index + 1;
      while (nextIndex < items.length) {
        final nextItem = items[nextIndex];
        if (nextItem['role']?.toString() != 'tool') break;
        final toolCallId = nextItem['tool_call_id']?.toString() ?? '';
        if (pendingToolCallIds.remove(toolCallId)) {
          sanitized.add(Map<String, dynamic>.from(nextItem));
        }
        nextIndex++;
      }

      for (final missingId in pendingToolCallIds) {
        sanitized.add(_interruptedToolResultForHistory(missingId));
      }

      index = nextIndex;
      continue;
    }

    if (role == 'tool') {
      index++;
      continue;
    }

    sanitized.add(Map<String, dynamic>.from(item));
    index++;
  }

  return sanitized;
}

Map<String, dynamic> _interruptedToolResultForHistory(String toolCallId) {
  return {
    'role': 'tool',
    'tool_call_id': toolCallId,
    'content': jsonEncode({
      'error': 'Tool call was interrupted before returning a result.',
    }),
  };
}

String? _extractReasoningDelta(dynamic delta) {
  if (delta is! Map) return null;

  for (final key in const ['reasoning_content', 'reasoning', 'thinking']) {
    final value = delta[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }

  final details = delta['reasoning_details'];
  if (details is List) {
    final buffer = StringBuffer();
    for (final item in details) {
      if (item is! Map) continue;
      final text = item['text'] ?? item['content'] ?? item['reasoning'];
      if (text is String && text.isNotEmpty) {
        buffer.write(text);
      }
    }
    if (buffer.isNotEmpty) {
      return buffer.toString();
    }
  }

  return null;
}

Map<String, dynamic> _assistantToolCallMessageForHistory({
  required String roundResponse,
  String roundReasoningText = '',
  bool preserveReasoningContent = false,
  required List<Map<String, dynamic>> toolCallsList,
}) {
  final message = <String, dynamic>{
    'role': 'assistant',
    'content': roundResponse.isEmpty ? null : roundResponse,
    'tool_calls': toolCallsList,
  };

  if (preserveReasoningContent && roundReasoningText.trim().isNotEmpty) {
    message['reasoning_content'] = roundReasoningText;
  }

  return message;
}
