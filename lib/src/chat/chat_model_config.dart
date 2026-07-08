enum ChatModelType { deepseek }

class ChatModelConfig {
  final ChatModelType type;
  final String modelName;
  final String displayName;
  final String iconPath;
  final String storageKey;
  final bool requiresDownload;
  final bool requiresToken;
  final String? tokenKey;
  final String? guideRoute;
  final String apiBaseUrl;

  const ChatModelConfig({
    required this.type,
    required this.modelName,
    required this.displayName,
    required this.iconPath,
    required this.storageKey,
    this.requiresDownload = false,
    this.requiresToken = false,
    this.tokenKey,
    this.guideRoute,
    required this.apiBaseUrl,
  });

  static const deepseek = ChatModelConfig(
    type: ChatModelType.deepseek,
    modelName: 'deepseek',
    displayName: 'DeepSeek',
    iconPath: 'assets/icons/deepseek.svg',
    storageKey: 'deepseek_api_key',
    requiresToken: true,
    tokenKey: 'deepseek_api_key',
    apiBaseUrl: 'https://api.deepseek.com/v1',
  );

  static ChatModelConfig fromType(ChatModelType type) {
    switch (type) {
      case ChatModelType.deepseek:
        return deepseek;
    }
  }
}
