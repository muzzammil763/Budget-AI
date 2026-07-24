import 'package:budget_ai/src/chat/expandable_user_message_text.dart';
import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BubbleStyleScreen extends StatelessWidget {
  const BubbleStyleScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const BubbleStyleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Message Bubble Style'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const _BubbleStyleScreenContent(),
          ),
        ),
      ),
    );
  }
}

class _BubbleStyleScreenContent extends StatelessWidget {
  const _BubbleStyleScreenContent();

  Future<void> _select(UserBubbleStyle style) async {
    if (BubbleStyleSettingsService.instance.current == style) return;
    HapticFeedback.selectionClick();
    await BubbleStyleSettingsService.instance.setStyle(style);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<UserBubbleStyle>(
      valueListenable: BubbleStyleSettingsService.instance.style,
      builder: (context, selected, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Pick how your messages look in chat. Tap a style to apply it '
              'right away — the preview shows exactly how it will appear.',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final style in UserBubbleStyle.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BubbleStyleOption(
                style: style,
                selected: selected == style,
                onTap: () => _select(style),
              ),
            ),
        ],
      ),
    );
  }
}

class _BubbleStyleOption extends StatelessWidget {
  const _BubbleStyleOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final UserBubbleStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  size: 30,
                ),
                const SizedBox(width: 8),
                Text(
                  style.label,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: UserBubbleStyleSurface(
                style: style,
                child: ExpandableUserMessageText(
                  text:
                      'This is how your message will look, take a look and choose your style',
                  style: UserBubbleStyleSurface.messageTextStyle(
                    context,
                    style,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
