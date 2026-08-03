enum LocalSpeechModelKind { speechToText, textToSpeech }

class LocalSpeechModel {
  const LocalSpeechModel({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.details,
    required this.downloadUrl,
    required this.archiveRoot,
    required this.requiredFiles,
    required this.downloadSizeBytes,
    this.recommended = false,
    this.whisperPrefix,
    this.piperPrefix,
    this.directDownloadBaseUrl,
  });

  final String id;
  final LocalSpeechModelKind kind;
  final String name;
  final String description;
  final List<String> details;
  final String downloadUrl;
  final String archiveRoot;
  final List<String> requiredFiles;
  final int downloadSizeBytes;
  final bool recommended;
  final String? whisperPrefix;
  final String? piperPrefix;
  final String? directDownloadBaseUrl;
}

class LocalSpeechModels {
  const LocalSpeechModels._();

  static const String defaultSttId = 'whisper-small-en-int8';
  static const String defaultTtsId = 'piper-lessac-medium';

  static const List<String> whisperLanguages = [
    'English',
    'Chinese',
    'German',
    'Spanish',
    'Russian',
    'Korean',
    'French',
    'Japanese',
    'Portuguese',
    'Turkish',
    'Polish',
    'Catalan',
    'Dutch',
    'Arabic',
    'Swedish',
    'Italian',
    'Indonesian',
    'Hindi',
    'Finnish',
    'Vietnamese',
    'Hebrew',
    'Ukrainian',
    'Greek',
    'Malay',
    'Czech',
    'Romanian',
    'Danish',
    'Hungarian',
    'Tamil',
    'Norwegian',
    'Thai',
    'Urdu',
    'Croatian',
    'Bulgarian',
    'Lithuanian',
    'Latin',
    'Maori',
    'Malayalam',
    'Welsh',
    'Slovak',
    'Telugu',
    'Persian',
    'Latvian',
    'Bengali',
    'Serbian',
    'Azerbaijani',
    'Slovenian',
    'Kannada',
    'Estonian',
    'Macedonian',
    'Breton',
    'Basque',
    'Icelandic',
    'Armenian',
    'Nepali',
    'Mongolian',
    'Bosnian',
    'Kazakh',
    'Albanian',
    'Swahili',
    'Galician',
    'Marathi',
    'Punjabi',
    'Sinhala',
    'Khmer',
    'Shona',
    'Yoruba',
    'Somali',
    'Afrikaans',
    'Occitan',
    'Georgian',
    'Belarusian',
    'Tajik',
    'Sindhi',
    'Gujarati',
    'Amharic',
    'Yiddish',
    'Lao',
    'Uzbek',
    'Faroese',
    'Haitian Creole',
    'Pashto',
    'Turkmen',
    'Nynorsk',
    'Maltese',
    'Sanskrit',
    'Luxembourgish',
    'Myanmar',
    'Tibetan',
    'Tagalog',
    'Malagasy',
    'Assamese',
    'Tatar',
    'Hawaiian',
    'Lingala',
    'Hausa',
    'Bashkir',
    'Javanese',
    'Sundanese',
  ];

  static final String whisperLanguageSummary = whisperLanguages.join(', ');

  static final List<LocalSpeechModel> all = List.unmodifiable([
    LocalSpeechModel(
      id: defaultSttId,
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Small English',
      description:
          'The English-only Whisper Small checkpoint, tuned for accurate '
          'offline English dictation on capable phones.',
      details: const [
        'Language: English only; fixed to English instead of spending time on language detection.',
        'Engine: Whisper Small with INT8 encoder and decoder, running fully on-device through Sherpa-ONNX.',
        'Trade-off: more accurate than Tiny or Base, but slower and more memory-intensive.',
        'Storage: about 376 MB installed. Microphone audio never leaves the device.',
      ],
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-small.en',
      requiredFiles: const [
        'small.en-encoder.int8.onnx',
        'small.en-decoder.int8.onnx',
        'small.en-tokens.txt',
      ],
      downloadSizeBytes: 376000000,
      recommended: true,
      whisperPrefix: 'small.en',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small.en/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-small-multilingual-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Small Multilingual',
      description:
          'The multilingual Whisper Small checkpoint with automatic spoken '
          'language detection and offline transcription.',
      details: [
        'Coverage: ${whisperLanguages.length} languages with automatic language detection.',
        'Languages: $whisperLanguageSummary.',
        'Engine: Whisper Small with INT8 encoder and decoder, running fully on-device through Sherpa-ONNX.',
        'Trade-off: best when you speak multiple languages; English-only is usually the better focused choice for English.',
        'Storage: about 376 MB installed. Microphone audio never leaves the device.',
      ],
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-small',
      requiredFiles: const [
        'small-encoder.int8.onnx',
        'small-decoder.int8.onnx',
        'small-tokens.txt',
      ],
      downloadSizeBytes: 376000000,
      whisperPrefix: 'small',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main',
    ),
    const LocalSpeechModel(
      id: defaultTtsId,
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Lessac (English US)',
      description:
          'A clear single-speaker US English Piper voice for reading Budget '
          'AI replies entirely on-device.',
      details: [
        'Language and voice: US English, one speaker, trained on the Lessac dataset.',
        'Audio: medium-quality Piper/VITS synthesis at 22,050 Hz.',
        'Pronunciation: eSpeak English-US phonemes; best suited to English text.',
        'Download: about 67.2 MB. Speech generation works offline and sends no reply audio to an API.',
      ],
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_US-lessac-medium',
      requiredFiles: [
        'en_US-lessac-medium.onnx',
        'tokens.txt',
        'espeak-ng-data',
      ],
      downloadSizeBytes: 67230653,
      recommended: true,
      piperPrefix: 'en_US-lessac-medium',
    ),
  ]);

  static Iterable<LocalSpeechModel> ofKind(LocalSpeechModelKind kind) =>
      all.where((model) => model.kind == kind);

  static LocalSpeechModel? byId(String id) {
    for (final model in all) {
      if (model.id == id) return model;
    }
    return null;
  }
}
