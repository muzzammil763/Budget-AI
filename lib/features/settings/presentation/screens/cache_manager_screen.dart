import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/chat/data/services/remote_file_cache_service.dart';
import 'package:budget_ai/features/chat/presentation/screens/image_viewer_screen.dart';
import 'package:budget_ai/features/chat/presentation/screens/video_preview_screen.dart';
import 'package:budget_ai/features/github/presentation/screens/gh_file_viewer_screen.dart';
import 'package:budget_ai/features/settings/data/update_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:toastification/toastification.dart';

class CacheManagerScreen extends StatefulWidget {
  const CacheManagerScreen({super.key});

  @override
  State<CacheManagerScreen> createState() => _CacheManagerScreenState();
}

class _CacheManagerScreenState extends State<CacheManagerScreen> {
  List<_CacheFile> _files = [];
  bool _isLoading = true;
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final dirs = <Directory>[];
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationCacheDirectory());
    } catch (_) {}
    try {
      dirs.add(await RemoteFileCacheService.instance.cacheDirectory());
    } catch (_) {}

    final seen = <String>{};
    final files = <_CacheFile>[];

    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await _collect(dir, dir.path, files, seen);
    }

    files.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final total = files.fold<int>(0, (s, f) => s + f.sizeBytes);

    if (!mounted) return;
    setState(() {
      _files = files;
      _totalBytes = total;
      _isLoading = false;
    });
  }

  Future<void> _collect(
    Directory dir,
    String rootPath,
    List<_CacheFile> out,
    Set<String> seen,
  ) async {
    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          if (seen.add(entity.path)) {
            try {
              final stat = await entity.stat();
              out.add(
                _CacheFile(
                  file: entity,
                  sizeBytes: stat.size,
                  modified: stat.modified,
                  rootPath: rootPath,
                ),
              );
            } catch (_) {}
          }
        } else if (entity is Directory) {
          await _collect(entity, rootPath, out, seen);
        }
      }
    } catch (_) {}
  }

  Future<bool?> _showDeleteDialog(_CacheFile item) {
    final theme = Theme.of(context);
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Delete File',
      headerIcon: Icon(
        CupertinoIcons.trash_fill,
        color: theme.colorScheme.onPrimary,
        size: 28,
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.error.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Delete "${item.name}"?',
          style: AppTheme.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This permanently removes the cached file. The app will re-download or recreate it when needed.',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(color: theme.colorScheme.outline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Delete'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool?> _showClearAllDialog() {
    final theme = Theme.of(context);
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Clear All Cache',
      headerIcon: Icon(
        CupertinoIcons.trash_fill,
        color: theme.colorScheme.onPrimary,
        size: 28,
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.error.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Clear all ${_files.length} cached files (${_formatBytes(_totalBytes)})?',
          style: AppTheme.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'All temporary and cached files will be deleted. The app will recreate them when needed.',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(color: theme.colorScheme.outline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Clear All'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteFile(_CacheFile item) async {
    try {
      await item.file.delete();
    } catch (_) {}
    if (!mounted) return;
    showAppToast(
      context,
      message: 'File deleted',
      type: ToastificationType.success,
    );
    setState(() {
      _files = _files.where((f) => f.file.path != item.file.path).toList();
      _totalBytes = (_totalBytes - item.sizeBytes).clamp(
        0,
        double.maxFinite.toInt(),
      );
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await _showClearAllDialog();
    if (confirmed != true || !mounted) return;

    var deleted = 0;
    for (final item in _files) {
      try {
        await item.file.delete();
        deleted++;
      } catch (_) {}
    }

    if (!mounted) return;
    showAppToast(
      context,
      message: deleted == 0
          ? 'Nothing deleted'
          : 'Cleared $deleted file${deleted == 1 ? '' : 's'}',
      type: ToastificationType.success,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Cache Manager'),
        actions: [
          if (!_isLoading && _files.isNotEmpty)
            IconButton(
              tooltip: 'Clear all cache',
              icon: const Icon(CupertinoIcons.trash, size: 20),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
          ? _buildEmpty(theme)
          : Column(
              children: [
                _buildSummaryBar(theme),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _files.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _files[index];
                      return Dismissible(
                        key: Key(item.file.path),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _showDeleteDialog(item),
                        onDismissed: (_) => _deleteFile(item),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            CupertinoIcons.trash_fill,
                            color: theme.colorScheme.onError,
                            size: 22,
                          ),
                        ),
                        child: _buildFileCard(item, theme),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.folder,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            '${_files.length} file${_files.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '·',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatBytes(_totalBytes),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            'Swipe left to delete',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.checkmark_shield,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Cache is clean',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No cached files found on disk.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(_CacheFile item, ThemeData theme) {
    final typeColor = _cacheFileTypeColor(item.typeLabel, theme);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _CacheFileDetailScreen(item: item)),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            _buildLeading(item, theme, typeColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.typeLabel.toUpperCase(),
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          style: AppTheme.headingSmall.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.subPath.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.55,
                        ),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatBytes(item.sizeBytes),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '·',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(item.modified),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(_CacheFile item, ThemeData theme, Color typeColor) {
    if (item.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          item.file,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _typeIconBox(item.icon, typeColor),
        ),
      );
    }
    return _typeIconBox(item.icon, typeColor);
  }

  Widget _typeIconBox(IconData icon, Color color) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }
}

class _CacheFileDetailScreen extends StatelessWidget {
  final _CacheFile item;

  const _CacheFileDetailScreen({required this.item});

  Future<void> _preview(BuildContext context) async {
    if (item.isImage) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImagePreviewScreen.file(
            filePath: item.file.path,
            title: item.name,
          ),
        ),
      );
      return;
    }

    if (item.isVideo || item.isAudio) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPreviewScreen.file(
            filePath: item.file.path,
            title: item.name,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GithubFileViewerScreen(
          filePath: p.basename(item.file.path),
          isLocalFile: true,
          localPath: p.dirname(item.file.path),
          fullName: '',
          branch: '',
        ),
      ),
    );
  }

  Future<void> _installApk(BuildContext context) async {
    final installPerm = await Permission.requestInstallPackages.status;
    if (!installPerm.isGranted) {
      final requested = await Permission.requestInstallPackages.request();
      if (!requested.isGranted) {
        if (context.mounted) {
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
      await UpdateService.instance.installApk(item.file.path);
    } catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Install failed: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _cacheFileTypeColor(item.typeLabel, theme);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('File Detail'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.isImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  item.file,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        CupertinoIcons.photo,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              item.typeLabel.toUpperCase(),
              style: TextStyle(
                color: typeColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              item.name,
              style: AppTheme.headingSmall.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            _infoRow(
              context,
              theme,
              label: 'SIZE',
              value: _formatBytes(item.sizeBytes),
            ),
            _infoRow(
              context,
              theme,
              label: 'MODIFIED',
              value: item.modified.toLocal().toString(),
            ),
            _infoRow(context, theme, label: 'PATH', value: item.file.path),
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.isPreviewable)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _preview(context),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Preview'),
                    ),
                  ),
                if (item.isPreviewable && item.isApk) const SizedBox(width: 10),
                if (item.isApk)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _installApk(context),
                      icon: const Icon(Icons.android_outlined, size: 18),
                      label: const Text('Install'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
            child: SelectableText(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inDays == 0) return 'Today';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

Color _cacheFileTypeColor(String type, ThemeData theme) {
  switch (type) {
    case 'image':
      return const Color.fromARGB(255, 47, 161, 255);
    case 'video':
      return const Color.fromARGB(255, 220, 66, 247);
    case 'audio':
      return const Color.fromARGB(255, 15, 201, 21);
    case 'json':
      return const Color.fromARGB(255, 223, 142, 21);
    case 'pdf':
      return const Color.fromARGB(255, 255, 80, 80);
    case 'archive':
      return const Color.fromARGB(255, 120, 120, 220);
    case 'text':
      return const Color.fromARGB(255, 100, 180, 130);
    case 'database':
      return const Color.fromARGB(255, 200, 110, 80);
    case 'apk':
      return const Color.fromARGB(255, 76, 175, 80);
    default:
      return theme.colorScheme.primary;
  }
}

// ── Model ─────────────────────────────────────────────────────

class _CacheFile {
  final File file;
  final int sizeBytes;
  final DateTime modified;
  final String rootPath;

  const _CacheFile({
    required this.file,
    required this.sizeBytes,
    required this.modified,
    required this.rootPath,
  });

  String get name => file.uri.pathSegments.last;

  String get subPath {
    final rel = file.path.replaceFirst(rootPath, '');
    final parts = rel.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return '';
    return parts.take(parts.length - 1).join('/');
  }

  String get ext =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';

  bool get isImage => const {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp',
  }.contains(ext);

  bool get isVideo => const {'mp4', 'mov', 'avi', 'mkv', 'webm'}.contains(ext);

  bool get isAudio => const {'mp3', 'aac', 'm4a', 'wav', 'flac'}.contains(ext);

  bool get isApk => ext == 'apk';

  bool get isCode => const {
    'txt',
    'log',
    'md',
    'json',
    'xml',
    'yaml',
    'yml',
    'dart',
    'py',
    'js',
    'ts',
    'tsx',
    'jsx',
    'java',
    'kt',
    'swift',
    'go',
    'rs',
    'c',
    'cpp',
    'h',
    'hpp',
    'css',
    'html',
    'sh',
    'gradle',
  }.contains(ext);

  bool get isPreviewable => isImage || isVideo || isAudio || isCode || isApk;

  String get typeLabel {
    if (isImage) return 'image';
    if (isVideo) return 'video';
    if (isAudio) return 'audio';
    if (isApk) return 'apk';
    switch (ext) {
      case 'json':
        return 'json';
      case 'pdf':
        return 'pdf';
      case 'zip':
      case 'gz':
      case 'tar':
      case '7z':
        return 'archive';
      case 'txt':
      case 'log':
        return 'text';
      case 'db':
      case 'sqlite':
        return 'database';
      default:
        return 'file';
    }
  }

  IconData get icon {
    switch (typeLabel) {
      case 'image':
        return CupertinoIcons.photo;
      case 'video':
        return CupertinoIcons.film;
      case 'audio':
        return CupertinoIcons.music_note;
      case 'json':
        return CupertinoIcons.doc_text;
      case 'pdf':
        return CupertinoIcons.doc_richtext;
      case 'archive':
        return CupertinoIcons.archivebox;
      case 'text':
        return CupertinoIcons.doc_plaintext;
      case 'database':
        return Icons.storage_outlined;
      case 'apk':
        return Icons.android_outlined;
      default:
        return CupertinoIcons.doc;
    }
  }
}
