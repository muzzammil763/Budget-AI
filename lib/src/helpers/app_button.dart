import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

enum AppButtonVariant { filled, outlined }

/// The app's single reusable action button, in two variants: [filled]
/// (solid primary background, onPrimary content) and [outlined] (1px
/// primary-colored border, transparent/surface background, primary
/// content). Pass [isRed] to recolor either variant for a destructive
/// action (sign out, delete, exit) instead of the caller building its own
/// colors. Content is always centered — [text] and [icon] are each
/// optional but at least one is required.
///
/// [isLoading] swaps the content for a spinner sized to fit in the same
/// space, without changing the button's height.
///
/// When [onPressed] is null the button is disabled. Two flavours:
///  - with a [disabledMessage] it still looks like a normal, full-strength
///    button and tapping it shows that message as a toast (used on forms so
///    the button explains what's missing instead of silently doing nothing);
///  - without one it renders dimmed and ignores taps (a plain disabled look).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    this.text,
    this.icon,
    required this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.isLoading = false,
    this.isRed = false,
    this.height = 48,
    this.fontSize = 15,
    this.iconSize = 18,
    this.spinnerSize = 20,
    this.borderAlpha = 0.7,
    this.disabledMessage,
  }) : assert(text != null || icon != null, 'Provide text and/or icon.'),
       assert(
         borderAlpha >= 0.1 && borderAlpha <= 1.0,
         'borderAlpha must be between 0.1 and 1.0.',
       );

  final String? text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final bool isRed;
  final double height;
  final double fontSize;
  final double iconSize;
  final double spinnerSize;

  /// Opacity of the outlined variant's border, 0.1–1.0 (default 0.7).
  /// Ignored by the filled variant.
  final double borderAlpha;

  /// Shown as a toast when a disabled ([onPressed] null) button is tapped.
  /// Providing it also keeps the button at full strength rather than dimmed.
  final String? disabledMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFilled = variant == AppButtonVariant.filled;
    final baseColor = isRed
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final onBaseColor = isRed
        ? theme.colorScheme.onError
        : theme.colorScheme.onPrimary;
    final foreground = isFilled ? onBaseColor : baseColor;

    final disabled = onPressed == null && !isLoading;
    // A disabled button with a hint stays at full strength and, on tap,
    // shows that hint instead of doing nothing; only a hint-less disabled
    // button gets the dimmed look.
    final softDisabled = disabled && disabledMessage != null;
    final opacity = (disabled && !softDisabled) ? 0.45 : 1.0;
    final content = foreground.withValues(alpha: opacity);

    VoidCallback? onTap;
    if (isLoading) {
      onTap = null;
    } else if (onPressed != null) {
      onTap = onPressed;
    } else if (softDisabled) {
      onTap = () => showAppToast(
        context,
        message: disabledMessage!,
        type: ToastificationType.info,
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      height: height,
      decoration: BoxDecoration(
        color: isFilled
            ? baseColor.withValues(alpha: opacity)
            : theme.colorScheme.surface,
        border: isFilled
            ? null
            : Border.all(
                color: baseColor.withValues(alpha: borderAlpha * opacity),
              ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: spinnerSize,
                    height: spinnerSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: content,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (text != null)
                        Text(
                          text!,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                            color: content,
                          ),
                        ),
                      if (icon != null && text != null)
                        const SizedBox(width: 8),
                      if (icon != null)
                        Icon(icon, size: iconSize, color: content),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
