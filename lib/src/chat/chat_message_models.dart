part of 'chat_provider.dart';

class _ToolCallTracker {
  _ToolCallTracker({required this.maxRounds, required this.maxTotalCalls});

  final int maxRounds;
  final int maxTotalCalls;

  int _roundCount = 0;
  int _totalCallCount = 0;
  final Map<String, int> _callFingerprintCounts = {};
  final Map<String, dynamic> _latestResultsByFingerprint = {};

  bool get isBudgetExhausted =>
      _roundCount >= maxRounds || _totalCallCount >= maxTotalCalls;

  /// Called at the top of each `do { } while (shouldContinue)` iteration.
  void beginRound() => _roundCount++;

  /// Returns `true` when the same call has been repeated 1+ times (loop).
  bool isLoop(String name, Map<String, dynamic> arguments) {
    final fingerprint = _fingerprint(name, arguments);
    return (_callFingerprintCounts[fingerprint] ?? 0) >= 1;
  }

  /// Records a call execution. Must be called once per executed tool.
  void recordCall(String name, Map<String, dynamic> arguments) {
    final fingerprint = _fingerprint(name, arguments);
    _callFingerprintCounts[fingerprint] =
        (_callFingerprintCounts[fingerprint] ?? 0) + 1;
    _totalCallCount++;
  }

  void recordResult(
    String name,
    Map<String, dynamic> arguments,
    dynamic result,
  ) {
    _latestResultsByFingerprint[_fingerprint(name, arguments)] = result;
  }

  dynamic latestResult(String name, Map<String, dynamic> arguments) {
    return _latestResultsByFingerprint[_fingerprint(name, arguments)];
  }

  String _fingerprint(String name, Map<String, dynamic> arguments) {
    // Sort keys for stable canonical JSON
    final canonical = _canonicalize(arguments);
    return '$name:${jsonEncode(canonical)}';
  }

  dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final sorted = Map.fromEntries(
        value.entries.toList()
          ..sort((a, b) => '${a.key}'.compareTo('${b.key}')),
      );
      return sorted.map((k, v) => MapEntry(k, _canonicalize(v)));
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }

  String get budgetSummary =>
      'rounds=$_roundCount/$_totalCallCount (limit $maxRounds/$maxTotalCalls)';
}

/// Represents a tool call in progress during streaming
class ToolCallChunk {
  final String id;
  final String? name;
  final Map<String, dynamic>? arguments;
  final String? rawArguments;
  final ToolCallStatus status;
  final dynamic result;

  ToolCallChunk({
    required this.id,
    this.name,
    this.arguments,
    this.rawArguments,
    this.status = ToolCallStatus.creating,
    this.result,
  });

  ToolCallChunk copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? arguments,
    String? rawArguments,
    ToolCallStatus? status,
    dynamic result,
  }) {
    return ToolCallChunk(
      id: id ?? this.id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
      rawArguments: rawArguments ?? this.rawArguments,
      status: status ?? this.status,
      result: result ?? this.result,
    );
  }
}

/// Chunk with optional thinking/reasoning content and tool calls
class ChatStreamChunk {
  final String content;
  final String? thinking;
  final bool isThinkingComplete;
  final ToolCallChunk? toolCall;
  final bool isToolCallComplete;
  final Map<String, dynamic>? responseMetadata;

  ChatStreamChunk({
    required this.content,
    this.thinking,
    this.isThinkingComplete = false,
    this.toolCall,
    this.isToolCallComplete = false,
    this.responseMetadata,
  });
}

List<Map<String, dynamic>> _deepCopyConversationState(
  List<Map<String, dynamic>> items,
) {
  return (jsonDecode(jsonEncode(items)) as List<dynamic>)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}

Map<String, dynamic> _extractResponseMetadata(
  Map<String, dynamic> payload, {
  required String requestedModel,
  required String providerName,
}) {
  final metadata = <String, dynamic>{
    'requestedModel': requestedModel,
    'providerName': providerName,
  };

  void addString(String outputKey, dynamic value) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) {
      metadata[outputKey] = text;
    }
  }

  void addNumber(String outputKey, dynamic value) {
    if (value is num) {
      metadata[outputKey] = value;
    }
  }

  void addFirstNumber(String outputKey, Iterable<dynamic> values) {
    for (final value in values) {
      if (value is num) {
        metadata[outputKey] = value;
        return;
      }
    }
  }

  addString('responseId', payload['id']);
  addString('resolvedModel', payload['model']);
  addString('systemFingerprint', payload['system_fingerprint']);
  addNumber('created', payload['created']);

  final provider = payload['provider'] ?? payload['provider_name'];
  if (provider is Map) {
    addString('resolvedProvider', provider['name'] ?? provider['id']);
    metadata['provider'] = Map<String, dynamic>.from(provider);
  } else {
    addString('resolvedProvider', provider);
  }

  final route = payload['route'] ?? payload['routing'] ?? payload['router'];
  if (route is Map) {
    metadata['routing'] = Map<String, dynamic>.from(route);
  } else {
    addString('routing', route);
  }

  final usage = payload['usage'];
  if (usage is Map) {
    final normalizedUsage = Map<String, dynamic>.from(usage);
    final promptTokenDetails = normalizedUsage['prompt_tokens_details'];
    final completionTokenDetails = normalizedUsage['completion_tokens_details'];
    final inputTokenDetails = normalizedUsage['input_token_details'];
    final outputTokenDetails = normalizedUsage['output_token_details'];
    metadata['usage'] = normalizedUsage;
    addFirstNumber('promptTokens', [
      normalizedUsage['prompt_tokens'],
      normalizedUsage['input_tokens'],
    ]);
    addFirstNumber('completionTokens', [
      normalizedUsage['completion_tokens'],
      normalizedUsage['output_tokens'],
    ]);
    addNumber('totalTokens', normalizedUsage['total_tokens']);
    addNumber('cacheMissTokens', normalizedUsage['prompt_cache_miss_tokens']);
    addFirstNumber('cacheReadTokens', [
      normalizedUsage['prompt_cache_hit_tokens'],
      normalizedUsage['cache_read_input_tokens'],
      normalizedUsage['cached_input_tokens'],
      normalizedUsage['cached_tokens'],
      normalizedUsage['prompt_cached_tokens'],
      if (promptTokenDetails is Map) promptTokenDetails['cached_tokens'],
      if (promptTokenDetails is Map) promptTokenDetails['cache_read_tokens'],
      if (inputTokenDetails is Map) inputTokenDetails['cache_read_tokens'],
      if (inputTokenDetails is Map) inputTokenDetails['cached_tokens'],
    ]);
    addFirstNumber('cacheWriteTokens', [
      normalizedUsage['cache_creation_input_tokens'],
      normalizedUsage['cache_write_input_tokens'],
      normalizedUsage['cache_creation_tokens'],
      normalizedUsage['prompt_cache_creation_tokens'],
      if (promptTokenDetails is Map)
        promptTokenDetails['cache_creation_tokens'],
      if (promptTokenDetails is Map) promptTokenDetails['cache_write_tokens'],
      if (inputTokenDetails is Map) inputTokenDetails['cache_write_tokens'],
    ]);
    addFirstNumber('reasoningTokens', [
      normalizedUsage['reasoning_tokens'],
      if (completionTokenDetails is Map)
        completionTokenDetails['reasoning_tokens'],
      if (outputTokenDetails is Map) outputTokenDetails['reasoning_tokens'],
    ]);
  }

  final choice = _firstChoice(payload);
  addString('finishReason', choice?['finish_reason']);
  addString('nativeFinishReason', choice?['native_finish_reason']);

  return metadata;
}

Map<String, dynamic> mergeResponseMetadata(
  Map<String, dynamic> current,
  Map<String, dynamic>? next,
) {
  if (next == null || next.isEmpty) return current;

  final merged = Map<String, dynamic>.from(current);
  for (final entry in next.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    merged[entry.key] = value;
  }

  if (next.containsKey('workflowTotalTokens') ||
      next.containsKey('usageRounds')) {
    return merged;
  }

  final usageRound = _usageRoundFromMetadata(next);
  if (usageRound == null) return merged;

  final rounds = ((current['usageRounds'] as List?) ?? const [])
      .whereType<Map>()
      .map((round) => Map<String, dynamic>.from(round))
      .toList();
  final responseId = usageRound['responseId']?.toString();
  final existingIndex = responseId == null
      ? -1
      : rounds.indexWhere(
          (round) => round['responseId']?.toString() == responseId,
        );
  if (existingIndex >= 0) {
    rounds[existingIndex] = {...rounds[existingIndex], ...usageRound};
  } else {
    rounds.add(usageRound);
  }
  merged['usageRounds'] = rounds;
  merged['modelRoundCount'] = rounds.length;
  merged['workflowPromptTokens'] = _sumRoundNumbers(rounds, 'promptTokens');
  merged['workflowCompletionTokens'] = _sumRoundNumbers(
    rounds,
    'completionTokens',
  );
  merged['workflowTotalTokens'] = _sumRoundNumbers(rounds, 'totalTokens');
  merged['workflowReasoningTokens'] = _sumRoundNumbers(
    rounds,
    'reasoningTokens',
  );
  merged['workflowCacheReadTokens'] = _sumRoundNumbers(
    rounds,
    'cacheReadTokens',
  );
  merged['workflowCacheMissTokens'] = _sumRoundNumbers(
    rounds,
    'cacheMissTokens',
  );
  merged['workflowCacheWriteTokens'] = _sumRoundNumbers(
    rounds,
    'cacheWriteTokens',
  );
  final workflowCost = _sumRoundDoubles(rounds, 'cost');
  if (workflowCost != null) {
    merged['workflowCost'] = workflowCost;
  }
  return merged;
}

Map<String, dynamic>? _usageRoundFromMetadata(Map<String, dynamic> metadata) {
  final prompt = metadata['promptTokens'];
  final completion = metadata['completionTokens'];
  final total = metadata['totalTokens'];
  final reasoning = metadata['reasoningTokens'];
  final cacheRead = metadata['cacheReadTokens'];
  final cacheMiss = metadata['cacheMissTokens'];
  final cacheWrite = metadata['cacheWriteTokens'];
  final cost = metadata['cost'];

  final hasUsage =
      prompt is num ||
      completion is num ||
      total is num ||
      reasoning is num ||
      cacheRead is num ||
      cacheMiss is num ||
      cacheWrite is num ||
      cost is num;
  if (!hasUsage) return null;

  return {
    if (metadata['responseId'] != null) 'responseId': metadata['responseId'],
    if (metadata['resolvedModel'] != null)
      'resolvedModel': metadata['resolvedModel'],
    if (metadata['resolvedProvider'] != null)
      'resolvedProvider': metadata['resolvedProvider'],
    if (prompt is num) 'promptTokens': prompt,
    if (completion is num) 'completionTokens': completion,
    if (total is num) 'totalTokens': total,
    if (reasoning is num) 'reasoningTokens': reasoning,
    if (cacheRead is num) 'cacheReadTokens': cacheRead,
    if (cacheMiss is num) 'cacheMissTokens': cacheMiss,
    if (cacheWrite is num) 'cacheWriteTokens': cacheWrite,
    if (cost is num) 'cost': cost,
  };
}

int _sumRoundNumbers(List<Map<String, dynamic>> rounds, String key) {
  return rounds.fold<int>(0, (sum, round) {
    final value = round[key];
    return value is num ? sum + value.round() : sum;
  });
}

double? _sumRoundDoubles(List<Map<String, dynamic>> rounds, String key) {
  var hasValue = false;
  final total = rounds.fold<double>(0, (sum, round) {
    final value = round[key];
    if (value is num) {
      hasValue = true;
      return sum + value.toDouble();
    }
    return sum;
  });
  return hasValue ? total : null;
}

/// Represents a single chat message in the active conversation.
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool? isLiked;
  final String? thinkingText;
  final bool isThinkingComplete;
  final List<ToolCall>? toolCalls;
  final bool isToolCallsComplete;
  final String? modelUsed;
  final int? tokensUsed;
  final double? tokensPerSec;
  final Duration? responseTime;
  final Map<String, dynamic>? responseMetadata;
  final List<ChatMessageBlock>? blocks;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLiked,
    this.thinkingText,
    this.isThinkingComplete = false,
    this.toolCalls,
    this.isToolCallsComplete = false,
    this.modelUsed,
    this.tokensUsed,
    this.tokensPerSec,
    this.responseTime,
    this.responseMetadata,
    this.blocks,
  });

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
    bool? isLiked,
    String? thinkingText,
    bool? isThinkingComplete,
    List<ToolCall>? toolCalls,
    bool? isToolCallsComplete,
    String? modelUsed,
    int? tokensUsed,
    double? tokensPerSec,
    Duration? responseTime,
    Map<String, dynamic>? responseMetadata,
    List<ChatMessageBlock>? blocks,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isLiked: isLiked ?? this.isLiked,
      thinkingText: thinkingText ?? this.thinkingText,
      isThinkingComplete: isThinkingComplete ?? this.isThinkingComplete,
      toolCalls: toolCalls ?? this.toolCalls,
      isToolCallsComplete: isToolCallsComplete ?? this.isToolCallsComplete,
      modelUsed: modelUsed ?? this.modelUsed,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      tokensPerSec: tokensPerSec ?? this.tokensPerSec,
      responseTime: responseTime ?? this.responseTime,
      responseMetadata: responseMetadata ?? this.responseMetadata,
      blocks: blocks ?? this.blocks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'isLiked': isLiked,
      'thinkingText': thinkingText,
      'isThinkingComplete': isThinkingComplete,
      'toolCalls': toolCalls?.map((tc) => tc.toJson()).toList(),
      'isToolCallsComplete': isToolCallsComplete,
      'modelUsed': modelUsed,
      'tokensUsed': tokensUsed,
      'tokensPerSec': tokensPerSec,
      'responseTime': responseTime?.inMilliseconds,
      'responseMetadata': responseMetadata,
      'blocks': blocks?.map((block) => block.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String? ?? '';
    final isUser = json['isUser'] as bool? ?? false;
    final timestampStr = json['timestamp'] as String?;
    DateTime timestamp;
    if (timestampStr != null) {
      try {
        timestamp = DateTime.parse(timestampStr);
      } catch (_) {
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }

    final toolCallsJson = json['toolCalls'] as List<dynamic>?;
    final toolCalls = toolCallsJson
        ?.map((tc) => ToolCall.fromJson(tc as Map<String, dynamic>))
        .toList();

    final responseTimeMs = json['responseTime'] as int?;
    final responseTime = responseTimeMs != null
        ? Duration(milliseconds: responseTimeMs)
        : null;

    final blocksJson = json['blocks'] as List<dynamic>?;
    final blocks = blocksJson
        ?.map(
          (block) => ChatMessageBlock.fromJson(block as Map<String, dynamic>),
        )
        .toList();

    return ChatMessage(
      text: text,
      isUser: isUser,
      timestamp: timestamp,
      isLiked: json['isLiked'] as bool?,
      thinkingText: json['thinkingText'] as String?,
      isThinkingComplete: json['isThinkingComplete'] as bool? ?? false,
      toolCalls: toolCalls,
      isToolCallsComplete: json['isToolCallsComplete'] as bool? ?? false,
      modelUsed: json['modelUsed'] as String?,
      tokensUsed: json['tokensUsed'] as int?,
      tokensPerSec: (json['tokensPerSec'] as num?)?.toDouble(),
      responseTime: responseTime,
      responseMetadata: (json['responseMetadata'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      blocks: blocks,
    );
  }
}

class ChatMessageBlock {
  final String id;
  final ChatMessageBlockType type;
  final String? text;
  final ToolCall? toolCall;
  final bool isComplete;

  ChatMessageBlock({
    required this.id,
    required this.type,
    this.text,
    this.toolCall,
    this.isComplete = false,
  });

  ChatMessageBlock copyWith({
    String? id,
    ChatMessageBlockType? type,
    String? text,
    ToolCall? toolCall,
    bool? isComplete,
  }) {
    return ChatMessageBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      toolCall: toolCall ?? this.toolCall,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'text': text,
      'toolCall': toolCall?.toJson(),
      'isComplete': isComplete,
    };
  }

  factory ChatMessageBlock.fromJson(Map<String, dynamic> json) {
    final typeName =
        json['type'] as String? ?? ChatMessageBlockType.response.name;
    final type = ChatMessageBlockType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => ChatMessageBlockType.response,
    );

    return ChatMessageBlock(
      id: json['id'] as String? ?? '',
      type: type,
      text: json['text'] as String?,
      toolCall: json['toolCall'] is Map<String, dynamic>
          ? ToolCall.fromJson(json['toolCall'] as Map<String, dynamic>)
          : null,
      isComplete: json['isComplete'] as bool? ?? false,
    );
  }
}

enum ChatMessageBlockType { thinking, toolCall, response }

class ToolCall {
  final String? id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? rawArguments;
  final String? result;
  final bool isComplete;
  final ToolCallStatus status;

  ToolCall({
    this.id,
    required this.name,
    required this.arguments,
    this.rawArguments,
    this.result,
    this.isComplete = false,
    this.status = ToolCallStatus.pending,
  });

  ToolCall copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? arguments,
    String? rawArguments,
    String? result,
    bool? isComplete,
    ToolCallStatus? status,
  }) {
    return ToolCall(
      id: id ?? this.id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
      rawArguments: rawArguments ?? this.rawArguments,
      result: result ?? this.result,
      isComplete: isComplete ?? this.isComplete,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'arguments': arguments,
      'rawArguments': rawArguments,
      'result': result,
      'isComplete': isComplete,
      'status': status.toString(),
    };
  }

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    ToolCallStatus status = ToolCallStatus.pending;
    if (statusStr != null) {
      try {
        status = ToolCallStatus.values.firstWhere(
          (s) => s.toString() == statusStr,
          orElse: () => ToolCallStatus.pending,
        );
      } catch (_) {
        status = ToolCallStatus.pending;
      }
    }

    return ToolCall(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      arguments: json['arguments'] as Map<String, dynamic>? ?? {},
      rawArguments: json['rawArguments'] as String?,
      result: json['result'] as String?,
      isComplete: json['isComplete'] as bool? ?? false,
      status: status,
    );
  }
}

enum ToolCallStatus { pending, creating, calling, completed, failed, cancelled }

String truncateToolPayloadForStorage(dynamic value) {
  return value is String ? value : jsonEncode(value);
}

const String _coreChatBehavior = '''
You are Budget AI, a friendly personal-finance assistant.

Response rules:
- Lead with the answer; default to 1-3 short sentences. Preserve necessary facts, amounts, dates, caveats, decisions, and next actions.
- Remove introductions, repetition, generic reassurance, optional background, and internal reasoning.
- Work autonomously until complete, using the fewest calls and batching similar actions. Ask only when a required choice is genuinely ambiguous.
- Use the selected currency display. In markdown tables, left-align every column with `---`; show amounts without leading + or - signs.
- Write every answer as natural, plain prose in the response's own language so it reads well aloud. Spell out amounts and currency names instead of using symbols, codes, abbreviations, or digits: English uses "two hundred and fifty rupees"; Roman Urdu uses "do sau pachaas rupees"; Urdu script uses natural Urdu number words with "روپے" or "ڈالر".
- Tables are visual-only. Introduce each table with one short natural sentence in the same response language (for example, "You can see the details in the visual table"), then put structured data in the table. Do not narrate every table cell in the prose.
''';

const String _financeGuidance = '''
Finance rules:
- For finance actions, call tools before writing anything; then give one short, natural confirmation. After a successful add, do not repeat a field-by-field list because the app renders the saved entry separately. Never call a list tool after a successful add.
- Expense/default cash out: finance_add. Clear income (salary, received money, freelance, refund, bonus, gift): finance_income_add. "200 fuel" is an expense.
- Loans use category "Loan": lent/paid repayment = expense; borrowed/received repayment = income.
- Infer category and today's date; omit time unless stated. Categories are concise, specific, title-cased, and never Other/Others. Entry titles are title-cased and replace "and" with "&".
- For spending or summaries, use finance_list/finance_summary. Whenever finance_list returns entries, give the concise spoken answer and mention in the same language that their details are visible in the visual table; the app renders that table, so do not duplicate those entries in a Markdown table. For biggest expenses, list expenses by amount_desc with the requested range and a sensible limit; use amount_greater_than for threshold requests.
- Update/delete directly when IDs are known; otherwise list first. finance_update may change all entry fields. finance_delete accepts IDs or an inclusive date range with optional type/category filters.
- If income versus expense is genuinely unclear, ask one short question before acting.
''';
