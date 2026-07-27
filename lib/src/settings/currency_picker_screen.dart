import 'package:budget_ai/src/chat/chat_loading_widgets.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/custom_currency_edit_screen.dart';
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
      body: const _CurrencyScreenContent(),
    );
  }
}

class _CurrencyScreenContent extends StatefulWidget {
  const _CurrencyScreenContent();

  @override
  State<_CurrencyScreenContent> createState() => _CurrencyScreenContentState();
}

class _CurrencyScreenContentState extends State<_CurrencyScreenContent> {
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

  bool _matchesSearch(CurrencyOption option) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return option.displayText.toLowerCase().contains(query) ||
        option.name.toLowerCase().contains(query);
  }

  Future<void> _selectCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    HapticFeedback.selectionClick();
    await CurrencySettingsService.instance.setCurrency(normalized);
  }

  GlobalKey _optionKey(String currency) {
    return _optionKeys.putIfAbsent(currency, GlobalKey.new);
  }

  void _scheduleScrollToCurrency(String currency, {bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final optionContext = _optionKeys[currency]?.currentContext;
      if (optionContext == null) return;
      Scrollable.ensureVisible(
        optionContext,
        alignment: 0.18,
        duration: animated ? const Duration(milliseconds: 420) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openCustomCurrencyEditor({String? currency}) async {
    final saved = await CustomCurrencyEditScreen.show(
      context,
      currency: currency,
    );
    if (!mounted || saved != true) return;
    _searchController.clear();
    setState(() {});
    _scheduleScrollToCurrency(CurrencySettingsService.instance.current);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const ValueKey('currency-options-scroll'),
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 104),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Choose how Budget AI displays amounts in finances, insights, '
                    'tool results and AI responses. Use + to add a custom display.',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ValueListenableBuilder<List<String>>(
                  valueListenable:
                      CurrencySettingsService.instance.customCurrencies,
                  builder: (context, customCurrencies, _) {
                    final options = [
                      ...kPresetCurrencyOptions,
                      ...customCurrencies.map(
                        (currency) => CurrencyOption(
                          displayText: currency,
                          name: 'Custom Display',
                        ),
                      ),
                    ].where(_matchesSearch).toList();

                    return ValueListenableBuilder<String>(
                      valueListenable:
                          CurrencySettingsService.instance.currency,
                      builder: (context, selectedCurrency, _) {
                        if (!_didScheduleInitialScroll && !_isSearching) {
                          _didScheduleInitialScroll = true;
                          _scheduleScrollToCurrency(selectedCurrency);
                        }
                        if (options.isEmpty) {
                          return _buildNoSearchResults(theme);
                        }
                        return Column(
                          children: [
                            for (final option in options)
                              Padding(
                                key: _optionKey(option.displayText),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _CurrencyOptionCard(
                                  option: option,
                                  selected:
                                      option.displayText == selectedCurrency,
                                  onTap: () =>
                                      _selectCurrency(option.displayText),
                                  onEdit:
                                      customCurrencies.contains(
                                        option.displayText,
                                      )
                                      ? () => _openCustomCurrencyEditor(
                                          currency: option.displayText,
                                        )
                                      : null,
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
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildCurrencySearchRow(theme),
        ),
      ],
    );
  }

  Widget _buildNoSearchResults(ThemeData theme) {
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
            'No currencies found',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try another code, symbol, or currency name.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencySearchRow(ThemeData theme) {
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
            Expanded(child: _buildCurrencySearchField(theme)),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Add custom currency',
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
                  key: const ValueKey('add-custom-currency'),
                  customBorder: const CircleBorder(),
                  onTap: _openCustomCurrencyEditor,
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

  Widget _buildCurrencySearchField(ThemeData theme) {
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
                tooltip: 'Search currencies',
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
                  key: const ValueKey('currency-search-field'),
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  cursorColor: theme.colorScheme.primary,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _searchFocusNode.unfocus(),
                  onTapOutside: (_) => _searchFocusNode.unfocus(),
                  decoration: InputDecoration(
                    hoverColor: Colors.transparent,
                    hintText: 'Search currencies',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    fillColor: Colors.transparent,
                  ),
                  maxLines: 1,
                  minLines: 1,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.characters,
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
                      key: const ValueKey('hide-currency-search-keyboard'),
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
                      key: const ValueKey('clear-currency-search'),
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
                      key: ValueKey('empty-currency-search-action'),
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

class _CurrencyOptionCard extends StatelessWidget {
  const _CurrencyOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
    this.onEdit,
  });

  final CurrencyOption option;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: selected
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
                  const SizedBox(height: 2),
                  Text(
                    _displayName,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'PREVIEW',
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
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onEdit == null)
              SizedBox.shrink()
            else
              IconButton(
                tooltip: 'Edit ${option.displayText}',
                onPressed: onEdit,
                icon: const Icon(CupertinoIcons.square_pencil, size: 19),
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
