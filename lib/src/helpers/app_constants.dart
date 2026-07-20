import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime constants loaded from the root `.env` Flutter asset.
class AppConstants {
  AppConstants._();

  static const String _openAIApiKeyFromBuild = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  /// OpenAI API key bundled from the root `.env` file.
  static String get openAIApiKey {
    final envKey = dotenv.env['OPENAI_API_KEY']?.trim() ?? '';
    return envKey.isNotEmpty ? envKey : _openAIApiKeyFromBuild;
  }

  static bool get hasOpenAIKey => openAIApiKey.isNotEmpty;
}
