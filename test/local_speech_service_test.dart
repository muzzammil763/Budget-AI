import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:budget_ai/src/speech/local_speech_model.dart';
import 'package:budget_ai/src/speech/local_speech_model_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('local speech catalog contains only Whisper Small English', () {
    expect(
      LocalSpeechModels.ofKind(LocalSpeechModelKind.speechToText),
      hasLength(1),
    );
    expect(LocalSpeechModels.byId(LocalSpeechModels.defaultSttId), isNotNull);
    expect(
      LocalSpeechModels.all.every(
        (model) =>
            model.downloadUrl.startsWith('https://github.com/k2-fsa/') &&
            (model.directDownloadBaseUrl == null ||
                model.directDownloadBaseUrl!.startsWith(
                  'https://huggingface.co/csukuangfj/',
                )),
      ),
      isTrue,
    );
    expect(
      LocalSpeechModels.all.map((model) => model.id).toSet(),
      hasLength(LocalSpeechModels.all.length),
    );
    expect(
      LocalSpeechModels.all.every(
        (model) =>
            model.requiredFiles.isNotEmpty &&
            model.downloadSizeBytes > 0 &&
            model.kind == LocalSpeechModelKind.speechToText &&
            model.whisperPrefix != null,
      ),
      isTrue,
    );
    expect(
      LocalSpeechModels.all.every((model) => model.details.length >= 4),
      isTrue,
    );
  });

  test('model archive extraction uses only sendable isolate data', () async {
    final root = await Directory.systemTemp.createTemp(
      'budget_ai_speech_extract_',
    );
    try {
      final source = Directory('${root.path}/whisper-model');
      final output = Directory('${root.path}/output');
      await source.create();
      await File('${source.path}/tokens.txt').writeAsString('test tokens');

      final tarPath = '${root.path}/model.tar';
      final archivePath = '${root.path}/model.tar.bz2';
      await TarFileEncoder().tarDirectory(source, filename: tarPath);
      await File(archivePath).writeAsBytes(
        BZip2Encoder().encodeBytes(await File(tarPath).readAsBytes()),
      );

      await compute(extractLocalSpeechArchive, (
        inputPath: archivePath,
        outputPath: output.path,
      ));

      expect(
        await File('${output.path}/whisper-model/tokens.txt').readAsString(),
        'test tokens',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('internal install failures are safe to display', () {
    final message = localSpeechDownloadErrorMessage(
      ArgumentError(
        'Illegal argument in isolate message: WidgetsFlutterBinding',
      ),
    );
    expect(
      message,
      'Could not install the downloaded model. Please try again.',
    );
    expect(message, isNot(contains('WidgetsFlutterBinding')));
  });
}
