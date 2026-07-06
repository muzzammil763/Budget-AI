import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChatToggleIconButton extends StatelessWidget {
  final bool isEnabled;
  final IconData enabledIcon;
  final IconData disabledIcon;
  final String enabledTooltip;
  final String disabledTooltip;
  final VoidCallback onPressed;

  const ChatToggleIconButton({
    super.key,
    required this.isEnabled,
    required this.enabledIcon,
    required this.disabledIcon,
    required this.enabledTooltip,
    required this.disabledTooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final borderColor = theme.colorScheme.outline;

    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(isEnabled ? enabledIcon : disabledIcon),
        onPressed: onPressed,
        color: isEnabled ? onPrimary : hintColor,
        style: IconButton.styleFrom(
          backgroundColor: isEnabled ? primary : Colors.transparent,
          shape: const CircleBorder(),
          side: isEnabled
              ? null
              : BorderSide(color: borderColor.withValues(alpha: 0.5), width: 1),
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        iconSize: 16,
        tooltip: isEnabled ? enabledTooltip : disabledTooltip,
      ),
    );
  }
}

class ImageAttachmentActionButton extends StatelessWidget {
  final int imageCount;
  final VoidCallback onPressed;

  const ImageAttachmentActionButton({
    super.key,
    required this.imageCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasImages = imageCount > 0;

    return ChatToggleIconButton(
      isEnabled: hasImages,
      enabledIcon: Icons.image,
      disabledIcon: Icons.image_outlined,
      enabledTooltip: '$imageCount Image(s) Attached - Tap To Add More',
      disabledTooltip: 'Attach images - Tap To Select From Gallery',
      onPressed: onPressed,
    );
  }
}

class VideoAttachmentActionButton extends StatelessWidget {
  final int videoCount;
  final VoidCallback onPressed;

  const VideoAttachmentActionButton({
    super.key,
    required this.videoCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasVideos = videoCount > 0;

    return ChatToggleIconButton(
      isEnabled: hasVideos,
      enabledIcon: Icons.videocam,
      disabledIcon: Icons.videocam_outlined,
      enabledTooltip: '$videoCount Video(s) Attached - Tap To Add More',
      disabledTooltip: 'Attach video',
      onPressed: onPressed,
    );
  }
}

class PdfAttachmentActionButton extends StatelessWidget {
  final int pdfCount;
  final VoidCallback onPressed;

  const PdfAttachmentActionButton({
    super.key,
    required this.pdfCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasPdfs = pdfCount > 0;

    return ChatToggleIconButton(
      isEnabled: hasPdfs,
      enabledIcon: Icons.picture_as_pdf,
      disabledIcon: Icons.picture_as_pdf_outlined,
      enabledTooltip: '$pdfCount PDF(s) Attached - Tap To Add More',
      disabledTooltip: 'Attach PDF',
      onPressed: onPressed,
    );
  }
}

class ContextUsageActionButton extends StatelessWidget {
  final double progress;
  final bool hasLimit;
  final bool isOverLimit;
  final String tooltip;
  final VoidCallback onPressed;

  const ContextUsageActionButton({
    super.key,
    required this.progress,
    required this.hasLimit,
    required this.isOverLimit,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final progressColor = (isOverLimit || normalizedProgress >= 0.80)
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        color: isOverLimit ? theme.colorScheme.error : hintColor,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: hasLimit ? normalizedProgress : null,
                strokeWidth: 2,
                strokeCap: StrokeCap.round,
                backgroundColor: progressColor.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            Icon(Icons.data_usage_rounded, size: 15, color: progressColor),
          ],
        ),
      ),
    );
  }
}

class ChatModeActionButton extends StatelessWidget {
  final bool isFastMode;
  final VoidCallback onPressed;

  const ChatModeActionButton({
    super.key,
    required this.isFastMode,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final borderColor = theme.colorScheme.outline;

    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: const Icon(Icons.flash_on_rounded),
        onPressed: onPressed,
        color: isFastMode ? onPrimary : hintColor,
        style: IconButton.styleFrom(
          backgroundColor: isFastMode ? primary : Colors.transparent,
          shape: const CircleBorder(),
          side: isFastMode
              ? null
              : BorderSide(color: borderColor.withValues(alpha: 0.5), width: 1),
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        iconSize: 15,
        tooltip: isFastMode
            ? 'Fast Mode: On — Tap to disable'
            : 'Fast Mode: Off — Tap to enable',
      ),
    );
  }
}

class WhatsAppSendFileButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onPressed;

  const WhatsAppSendFileButton({
    super.key,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final hintColor = theme.colorScheme.onSurfaceVariant;
    final borderColor = theme.colorScheme.outline;

    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: SvgPicture.asset(
          'assets/icons/whatsapp.svg',
          width: 15,
          height: 15,
          colorFilter: ColorFilter.mode(
            isActive ? onPrimary : hintColor,
            BlendMode.srcIn,
          ),
        ),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: isActive ? primary : Colors.transparent,
          shape: const CircleBorder(),
          side: isActive
              ? null
              : BorderSide(color: borderColor.withValues(alpha: 0.5), width: 1),
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        iconSize: 15,
        tooltip: isActive
            ? 'WhatsApp file attached — tap to change'
            : 'Send file via WhatsApp',
      ),
    );
  }
}
