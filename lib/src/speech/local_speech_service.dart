import 'package:budget_ai/src/speech/local_speech_model.dart';
import 'package:budget_ai/src/speech/local_speech_model_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class LocalSpeechService {
  LocalSpeechService({LocalSpeechModelManager? manager})
    : _manager = manager ?? LocalSpeechModelManager.instance;

  final LocalSpeechModelManager _manager;

  bool get isReadyForVoiceTurn =>
      _manager.installed(_manager.selectedSttId.value) &&
      _manager.installed(_manager.selectedTtsId.value);

  Future<String> transcribe(String audioPath) async {
    final model = LocalSpeechModels.byId(_manager.selectedSttId.value);
    if (model == null || !await _manager.isInstalled(model)) {
      throw StateError(
        'Download and select a speech-to-text model in Settings first.',
      );
    }
    final directory = await _manager.directoryFor(model);
    return compute(transcribeWithWhisper, (
      audioPath: audioPath,
      directory: directory.path,
      whisperPrefix: model.whisperPrefix!,
    ));
  }

  Future<Uint8List> synthesize(String text, {String? modelId}) async {
    final model = LocalSpeechModels.byId(
      modelId ?? _manager.selectedTtsId.value,
    );
    if (model == null || !await _manager.isInstalled(model)) {
      throw StateError(
        'Download and select a text-to-speech voice in Settings first.',
      );
    }
    final directory = await _manager.directoryFor(model);
    return compute(synthesizeWithPiper, (
      text: text,
      directory: directory.path,
      piperPrefix: model.piperPrefix!,
    ));
  }

  static List<String> speechChunks(String input, {int maxLength = 1200}) {
    final normalized = input
        .replaceAll(RegExp(r'[`#*_>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];

    final chunks = <String>[];
    var remaining = normalized;
    while (remaining.length > maxLength) {
      var splitAt = remaining.lastIndexOf(RegExp(r'[.!?]'), maxLength - 1);
      var includeBoundary = splitAt >= maxLength ~/ 2;
      if (splitAt < maxLength ~/ 2) {
        splitAt = remaining.lastIndexOf(' ', maxLength - 1);
        includeBoundary = false;
      }
      if (splitAt <= 0) {
        splitAt = maxLength;
        includeBoundary = false;
      }
      final end = includeBoundary ? splitAt + 1 : splitAt;
      chunks.add(remaining.substring(0, end).trim());
      remaining = remaining.substring(end).trim();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }
}

String transcribeWithWhisper(
  ({String audioPath, String directory, String whisperPrefix}) input,
) {
  sherpa.initBindings();
  final prefix = input.whisperPrefix;
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: p.join(input.directory, '$prefix-encoder.int8.onnx'),
          decoder: p.join(input.directory, '$prefix-decoder.int8.onnx'),
          language: prefix.endsWith('.en') ? 'en' : '',
          task: 'transcribe',
        ),
        tokens: p.join(input.directory, '$prefix-tokens.txt'),
        modelType: 'whisper',
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  final stream = recognizer.createStream();
  try {
    final wave = sherpa.readWave(input.audioPath);
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream.free();
    recognizer.free();
  }
}

Uint8List synthesizeWithPiper(
  ({String text, String directory, String piperPrefix}) input,
) {
  sherpa.initBindings();
  final prefix = input.piperPrefix;
  final tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: p.join(input.directory, '$prefix.onnx'),
          tokens: p.join(input.directory, 'tokens.txt'),
          dataDir: p.join(input.directory, 'espeak-ng-data'),
        ),
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  try {
    final generated = tts.generate(text: input.text);
    if (generated.samples.isEmpty || generated.sampleRate <= 0) {
      throw const FormatException('The local voice generated no audio.');
    }
    return _encodePcm16Wave(generated.samples, generated.sampleRate);
  } finally {
    tts.free();
  }
}

Uint8List _encodePcm16Wave(Float32List samples, int sampleRate) {
  final dataLength = samples.length * 2;
  final bytes = ByteData(44 + dataLength);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    final sample = samples[index].clamp(-1.0, 1.0);
    bytes.setInt16(44 + index * 2, (sample * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
