import 'package:budget_ai/src/settings/openai_usage_service.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await OpenAIUsageService.instance.initialize();
  });

  test('tracks and persists all OpenAI usage categories', () async {
    final service = OpenAIUsageService.instance;
    await service.recordResponse(
      model: 'gpt-5.6-luna',
      usageData: {
        'input_tokens': 100,
        'output_tokens': 25,
        'total_tokens': 125,
        'input_tokens_details': {'cached_tokens': 40},
        'output_tokens_details': {'reasoning_tokens': 5},
      },
    );
    await service.recordTranscription(seconds: 12.5);
    await service.recordSpeech(characters: 80);
    await service.initialize();

    final usage = service.usage.value;
    expect(usage.responseRequests, 1);
    expect(usage.inputTokens, 100);
    expect(usage.cachedInputTokens, 40);
    expect(usage.outputTokens, 25);
    expect(usage.reasoningTokens, 5);
    expect(usage.totalTokens, 125);
    expect(usage.transcriptionRequests, 1);
    expect(usage.transcriptionSeconds, 12.5);
    expect(usage.speechRequests, 1);
    expect(usage.speechCharacters, 80);
    expect(usage.byModel, {'gpt-5.6-luna': 1});
  });

  test('reset clears only local counters', () async {
    final service = OpenAIUsageService.instance;
    await service.recordSpeech(characters: 10);
    await service.reset();
    expect(service.usage.value.isEmpty, isTrue);
    expect(service.usage.value.trackingSince, isNull);
  });
}
