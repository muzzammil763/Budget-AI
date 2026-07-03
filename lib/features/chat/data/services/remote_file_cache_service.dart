import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RemoteFileCacheService {
  RemoteFileCacheService._();

  static final RemoteFileCacheService instance = RemoteFileCacheService._();

  static const String directoryName = 'remote_file_cache';

  final Dio _dio = Dio();

  Future<Directory> cacheDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, directoryName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File?> cachedFileForUrl(String url, {String? filename}) async {
    final file = await cacheFileForUrl(url, filename: filename);
    if (await file.exists()) return file;
    return null;
  }

  Future<File> cacheFileForUrl(String url, {String? filename}) async {
    final dir = await cacheDirectory();
    final safeName = _safeFilename(filename ?? _filenameFromUrl(url));
    final digest = sha1.convert(utf8.encode(url)).toString().substring(0, 12);
    return File(p.join(dir.path, '${digest}_$safeName'));
  }

  Future<File> getOrDownload({
    required String url,
    String? filename,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final file = await cacheFileForUrl(url, filename: filename);
    if (await file.exists() && await file.length() > 0) {
      return file;
    }
    await download(
      url: url,
      destination: file,
      headers: headers,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
    return file;
  }

  Future<void> download({
    required String url,
    required File destination,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    await destination.parent.create(recursive: true);
    final tempPath = '${destination.path}.download';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    try {
      await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        options: Options(headers: headers),
        onReceiveProgress: onReceiveProgress,
      );
      if (await destination.exists()) {
        await destination.delete();
      }
      await tempFile.rename(destination.path);
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  String _filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    return lastSegment.trim().isEmpty ? 'remote-file' : lastSegment;
  }

  String _safeFilename(String value) {
    final basename = p.basename(value.trim());
    final safe = basename.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return safe.isEmpty ? 'remote-file' : safe;
  }
}
