import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:budget_ai/src/speech/local_speech_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSpeechDownloadState {
  const LocalSpeechDownloadState({
    this.installed = false,
    this.downloading = false,
    this.progress,
    this.error,
  });

  final bool installed;
  final bool downloading;
  final double? progress;
  final String? error;
}

Future<void> extractLocalSpeechArchive(
  ({String inputPath, String outputPath}) paths,
) {
  return extractFileToDisk(paths.inputPath, paths.outputPath);
}

String localSpeechDownloadErrorMessage(Object error) {
  if (error is DioException) {
    return 'Download failed. Check your connection and try again.';
  }
  if (error is FormatException) {
    return error.message;
  }
  if (error is FileSystemException) {
    return 'Could not install the downloaded model. Check available storage '
        'and try again.';
  }
  return 'Could not install the downloaded model. Please try again.';
}

class LocalSpeechModelManager {
  LocalSpeechModelManager._();

  static final LocalSpeechModelManager instance = LocalSpeechModelManager._();
  static const _sttKey = 'budget_local_stt_model_id';
  static const _ttsKey = 'budget_local_tts_model_id';

  final ValueNotifier<String> selectedSttId = ValueNotifier(
    LocalSpeechModels.defaultSttId,
  );
  final ValueNotifier<String> selectedTtsId = ValueNotifier(
    LocalSpeechModels.defaultTtsId,
  );
  final ValueNotifier<Map<String, LocalSpeechDownloadState>> states =
      ValueNotifier(const {});
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final Dio _dio = Dio();
  Directory? _modelsDirectory;

  Future<void> initialize() async {
    final support = await getApplicationSupportDirectory();
    _modelsDirectory = Directory(p.join(support.path, 'speech_models'));
    await _modelsDirectory!.create(recursive: true);
    final savedStt = await _preferences.getString(_sttKey);
    final savedTts = await _preferences.getString(_ttsKey);
    if (LocalSpeechModels.byId(savedStt ?? '')?.kind ==
        LocalSpeechModelKind.speechToText) {
      selectedSttId.value = savedStt!;
    }
    if (LocalSpeechModels.byId(savedTts ?? '')?.kind ==
        LocalSpeechModelKind.textToSpeech) {
      selectedTtsId.value = savedTts!;
    }
    await refresh();
  }

  Future<Directory> directoryFor(LocalSpeechModel model) async {
    if (_modelsDirectory == null) await initialize();
    return Directory(p.join(_modelsDirectory!.path, model.id));
  }

  Future<bool> isInstalled(LocalSpeechModel model) async {
    final directory = await directoryFor(model);
    for (final relativePath in model.requiredFiles) {
      final type = FileSystemEntity.typeSync(
        p.join(directory.path, relativePath),
      );
      if (type == FileSystemEntityType.notFound) return false;
    }
    return true;
  }

  Future<void> refresh() async {
    final next = <String, LocalSpeechDownloadState>{};
    for (final model in LocalSpeechModels.all) {
      next[model.id] = LocalSpeechDownloadState(
        installed: await isInstalled(model),
      );
    }
    states.value = next;
  }

  bool installed(String id) => states.value[id]?.installed ?? false;

  Future<void> select(LocalSpeechModel model) async {
    if (!await isInstalled(model)) {
      throw StateError('Download ${model.name} before selecting it.');
    }
    if (model.kind == LocalSpeechModelKind.speechToText) {
      await _preferences.setString(_sttKey, model.id);
      selectedSttId.value = model.id;
    } else {
      await _preferences.setString(_ttsKey, model.id);
      selectedTtsId.value = model.id;
    }
  }

  Future<void> download(LocalSpeechModel model) async {
    if (states.value[model.id]?.downloading ?? false) return;
    _setState(model.id, const LocalSpeechDownloadState(downloading: true));
    final base = _modelsDirectory ?? (await directoryFor(model)).parent;
    final archive = File(p.join(base.path, '${model.id}.download.tar.bz2'));
    final staging = Directory(p.join(base.path, '${model.id}.installing'));
    final destination = await directoryFor(model);
    try {
      if (await archive.exists()) await archive.delete();
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final Directory extracted;
      if (model.directDownloadBaseUrl != null) {
        await _downloadFiles(model, staging);
        extracted = staging;
      } else {
        await _dio.download(
          model.downloadUrl,
          archive.path,
          onReceiveProgress: (received, total) {
            _setState(
              model.id,
              LocalSpeechDownloadState(
                downloading: true,
                progress: total > 0 ? received / total : null,
              ),
            );
          },
        );
        await compute(extractLocalSpeechArchive, (
          inputPath: archive.path,
          outputPath: staging.path,
        ));
        extracted = Directory(p.join(staging.path, model.archiveRoot));
      }
      if (!await extracted.exists()) {
        throw const FormatException('The downloaded model archive is invalid.');
      }
      if (await destination.exists()) await destination.delete(recursive: true);
      await extracted.rename(destination.path);
      await _removeUnneededWhisperFiles(model, destination);
      if (!await isInstalled(model)) {
        throw const FormatException('The model download is incomplete.');
      }
      _setState(model.id, const LocalSpeechDownloadState(installed: true));
      await select(model);
    } catch (error) {
      _setState(
        model.id,
        LocalSpeechDownloadState(error: localSpeechDownloadErrorMessage(error)),
      );
      rethrow;
    } finally {
      if (await archive.exists()) await archive.delete();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _downloadFiles(
    LocalSpeechModel model,
    Directory destination,
  ) async {
    final files = model.requiredFiles;
    for (var index = 0; index < files.length; index++) {
      final relativePath = files[index];
      final output = File(p.join(destination.path, relativePath));
      await output.parent.create(recursive: true);
      await _dio.download(
        '${model.directDownloadBaseUrl}/$relativePath?download=true',
        output.path,
        onReceiveProgress: (received, total) {
          final fileProgress = total > 0 ? received / total : 0.0;
          _setState(
            model.id,
            LocalSpeechDownloadState(
              downloading: true,
              progress: (index + fileProgress) / files.length,
            ),
          );
        },
      );
    }
  }

  Future<void> delete(LocalSpeechModel model) async {
    final previousState =
        states.value[model.id] ?? const LocalSpeechDownloadState();
    _setState(model.id, const LocalSpeechDownloadState());
    try {
      final directory = await directoryFor(model);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      _setState(
        model.id,
        LocalSpeechDownloadState(
          installed: previousState.installed,
          error: localSpeechDownloadErrorMessage(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> _removeUnneededWhisperFiles(
    LocalSpeechModel model,
    Directory directory,
  ) async {
    if (model.kind != LocalSpeechModelKind.speechToText) return;
    final keep = model.requiredFiles.map(p.normalize).toSet();
    await for (final entity in directory.list()) {
      final relative = p.relative(entity.path, from: directory.path);
      if (!keep.contains(relative)) await entity.delete(recursive: true);
    }
  }

  void _setState(String id, LocalSpeechDownloadState state) {
    states.value = {...states.value, id: state};
  }
}
