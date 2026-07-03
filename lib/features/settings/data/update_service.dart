import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api_key_storage_service.dart';

class UpdateInfo {
  final String tagName;
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final String assetName;

  const UpdateInfo({
    required this.tagName,
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.assetName,
  });
}

class UpdateService {
  static const _owner = 'muzzammil763';
  static const _repo = 'Remote-Agent';
  static const _installChannel = MethodChannel('open_gate/install_apk');

  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 180),
    ),
  );

  /// Returns [UpdateInfo] when a newer release exists, or null when up to date
  /// or when no GitHub token is configured.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final token = await ApiKeyStorageService.getGithubApiKey();
      if (token == null || token.trim().isEmpty) return null;

      final currentInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(currentInfo.buildNumber) ?? 0;

      final response = await _dio.get(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
        options: Options(
          headers: {
            'Authorization': 'token ${token.trim()}',
            'Accept': 'application/vnd.github.v3+json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').trim();

      // Parse "v1.0.38+39" → version="1.0.38", buildNumber=39
      final raw = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      final parts = raw.split('+');
      final version = parts[0];
      final remoteBuild = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

      if (remoteBuild <= currentBuild) return null;

      // Find the first APK asset
      final assets = data['assets'] as List<dynamic>? ?? [];
      String? downloadUrl;
      String? assetName;
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '');
        if (name.endsWith('.apk')) {
          downloadUrl = asset['url'] as String?;
          assetName = name;
          break;
        }
      }

      if (downloadUrl == null) return null;

      return UpdateInfo(
        tagName: tagName,
        version: version,
        buildNumber: remoteBuild,
        releaseNotes: (data['body'] as String? ?? '').trim(),
        downloadUrl: downloadUrl,
        assetName: assetName ?? 'OpenGate.apk',
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK to the app's cache directory and reports [0,1] progress.
  Future<File?> downloadApk(
    String downloadUrl,
    String assetName, {
    void Function(double progress)? onProgress,
  }) async {
    final token = await ApiKeyStorageService.getGithubApiKey();
    if (token == null) return null;

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$assetName';

    await _dio.download(
      downloadUrl,
      filePath,
      options: Options(
        headers: {
          'Authorization': 'token ${token.trim()}',
          'Accept': 'application/octet-stream',
        },
      ),
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    return File(filePath);
  }

  /// Copies the APK to external cache (most reliable FileProvider path) and
  /// triggers the Android package-installer. Throws on failure so callers can
  /// surface the error to the user.
  Future<bool> installApk(String filePath) async {
    final source = File(filePath);
    if (!await source.exists()) {
      throw Exception('APK not found: $filePath');
    }

    // Copy to external cache — the safest FileProvider-backed directory.
    final externalCache = await getExternalCacheDirectories().then(
      (dirs) => dirs?.firstOrNull,
    );
    final destDir = externalCache ?? await getTemporaryDirectory();
    final dest = File(p.join(destDir.path, p.basename(filePath)));

    await source.copy(dest.path);

    final result = await _installChannel.invokeMethod<dynamic>('installApk', {
      'path': dest.path,
    });
    if (result == true) return true;
    throw Exception('APK install failed: $result');
  }
}
