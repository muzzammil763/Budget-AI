import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/settings/currency_display_card.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CurrencyPickerSheet {
  const CurrencyPickerSheet._();

  static Future<String?> show(BuildContext context) {
    final theme = Theme.of(context);
    return ResponsiveInfoSheet.show<String>(
      context,
      title: 'Choose currency display',
      headerIcon: Icon(
        CupertinoIcons.money_dollar_circle,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: const [_CurrencySheetContent()],
    );
  }
}

class _CurrencySheetContent extends StatefulWidget {
  const _CurrencySheetContent();

  @override
  State<_CurrencySheetContent> createState() => _CurrencySheetContentState();
}

class _CurrencySheetContentState extends State<_CurrencySheetContent> {
  final TextEditingController _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _submitCustom(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.pop(context, normalized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose how Budget AI displays amounts in finances, insights, tool results and AI responses.',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<List<String>>(
          valueListenable: CurrencySettingsService.instance.customCurrencies,
          builder: (context, customCurrencies, _) =>
              ValueListenableBuilder<String>(
                valueListenable: CurrencySettingsService.instance.currency,
                builder: (context, selectedCurrency, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CurrencyDisplayCard(currency: selectedCurrency),
                      const SizedBox(height: 18),
                      Text(
                        'AVAILABLE DISPLAYS',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option
                              in CurrencySettingsService
                                  .instance
                                  .availableOptions)
                            _CurrencyOptionChip(
                              option: option,
                              selected: option.displayText == selectedCurrency,
                              onTap: () =>
                                  Navigator.pop(context, option.displayText),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
        ),
        const SizedBox(height: 16),
        Text(
          'Add a custom display',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.fromLTRB(14, 7, 7, 7),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
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
                  cursorColor: theme.colorScheme.primary,
                  maxLength: 8,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submitCustom,
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
                onTap: () => _submitCustom(_customController.text),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    CupertinoIcons.arrow_up_right,
                    color: theme.colorScheme.onPrimary,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurrencyOptionChip extends StatelessWidget {
  const _CurrencyOptionChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CurrencyOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              option.displayText,
              style: AppTheme.bodyMedium.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              option.name,
              style: AppTheme.bodySmall.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.76)
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
