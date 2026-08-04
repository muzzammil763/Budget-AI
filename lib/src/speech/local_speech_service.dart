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
      _manager.installed(_manager.selectedSttId.value);

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
