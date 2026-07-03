import 'dart:async';

// ============================================================
// SECTION 1 — TOOL MODELS
// Data classes that define what a tool looks like.
// ============================================================

/// Definition of a single tool exposed to the model.
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<dynamic> Function(Map<String, dynamic>)? handler;
  final Stream<ToolExecutionEvent> Function(Map<String, dynamic>)?
  streamHandler;

  ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.handler,
    this.streamHandler,
  });

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// Event emitted during a streaming tool execution.
class ToolExecutionEvent {
  const ToolExecutionEvent({
    required this.result,
    this.isComplete = false,
    this.isError = false,
  });

  final dynamic result;
  final bool isComplete;
  final bool isError;
}

class ToolLocationFix {
  const ToolLocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (accuracy != null) 'accuracy_meters': accuracy,
    'timestamp': timestamp.toIso8601String(),
  };
}

class WeatherGeoResult {
  const WeatherGeoResult({
    required this.latitude,
    required this.longitude,
    required this.name,
    this.admin1,
    this.country,
    this.timezone,
  });

  final double latitude;
  final double longitude;
  final String name;
  final String? admin1;
  final String? country;
  final String? timezone;

  String get label => [
    name,
    if (admin1 != null && admin1!.trim().isNotEmpty) admin1,
    if (country != null && country!.trim().isNotEmpty) country,
  ].join(', ');

  Map<String, dynamic> toJson() => {
    'name': name,
    if (admin1 != null) 'admin1': admin1,
    if (country != null) 'country': country,
    if (timezone != null) 'timezone': timezone,
    'latitude': latitude,
    'longitude': longitude,
  };
}

// ============================================================
// SECTION 2 — TOOL DEFINITIONS (Catalog)
// The schemas / definitions the AI sees. Each ToolDefinition
// tells the model the tool name, description, and parameters.
// ============================================================

typedef ToolHandler = Future<dynamic> Function(Map<String, dynamic>);
typedef ToolStreamHandler =
    Stream<ToolExecutionEvent> Function(Map<String, dynamic>);
