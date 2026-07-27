import 'package:budget_ai/src/chat/chat_loading_widgets.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _optionKeys = {};
  bool _didScheduleInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  void _handleSearchFocusChanged() {
    if (mounted) setState(() {});
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
    _searchController.clear();
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

  bool _matches(_BubbleChoice choice) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      choice.label,
      if (choice.customStyle != null) ...[
        choice.customStyle!.shape.label,
        choice.customStyle!.pattern.label,
        'custom',
      ],
    ].join(' ').toLowerCase();
    return haystack.contains(query);
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 104),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Pick how your messages look in chat, or use + to create '
                    'a custom bubble with your own colors, shape and pattern.',
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
                    ].where(_matches).toList(growable: false);
                    return ValueListenableBuilder<UserBubbleStyle>(
                      valueListenable: service.style,
                      builder: (context, selected, _) {
                        final selectedId = selected == UserBubbleStyle.custom
                            ? 'custom:${service.currentCustomStyle?.id}'
                            : 'preset:${selected.name}';
                        if (!_didScheduleInitialScroll && !_isSearching) {
                          _didScheduleInitialScroll = true;
                          _scheduleReveal(selectedId);
                        }
                        if (choices.isEmpty) {
                          return _buildNoResults(theme);
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
        Align(alignment: Alignment.bottomCenter, child: _buildSearchRow(theme)),
      ],
    );
  }

  Widget _buildNoResults(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.search,
            size: 42,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(
            'No bubble styles found',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try another style, shape, or pattern name.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow(ThemeData theme) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    const keyboardHeightApprox = 280.0;
    final progress = (bottomInset / keyboardHeightApprox).clamp(0.0, 1.0);
    final horizontalPadding = 32 - (32 - 8) * progress;
    final safeAreaBottom = 32 - (32 - 12) * progress;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: safeAreaBottom),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            Expanded(child: _buildSearchField(theme)),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Add custom bubble',
              child: Material(
                color: theme.colorScheme.primary,
                shape: CircleBorder(
                  side: BorderSide(
                    color: theme.colorScheme.outline.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.2 : 0.06,
                    ),
                  ),
                ),
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                child: InkWell(
                  key: const ValueKey('add-custom-bubble'),
                  customBorder: const CircleBorder(),
                  onTap: _openCustomEditor,
                  child: SizedBox.square(
                    dimension: 56,
                    child: Icon(
                      CupertinoIcons.add,
                      size: 28,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return ChatWorkingComposerFrame(
      isWorking: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.outline.withValues(alpha: 0.2)
                : theme.colorScheme.outline.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: 'Search bubble styles',
                onPressed: _searchFocusNode.requestFocus,
                icon: Icon(
                  CupertinoIcons.search,
                  size: 26,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  key: const ValueKey('bubble-style-search-field'),
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  cursorColor: theme.colorScheme.primary,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _searchFocusNode.unfocus(),
                  onTapOutside: (_) => _searchFocusNode.unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Search bubble styles',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    fillColor: Colors.transparent,
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _searchFocusNode.hasFocus
                  ? SizedBox(
                      key: const ValueKey('hide-bubble-search-keyboard'),
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: 'Hide keyboard',
                        onPressed: _searchFocusNode.unfocus,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : _isSearching
                  ? SizedBox(
                      key: const ValueKey('clear-bubble-search'),
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('empty-bubble-search-action'),
                      width: 44,
                      height: 44,
                    ),
            ),
          ],
        ),
      ),
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
