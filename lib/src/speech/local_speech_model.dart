import 'package:budget_ai/src/speech/local_piper_voice_catalog.dart';

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

  static const List<LocalSpeechModel> _speechToTextModels = [
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
  ];

  static const String _defaultTtsPrefix = 'en_US-lessac-medium';

  static const Map<String, String> _legacyPiperIds = {
    'en_US-lessac-medium': defaultTtsId,
    'en_US-amy-low': 'piper-amy-low',
    'en_US-ryan-medium': 'piper-ryan-medium',
    'en_US-kristin-medium': 'piper-kristin-medium',
    'en_US-sam-medium': 'piper-sam-medium',
    'en_US-joe-medium': 'piper-joe-medium',
    'en_GB-cori-medium': 'piper-cori-medium',
    'en_GB-alba-medium': 'piper-alba-medium',
    'en_GB-alan-medium': 'piper-alan-medium',
  };

  static final List<LocalSpeechModel> _textToSpeechModels = [
    _piperModel(
      piperVoiceAssets.firstWhere((asset) => asset.prefix == _defaultTtsPrefix),
    ),
    for (final asset in piperVoiceAssets)
      if (asset.prefix != _defaultTtsPrefix) _piperModel(asset),
  ];

  static final List<LocalSpeechModel> all = List.unmodifiable([
    ..._speechToTextModels,
    ..._textToSpeechModels,
  ]);

  static LocalSpeechModel _piperModel(PiperVoiceAsset asset) {
    final localeSeparator = asset.prefix.indexOf('-');
    final locale = asset.prefix.substring(0, localeSeparator);
    final voiceAndQuality = asset.prefix.substring(localeSeparator + 1);
    final qualitySuffix = _qualitySuffix(voiceAndQuality);
    final voiceSlug = qualitySuffix.isEmpty
        ? voiceAndQuality
        : voiceAndQuality.substring(
            0,
            voiceAndQuality.length - qualitySuffix.length,
          );
    final voiceName = voiceSlug
        .split(RegExp('[-_]'))
        .where((part) => part.isNotEmpty)
        .map(_capitalize)
        .join(' ');
    final archiveRoot = 'vits-piper-${asset.prefix}';

    return LocalSpeechModel(
      id: _legacyPiperIds[asset.prefix] ?? 'piper-${asset.prefix}',
      kind: LocalSpeechModelKind.textToSpeech,
      name: '$voiceName (${locale.replaceAll('_', '-')})',
      description: 'Offline Piper voice',
      downloadUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
          '$archiveRoot.tar.bz2',
      archiveRoot: archiveRoot,
      requiredFiles: ['${asset.prefix}.onnx', 'tokens.txt', 'espeak-ng-data'],
      installedSizeLabel: _qualityLabel(qualitySuffix),
      downloadSizeBytes: asset.downloadSizeBytes,
      recommended: asset.prefix == _defaultTtsPrefix,
      piperPrefix: asset.prefix,
    );
  }

  static String _qualitySuffix(String voiceAndQuality) {
    for (final suffix in const ['-x_low', '-medium', '-high', '-low', '_low']) {
      if (voiceAndQuality.endsWith(suffix)) return suffix;
    }
    return '';
  }

  static String _qualityLabel(String suffix) {
    return switch (suffix) {
      '-x_low' => 'extra-low quality',
      '-low' || '_low' => 'low quality',
      '-medium' => 'medium quality',
      '-high' => 'high quality',
      _ => 'standard quality',
    };
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static Iterable<LocalSpeechModel> ofKind(LocalSpeechModelKind kind) =>
      all.where((model) => model.kind == kind);

  static LocalSpeechModel? byId(String id) {
    for (final model in all) {
      if (model.id == id) return model;
    }
    return null;
  }
}
