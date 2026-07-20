import 'dart:async';

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CurrencyPickerScreen extends StatelessWidget {
  const CurrencyPickerScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CurrencyPickerScreen()),
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
        title: const Text('Choose Currency Display'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const _CurrencyScreenContent(),
          ),
        ),
      ),
    );
  }
}

class _CurrencyScreenContent extends StatefulWidget {
  const _CurrencyScreenContent();

  @override
  State<_CurrencyScreenContent> createState() => _CurrencyScreenContentState();
}

class _CurrencyScreenContentState extends State<_CurrencyScreenContent> {
  final TextEditingController _customController = TextEditingController();
  final FocusNode _customFocusNode = FocusNode();
  final GlobalKey _keyboardKey = GlobalKey();
  bool _keyboardVisible = false;
  bool _isClosing = false;
  int _keyboardTransition = 0;

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  void _toggleKeyboard() {
    final transition = ++_keyboardTransition;
    if (_keyboardVisible) {
      _customFocusNode.unfocus();
      setState(() => _keyboardVisible = false);
      return;
    }
    setState(() => _keyboardVisible = true);
    _customFocusNode.requestFocus();
    _scrollKeyboardIntoView(transition);
  }

  void _scrollKeyboardIntoView(int transition) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureKeyboardVisible(transition, const Duration(milliseconds: 180));
    });

    // AnimatedSize initially reports a near-zero keyboard height. Scroll once
    // more after expansion so the actual keys, not only the field, are shown.
    Future<void>.delayed(const Duration(milliseconds: 330), () {
      _ensureKeyboardVisible(transition, const Duration(milliseconds: 320));
    });
  }

  void _ensureKeyboardVisible(int transition, Duration duration) {
    if (!mounted || !_keyboardVisible || transition != _keyboardTransition) {
      return;
    }
    final keyboardContext = _keyboardKey.currentContext;
    if (keyboardContext == null) return;
    Scrollable.ensureVisible(
      keyboardContext,
      alignment: 1,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  void _enterCustomCharacter(String value) {
    final current = _customController.text;
    if (current.length + value.length > 8) return;
    final updated = '$current$value';
    _customController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    setState(() {});
  }

  void _enterCustomSpace() {
    final current = _customController.text;
    if (current.isEmpty || current.endsWith(' ') || current.length >= 8) return;
    _enterCustomCharacter(' ');
  }

  void _backspaceCustom() {
    final current = _customController.text;
    if (current.isEmpty) return;
    final updated = current.substring(0, current.length - 1);
    _customController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    setState(() {});
  }

  Future<void> _selectCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty || _isClosing) return;
    _isClosing = true;
    HapticFeedback.selectionClick();
    await CurrencySettingsService.instance.setCurrency(normalized);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submitCustom(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty || _isClosing) return;
    _isClosing = true;
    HapticFeedback.selectionClick();
    _customFocusNode.unfocus();
    _keyboardTransition++;
    setState(() => _keyboardVisible = false);
    await CurrencySettingsService.instance.setCurrency(normalized);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customValue = _customController.text.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text(
            'Choose how Budget AI displays amounts in finances, insights, '
            'tool results and AI responses.',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ValueListenableBuilder<List<String>>(
          valueListenable: CurrencySettingsService.instance.customCurrencies,
          builder: (context, customCurrencies, _) =>
              ValueListenableBuilder<String>(
                valueListenable: CurrencySettingsService.instance.currency,
                builder: (context, selectedCurrency, _) => Column(
                  children: [
                    for (final option
                        in CurrencySettingsService.instance.availableOptions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CurrencyOptionCard(
                          option: option,
                          selected: option.displayText == selectedCurrency,
                          onTap: () => _selectCurrency(option.displayText),
                        ),
                      ),
                  ],
                ),
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add a Custom Display',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.textformat,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: TextField(
                  controller: _customController,
                  focusNode: _customFocusNode,
                  readOnly: true,
                  showCursor: _keyboardVisible,
                  enableInteractiveSelection: false,
                  onTap: _toggleKeyboard,
                  cursorColor: theme.colorScheme.primary,
                  maxLength: 8,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'e.g. CHF, kr, ¥',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.68,
                      ),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    fillColor: Colors.transparent,
                  ),
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: customValue.isEmpty
                    ? null
                    : () => _submitCustom(customValue),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: customValue.isEmpty
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.12)
                        : theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    CupertinoIcons.arrow_up_right,
                    color: customValue.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimary,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: customValue.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _CurrencyOptionCard(
                    option: CurrencyOption(
                      displayText: customValue,
                      name: 'Custom Display',
                    ),
                    selected: false,
                    preview: true,
                    onTap: () => _submitCustom(customValue),
                  ),
                ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: _keyboardVisible
              ? Padding(
                  key: _keyboardKey,
                  padding: const EdgeInsets.only(top: 10),
                  child: _InlineCurrencyKeyboard(
                    onCharacter: _enterCustomCharacter,
                    onSpace: _enterCustomSpace,
                    onBackspace: _backspaceCustom,
                    onDone: () => _submitCustom(_customController.text),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        SizedBox(height: 8),
      ],
    );
  }
}

class _CurrencyOptionCard extends StatelessWidget {
  const _CurrencyOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
    this.preview = false,
  });

  final CurrencyOption option;
  final bool selected;
  final bool preview;
  final VoidCallback onTap;

  String get _displayName => option.name
      .replaceFirst(' symbol', ' Symbol')
      .replaceFirst(' code', ' Code');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountPreview = CurrencySettingsService.instance.formatAmount(
      100,
      currency: option.displayText,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.32),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : preview
                    ? CupertinoIcons.eye
                    : CupertinoIcons.circle,
                color: selected || preview
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.displayText,
                    style: AppTheme.bodyLarge.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _displayName,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        preview ? 'LIVE PREVIEW' : 'PREVIEW',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        amountPreview,
                        style: AppTheme.bodyMedium.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: theme.colorScheme.onSurfaceVariant,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineCurrencyKeyboard extends StatefulWidget {
  const _InlineCurrencyKeyboard({
    required this.onCharacter,
    required this.onSpace,
    required this.onBackspace,
    required this.onDone,
  });

  final ValueChanged<String> onCharacter;
  final VoidCallback onSpace;
  final VoidCallback onBackspace;
  final VoidCallback onDone;

  @override
  State<_InlineCurrencyKeyboard> createState() =>
      _InlineCurrencyKeyboardState();
}

class _InlineCurrencyKeyboardState extends State<_InlineCurrencyKeyboard> {
  static const _letterRows = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];
  static const _symbolRows = <List<String>>[
    [r'$', '€', '£', '¥', '₩', '₱'],
    ['₿', '₦', '₫', '฿', '₴', '₵', '₭', '元'],
    ['¢', '¤', 'ƒ', '₪', 'kr'],
  ];

  bool _showSymbols = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final keyGap = screenSize.width * 0.009;
    final rows = _showSymbols ? _symbolRows : _letterRows;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, progress, keyboard) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, (1 - progress) * 10),
          child: keyboard,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(screenSize.shortestSide * 0.026),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(screenSize.shortestSide * 0.046),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: screenSize.shortestSide * 0.046,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [...previousChildren, ?currentChild],
          ),
          child: Column(
            key: ValueKey(_showSymbols),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (
                      var index = 0;
                      index < rows[rowIndex].length;
                      index++
                    ) ...[
                      if (index > 0) SizedBox(width: keyGap),
                      Expanded(
                        child: _CurrencyKeyboardKey(
                          label: rows[rowIndex][index],
                          onTap: () =>
                              widget.onCharacter(rows[rowIndex][index]),
                        ),
                      ),
                    ],
                    if (rowIndex == rows.length - 1) ...[
                      SizedBox(width: keyGap),
                      Expanded(
                        child: _CurrencyKeyboardKey(
                          icon: CupertinoIcons.delete_left,
                          repeatOnLongPress: true,
                          onTap: widget.onBackspace,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: keyGap),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _CurrencyKeyboardKey(
                      label: _showSymbols ? 'ABC' : r'#+=',
                      onTap: () => setState(() => _showSymbols = !_showSymbols),
                    ),
                  ),
                  SizedBox(width: keyGap),
                  Expanded(
                    flex: 6,
                    child: _CurrencyKeyboardKey(
                      label: 'SPACE',
                      onTap: widget.onSpace,
                    ),
                  ),
                  SizedBox(width: keyGap),
                  Expanded(
                    flex: 2,
                    child: _CurrencyKeyboardKey(
                      icon: CupertinoIcons.check_mark,
                      emphasized: true,
                      onTap: widget.onDone,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyKeyboardKey extends StatefulWidget {
  const _CurrencyKeyboardKey({
    this.label,
    this.icon,
    this.emphasized = false,
    this.repeatOnLongPress = false,
    required this.onTap,
  }) : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final bool emphasized;
  final bool repeatOnLongPress;
  final VoidCallback onTap;

  @override
  State<_CurrencyKeyboardKey> createState() => _CurrencyKeyboardKeyState();
}

class _CurrencyKeyboardKeyState extends State<_CurrencyKeyboardKey> {
  bool _isPressed = false;
  bool _isRepeating = false;
  Timer? _repeatTimer;

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _startRepeating() {
    if (!widget.repeatOnLongPress || _isRepeating) return;
    _isRepeating = true;
    HapticFeedback.selectionClick();
    widget.onTap();
    _repeatTimer = Timer.periodic(
      const Duration(milliseconds: 70),
      (_) => widget.onTap(),
    );
  }

  void _stopRepeating() {
    if (!_isRepeating) return;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _isRepeating = false;
    if (mounted) setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final keyHeight = screenSize.shortestSide * 0.1;
    final foreground = widget.emphasized
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    Widget keyContent(Color color, {bool preview = false}) {
      if (widget.icon != null) {
        return Icon(
          widget.icon,
          color: color,
          size: screenSize.shortestSide * (preview ? 0.052 : 0.041),
        );
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          widget.label!,
          style: TextStyle(
            color: color,
            fontFamily: 'Boldonse',
            letterSpacing: 1,
            fontSize: screenSize.shortestSide * (preview ? 0.034 : 0.026),
            height: 1,
          ),
        ),
      );
    }

    return SizedBox(
      height: keyHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -2,
            right: -2,
            bottom: keyHeight + 4,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _isPressed ? 1 : 0,
                duration: const Duration(milliseconds: 80),
                child: AnimatedScale(
                  scale: _isPressed ? 1 : 0.72,
                  duration: const Duration(milliseconds: 120),
                  curve: _isPressed ? Curves.easeOutBack : Curves.easeInCubic,
                  child: Container(
                    height: keyHeight * 1.08,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: keyContent(
                        theme.colorScheme.onPrimary,
                        preview: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              onPointerUp: (_) => _stopRepeating(),
              onPointerCancel: (_) => _stopRepeating(),
              child: AnimatedScale(
                scale: _isPressed ? 0.86 : 1,
                duration: Duration(milliseconds: _isPressed ? 65 : 190),
                curve: _isPressed ? Curves.easeOutCubic : Curves.easeOutBack,
                child: Material(
                  color: widget.emphasized
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTapDown: (_) => setState(() => _isPressed = true),
                    onTapUp: (_) => setState(() => _isPressed = false),
                    onTapCancel: () => setState(() => _isPressed = false),
                    onLongPress: widget.repeatOnLongPress
                        ? _startRepeating
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTap();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Center(child: keyContent(foreground)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
