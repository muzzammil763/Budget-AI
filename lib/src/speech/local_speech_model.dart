enum LocalSpeechModelKind { speechToText }

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
  final String? directDownloadBaseUrl;
}

class LocalSpeechModels {
  const LocalSpeechModels._();

  static const String defaultSttId = 'whisper-small-en-int8';

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
