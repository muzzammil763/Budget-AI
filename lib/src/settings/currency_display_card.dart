import 'package:auto_size_text/auto_size_text.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CurrencyDisplayCard extends StatelessWidget {
  const CurrencyDisplayCard({super.key, required this.currency, this.onTap});

  final String currency;
  final VoidCallback? onTap;

  CurrencyOption get _selectedOption {
    for (final option in CurrencySettingsService.instance.availableOptions) {
      if (option.displayText == currency) return option;
    }
    return CurrencyOption(displayText: currency, name: 'Custom display');
  }

  String get _currencyName => _selectedOption.name
      .replaceFirst(' symbol', '')
      .replaceFirst(' code', '');

  String get _displayType {
    final name = _selectedOption.name.toLowerCase();
    if (name.contains('symbol')) return 'Currency symbol';
    if (name.contains('code') ||
        kPresetCurrencyOptions.any(
          (option) => option.displayText == currency,
        )) {
      return 'Currency code';
    }
    return 'Custom display';
  }

  String get _placement {
    const prefixSymbols = {r'$', '€', '£', '₹', '¥'};
    return prefixSymbols.contains(currency)
        ? 'Prefix display'
        : 'Suffix display';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onPrimary;
    final preview = CurrencySettingsService.instance.formatAmount(12500);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final cardHeight = (screenHeight * 0.35).clamp(270.0, 310.0);
    final contentPadding = (screenHeight * 0.016).clamp(12.0, 15.0);
    final tokenSize = (screenHeight * 0.05).clamp(36.0, 44.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Ink(
          width: double.infinity,
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                Color.lerp(
                  theme.colorScheme.primary,
                  theme.colorScheme.onSurfaceVariant,
                  0.2,
                )!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.3 : 0.16,
                ),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Stack(
              children: [
                Positioned(
                  right: -54,
                  top: -68,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 28,
                        color: foreground.withValues(alpha: 0.055),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -70,
                  bottom: -96,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: foreground.withValues(alpha: 0.035),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(contentPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: foreground.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.globe,
                              color: foreground,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CURRENT DISPLAY',
                                style: AppTheme.bodySmall.copyWith(
                                  color: foreground.withValues(alpha: 0.8),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              Text(
                                'Applied everywhere',
                                style: AppTheme.bodySmall.copyWith(
                                  color: foreground,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: foreground.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.check_mark,
                              color: foreground,
                              size: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AutoSizeText(
                        currency,
                        maxLines: 1,
                        minFontSize: 24,
                        maxFontSize: tokenSize,
                        stepGranularity: 0.5,
                        style: AppTheme.headingLarge.copyWith(
                          color: foreground,
                          fontSize: tokenSize,
                          fontWeight: FontWeight.w900,
                          height: 0.95,
                          letterSpacing: 0.75,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currencyName,
                        style: AppTheme.headingSmall.copyWith(
                          color: foreground.withValues(alpha: 0.82),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _CurrencyCardBadge(
                            label: _displayType,
                            foreground: foreground,
                          ),
                          _CurrencyCardBadge(
                            label: _placement,
                            foreground: foreground,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Divider(color: foreground.withValues(alpha: 0.25)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AMOUNT PREVIEW',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: foreground.withValues(alpha: 0.75),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                AutoSizeText(
                                  preview,
                                  maxLines: 1,
                                  minFontSize: 16,
                                  maxFontSize: 22,
                                  style: AppTheme.headingSmall.copyWith(
                                    color: foreground,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.75,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: foreground.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.arrow_up_right,
                              color: foreground,
                              size: 15,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Center(
                        child: Text(
                          'Finances  •  Insights  •  AI responses',
                          style: AppTheme.bodySmall.copyWith(
                            color: foreground.withValues(alpha: 0.75),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrencyCardBadge extends StatelessWidget {
  const _CurrencyCardBadge({required this.label, required this.foreground});

  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: foreground.withValues(alpha: 0.1)),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: foreground.withValues(alpha: 0.8),
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
