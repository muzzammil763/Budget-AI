import 'dart:ui';

import 'package:flutter/material.dart';
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
              topRight: Radius.circular(32),
              topLeft: Radius.circular(32),
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
                              topLeft: Radius.circular(32),
                              topRight: Radius.circular(32),
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
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 0,
                    side: BorderSide(color: theme.colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    cancelLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
