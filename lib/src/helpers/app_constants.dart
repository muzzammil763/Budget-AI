import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime constants loaded from the root `.env` Flutter asset.
class AppConstants {
  AppConstants._();

  static const String _deepSeekApiKeyFromBuild = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
    defaultValue: '',
  );

  /// DeepSeek API key bundled from the root `.env` file.
  static String get deepSeekApiKey {
    final envKey = dotenv.env['DEEPSEEK_API_KEY']?.trim() ?? '';
    return envKey.isNotEmpty ? envKey : _deepSeekApiKeyFromBuild;
  }

  static bool get hasDeepSeekKey => deepSeekApiKey.isNotEmpty;
}
