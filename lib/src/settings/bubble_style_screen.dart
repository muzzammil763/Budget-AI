import 'package:budget_ai/src/chat/expandable_user_message_text.dart';
import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/custom_bubble_style_edit_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BubbleStyleScreen extends StatelessWidget {
  const BubbleStyleScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const BubbleStyleScreen()));
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

class _BubbleStyleScreenContent extends StatefulWidget {
  const _BubbleStyleScreenContent();

  @override
  State<_BubbleStyleScreenContent> createState() =>
      _BubbleStyleScreenContentState();
}

class _BubbleStyleScreenContentState extends State<_BubbleStyleScreenContent> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _optionKeys = {};
  bool _didScheduleInitialScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _optionKey(String id) => _optionKeys.putIfAbsent(id, GlobalKey.new);

  void _scheduleReveal(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final optionContext = _optionKeys[id]?.currentContext;
      if (optionContext == null) return;
      Scrollable.ensureVisible(
        optionContext,
        alignment: 0.18,
        duration: Duration.zero,
      );
    });
  }

  Future<void> _selectPreset(UserBubbleStyle style) async {
    if (BubbleStyleSettingsService.instance.current == style) return;
    HapticFeedback.selectionClick();
    await BubbleStyleSettingsService.instance.setStyle(style);
  }

  Future<void> _selectCustom(CustomBubbleStyle style) async {
    final service = BubbleStyleSettingsService.instance;
    if (service.current == UserBubbleStyle.custom &&
        service.currentCustomStyle?.id == style.id) {
      return;
    }
    HapticFeedback.selectionClick();
    await service.setCustomStyle(style.id);
  }

  Future<void> _openCustomEditor({CustomBubbleStyle? style}) async {
    final result = await CustomBubbleStyleEditScreen.show(
      context,
      style: style,
    );
    if (!mounted || result == null) return;
    setState(() {});
    if (result case CustomBubbleSaved(:final style)) {
      _scheduleReveal('custom:${style.id}');
      return;
    }
    final service = BubbleStyleSettingsService.instance;
    final selectedId = service.current == UserBubbleStyle.custom
        ? 'custom:${service.currentCustomStyle?.id}'
        : 'preset:${service.current.name}';
    _scheduleReveal(selectedId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = BubbleStyleSettingsService.instance;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const ValueKey('bubble-style-options-scroll'),
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Pick how your messages look in chat.',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ValueListenableBuilder<List<CustomBubbleStyle>>(
                  valueListenable: service.customStyles,
                  builder: (context, customStyles, _) {
                    final choices = [
                      for (final style in UserBubbleStyle.values)
                        if (style != UserBubbleStyle.custom)
                          _BubbleChoice.preset(style),
                      for (final custom in customStyles)
                        _BubbleChoice.custom(custom),
                    ];
                    return ValueListenableBuilder<UserBubbleStyle>(
                      valueListenable: service.style,
                      builder: (context, selected, _) {
                        final selectedId = selected == UserBubbleStyle.custom
                            ? 'custom:${service.currentCustomStyle?.id}'
                            : 'preset:${selected.name}';
                        if (!_didScheduleInitialScroll) {
                          _didScheduleInitialScroll = true;
                          _scheduleReveal(selectedId);
                        }
                        return Column(
                          children: [
                            for (final choice in choices)
                              Padding(
                                key: _optionKey(choice.id),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _BubbleStyleOption(
                                  choice: choice,
                                  selected: choice.id == selectedId,
                                  onTap: choice.customStyle == null
                                      ? () => _selectPreset(choice.style)
                                      : () =>
                                            _selectCustom(choice.customStyle!),
                                  onEdit: choice.customStyle == null
                                      ? null
                                      : () => _openCustomEditor(
                                          style: choice.customStyle,
                                        ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleChoice {
  const _BubbleChoice._({
    required this.id,
    required this.label,
    required this.style,
    this.customStyle,
  });

  factory _BubbleChoice.preset(UserBubbleStyle style) => _BubbleChoice._(
    id: 'preset:${style.name}',
    label: style.label,
    style: style,
  );

  factory _BubbleChoice.custom(CustomBubbleStyle custom) => _BubbleChoice._(
    id: 'custom:${custom.id}',
    label: custom.name,
    style: UserBubbleStyle.custom,
    customStyle: custom,
  );

  final String id;
  final String label;
  final UserBubbleStyle style;
  final CustomBubbleStyle? customStyle;
}

class _BubbleStyleOption extends StatelessWidget {
  const _BubbleStyleOption({
    required this.choice,
    required this.selected,
    required this.onTap,
    this.onEdit,
  });

  final _BubbleChoice choice;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

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
            width: 1.5,
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
                Expanded(
                  child: Text(
                    choice.label,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Edit ${choice.label}',
                    onPressed: onEdit,
                    icon: const Icon(CupertinoIcons.square_pencil, size: 19),
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: UserBubbleStyleSurface(
                style: choice.style,
                customStyle: choice.customStyle,
                child: ExpandableUserMessageText(
                  text:
                      'This is how your message will look, take a look and '
                      'choose your style',
                  style: UserBubbleStyleSurface.messageTextStyle(
                    context,
                    choice.style,
                    customStyle: choice.customStyle,
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
