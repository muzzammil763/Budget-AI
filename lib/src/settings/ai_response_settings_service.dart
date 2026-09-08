import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';

/// Device-local preferences that control how AI responses are requested.
class AiResponseSettingsService {
  AiResponseSettingsService._();

  static final AiResponseSettingsService instance =
      AiResponseSettingsService._();

  static const _showToolCallsKey = 'ai_show_tool_calls';
  final ValueNotifier<bool> showToolCalls = ValueNotifier(true);

  static const _fastResponsesKey = 'ai_fast_responses_enabled';

  /// Uses OpenAI Fast mode when enabled. Standard processing remains the
  /// default because Fast mode carries a per-token pricing premium.
  final ValueNotifier<bool> fastResponsesEnabled = ValueNotifier(false);

  Future<void> load() async {
    showToolCalls.value =
        await LocalSettingsStore.instance.getBool(_showToolCallsKey) ?? true;
    fastResponsesEnabled.value =
        await LocalSettingsStore.instance.getBool(_fastResponsesKey) ?? false;
  }

  Future<void> setFastResponsesEnabled(bool value) async {
    fastResponsesEnabled.value = value;
    await LocalSettingsStore.instance.setBool(_fastResponsesKey, value);
  }

  Future<void> setShowToolCalls(bool value) async {
    showToolCalls.value = value;
    await LocalSettingsStore.instance.setBool(_showToolCallsKey, value);
  }

  void resetLocalState() {
    showToolCalls.value = true;
    fastResponsesEnabled.value = false;
  }
}
