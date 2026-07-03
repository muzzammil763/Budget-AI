import 'dart:io';

import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/data/services/remote_file_cache_service.dart';
import 'package:video_player/video_player.dart';

class VideoPreviewScreen extends StatefulWidget {
  const VideoPreviewScreen.network({
    super.key,
    required this.videoUrl,
    this.headers,
    this.title = 'Screen Recording',
  }) : filePath = null;

  const VideoPreviewScreen.file({
    super.key,
    required this.filePath,
    this.title = 'Screen Recording',
  }) : videoUrl = null,
       headers = null;

  final String? videoUrl;
  final String? filePath;
  final Map<String, String>? headers;
  final String title;

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  Future<File>? _downloadFuture;
  VideoPlayerController? _controller;
  bool _initializing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.filePath != null) {
      _initializeController(File(widget.filePath!));
    } else {
      _downloadFuture = RemoteFileCacheService.instance.getOrDownload(
        url: widget.videoUrl!,
        headers: widget.headers,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeController(File file) async {
    if (_initializing || _controller != null) return;
    _initializing = true;
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      await controller.play();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      _initializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: AppTheme.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: widget.filePath != null
          ? _buildPlayerBody()
          : FutureBuilder<File>(
              future: _downloadFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                final file = snapshot.data;
                if (file == null) return _buildError();
                _initializeController(file);
                return _buildPlayerBody();
              },
            ),
    );
  }

  Widget _buildPlayerBody() {
    if (_error != null) return _buildError();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 10,
            panEnabled: true,
            scaleEnabled: true,
            child: Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: _VideoControls(controller: controller),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            color: Colors.white70,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Could not load screen recording.',
            style: AppTheme.bodyMedium.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  color: Colors.white,
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    value.isPlaying ? controller.pause() : controller.play();
                  },
                ),
                Expanded(
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white12,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_formatDuration(value.position)} / '
                  '${_formatDuration(value.duration)}',
                  style: AppTheme.bodySmall.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
