import 'dart:convert';

/// Notification payload for approval requests.
class ApprovalNotificationPayload {
  final String requestId;
  final String toolName;
  final String command;
  final Map<String, dynamic> arguments;
  final String riskLevel;
  final List<String> affectedPaths;
  final String? sessionId;
  final DateTime timestamp;
  final String? chatId;
  /// The approval request ID from the backend (for remote commands)
  /// or the local tool request ID (for local tools).
  final String? approvalRequestId;
  /// The kind of approval: 'local_tool', 'local_github_branch_delete', or null for remote.
  final String? kind;

  const ApprovalNotificationPayload({
    required this.requestId,
    required this.toolName,
    required this.command,
    required this.arguments,
    required this.riskLevel,
    required this.affectedPaths,
    this.sessionId,
    required this.timestamp,
    this.chatId,
    this.approvalRequestId,
    this.kind,
  });

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'toolName': toolName,
    'command': command,
    'arguments': arguments,
    'riskLevel': riskLevel,
    'affectedPaths': affectedPaths,
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'chatId': chatId,
    'approvalRequestId': approvalRequestId,
    'kind': kind,
  };

  factory ApprovalNotificationPayload.fromJson(Map<String, dynamic> json) {
    return ApprovalNotificationPayload(
      requestId: json['requestId'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
      command: json['command'] as String? ?? '',
      arguments: json['arguments'] is Map
          ? Map<String, dynamic>.from(json['arguments'] as Map)
          : {},
      riskLevel: json['riskLevel'] as String? ?? 'unknown',
      affectedPaths: (json['affectedPaths'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      sessionId: json['sessionId'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      chatId: json['chatId'] as String?,
      approvalRequestId: json['approvalRequestId'] as String?,
      kind: json['kind'] as String?,
    );
  }

  String toPayloadString() => jsonEncode(toJson());

  factory ApprovalNotificationPayload.fromPayloadString(String payload) {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    return ApprovalNotificationPayload.fromJson(json);
  }
}

/// Notification payload for response completion.
class ResponseReadyPayload {
  final String chatId;
  final String? modelUsed;
  final int toolCallCount;
  final String status;
  final String? summary;
  final DateTime timestamp;
  final bool hasError;

  const ResponseReadyPayload({
    required this.chatId,
    this.modelUsed,
    this.toolCallCount = 0,
    this.status = 'success',
    this.summary,
    required this.timestamp,
    this.hasError = false,
  });

  Map<String, dynamic> toJson() => {
    'chatId': chatId,
    'modelUsed': modelUsed,
    'toolCallCount': toolCallCount,
    'status': status,
    'summary': summary,
    'timestamp': timestamp.toIso8601String(),
    'hasError': hasError,
  };

  factory ResponseReadyPayload.fromJson(Map<String, dynamic> json) {
    return ResponseReadyPayload(
      chatId: json['chatId'] as String? ?? '',
      modelUsed: json['modelUsed'] as String?,
      toolCallCount: json['toolCallCount'] as int? ?? 0,
      status: json['status'] as String? ?? 'success',
      summary: json['summary'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      hasError: json['hasError'] as bool? ?? false,
    );
  }

  String toPayloadString() => jsonEncode(toJson());

  factory ResponseReadyPayload.fromPayloadString(String payload) {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    return ResponseReadyPayload.fromJson(json);
  }
}
