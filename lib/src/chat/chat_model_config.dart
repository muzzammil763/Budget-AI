class ChatModelConfig {
  final String id;
  final String modelName;
  final String displayName;
  final String iconPath;
  final String apiBaseUrl;

  const ChatModelConfig({
    required this.id,
    required this.modelName,
    required this.displayName,
    required this.iconPath,
    required this.apiBaseUrl,
  });

  static const deepseek = ChatModelConfig(
    id: 'deepseek',
    modelName: 'deepseek',
    displayName: 'DeepSeek',
    iconPath: 'assets/icons/deepseek.svg',
    apiBaseUrl: 'https://api.deepseek.com/v1',
  );
}
