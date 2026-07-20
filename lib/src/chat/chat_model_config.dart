class ChatModelConfig {
  final String id;
  final String modelName;
  final String displayName;
  final String apiBaseUrl;

  const ChatModelConfig({
    required this.id,
    required this.modelName,
    required this.displayName,
    required this.apiBaseUrl,
  });

  static const openAI = ChatModelConfig(
    id: 'openai',
    modelName: 'openai',
    displayName: 'OpenAI',
    apiBaseUrl: 'https://api.openai.com/v1',
  );
}
