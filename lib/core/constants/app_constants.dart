/// Build-time constants/flags set via --dart-define in the Makefile.
class AppConstants {
  AppConstants._();

  /// DeepSeek API key baked in at build time.
  static const String deepSeekApiKey = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
    defaultValue: '',
  );

  static bool get hasDeepSeekKey => deepSeekApiKey.isNotEmpty;
}
