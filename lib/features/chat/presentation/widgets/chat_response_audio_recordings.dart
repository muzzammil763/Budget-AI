import 'dart:io';

import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/data/services/remote_file_cache_service.dart';
import 'package:video_player/video_player.dart';

class ChatResponseAudioRecordings extends StatelessWidget {
  const ChatResponseAudioRecordings({
    super.key,
    required this.audioUrls,
    required this.authToken,
  });

  final List<String> audioUrls;
  final String authToken;

  @override
  Widget build(BuildContext context) {
    if (audioUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < audioUrls.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _AudioRecordingPlayer(audioUrl: audioUrls[i], authToken: authToken),
          ],
        ],
      ),
    );
  }
}

class _AudioRecordingPlayer extends StatefulWidget {
  const _AudioRecordingPlayer({
    required this.audioUrl,
    required this.authToken,
  });

  final String audioUrl;
  final String authToken;

  @override
  State<_AudioRecordingPlayer> createState() => _AudioRecordingPlayerState();
}

class _AudioRecordingPlayerState extends State<_AudioRecordingPlayer> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _isLoading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load(++_loadGeneration);
  }

  @override
  void didUpdateWidget(covariant _AudioRecordingPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl ||
        oldWidget.authToken != widget.authToken) {
      _controller?.removeListener(_handleControllerUpdate);
      _controller?.dispose();
      _controller = null;
      _error = null;
      _isLoading = true;
      _load(++_loadGeneration);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _controller?.removeListener(_handleControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load(int generation) async {
    try {
      final file = await _downloadAudioFile();
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.pause();
      await controller.seekTo(Duration.zero);
      controller.addListener(_handleControllerUpdate);
      if (!mounted || generation != _loadGeneration) {
        controller.removeListener(_handleControllerUpdate);
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
        _isLoading = false;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = error;
          _isLoading = false;
        });
      }
    }
  }

  Future<File> _downloadAudioFile() async {
    return RemoteFileCacheService.instance.getOrDownload(
      url: widget.audioUrl,
      headers: {'X-API-Key': widget.authToken},
    );
  }

  void _handleControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      return;
    }
    if (controller.value.position >= controller.value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
  }

  Future<void> _seek(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.seekTo(Duration(milliseconds: value.round()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final isReady = controller != null && controller.value.isInitialized;
    final duration = isReady ? controller.value.duration : Duration.zero;
    final position = isReady ? controller.value.position : Duration.zero;
    final maxMs = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final valueMs = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton.filled(
              tooltip: isReady && controller.value.isPlaying ? 'Pause' : 'Play',
              onPressed: isReady ? _togglePlayback : null,
              icon: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      isReady && controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: theme.colorScheme.surface,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              spacing: 2,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error == null
                      ? 'Audio recording'
                      : 'Could not load audio recording.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatDuration(position),
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.64,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          min: 0,
                          max: maxMs,
                          value: valueMs,
                          onChanged: isReady ? _seek : null,
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.64,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
