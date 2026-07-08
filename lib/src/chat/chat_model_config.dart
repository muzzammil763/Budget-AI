class ChatModelConfig {
  final String modelName;
  final String displayName;
  final String iconPath;
  final String apiBaseUrl;

  const ChatModelConfig({
    required this.modelName,
    required this.displayName,
    required this.iconPath,
    required this.apiBaseUrl,
  });

  static const deepseek = ChatModelConfig(
    modelName: 'deepseek',
    displayName: 'DeepSeek',
    iconPath: 'assets/icons/deepseek.svg',
    apiBaseUrl: 'https://api.deepseek.com/v1',
  );
}
