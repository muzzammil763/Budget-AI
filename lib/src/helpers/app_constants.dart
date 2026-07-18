import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime constants loaded from the root `.env` Flutter asset.
class AppConstants {
  AppConstants._();

  static const String _deepSeekApiKeyFromBuild = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
    defaultValue: '',
  );
  static const String _groqApiKeyFromBuild = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
  static const String _elevenLabsApiKeyFromBuild = String.fromEnvironment(
    'ELEVENLABS_API_KEY',
    defaultValue: '',
  );
  static const String _geminiApiKeyFromBuild = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// DeepSeek API key bundled from the root `.env` file.
  static String get deepSeekApiKey {
    final envKey = dotenv.env['DEEPSEEK_API_KEY']?.trim() ?? '';
    return envKey.isNotEmpty ? envKey : _deepSeekApiKeyFromBuild;
  }

  static bool get hasDeepSeekKey => deepSeekApiKey.isNotEmpty;

  static String get groqApiKey {
    final envKey = dotenv.env['GROQ_API_KEY']?.trim() ?? '';
    return envKey.isNotEmpty ? envKey : _groqApiKeyFromBuild;
  }

  static bool get hasGroqKey => groqApiKey.isNotEmpty;

  static String get elevenLabsApiKey {
    final envKey = dotenv.env['ELEVENLABS_API_KEY']?.trim() ?? '';
    return envKey.isNotEmpty ? envKey : _elevenLabsApiKeyFromBuild;
  }

  static bool get hasElevenLabsKey => elevenLabsApiKey.isNotEmpty;

  static String get geminiApiKey {
    final envKey = dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
    return envKey.isNotEmpty ? envKey : _geminiApiKeyFromBuild;
  }

  static bool get hasGeminiKey => geminiApiKey.isNotEmpty;
}
