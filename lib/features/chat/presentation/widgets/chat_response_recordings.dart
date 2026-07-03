import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/data/services/remote_file_cache_service.dart';
import 'package:video_player/video_player.dart';

class ChatResponseRecordings extends StatelessWidget {
  const ChatResponseRecordings({
    super.key,
    required this.recordingUrls,
    required this.authToken,
    required this.onRecordingTap,
  });

  final List<String> recordingUrls;
  final String authToken;
  final ValueChanged<String> onRecordingTap;

  @override
  Widget build(BuildContext context) {
    if (recordingUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < recordingUrls.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _RecordingPreview(
              videoUrl: recordingUrls[i],
              authToken: authToken,
              onTap: onRecordingTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordingPreview extends StatefulWidget {
  const _RecordingPreview({
    required this.videoUrl,
    required this.authToken,
    required this.onTap,
  });

  final String videoUrl;
  final String authToken;
  final ValueChanged<String> onTap;

  @override
  State<_RecordingPreview> createState() => _RecordingPreviewState();
}

class _RecordingPreviewState extends State<_RecordingPreview> {
  late Future<File?> _previewFuture;
  VideoPlayerController? _controller;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _previewFuture = _loadPreview(++_loadGeneration);
  }

  @override
  void didUpdateWidget(covariant _RecordingPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.authToken != widget.authToken) {
      _controller?.dispose();
      _controller = null;
      _error = null;
      _previewFuture = _loadPreview(++_loadGeneration);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  Future<File?> _loadPreview(int generation) async {
    try {
      final file = await RemoteFileCacheService.instance.getOrDownload(
        url: widget.videoUrl,
        headers: {'X-API-Key': widget.authToken},
      );
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.pause();
      await controller.seekTo(Duration.zero);
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return file;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      return file;
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error);
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => widget.onTap(widget.videoUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: FutureBuilder<File?>(
            future: _previewFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData &&
                  _controller == null) {
                return _RecordingLoading(theme: theme);
              }
              if (_error != null ||
                  _controller == null ||
                  !_controller!.value.isInitialized) {
                return _RecordingError(theme: theme);
              }
              return _RecordingThumbnail(controller: _controller!);
            },
          ),
        ),
      ),
    );
  }
}

class _RecordingThumbnail extends StatelessWidget {
  const _RecordingThumbnail({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.06),
                  Colors.black.withValues(alpha: 0.20),
                ],
              ),
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0.3, sigmaY: 0.3),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.52),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 10,
          child: Text(
            _formatDuration(controller.value.duration),
            style: AppTheme.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w700,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _RecordingLoading extends StatelessWidget {
  const _RecordingLoading({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child: CircularProgressIndicator(color: theme.colorScheme.primary),
    );
  }
}

class _RecordingError extends StatelessWidget {
  const _RecordingError({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_off_outlined,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            'Could not render recording preview.',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
