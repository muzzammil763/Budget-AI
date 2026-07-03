import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/chat/data/services/remote_file_cache_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams, XFile;
import 'package:budget_ai/features/chat/presentation/screens/image_viewer_screen.dart';
import 'package:budget_ai/features/chat/presentation/screens/video_preview_screen.dart';
import 'package:budget_ai/features/github/presentation/screens/gh_file_viewer_screen.dart';
import 'package:budget_ai/features/settings/data/update_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:toastification/toastification.dart';

enum _DownloadState { idle, downloading, done, error }

class ChatResponseFile extends StatelessWidget {
  const ChatResponseFile({
    super.key,
    required this.fileInfos,
    required this.authToken,
  });

  final List<Map<String, dynamic>> fileInfos;
  final String authToken;

  @override
  Widget build(BuildContext context) {
    if (fileInfos.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < fileInfos.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _FileCard(
              fileUrl: fileInfos[i]['file_url'] as String,
              filename: fileInfos[i]['filename'] as String? ?? 'file',
              sizeBytes: (fileInfos[i]['size_bytes'] as num?)?.toInt() ?? 0,
              authToken: authToken,
            ),
          ],
        ],
      ),
    );
  }
}

class _FileCard extends StatefulWidget {
  const _FileCard({
    required this.fileUrl,
    required this.filename,
    required this.sizeBytes,
    required this.authToken,
  });

  final String fileUrl;
  final String filename;
  final int sizeBytes;
  final String authToken;

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  _DownloadState _state = _DownloadState.idle;
  double _progress = 0.0;
  String? _localPath;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCachedFile());
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _restoreCachedFile() async {
    final cached = await RemoteFileCacheService.instance.cachedFileForUrl(
      widget.fileUrl,
      filename: widget.filename,
    );
    if (!mounted || cached == null) return;
    setState(() {
      _localPath = cached.path;
      _state = _DownloadState.done;
      _progress = 1.0;
    });
  }

  Future<bool> _performDownload(String destPath) async {
    _cancelToken = CancelToken();
    try {
      await RemoteFileCacheService.instance.download(
        url: widget.fileUrl,
        destination: File(destPath),
        headers: {'X-API-Key': widget.authToken},
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = _DownloadState.downloading;
      _progress = 0.0;
    });

    final destFile = await RemoteFileCacheService.instance.cacheFileForUrl(
      widget.fileUrl,
      filename: widget.filename,
    );
    final destPath = destFile.path;
    final ok = await _performDownload(destPath);

    if (ok && mounted) {
      setState(() {
        _state = _DownloadState.done;
        _localPath = destPath;
      });
      showAppToast(context, message: '${widget.filename} ready');
    } else if (mounted) {
      setState(() => _state = _DownloadState.error);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _state = _DownloadState.idle);
    }
  }

  Future<void> _saveToDownloads() async {
    final source = _localPath;
    if (source == null) return;

    try {
      String? destPath;
      if (Platform.isAndroid) {
        final destDir = Directory('/storage/emulated/0/Download/Remote-Agent');
        await destDir.create(recursive: true);
        if (!mounted) return;
        destPath = p.join(destDir.path, widget.filename);
      } else {
        final base = await getDownloadsDirectory();
        if (!mounted) return;
        if (base != null) {
          final destDir = Directory(p.join(base.path, 'Remote Agent'));
          await destDir.create(recursive: true);
          if (!mounted) return;
          destPath = p.join(destDir.path, widget.filename);
        }
      }

      if (destPath == null) {
        if (!mounted) return;
        showAppToast(
          context,
          message: 'Could not access Downloads folder',
          type: ToastificationType.error,
        );
        return;
      }

      await File(source).copy(destPath);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Saved to Downloads/Remote-Agent/${widget.filename}',
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Could not save: $e',
        type: ToastificationType.error,
      );
    }
  }

  Future<void> _shareFile() async {
    final path = _localPath;
    if (path == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Future<void> _installApk() async {
    final path = _localPath;
    if (path == null) return;

    final installPerm = await Permission.requestInstallPackages.status;
    if (!installPerm.isGranted) {
      final requested = await Permission.requestInstallPackages.request();
      if (!requested.isGranted) {
        if (mounted) {
          showAppToast(
            context,
            message: 'Install permission required. Enable in Settings.',
            type: ToastificationType.error,
          );
        }
        return;
      }
    }
    try {
      await UpdateService.instance.installApk(path);
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Install failed: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> _viewFile() async {
    final ext = p.extension(widget.filename).toLowerCase();

    final localPath = await _ensureLocalFile();
    if (localPath == null) return;

    // Images
    const imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};
    if (imageExts.contains(ext)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen.file(
            filePath: localPath,
            title: widget.filename,
          ),
        ),
      );
      return;
    }

    // Videos
    const videoExts = {'.mp4', '.mov', '.avi', '.mkv'};
    if (videoExts.contains(ext)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPreviewScreen.file(
            filePath: localPath,
            title: widget.filename,
          ),
        ),
      );
      return;
    }

    // All other files – open with the GitHub file viewer
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GithubFileViewerScreen(
          filePath: p.basename(localPath),
          isLocalFile: true,
          localPath: p.dirname(localPath),
          fullName: '',
          branch: '',
        ),
      ),
    );
  }

  Future<String?> _ensureLocalFile() async {
    String? path = _localPath;
    if (path == null) {
      setState(() {
        _state = _DownloadState.downloading;
        _progress = 0.0;
      });
      path = (await RemoteFileCacheService.instance.cacheFileForUrl(
        widget.fileUrl,
        filename: widget.filename,
      )).path;
      final ok = await _performDownload(path);
      if (!ok) {
        if (mounted) {
          setState(() => _state = _DownloadState.error);
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) setState(() => _state = _DownloadState.idle);
        }
        return null;
      }
      if (mounted) setState(() => _state = _DownloadState.done);
      _localPath = path;
    }
    return path;
  }

  bool get _isApk => p.extension(widget.filename).toLowerCase() == '.apk';
  bool get _isViewable {
    final ext = p.extension(widget.filename).toLowerCase();
    const viewable = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
    };
    return viewable.contains(ext);
  }

  IconData _iconForFile() {
    final ext = p.extension(widget.filename).toLowerCase();
    switch (ext) {
      case '.apk':
        return Icons.android_outlined;
      case '.ipa':
        return Icons.phone_iphone_outlined;
      case '.pdf':
        return Icons.picture_as_pdf_outlined;
      case '.zip':
      case '.tar':
      case '.gz':
      case '.rar':
      case '.7z':
        return Icons.folder_zip_outlined;
      case '.mp4':
      case '.mov':
      case '.avi':
      case '.mkv':
        return Icons.video_file_outlined;
      case '.mp3':
      case '.wav':
      case '.aac':
      case '.m4a':
        return Icons.audio_file_outlined;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
        return Icons.image_outlined;
      case '.txt':
      case '.log':
      case '.md':
        return Icons.text_snippet_outlined;
      case '.json':
      case '.xml':
      case '.yaml':
      case '.yml':
      case '.dart':
      case '.py':
      case '.js':
      case '.ts':
        return Icons.code_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildTrailing(ThemeData theme) {
    switch (_state) {
      case _DownloadState.idle:
        return IconButton(
          onPressed: _startDownload,
          icon: Icon(Icons.download_outlined, color: theme.colorScheme.primary),
          tooltip: 'Download',
        );

      case _DownloadState.downloading:
        return SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _progress,
                strokeWidth: 3,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.2,
                ),
              ),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );

      case _DownloadState.done:
        final children = <Widget>[
          IconButton(
            onPressed: _saveToDownloads,
            icon: Icon(
              Icons.save_alt_outlined,
              color: theme.colorScheme.primary,
            ),
            tooltip: 'Save to Downloads',
          ),
          if (_isApk)
            IconButton(
              onPressed: _installApk,
              icon: Icon(
                Icons.android_outlined,
                color: theme.colorScheme.primary,
              ),
              tooltip: 'Install',
            )
          else if (_isViewable)
            IconButton(
              onPressed: _viewFile,
              icon: Icon(
                Icons.visibility_outlined,
                color: theme.colorScheme.primary,
              ),
              tooltip: 'View',
            ),
          IconButton(
            onPressed: _shareFile,
            icon: Icon(Icons.share_outlined, color: theme.colorScheme.primary),
            tooltip: 'Share',
          ),
        ];
        return Row(mainAxisSize: MainAxisSize.min, children: children);

      case _DownloadState.error:
        return Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
          size: 24,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(_iconForFile(), color: theme.colorScheme.primary, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.filename,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.sizeBytes > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatSize(widget.sizeBytes),
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          _buildTrailing(theme),
        ],
      ),
    );
  }
}
