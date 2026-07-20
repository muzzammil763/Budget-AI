import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class OpenAIUsageSnapshot {
  const OpenAIUsageSnapshot({
    this.responseRequests = 0,
    this.inputTokens = 0,
    this.cachedInputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.totalTokens = 0,
    this.transcriptionRequests = 0,
    this.transcriptionSeconds = 0,
    this.speechRequests = 0,
    this.speechCharacters = 0,
    this.byModel = const {},
    this.trackingSince,
  });

  final int responseRequests;
  final int inputTokens;
  final int cachedInputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int totalTokens;
  final int transcriptionRequests;
  final double transcriptionSeconds;
  final int speechRequests;
  final int speechCharacters;
  final Map<String, int> byModel;
  final DateTime? trackingSince;

  bool get isEmpty =>
      responseRequests == 0 &&
      transcriptionRequests == 0 &&
      speechRequests == 0;

  Map<String, dynamic> toJson() => {
    'responseRequests': responseRequests,
    'inputTokens': inputTokens,
    'cachedInputTokens': cachedInputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'totalTokens': totalTokens,
    'transcriptionRequests': transcriptionRequests,
    'transcriptionSeconds': transcriptionSeconds,
    'speechRequests': speechRequests,
    'speechCharacters': speechCharacters,
    'byModel': byModel,
    if (trackingSince != null)
      'trackingSince': trackingSince!.toUtc().toIso8601String(),
  };

  factory OpenAIUsageSnapshot.fromJson(Map<String, dynamic> json) {
    int integer(String key) => (json[key] as num?)?.round() ?? 0;
    final rawModels = json['byModel'];
    return OpenAIUsageSnapshot(
      responseRequests: integer('responseRequests'),
      inputTokens: integer('inputTokens'),
      cachedInputTokens: integer('cachedInputTokens'),
      outputTokens: integer('outputTokens'),
      reasoningTokens: integer('reasoningTokens'),
      totalTokens: integer('totalTokens'),
      transcriptionRequests: integer('transcriptionRequests'),
      transcriptionSeconds:
          (json['transcriptionSeconds'] as num?)?.toDouble() ?? 0,
      speechRequests: integer('speechRequests'),
      speechCharacters: integer('speechCharacters'),
      byModel: rawModels is Map
          ? rawModels.map(
              (key, value) =>
                  MapEntry(key.toString(), (value as num?)?.round() ?? 0),
            )
          : const {},
      trackingSince: DateTime.tryParse(json['trackingSince']?.toString() ?? ''),
    );
  }
}

/// Device-local OpenAI metering. This deliberately does not use an Admin key.
class OpenAIUsageService {
  OpenAIUsageService._();

  static final OpenAIUsageService instance = OpenAIUsageService._();
  static const _storageKey = 'budget_openai_usage_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final ValueNotifier<OpenAIUsageSnapshot> usage = ValueNotifier(
    const OpenAIUsageSnapshot(),
  );
  Future<void> _writeQueue = Future.value();

  Future<void> initialize() async {
    final encoded = await _preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      usage.value = const OpenAIUsageSnapshot();
      return;
    }
    try {
      final decoded = jsonDecode(encoded);
      usage.value = decoded is Map
          ? OpenAIUsageSnapshot.fromJson(Map<String, dynamic>.from(decoded))
          : const OpenAIUsageSnapshot();
    } catch (_) {
      usage.value = const OpenAIUsageSnapshot();
    }
  }

  Future<void> recordResponse({
    required String model,
    required Map<String, dynamic> usageData,
  }) {
    final current = usage.value;
    int value(String key) => (usageData[key] as num?)?.round() ?? 0;
    final inputDetails = usageData['input_tokens_details'];
    final outputDetails = usageData['output_tokens_details'];
    final input = value('input_tokens');
    final output = value('output_tokens');
    final total = value('total_tokens');
    final cached = inputDetails is Map
        ? (inputDetails['cached_tokens'] as num?)?.round() ?? 0
        : 0;
    final reasoning = outputDetails is Map
        ? (outputDetails['reasoning_tokens'] as num?)?.round() ?? 0
        : 0;
    final models = Map<String, int>.from(current.byModel);
    models[model] = (models[model] ?? 0) + 1;
    return _save(
      OpenAIUsageSnapshot(
        responseRequests: current.responseRequests + 1,
        inputTokens: current.inputTokens + input,
        cachedInputTokens: current.cachedInputTokens + cached,
        outputTokens: current.outputTokens + output,
        reasoningTokens: current.reasoningTokens + reasoning,
        totalTokens:
            current.totalTokens + (total == 0 ? input + output : total),
        transcriptionRequests: current.transcriptionRequests,
        transcriptionSeconds: current.transcriptionSeconds,
        speechRequests: current.speechRequests,
        speechCharacters: current.speechCharacters,
        byModel: models,
        trackingSince: current.trackingSince ?? DateTime.now(),
      ),
    );
  }

  Future<void> recordTranscription({required double seconds}) {
    final current = usage.value;
    return _save(
      OpenAIUsageSnapshot(
        responseRequests: current.responseRequests,
        inputTokens: current.inputTokens,
        cachedInputTokens: current.cachedInputTokens,
        outputTokens: current.outputTokens,
        reasoningTokens: current.reasoningTokens,
        totalTokens: current.totalTokens,
        transcriptionRequests: current.transcriptionRequests + 1,
        transcriptionSeconds: current.transcriptionSeconds + seconds,
        speechRequests: current.speechRequests,
        speechCharacters: current.speechCharacters,
        byModel: current.byModel,
        trackingSince: current.trackingSince ?? DateTime.now(),
      ),
    );
  }

  Future<void> recordSpeech({required int characters}) {
    final current = usage.value;
    return _save(
      OpenAIUsageSnapshot(
        responseRequests: current.responseRequests,
        inputTokens: current.inputTokens,
        cachedInputTokens: current.cachedInputTokens,
        outputTokens: current.outputTokens,
        reasoningTokens: current.reasoningTokens,
        totalTokens: current.totalTokens,
        transcriptionRequests: current.transcriptionRequests,
        transcriptionSeconds: current.transcriptionSeconds,
        speechRequests: current.speechRequests + 1,
        speechCharacters: current.speechCharacters + characters,
        byModel: current.byModel,
        trackingSince: current.trackingSince ?? DateTime.now(),
      ),
    );
  }

  Future<void> reset() => _save(const OpenAIUsageSnapshot());

  Future<void> _save(OpenAIUsageSnapshot snapshot) {
    usage.value = snapshot;
    _writeQueue = _writeQueue.then(
      (_) => _preferences.setString(_storageKey, jsonEncode(snapshot.toJson())),
    );
    return _writeQueue;
  }
}
