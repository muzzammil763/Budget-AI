import 'dart:convert';

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
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
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
