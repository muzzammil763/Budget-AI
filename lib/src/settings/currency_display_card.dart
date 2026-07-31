import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CurrencyDisplayCard extends StatelessWidget {
  const CurrencyDisplayCard({
    super.key,
    required this.currency,
    this.onTap,
    this.height,
  });

  final String currency;
  final VoidCallback? onTap;
  final double? height;

  CurrencyOption get _selectedOption {
    for (final option in CurrencySettingsService.instance.availableOptions) {
      if (option.displayText == currency) return option;
    }
    return CurrencyOption(displayText: currency, name: 'Custom Display');
  }

  String get _currencyName => _selectedOption.name
      .replaceFirst(' symbol', '')
      .replaceFirst(' code', '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onPrimary;
    final preview = CurrencySettingsService.instance.formatAmount(12500);
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height;
    final cardHeight =
        height ?? math.min(screenHeight * 0.35, screenSize.shortestSide * 0.76);

    return SizedBox(
      width: double.infinity,
      height: cardHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final availableHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : screenHeight * 0.35;
          final responsiveUnit = math.min(
            screenSize.shortestSide,
            availableHeight / 0.76,
          );
          final contentPadding = responsiveUnit * 0.032;
          final majorVerticalGap = responsiveUnit * 0.032;
          final smallVerticalGap = responsiveUnit * 0.012;
          final eyebrowFontSize = responsiveUnit * 0.025;
          final supportingFontSize = responsiveUnit * 0.042;
          final currencyNameFontSize = responsiveUnit * 0.048;
          final footerFontSize = responsiveUnit * 0.036;
          final tokenSize = responsiveUnit * 0.140;
          final steppedTokenSize = (tokenSize * 2).round() / 2;
          final minimumTokenFontSize =
              (steppedTokenSize * 0.58 * 2).floor() / 2;
          final previewFontSize = (responsiveUnit * 0.07 * 2).round() / 2;
          final minimumPreviewFontSize =
              (previewFontSize * 0.72 * 2).floor() / 2;
          final actionSize = responsiveUnit * 0.1;
          final actionIconSize = responsiveUnit * 0.042;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(12),
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
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'CURRENT DISPLAY',
                                      style: AppTheme.bodySmall.copyWith(
                                        color: foreground.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: eyebrowFontSize,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: responsiveUnit * 0.0041,
                                      ),
                                    ),
                                    Text(
                                      'Applied everywhere',
                                      style: AppTheme.bodySmall.copyWith(
                                        color: foreground,
                                        fontSize: supportingFontSize,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(height: majorVerticalGap),
                            AutoSizeText(
                              currency,
                              maxLines: 1,
                              minFontSize: minimumTokenFontSize,
                              maxFontSize: steppedTokenSize,
                              stepGranularity: 0.5,
                              style: AppTheme.headingLarge.copyWith(
                                color: foreground,
                                fontSize: steppedTokenSize,
                                fontWeight: FontWeight.w900,
                                height: 0.95,
                                letterSpacing: responsiveUnit * 0.0019,
                              ),
                            ),
                            SizedBox(height: smallVerticalGap),
                            Text(
                              _currencyName,
                              style: AppTheme.headingSmall.copyWith(
                                color: foreground.withValues(alpha: 0.82),
                                fontSize: currencyNameFontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: smallVerticalGap),
                            Divider(color: foreground.withValues(alpha: 0.15)),
                            SizedBox(height: smallVerticalGap),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'AMOUNT PREVIEW',
                                        style: AppTheme.bodySmall.copyWith(
                                          color: foreground.withValues(
                                            alpha: 0.75,
                                          ),
                                          fontSize: eyebrowFontSize,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing:
                                              responsiveUnit * 0.0033,
                                        ),
                                      ),
                                      SizedBox(height: smallVerticalGap),
                                      AutoSizeText(
                                        preview,
                                        maxLines: 1,
                                        minFontSize: minimumPreviewFontSize,
                                        maxFontSize: previewFontSize,
                                        stepGranularity: 0.5,
                                        style: AppTheme.headingSmall.copyWith(
                                          color: foreground,
                                          fontSize: previewFontSize,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing:
                                              responsiveUnit * 0.0019,
                                          fontFamily: "Boldonse",
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: actionSize,
                                  height: actionSize,
                                  decoration: BoxDecoration(
                                    color: foreground.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.arrow_up_right,
                                    color: foreground,
                                    size: actionIconSize,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Center(
                              child: Text(
                                'Finances  •  Insights  •  AI Responses',
                                style: AppTheme.bodySmall.copyWith(
                                  color: foreground.withValues(alpha: 0.75),
                                  fontSize: footerFontSize,
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
        },
      ),
    );
  }
}
