enum LocalSpeechModelKind { speechToText, textToSpeech }

class LocalSpeechModel {
  const LocalSpeechModel({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.downloadUrl,
    required this.archiveRoot,
    required this.requiredFiles,
    required this.installedSizeLabel,
    this.recommended = false,
    this.whisperPrefix,
    this.piperPrefix,
    this.directDownloadBaseUrl,
  });

  final String id;
  final LocalSpeechModelKind kind;
  final String name;
  final String description;
  final String downloadUrl;
  final String archiveRoot;
  final List<String> requiredFiles;
  final String installedSizeLabel;
  final bool recommended;
  final String? whisperPrefix;
  final String? piperPrefix;
  final String? directDownloadBaseUrl;
}

class LocalSpeechModels {
  const LocalSpeechModels._();

  static const String defaultSttId = 'whisper-tiny-en-int8';
  static const String defaultTtsId = 'piper-lessac-medium';

  static const List<LocalSpeechModel> all = [
    LocalSpeechModel(
      id: defaultSttId,
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Tiny English',
      description: 'Fast, English-optimized offline transcription',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-tiny.en',
      requiredFiles: [
        'tiny.en-encoder.int8.onnx',
        'tiny.en-decoder.int8.onnx',
        'tiny.en-tokens.txt',
      ],
      installedSizeLabel: 'about 118 MB installed',
      recommended: true,
      whisperPrefix: 'tiny.en',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-tiny-multilingual-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Tiny Multilingual',
      description: 'Offline transcription for multiple languages',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-tiny',
      requiredFiles: [
        'tiny-encoder.int8.onnx',
        'tiny-decoder.int8.onnx',
        'tiny-tokens.txt',
      ],
      installedSizeLabel: 'about 118 MB installed',
      whisperPrefix: 'tiny',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main',
    ),
    LocalSpeechModel(
      id: defaultTtsId,
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Lessac',
      description: 'Clear US English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_US-lessac-medium',
      requiredFiles: [
        'en_US-lessac-medium.onnx',
        'tokens.txt',
        'espeak-ng-data',
      ],
      installedSizeLabel: 'medium quality',
      recommended: true,
      piperPrefix: 'en_US-lessac-medium',
    ),
    LocalSpeechModel(
      id: 'piper-amy-low',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Amy',
      description: 'Compact US English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-low.tar.bz2',
      archiveRoot: 'vits-piper-en_US-amy-low',
      requiredFiles: ['en_US-amy-low.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: 'small, fastest download',
      piperPrefix: 'en_US-amy-low',
    ),
    LocalSpeechModel(
      id: 'piper-ryan-medium',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Ryan',
      description: 'Natural US English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ryan-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_US-ryan-medium',
      requiredFiles: ['en_US-ryan-medium.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: 'medium quality',
      piperPrefix: 'en_US-ryan-medium',
    ),
  ];

  static Iterable<LocalSpeechModel> ofKind(LocalSpeechModelKind kind) =>
      all.where((model) => model.kind == kind);

  static LocalSpeechModel? byId(String id) {
    for (final model in all) {
      if (model.id == id) return model;
    }
    return null;
  }
}
