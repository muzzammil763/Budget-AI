class OpenAIVoice {
  const OpenAIVoice({
    required this.id,
    required this.name,
    required this.description,
    this.recommended = false,
  });

  final String id;
  final String name;
  final String description;
  final bool recommended;

  String get previewAsset => 'audio/openai_voices/$id.mp3';
}

abstract final class OpenAIVoices {
  static const String defaultVoiceId = 'marin';

  static const List<OpenAIVoice> all = [
    OpenAIVoice(
      id: 'alloy',
      name: 'Alloy',
      description: 'Neutral and balanced',
    ),
    OpenAIVoice(id: 'ash', name: 'Ash', description: 'Clear and articulate'),
    OpenAIVoice(
      id: 'ballad',
      name: 'Ballad',
      description: 'Warm and expressive',
    ),
    OpenAIVoice(id: 'coral', name: 'Coral', description: 'Bright and engaging'),
    OpenAIVoice(id: 'echo', name: 'Echo', description: 'Calm and measured'),
    OpenAIVoice(
      id: 'fable',
      name: 'Fable',
      description: 'Expressive storytelling',
    ),
    OpenAIVoice(
      id: 'nova',
      name: 'Nova',
      description: 'Friendly and energetic',
    ),
    OpenAIVoice(id: 'onyx', name: 'Onyx', description: 'Deep and confident'),
    OpenAIVoice(
      id: 'sage',
      name: 'Sage',
      description: 'Composed and authoritative',
    ),
    OpenAIVoice(id: 'shimmer', name: 'Shimmer', description: 'Soft and gentle'),
    OpenAIVoice(
      id: 'verse',
      name: 'Verse',
      description: 'Dynamic and versatile',
    ),
    OpenAIVoice(
      id: 'marin',
      name: 'Marin',
      description: 'Smooth and natural',
      recommended: true,
    ),
    OpenAIVoice(
      id: 'cedar',
      name: 'Cedar',
      description: 'Rich and grounded',
      recommended: true,
    ),
  ];

  static OpenAIVoice? byId(String id) {
    for (final voice in all) {
      if (voice.id == id) return voice;
    }
    return null;
  }
}
