import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class DelayedMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration startDelay;
  final Duration endPause;
  final double pixelsPerSecond;
  final double endPadding;

  const DelayedMarqueeText({
    super.key,
    required this.text,
    required this.style,
    required this.startDelay,
    required this.endPause,
    required this.pixelsPerSecond,
    this.endPadding = 16,
  });

  @override
  State<DelayedMarqueeText> createState() => _DelayedMarqueeTextState();
}

class _DelayedMarqueeTextState extends State<DelayedMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _isOverflowing = false;
  double _scrollDistance = 0;
  double _textWidth = 0;
  double _lastAvailableWidth = -1;
  String _lastText = '';
  int _configurationVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_handleAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant DelayedMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.startDelay != widget.startDelay ||
        oldWidget.endPause != widget.endPause ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond ||
        oldWidget.endPadding != widget.endPadding) {
      _resetMarquee();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_isOverflowing) return;
    _timer?.cancel();
    _timer = Timer(widget.endPause, () {
      if (!mounted || !_isOverflowing) return;
      _controller.value = 0;
      _scheduleNextRun();
    });
  }

  void _scheduleNextRun() {
    _timer?.cancel();
    _timer = Timer(widget.startDelay, () {
      if (!mounted || !_isOverflowing || _controller.isAnimating) return;
      _controller.forward(from: 0);
    });
  }

  void _resetMarquee() {
    _timer?.cancel();
    _controller.stop();
    _controller.value = 0;
    _lastAvailableWidth = -1;
    _lastText = '';
    _isOverflowing = false;
    _scrollDistance = 0;
    _textWidth = 0;
    _configurationVersion++;
  }

  void _configureForWidth({
    required double availableWidth,
    required double textWidth,
  }) {
    final paddedTextWidth = textWidth + widget.endPadding;
    final isOverflowing = textWidth > availableWidth;
    final changed =
        _lastText != widget.text ||
        (_lastAvailableWidth - availableWidth).abs() > 0.5 ||
        (_textWidth - paddedTextWidth).abs() > 0.5 ||
        _isOverflowing != isOverflowing;
    if (!changed) return;

    _lastText = widget.text;
    _lastAvailableWidth = availableWidth;
    _textWidth = paddedTextWidth;
    _isOverflowing = isOverflowing;
    _scrollDistance = math.max(0, paddedTextWidth - availableWidth);
    _configurationVersion++;
    final version = _configurationVersion;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || version != _configurationVersion) return;
      _timer?.cancel();
      _controller.stop();
      _controller.value = 0;

      if (!_isOverflowing || _scrollDistance <= 0) {
        return;
      }

      final seconds = (_scrollDistance / widget.pixelsPerSecond).clamp(
        2.0,
        12.0,
      );
      _controller.duration = Duration(milliseconds: (seconds * 1000).round());
      _scheduleNextRun();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        if (!availableWidth.isFinite || availableWidth <= 0) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        _configureForWidth(
          availableWidth: availableWidth,
          textWidth: textPainter.width,
        );

        if (!_isOverflowing) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: widget.style,
          );
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_scrollDistance * _controller.value, 0),
                child: child,
              );
            },
            child: SizedBox(
              width: _textWidth,
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}
