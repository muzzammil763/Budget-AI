import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import 'package:budget_ai/app/theme/app_theme.dart';

class ChatShimmerBlock extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ChatShimmerBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<ChatShimmerBlock> createState() => _ChatShimmerBlockState();
}

class _ChatShimmerBlockState extends State<ChatShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.14,
    );
    final highlightColor = theme.colorScheme.surface.withValues(alpha: 0.50);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) {
                final width = bounds.width;
                final slide = width * 2 * _controller.value - width;
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    baseColor,
                    baseColor.withValues(alpha: 0.32),
                    highlightColor,
                    baseColor.withValues(alpha: 0.32),
                    baseColor,
                  ],
                  stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
                  transform: _SlidingGradientTransform(slide),
                ).createShader(bounds);
              },
              child: child,
            );
          },
          child: ColoredBox(color: baseColor),
        ),
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slide;

  const _SlidingGradientTransform(this.slide);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(slide, 0, 0);
  }
}

class ChatLoadingMessage extends StatelessWidget {
  final String iconPath;
  final String message;

  const ChatLoadingMessage({
    super.key,
    required this.iconPath,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: SvgPicture.asset(
              iconPath,
              colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
              width: 16,
              height: 16,
            ),
          ),
          const SizedBox(width: 8),
          const ChatLoadingLottie(size: 48),
        ],
      ),
    );
  }
}

class ChatLoadingLottie extends StatelessWidget {
  final double size;
  final bool reverse;

  const ChatLoadingLottie({
    super.key,
    required this.size,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRect(
        child: Transform.scale(
          scale: 2.35,
          child: Lottie.asset(
            'assets/lotties/loading.json',
            width: size,
            height: size,
            fit: BoxFit.contain,
            animate: true,
            frameRate: FrameRate.max,
            reverse: reverse,
          ),
        ),
      ),
    );
  }
}

class ChatInitializingSection extends StatelessWidget {
  const ChatInitializingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChatShimmerBlock(
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(28),
          ),
          const SizedBox(height: 24),
          ChatShimmerBlock(
            width: 132,
            height: 14,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 12),
          Text(
            'Initializing ...',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
