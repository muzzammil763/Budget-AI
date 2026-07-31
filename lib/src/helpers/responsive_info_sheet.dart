import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';

class ResponsiveInfoSheet extends StatelessWidget {
  final String title;
  final Widget headerIcon;
  final List<Color> gradientColors;
  final List<Widget> contentWidgets;
  final bool showCloseButton;

  const ResponsiveInfoSheet({
    super.key,
    required this.title,
    required this.headerIcon,
    required this.gradientColors,
    required this.contentWidgets,
    this.showCloseButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerForeground = AppTheme.readableOn(gradientColors.first);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              topLeft: Radius.circular(12),
            ),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.18),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenHeight = MediaQuery.of(context).size.height;
              final visibleHeight = screenHeight - bottomInset;
              final maxHeight = visibleHeight * 0.82;

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradientColors,
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.05,
                                width:
                                    MediaQuery.of(context).size.height * 0.05,
                                child: Center(child: headerIcon),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize:
                                          MediaQuery.of(context).size.height *
                                          0.022,
                                      color: headerForeground,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (showCloseButton)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.close, color: headerForeground),
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                              style: IconButton.styleFrom(
                                backgroundColor: headerForeground.withValues(
                                  alpha: 0.1,
                                ),
                                shape: const CircleBorder(),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: 12,
                            left: 8,
                            right: 8,
                            bottom: 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: contentWidgets,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget headerIcon,
    required List<Color> gradientColors,
    required List<Widget> contentWidgets,
    bool isDismissible = true,
    bool enableDrag = true,
    bool showCloseButton = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: (context) => ResponsiveInfoSheet(
        title: title,
        headerIcon: headerIcon,
        gradientColors: gradientColors,
        contentWidgets: contentWidgets,
        showCloseButton: showCloseButton,
      ),
    );
  }

  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool isDismissible = true,
    bool enableDrag = true,
    bool showCloseButton = true,
    bool isRed = false,
    Future<void> Function()? onConfirm,
  }) {
    final theme = Theme.of(context);
    return show<bool>(
      context,
      title: title,
      headerIcon: Icon(
        icon,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showCloseButton: showCloseButton,
      contentWidgets: [
        Text(
          message,
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _ConfirmButtonsRow(
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          isRed: isRed,
          onConfirm: onConfirm,
        ),
      ],
    );
  }
}

/// The Cancel/Confirm row used by [ResponsiveInfoSheet.confirm]. Kept
/// stateful so that when [onConfirm] is provided, the confirm button can
/// show its own loading spinner while that action runs — the sheet stays
/// open until it finishes instead of closing immediately and leaving the
/// caller to show progress somewhere else.
class _ConfirmButtonsRow extends StatefulWidget {
  const _ConfirmButtonsRow({
    required this.cancelLabel,
    required this.confirmLabel,
    required this.isRed,
    required this.onConfirm,
  });

  final String cancelLabel;
  final String confirmLabel;
  final bool isRed;
  final Future<void> Function()? onConfirm;

  @override
  State<_ConfirmButtonsRow> createState() => _ConfirmButtonsRowState();
}

class _ConfirmButtonsRowState extends State<_ConfirmButtonsRow> {
  bool _working = false;

  Future<void> _handleConfirm() async {
    final onConfirm = widget.onConfirm;
    if (onConfirm == null) {
      Navigator.pop(context, true);
      return;
    }
    if (_working) return;
    setState(() => _working = true);
    try {
      await onConfirm();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      // The caller's onConfirm is responsible for surfacing its own error
      // (e.g. a toast) — this just leaves the sheet open so they can retry.
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // While the confirmed action is running, block the system back button
      // so the sheet can't be dismissed and the in-flight work interrupted.
      canPop: !_working,
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: AppButton(
              text: widget.cancelLabel,
              variant: AppButtonVariant.outlined,
              fontSize: 15,
              onPressed: _working ? null : () => Navigator.pop(context, false),
            ),
          ),
          Expanded(
            child: AppButton(
              text: widget.confirmLabel,
              isRed: widget.isRed,
              isLoading: _working,
              fontSize: 15,
              onPressed: _handleConfirm,
            ),
          ),
        ],
      ),
    );
  }
}
