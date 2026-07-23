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
  final String downloadUrl;
  final String archiveRoot;
  final List<String> requiredFiles;
  final String installedSizeLabel;
  final int downloadSizeBytes;
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
      downloadSizeBytes: 118000000,
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
      installedSizeLabel: 'about 99 MB installed',
      downloadSizeBytes: 99000000,
      whisperPrefix: 'tiny',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-base-en-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Base English',
      description: 'More accurate English transcription with balanced speed',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.en.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-base.en',
      requiredFiles: [
        'base.en-encoder.int8.onnx',
        'base.en-decoder.int8.onnx',
        'base.en-tokens.txt',
      ],
      installedSizeLabel: 'about 161 MB installed',
      downloadSizeBytes: 161000000,
      whisperPrefix: 'base.en',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base.en/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-base-multilingual-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Base Multilingual',
      description: 'Better multilingual accuracy with balanced speed',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-base',
      requiredFiles: [
        'base-encoder.int8.onnx',
        'base-decoder.int8.onnx',
        'base-tokens.txt',
      ],
      installedSizeLabel: 'about 161 MB installed',
      downloadSizeBytes: 161000000,
      whisperPrefix: 'base',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-small-en-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Small English',
      description: 'High-accuracy English transcription for faster devices',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-small.en',
      requiredFiles: [
        'small.en-encoder.int8.onnx',
        'small.en-decoder.int8.onnx',
        'small.en-tokens.txt',
      ],
      installedSizeLabel: 'about 376 MB installed',
      downloadSizeBytes: 376000000,
      whisperPrefix: 'small.en',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small.en/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-small-multilingual-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Small Multilingual',
      description: 'High multilingual accuracy for faster devices',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-small',
      requiredFiles: [
        'small-encoder.int8.onnx',
        'small-decoder.int8.onnx',
        'small-tokens.txt',
      ],
      installedSizeLabel: 'about 376 MB installed',
      downloadSizeBytes: 376000000,
      whisperPrefix: 'small',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-distil-small-en-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Distil Small English',
      description: 'Fast, accurate distilled English transcription',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-distil-small.en.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-distil-small.en',
      requiredFiles: [
        'distil-small.en-encoder.int8.onnx',
        'distil-small.en-decoder.int8.onnx',
        'distil-small.en-tokens.txt',
      ],
      installedSizeLabel: 'about 299 MB installed',
      downloadSizeBytes: 299000000,
      whisperPrefix: 'distil-small.en',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-distil-small.en/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-medium-en-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Medium English',
      description: 'Highest English accuracy in the mobile catalog',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium.en.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-medium.en',
      requiredFiles: [
        'medium.en-encoder.int8.onnx',
        'medium.en-decoder.int8.onnx',
        'medium.en-tokens.txt',
      ],
      installedSizeLabel: 'about 946 MB installed',
      downloadSizeBytes: 946000000,
      whisperPrefix: 'medium.en',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-medium.en/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-distil-medium-en-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Distil Medium English',
      description: 'Faster high-accuracy distilled English transcription',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-distil-medium.en.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-distil-medium.en',
      requiredFiles: [
        'distil-medium.en-encoder.int8.onnx',
        'distil-medium.en-decoder.int8.onnx',
        'distil-medium.en-tokens.txt',
      ],
      installedSizeLabel: 'about 574 MB installed',
      downloadSizeBytes: 574000000,
      whisperPrefix: 'distil-medium.en',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-distil-medium.en/resolve/main',
    ),
    LocalSpeechModel(
      id: 'whisper-medium-multilingual-int8',
      kind: LocalSpeechModelKind.speechToText,
      name: 'Whisper Medium Multilingual',
      description: 'Highest multilingual accuracy in the mobile catalog',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium.tar.bz2',
      archiveRoot: 'sherpa-onnx-whisper-medium',
      requiredFiles: [
        'medium-encoder.int8.onnx',
        'medium-decoder.int8.onnx',
        'medium-tokens.txt',
      ],
      installedSizeLabel: 'about 946 MB installed',
      downloadSizeBytes: 946000000,
      whisperPrefix: 'medium',
      directDownloadBaseUrl:
          'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-medium/resolve/main',
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
      downloadSizeBytes: 67230653,
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
      downloadSizeBytes: 67095344,
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
      downloadSizeBytes: 67213100,
      piperPrefix: 'en_US-ryan-medium',
    ),
    LocalSpeechModel(
      id: 'piper-kristin-medium',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Kristin',
      description: 'Warm US English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-kristin-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_US-kristin-medium',
      requiredFiles: [
        'en_US-kristin-medium.onnx',
        'tokens.txt',
        'espeak-ng-data',
      ],
      installedSizeLabel: 'medium quality',
      downloadSizeBytes: 67259230,
      piperPrefix: 'en_US-kristin-medium',
    ),
    LocalSpeechModel(
      id: 'piper-sam-medium',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Sam',
      description: 'Smooth US English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-sam-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_US-sam-medium',
      requiredFiles: ['en_US-sam-medium.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: 'medium quality',
      downloadSizeBytes: 67249919,
      piperPrefix: 'en_US-sam-medium',
    ),
    LocalSpeechModel(
      id: 'piper-joe-medium',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Joe',
      description: 'Conversational US English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-joe-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_US-joe-medium',
      requiredFiles: ['en_US-joe-medium.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: 'medium quality',
      downloadSizeBytes: 67169394,
      piperPrefix: 'en_US-joe-medium',
    ),
    LocalSpeechModel(
      id: 'piper-cori-medium',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Cori',
      description: 'Natural British English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-cori-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_GB-cori-medium',
      requiredFiles: ['en_GB-cori-medium.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: 'medium quality',
      downloadSizeBytes: 67257412,
      piperPrefix: 'en_GB-cori-medium',
    ),
    LocalSpeechModel(
      id: 'piper-alba-medium',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Alba',
      description: 'Clear British English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_GB-alba-medium',
      requiredFiles: ['en_GB-alba-medium.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: 'medium quality',
      downloadSizeBytes: 67212349,
      piperPrefix: 'en_GB-alba-medium',
    ),
    LocalSpeechModel(
      id: 'piper-alan-medium',
      kind: LocalSpeechModelKind.textToSpeech,
      name: 'Alan',
      description: 'Classic British English Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alan-medium.tar.bz2',
      archiveRoot: 'vits-piper-en_GB-alan-medium',
      requiredFiles: ['en_GB-alan-medium.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: 'medium quality',
      downloadSizeBytes: 67220121,
      piperPrefix: 'en_GB-alan-medium',
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
