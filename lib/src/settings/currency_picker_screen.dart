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
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add custom currency',
        onPressed: () => CustomCurrencyEditScreen.show(context),
        child: const Icon(CupertinoIcons.add),
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
  bool _isClosing = false;

  Future<void> _selectCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty || _isClosing) return;
    _isClosing = true;
    HapticFeedback.selectionClick();
    await CurrencySettingsService.instance.setCurrency(normalized);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
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
          valueListenable: CurrencySettingsService.instance.customCurrencies,
          builder: (context, customCurrencies, _) =>
              ValueListenableBuilder<String>(
                valueListenable: CurrencySettingsService.instance.currency,
                builder: (context, selectedCurrency, _) => Column(
                  children: [
                    for (final option in kPresetCurrencyOptions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CurrencyOptionCard(
                          option: option,
                          selected: option.displayText == selectedCurrency,
                          onTap: () => _selectCurrency(option.displayText),
                        ),
                      ),
                    for (final customCurrency in customCurrencies)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CurrencyOptionCard(
                          option: CurrencyOption(
                            displayText: customCurrency,
                            name: 'Custom Display',
                          ),
                          selected: customCurrency == selectedCurrency,
                          onTap: () => _selectCurrency(customCurrency),
                          onEdit: () => CustomCurrencyEditScreen.show(
                            context,
                            currency: customCurrency,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ),
      ],
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
              Icon(
                CupertinoIcons.chevron_forward,
                color: theme.colorScheme.onSurfaceVariant,
                size: 17,
              )
            else
              IconButton(
                tooltip: 'Edit ${option.displayText}',
                onPressed: onEdit,
                icon: const Icon(CupertinoIcons.pencil, size: 19),
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
