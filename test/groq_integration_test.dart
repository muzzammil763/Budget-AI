import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/groq_audio_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
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
    await ModelSettingsService.instance.initialize();
  });

  test('DeepSeek remains the default provider', () {
    expect(
      ModelSettingsService.instance.currentProvider,
      ChatModelConfig.deepseek.id,
    );
    expect(ModelSettingsService.instance.current, AIModels.defaultModelId);
  });

  test('Groq selection uses and preserves a Groq model', () async {
    final settings = ModelSettingsService.instance;
    await settings.setProvider(ChatModelConfig.groq.id);
    expect(settings.current, AIModels.defaultGroqModelId);

    await settings.setModel('llama-3.3-70b-versatile');
    await settings.setProvider(ChatModelConfig.deepseek.id);
    await settings.setProvider(ChatModelConfig.groq.id);

    expect(settings.current, 'llama-3.3-70b-versatile');
    expect(
      AIModels.modelsForProvider(
        ChatModelConfig.groq.id,
      ).map((model) => model.id),
      contains('openai/gpt-oss-120b'),
    );
  });

  test('Orpheus speech chunks respect its 200 character limit', () {
    final chunks = GroqAudioService.speechChunks(
      List.filled(80, 'Budget AI gives a clear answer.').join(' '),
    );

    expect(chunks, isNotEmpty);
    expect(chunks.every((chunk) => chunk.length <= 200), isTrue);
    expect(chunks.join(' '), contains('Budget AI gives a clear answer.'));
  });
}
