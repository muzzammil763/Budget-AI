import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_settings/app_settings.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:budget_ai/src/auth/auth_gate.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/chat/chat_activity_sections.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/onboarding/onboarding_app_showcase.dart';
import 'package:budget_ai/src/settings/currency_display_card.dart';
import 'package:budget_ai/src/settings/currency_picker_screen.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const _onboardingCompletedKey = 'onboarding_completed';
const _onboardingCompletedAtKey = 'onboarding_completed_at';
const _pageStateAnimationDuration = Duration(milliseconds: 280);
const _pageStateAnimationCurve = Curves.easeOutCubic;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _pageCount = 5;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _animateChatPreview = false;
  bool _isFinishing = false;

  bool? _notificationGranted;
  bool? _backgroundBatteryGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Recheck permissions when app comes back from settings
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final notificationStatus = await Permission.notification.status;

    bool? backgroundBatteryGranted;
    if (Platform.isAndroid) {
      backgroundBatteryGranted =
          await AndroidBackgroundChatService.isBatteryOptimizationIgnored();
    }

    if (mounted) {
      setState(() {
        _notificationGranted = notificationStatus.isGranted;
        _backgroundBatteryGranted = backgroundBatteryGranted;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final granted = Platform.isIOS
        ? await NotificationService.instance.requestPermission()
        : (await Permission.notification.request()).isGranted;
    final status = await Permission.notification.status;
    final isGranted = granted || status.isGranted;
    if (mounted) {
      setState(() => _notificationGranted = isGranted);
      if (!isGranted) {
        _showPermissionDeniedDialog('Notifications');
      }
    }
  }

  Future<void> _requestBackgroundBatteryPermission() async {
    if (!(_notificationGranted ?? false)) {
      await _requestNotificationPermission();
    }
    await AndroidBackgroundChatService.requestBatteryOptimizationExemption();
    final granted =
        await AndroidBackgroundChatService.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() => _backgroundBatteryGranted = granted);
    }
  }

  Future<void> _showPermissionDeniedDialog(String permissionName) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: '$permissionName Permission Required',
      message:
          'You have denied $permissionName permission. Please open settings to enable it.',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      confirmLabel: 'Open Settings',
    );
    if (confirmed == true) {
      await AppSettings.openAppSettings();
    }
  }

  bool get _isLastPage => _currentPage == _pageCount - 1;

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  void _next() {
    if (_isLastPage) {
      _finish();
    } else {
      _goToPage(_currentPage + 1);
    }
  }

  bool _handlePageScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification || !_pageController.hasClients) {
      return false;
    }

    final settledPage = (_pageController.page ?? _currentPage.toDouble())
        .round();
    final shouldAnimate = settledPage == 3;
    if (_animateChatPreview != shouldAnimate) {
      setState(() => _animateChatPreview = shouldAnimate);
    }
    return false;
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    try {
      await LocalSettingsStore.instance.setBool(_onboardingCompletedKey, true);
      await LocalSettingsStore.instance.setString(
        _onboardingCompletedAtKey,
        DateTime.now().toIso8601String(),
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      await Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthGate()));
    } finally {
      if (mounted) {
        setState(() => _isFinishing = false);
      }
    }
  }

  double _introStagger(double t, double start, double end) {
    return Curves.easeOutCubic.transform(
      ((t - start) / (end - start)).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = (screenHeight * 0.15).clamp(92.0, 132.0);
    final heroGap = (screenHeight * 0.035).clamp(12.0, 30.0);

    return Scaffold(
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1100),
          child: NotificationListener<ScrollNotification>(
            onNotification: _handlePageScrollNotification,
            child: PageView(
              controller: _pageController,
              physics: const ClampingScrollPhysics(),
              onPageChanged: (page) {
                HapticFeedback.selectionClick();
                setState(() {
                  _currentPage = page;
                  if (page == 3) _animateChatPreview = true;
                });
              },
              children: [
                _buildWelcomePage(theme),
                _buildCurrencyPage(theme),
                _buildTrackPage(theme),
                _buildChatPage(theme),
                _buildPermissionsPage(theme),
              ],
            ),
          ),
          builder: (context, t, pageView) {
            final headerT = _introStagger(t, 0.35, 0.75);
            final heroT = _introStagger(t, 0.0, 0.55);
            final footerT = _introStagger(t, 0.45, 0.9);
            return Column(
              children: [
                Opacity(
                  opacity: headerT,
                  child: Transform.translate(
                    offset: Offset(0, (1 - headerT) * -8),
                    child: _buildHeader(theme),
                  ),
                ),
                SizedBox(height: heroGap),
                Opacity(
                  opacity: heroT,
                  child: _buildHeroArea(theme, introT: t, height: heroHeight),
                ),
                Expanded(child: pageView!),
                Opacity(
                  opacity: footerT,
                  child: Transform.translate(
                    offset: Offset(0, (1 - footerT) * 16),
                    child: _buildFooter(theme),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// A shared hero slot above the PageView. The page marks live here in
  /// one Stack and morph into each other, driven by the live scroll position,
  /// so the icon feels like a single element travelling across pages.
  Widget _buildHeroArea(
    ThemeData theme, {
    required double introT,
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: _pageController,
        builder: (context, _) {
          final page =
              _pageController.hasClients &&
                  _pageController.position.haveDimensions
              ? (_pageController.page ?? _currentPage.toDouble())
              : _currentPage.toDouble();
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < _pageCount; i++)
                if ((i - page).abs() < 1)
                  _buildConnectedHero(
                    theme,
                    index: i,
                    shift: i - page,
                    introT: introT,
                    areaHeight: height,
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectedHero(
    ThemeData theme, {
    required int index,
    required double shift,
    required double introT,
    required double areaHeight,
  }) {
    final presence = (1 - shift.abs()).clamp(0.0, 1.0);
    // Position/scale settle smoothly while opacity ramps in late, so the
    // incoming mark reveals faintly from afar and solidifies as it arrives.
    final settle = Curves.easeOutCubic.transform(presence);
    final fade = Curves.easeInQuad.transform(presence);
    return Opacity(
      opacity: fade,
      child: Transform.translate(
        offset: Offset(shift * 118, shift.abs() * areaHeight * 0.35),
        child: Transform.rotate(
          angle: shift * 0.85,
          child: Transform.scale(
            scale: 0.60 + 0.45 * settle,
            child: index == 0
                ? CustomPaint(
                    size: Size.square((areaHeight * 0.99).clamp(86.0, 122.0)),
                    painter: BudgetMarkPainter(
                      progress: introT,
                      primary: theme.colorScheme.primary,
                      surface: theme.scaffoldBackgroundColor,
                      accent: AppTheme.highlight,
                      isDark: theme.brightness == Brightness.dark,
                    ),
                  )
                : index == 1
                ? _HeroCurrencyToken(
                    currency: CurrencySettingsService.instance.current,
                    progress: introT,
                    theme: theme,
                    size: (areaHeight * 0.99).clamp(80.0, 108.0),
                  )
                : _HeroIcon(
                    icon: _heroIcons[index]!,
                    progress: introT,
                    theme: theme,
                    size: (areaHeight * 0.99).clamp(80.0, 108.0),
                  ),
          ),
        ),
      ),
    );
  }

  static const _heroIcons = <IconData?>[
    null, // Welcome uses the custom-painted brand mark.
    null, // Currency uses the currently selected display token.
    CupertinoIcons.chart_pie,
    CupertinoIcons.chat_bubble,
    CupertinoIcons.checkmark_shield,
  ];

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        const Spacer(),
        AnimatedOpacity(
          opacity: _isLastPage ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: TextButton(
            onPressed: _isLastPage ? null : () => _goToPage(_pageCount - 1),
            child: Text("Skip"),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderChromeButton(
    ThemeData theme, {
    required double width,
    double height = 48,
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget child,
    double borderRadius = 32,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
              : theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Tooltip(
            message: tooltip,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final screenSize = MediaQuery.sizeOf(context);
    final controlSize = screenSize.shortestSide * 0.123;
    final horizontalPadding = screenSize.width * 0.031;
    final verticalPadding = screenSize.height * 0.014;
    final indicatorHeight = screenSize.shortestSide * 0.015;
    final indicatorGap = screenSize.width * 0.008;
    final collapsedIndicatorWidth = screenSize.width * 0.015;
    final activeIndicatorWidth = screenSize.width * 0.062;
    final backSlotGap = screenSize.width * 0.021;
    final backButtonWidth = (screenSize.width * 0.24).clamp(88.0, 108.0);

    return Padding(
      padding: EdgeInsets.only(
        top: horizontalPadding / 2,
        left: horizontalPadding,
        right: horizontalPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _pageCount; i++)
                AnimatedContainer(
                  duration: _pageStateAnimationDuration,
                  curve: _pageStateAnimationCurve,
                  margin: EdgeInsets.symmetric(horizontal: indicatorGap),
                  width: i == _currentPage
                      ? activeIndicatorWidth
                      : collapsedIndicatorWidth,
                  height: indicatorHeight,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(indicatorHeight),
                  ),
                ),
            ],
          ),
          SizedBox(height: verticalPadding),
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: _currentPage > 0 ? 1 : 0),
                duration: _pageStateAnimationDuration,
                curve: _pageStateAnimationCurve,
                builder: (context, progress, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Opacity(
                        opacity: progress,
                        child: Transform.scale(
                          scale: 0.88 + (0.12 * progress),
                          alignment: Alignment.centerLeft,
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: IgnorePointer(
                  ignoring: _currentPage == 0,
                  child: SizedBox(
                    width: backButtonWidth + backSlotGap,
                    child: Row(
                      children: [
                        SizedBox(
                          width: backButtonWidth,
                          height: controlSize,
                          child: _buildHeaderChromeButton(
                            theme,
                            width: backButtonWidth,
                            height: controlSize,
                            borderRadius: 12,
                            tooltip: 'Previous page',
                            onPressed: _currentPage == 0
                                ? null
                                : () => _goToPage(_currentPage - 1),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.back,
                                  color: theme.colorScheme.onSurface,
                                  size: screenSize.shortestSide * 0.045,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Back',
                                  style: AppTheme.bodyLarge.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: screenSize.shortestSide * 0.037,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: backSlotGap),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: controlSize,
                  child: ElevatedButton(
                    onPressed: _isFinishing ? null : _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isFinishing
                        ? SizedBox(
                            width: screenSize.shortestSide * 0.051,
                            height: screenSize.shortestSide * 0.051,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentPage == 0
                                    ? 'Get Started'
                                    : _isLastPage
                                    ? 'Done'
                                    : 'Next',
                                style: AppTheme.bodyLarge.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: screenSize.shortestSide * 0.041,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_currentPage > 0 && !_isLastPage) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  CupertinoIcons.forward,
                                  size: screenSize.shortestSide * 0.043,
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'WELCOME TO',
      title: 'Budget AI',
      emphasizeTitle: _currentPage == 0,
      description:
          'Money, clarity and momentum — a personal finance companion powered by AI.',
      items: const [],
      extra: const OnboardingAppShowcase(showDynamicIsland: false),
    );
  }

  Widget _buildCurrencyPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'MAKE IT YOURS',
      title: 'Choose\nCurrency Display',
      description:
          'Budget AI will use this everywhere — in your finances, insights, tool results and AI responses.',
      items: const [],
      extra: _CurrencySelectorPanel(
        selectedCurrency: CurrencySettingsService.instance.current,
        onCustomRequested: _showOnboardingCurrencyScreen,
      ),
    );
  }

  Widget _buildTrackPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'STAY ON TOP',
      title: 'Track Every Expense\n& Income',
      description:
          'Log every kind of income and expense, including loan cashflows, and see where your month went.',
      items: const [],
      extra: _InsightsShowcase(
        currency: CurrencySettingsService.instance.current,
      ),
    );
  }

  Widget _buildChatPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'YOUR AI CHAT',
      title: 'Just Say It,\nBudget AI Does It',
      description:
          'Chat naturally — the AI adds entries, searches your history and builds summaries for you.',
      items: const [],
      extra: _ChatPreview(
        currency: CurrencySettingsService.instance.current,
        animate: _animateChatPreview,
      ),
    );
  }

  Future<void> _showOnboardingCurrencyScreen() async {
    await CurrencyPickerScreen.show(context);
    if (mounted) setState(() {});
  }

  Widget _buildPermissionsPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'PERSONALIZE & PREPARE',
      title: 'Make It Personal,\nThen Get Ready',
      description: Platform.isAndroid
          ? 'Choose what Budget AI calls you, then enable access for updates and background work.'
          : 'Choose what Budget AI calls you, then enable notifications for important updates.',
      items: const [],
      extra: _FinalSetupPanel(
        notificationGranted: _notificationGranted ?? false,
        backgroundBatteryGranted: _backgroundBatteryGranted ?? false,
        onRequestNotification: _requestNotificationPermission,
        onRequestBackgroundBattery: _requestBackgroundBatteryPermission,
      ),
    );
  }
}

class _CurrencySelectorPanel extends StatelessWidget {
  const _CurrencySelectorPanel({
    required this.selectedCurrency,
    required this.onCustomRequested,
  });

  final String selectedCurrency;
  final VoidCallback onCustomRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CurrencyDisplayCard(
              currency: selectedCurrency,
              onTap: onCustomRequested,
              height: double.infinity,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onCustomRequested,
            iconAlignment: IconAlignment.end,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(CupertinoIcons.chevron_right, size: 13),
            label: Text(
              'Tap the card to choose more or add your own',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.kicker,
    required this.title,
    required this.description,
    required this.items,
    this.extra,
    this.emphasizeTitle = false,
  });

  final String kicker;
  final String title;
  final String description;
  final List<(IconData, String, String)> items;
  final Widget? extra;
  final bool emphasizeTitle;

  double _stagger(double t, double start, double end) {
    return Curves.easeOutCubic.transform(
      ((t - start) / (end - start)).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalPadding = screenSize.width * 0.031;
    final verticalPadding = screenSize.height * 0.009;
    final titleFontSize = screenSize.shortestSide * 0.066;
    final emphasizedTitleFontSize = screenSize.shortestSide * 0.103;
    final descriptionFontSize = screenSize.shortestSide * 0.04;
    final titleToBodyGap = screenSize.height * 0.009;
    final bodyToExtraGap = screenSize.height * 0.014;
    final minimumTitleFontSize = ((titleFontSize * 0.72) * 2).floor() / 2;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 820),
        builder: (context, t, _) {
          final headT = _stagger(t, 0.08, 0.42);
          final bodyT = _stagger(t, 0.14, 0.5);
          final extraT = _stagger(t, 0.18, 0.55);
          return Column(
            children: [
              Opacity(
                opacity: headT,
                child: Transform.translate(
                  offset: Offset(0, (1 - headT) * screenSize.height * 0.012),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      end: emphasizeTitle
                          ? emphasizedTitleFontSize
                          : titleFontSize,
                    ),
                    duration: _pageStateAnimationDuration,
                    curve: _pageStateAnimationCurve,
                    builder: (context, animatedFontSize, _) {
                      final steppedFontSize =
                          (animatedFontSize * 2).round() / 2;
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: AutoSizeText(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          minFontSize: minimumTitleFontSize,
                          maxFontSize: steppedFontSize,
                          stepGranularity: 0.5,
                          style: AppTheme.headingLarge.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontSize: steppedFontSize,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                            fontFamily: 'Boldonse',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: titleToBodyGap),
              Opacity(
                opacity: bodyT,
                child: Transform.translate(
                  offset: Offset(0, (1 - bodyT) * screenSize.height * 0.012),
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: descriptionFontSize,
                    ),
                  ),
                ),
              ),
              SizedBox(height: bodyToExtraGap),
              for (var i = 0; i < items.length; i++)
                _FeatureCard(
                  icon: items[i].$1,
                  title: items[i].$2,
                  subtitle: items[i].$3,
                  reveal: _stagger(t, 0.2 + i * 0.06, 0.55 + i * 0.06),
                ),
              if (extra != null)
                Expanded(
                  child: Opacity(
                    opacity: extraT,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        (1 - extraT) * screenSize.height * 0.017,
                      ),
                      child: SizedBox.expand(child: extra),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({
    required this.icon,
    required this.progress,
    required this.theme,
    required this.size,
  });

  final IconData icon;
  final double progress;
  final ThemeData theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final entry = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final isDark = theme.brightness == Brightness.dark;
    return Transform.scale(
      scale: 0.85 + 0.15 * entry,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.31),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              Color.lerp(theme.colorScheme.primary, AppTheme.highlight, 0.28)!,
            ],
          ),
          boxShadow: [
            if (isDark)
              BoxShadow(
                color: AppTheme.highlight.withValues(alpha: 0.14 * entry),
                blurRadius: 16,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18 * entry),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Icon(
          icon,
          size: size * 0.44,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}

class _HeroCurrencyToken extends StatelessWidget {
  const _HeroCurrencyToken({
    required this.currency,
    required this.progress,
    required this.theme,
    required this.size,
  });

  final String currency;
  final double progress;
  final ThemeData theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final entry = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final isDark = theme.brightness == Brightness.dark;
    return Transform.scale(
      scale: 0.85 + 0.15 * entry,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.31),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              Color.lerp(theme.colorScheme.primary, AppTheme.highlight, 0.28)!,
            ],
          ),
          boxShadow: [
            if (isDark)
              BoxShadow(
                color: AppTheme.highlight.withValues(alpha: 0.14 * entry),
                blurRadius: 16,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18 * entry),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: FittedBox(
            key: ValueKey(currency),
            fit: BoxFit.scaleDown,
            child: Text(
              currency,
              maxLines: 1,
              style: AppTheme.headingLarge.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.reveal,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, (1 - reveal) * 14),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.highlight),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyMedium.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),

                    Text(
                      subtitle,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _InsightPreviewKind { overview, activity, recentDays }

class _InsightsShowcase extends StatefulWidget {
  const _InsightsShowcase({required this.currency});

  final String currency;

  @override
  State<_InsightsShowcase> createState() => _InsightsShowcaseState();
}

class _InsightsShowcaseState extends State<_InsightsShowcase> {
  static const _sideCardScale = 0.76;

  // Keep the bar chart primary/front, with overview on the left and spending
  // activity on the right. Cards move only when the user taps a side card.
  int _front = 2;
  int _left = 0;
  int _right = 1;

  void _bringToFront(int item, {bool haptic = true}) {
    if (item == _front) return;
    if (haptic) HapticFeedback.lightImpact();
    setState(() {
      if (item == _left) {
        _left = _front;
      } else {
        _right = _front;
      }
      _front = item;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showcaseHeight = (MediaQuery.sizeOf(context).height * 0.5).clamp(
      230.0,
      285.0,
    );
    return SizedBox(
      height: showcaseHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth * 0.49).clamp(156.0, 188.0);
          final cardHeight = showcaseHeight + 16;
          const sideRotation = 0.13;
          const edgeMargin = 4.0;
          final sideVisualHalfWidth =
              _sideCardScale *
              ((cardWidth / 2) * math.cos(sideRotation) +
                  (cardHeight / 2) * math.sin(sideRotation));
          final maximumSideShift = math.max(
            0.0,
            (constraints.maxWidth / 2) - sideVisualHalfWidth - edgeMargin,
          );
          final sideShift = math.min(
            constraints.maxWidth * 0.29,
            maximumSideShift,
          );
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              _buildCard(_left, -sideShift, cardWidth, cardHeight),
              _buildCard(_right, sideShift, cardWidth, cardHeight),
              _buildCard(_front, 0, cardWidth, cardHeight),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(int item, double dx, double cardWidth, double cardHeight) {
    final isFront = item == _front;
    final dy = isFront ? 0.0 : cardHeight * 0.05;
    return AnimatedContainer(
      key: ValueKey(item),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      transformAlignment: Alignment.center,
      transform: Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..rotateZ(isFront ? 0 : (dx < 0 ? -0.13 : 0.13))
        ..scaleByDouble(
          isFront ? 1 : _sideCardScale,
          isFront ? 1 : _sideCardScale,
          1,
          1,
        ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _bringToFront(item),
        child: SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: _InsightPreviewCard(
            kind: _InsightPreviewKind.values[item],
            isActive: isFront,
            currency: widget.currency,
          ),
        ),
      ),
    );
  }
}

class _InsightPreviewCard extends StatelessWidget {
  const _InsightPreviewCard({
    required this.kind,
    required this.isActive,
    required this.currency,
  });

  final _InsightPreviewKind kind;
  final bool isActive;
  final String currency;

  IconData get _icon => switch (kind) {
    _InsightPreviewKind.overview => Icons.insights_rounded,
    _InsightPreviewKind.activity => Icons.grid_view_rounded,
    _InsightPreviewKind.recentDays => Icons.bar_chart_rounded,
  };

  String get _title => switch (kind) {
    _InsightPreviewKind.overview => 'Monthly Overview',
    _InsightPreviewKind.activity => 'Spending Activity',
    _InsightPreviewKind.recentDays => 'Last 7 Days',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _icon,
                  size: 17,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _title,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('${kind.name}-$isActive'),
              child: _InsightPreviewGraphic(
                kind: kind,
                animate: isActive,
                currency: currency,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'INSIGHTS PREVIEW',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightPreviewGraphic extends StatelessWidget {
  const _InsightPreviewGraphic({
    required this.kind,
    required this.animate,
    required this.currency,
  });

  final _InsightPreviewKind kind;
  final bool animate;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      _InsightPreviewKind.overview => _OverviewGraphic(
        animate: animate,
        currency: currency,
      ),
      _InsightPreviewKind.activity => _ActivityGraphic(animate: animate),
      _InsightPreviewKind.recentDays => _RecentDaysGraphic(animate: animate),
    };
  }
}

class _OverviewGraphic extends StatelessWidget {
  const _OverviewGraphic({required this.animate, required this.currency});

  final bool animate;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey(currency),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : 1, end: 1),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          final onCard = theme.colorScheme.onPrimary;
          final spent = 3240 * value;
          final income = 8500 * value;
          final remaining = income - spent;
          final budgetProgress = 0.62 * value;
          return LayoutBuilder(
            builder: (context, constraints) {
              final contentScale = math
                  .min(constraints.maxWidth / 125, constraints.maxHeight / 128)
                  .clamp(0.72, 1.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text(
                        'DEMO · THIS MONTH',
                        style: AppTheme.bodySmall.copyWith(
                          color: onCard.withValues(alpha: 0.62),
                          fontSize: 7 * contentScale,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8 * contentScale,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5 * contentScale,
                          vertical: 2 * contentScale,
                        ),
                        decoration: BoxDecoration(
                          color: onCard.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'ON TRACK',
                          style: AppTheme.bodySmall.copyWith(
                            color: onCard,
                            fontSize: 6 * contentScale,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * contentScale),
                  Text(
                    'Total spent',
                    style: AppTheme.bodySmall.copyWith(
                      color: onCard.withValues(alpha: 0.68),
                      fontSize: 7 * contentScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    CurrencySettingsService.instance.formatAmount(spent),
                    style: AppTheme.headingSmall.copyWith(
                      color: onCard,
                      fontSize: 18 * contentScale,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6 * contentScale),
                  Row(
                    children: [
                      Expanded(
                        child: _OverviewAmount(
                          label: 'Income',
                          scale: contentScale,
                          value: CurrencySettingsService.instance.formatAmount(
                            income,
                          ),
                        ),
                      ),
                      SizedBox(width: 5 * contentScale),
                      Expanded(
                        child: _OverviewAmount(
                          label: 'Remaining',
                          scale: contentScale,
                          value: CurrencySettingsService.instance.formatAmount(
                            remaining,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 7 * contentScale),
                  Row(
                    children: [
                      Text(
                        'Monthly budget',
                        style: AppTheme.bodySmall.copyWith(
                          color: onCard.withValues(alpha: 0.68),
                          fontSize: 7 * contentScale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(budgetProgress * 100).round()}% used',
                        style: AppTheme.bodySmall.copyWith(
                          color: onCard,
                          fontSize: 7 * contentScale,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 3 * contentScale),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LinearProgressIndicator(
                      value: budgetProgress,
                      minHeight: 4 * contentScale,
                      backgroundColor: onCard.withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(onCard),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _OverviewAmount extends StatelessWidget {
  const _OverviewAmount({
    required this.label,
    required this.value,
    required this.scale,
  });

  final String label;
  final String value;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final onCard = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 5 * scale),
      decoration: BoxDecoration(
        color: onCard.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: onCard.withValues(alpha: 0.62),
              fontSize: 7 * scale,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(
              color: onCard,
              fontSize: 8 * scale,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityGraphic extends StatelessWidget {
  const _ActivityGraphic({required this.animate});

  final bool animate;

  static const _levels = [
    0.0,
    0.2,
    0.6,
    0.3,
    0.9,
    0.1,
    0.5,
    0.3,
    0.8,
    0.4,
    0.0,
    0.6,
    1.0,
    0.2,
    0.5,
    0.1,
    0.8,
    0.4,
    0.7,
    0.3,
    0.9,
    0.2,
    0.7,
    0.1,
    0.9,
    0.5,
    0.2,
    0.6,
    0.8,
    0.3,
    0.5,
    1.0,
    0.4,
    0.7,
    0.1,
    0.1,
    0.9,
    0.6,
    0.2,
    0.6,
    0.8,
    0.3,
    0.5,
    1.0,
    0.4,
    0.7,
    0.8,
    0.1,
    0.9,
    0.2,
    0.2,
    0.6,
    0.8,
    0.9,
    0.5,
    1.0,
    0.4,
    0.7,
    0.3,
    0.6,
    0.8,
    0.9,
    0.5,
    1.0,
    0.4,
    0.6,
    0.8,
    0.9,
    0.5,
    1.0,
    0.4,
    0.7,
    0.3,
    0.7,
    0.3,
    0.1,
    0.9,
    0.5,
    0.9,
    0.6,
    0.8,
    0.3,
    0.5,
    1.0,
    0.6,
    0.8,
    0.9,
    0.5,
    1.0,
    0.6,
    0.8,
    0.9,
    0.5,
    1.0,
    0.4,
    0.7,
    0.3,
    0.4,
    0.7,
    0.3,
    0.4,
    0.7,
    0.9,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : availableWidth;
        final gap = (math.min(availableWidth, availableHeight) * 0.022).clamp(
          1.5,
          4.0,
        );

        var squareSize = 0.0;
        for (var columns = 1; columns <= _levels.length; columns++) {
          final rows = (_levels.length / columns).ceil();
          final widthForSquares = availableWidth - gap * (columns - 1);
          final heightForSquares = availableHeight - gap * (rows - 1);
          final candidateSize = math.min(
            widthForSquares / columns,
            heightForSquares / rows,
          );
          if (candidateSize > squareSize) {
            squareSize = candidateSize;
          }
        }
        squareSize = math.max(0, squareSize - 0.1);

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: animate ? 0 : 1, end: 1),
          duration: const Duration(milliseconds: 1900),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) => Align(
            alignment: Alignment.topCenter,
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final level in _levels)
                  Container(
                    width: squareSize,
                    height: squareSize,
                    decoration: BoxDecoration(
                      color: level == 0
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.primary.withValues(
                              alpha: (0.12 + level * 0.82) * progress,
                            ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentDaysGraphic extends StatelessWidget {
  const _RecentDaysGraphic({required this.animate});

  final bool animate;

  static const _values = [0.2, 0.7, 0.45, 0.92, 0.22, 0.68, 0.5];
  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: (_values[i] * progress).clamp(0.04, 1),
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: i == 3
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _days[i],
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChatPreview extends StatefulWidget {
  const _ChatPreview({required this.currency, required this.animate});

  final String currency;
  final bool animate;

  @override
  State<_ChatPreview> createState() => _ChatPreviewState();
}

class _ChatPreviewState extends State<_ChatPreview> {
  static const _userMessage =
      'I just spent 100 on groceries and 100 on a Budget AI subscription';

  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  Completer<void>? _typingCompleter;
  int _sequence = 0;
  int _typedCharacters = 0;
  bool _showUserBubble = false;
  bool _showFirstResponse = false;
  bool _showFirstToolCall = false;
  bool _showSecondToolCall = false;
  bool _showFinalResponse = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playSequence());
    }
  }

  @override
  void didUpdateWidget(covariant _ChatPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _playSequence();
    } else if (!widget.animate && oldWidget.animate) {
      _resetSequence();
    }
  }

  @override
  void dispose() {
    _sequence++;
    _typingTimer?.cancel();
    if (!(_typingCompleter?.isCompleted ?? true)) {
      _typingCompleter?.complete();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _resetSequence() {
    _sequence++;
    _typingTimer?.cancel();
    if (!(_typingCompleter?.isCompleted ?? true)) {
      _typingCompleter?.complete();
    }
    if (!mounted) return;
    setState(() {
      _typedCharacters = 0;
      _showUserBubble = false;
      _showFirstResponse = false;
      _showFirstToolCall = false;
      _showSecondToolCall = false;
      _showFinalResponse = false;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _playSequence() async {
    _resetSequence();
    final sequence = _sequence;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!_isCurrent(sequence)) return;
    setState(() => _showUserBubble = true);

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!_isCurrent(sequence)) return;
    await _typeUserMessage(sequence);

    if (!await _revealAfter(sequence, const Duration(milliseconds: 100), () {
      _showFirstResponse = true;
    })) {
      return;
    }
    if (!await _revealAfter(sequence, const Duration(milliseconds: 320), () {
      _showFirstToolCall = true;
    })) {
      return;
    }
    if (!await _revealAfter(sequence, const Duration(milliseconds: 260), () {
      _showSecondToolCall = true;
    })) {
      return;
    }
    await _revealAfter(sequence, const Duration(milliseconds: 300), () {
      _showFinalResponse = true;
    });
  }

  bool _isCurrent(int sequence) =>
      mounted && widget.animate && sequence == _sequence;

  Future<void> _typeUserMessage(int sequence) {
    final completer = Completer<void>();
    _typingCompleter = completer;
    _typingTimer = Timer.periodic(const Duration(milliseconds: 9), (timer) {
      if (!_isCurrent(sequence)) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      } else if (_typedCharacters < _userMessage.length) {
        setState(() => _typedCharacters++);
      } else {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  Future<bool> _revealAfter(
    int sequence,
    Duration delay,
    VoidCallback reveal,
  ) async {
    await Future<void>.delayed(delay);
    if (!_isCurrent(sequence)) return false;
    setState(reveal);
    _scrollToLatest();
    return true;
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !widget.animate) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;
    final screenSize = MediaQuery.sizeOf(context);
    final displayScale = math
        .min(screenSize.shortestSide / 390, screenSize.height / 844)
        .clamp(0.78, 1.15);
    final verticalGap = 12.0 * displayScale;
    final smallGap = 6.0 * displayScale;
    final bodyFontSize = 15 * displayScale;
    final groceriesAmount = CurrencySettingsService.instance.formatAmount(100);
    final subscriptionAmount = CurrencySettingsService.instance.formatAmount(
      100,
    );
    final totalAmount = CurrencySettingsService.instance.formatAmount(200);
    final groceriesToolCall = ToolCall(
      id: 'onboarding-finance-add-groceries',
      name: 'finance_add',
      arguments: {
        'amount': 100,
        'category': 'Groceries',
        'description': 'Groceries',
      },
      result: jsonEncode({
        'ok': true,
        'message': 'Expense added successfully',
        'amount': groceriesAmount,
        'category': 'Groceries',
      }),
      isComplete: true,
      status: ToolCallStatus.completed,
    );
    final subscriptionToolCall = ToolCall(
      id: 'onboarding-finance-add-subscription',
      name: 'finance_add',
      arguments: {
        'amount': 100,
        'category': 'Subscriptions',
        'description': 'Budget AI subscription',
      },
      result: jsonEncode({
        'ok': true,
        'message': 'Expense added successfully',
        'amount': subscriptionAmount,
        'category': 'Subscriptions',
        'description': 'Budget AI subscription',
      }),
      isComplete: true,
      status: ToolCallStatus.completed,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: verticalGap),
        Align(
          alignment: Alignment.centerRight,
          child: AnimatedSlide(
            offset: _showUserBubble ? Offset.zero : const Offset(0, 0.4),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: _showUserBubble ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                margin: const EdgeInsets.only(left: 24),
                padding: EdgeInsets.symmetric(
                  horizontal: 14 * displayScale,
                  vertical: 10 * displayScale,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(4 * displayScale),
                    topRight: Radius.circular(12 * displayScale),
                    bottomLeft: Radius.circular(12 * displayScale),
                    bottomRight: Radius.circular(4 * displayScale),
                  ),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 100),
                  alignment: Alignment.topRight,
                  child: Text(
                    _userMessage.substring(0, _typedCharacters),
                    style: AppTheme.bodyMedium.copyWith(
                      color: onPrimary,
                      fontSize: bodyFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: smallGap),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.only(bottom: smallGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChatPreviewReveal(
                    visible: _showFirstResponse,
                    child: Text(
                      'I’ll add both expenses for today — groceries and your Budget AI subscription.',
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: bodyFontSize,
                        height: 1.4,
                      ),
                    ),
                  ),
                  _ChatPreviewReveal(
                    visible: _showFirstToolCall,
                    child: ChatToolCallSection(
                      horizontalPadding: 0,
                      toolCall: groceriesToolCall,
                      themeColor: theme.colorScheme.primary,
                      isInProgress: false,
                      displayScale: displayScale,
                    ),
                  ),
                  _ChatPreviewReveal(
                    visible: _showSecondToolCall,
                    child: ChatToolCallSection(
                      horizontalPadding: 0,
                      toolCall: subscriptionToolCall,
                      themeColor: theme.colorScheme.primary,
                      isInProgress: false,
                      displayScale: displayScale,
                    ),
                  ),
                  _ChatPreviewReveal(
                    visible: _showFinalResponse,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text:
                                'Both expenses are recorded for today:\n'
                                '• Groceries\n'
                                '• Budget AI subscription\n\n',
                          ),
                          TextSpan(
                            text:
                                'Done — I added 2 entries totaling $totalAmount.',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: bodyFontSize,
                            ),
                          ),
                        ],
                      ),
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: bodyFontSize,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatPreviewReveal extends StatelessWidget {
  const _ChatPreviewReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.18),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: visible ? child : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _FinalSetupPanel extends StatefulWidget {
  const _FinalSetupPanel({
    required this.notificationGranted,
    required this.backgroundBatteryGranted,
    required this.onRequestNotification,
    required this.onRequestBackgroundBattery,
  });

  final bool notificationGranted;
  final bool backgroundBatteryGranted;
  final VoidCallback onRequestNotification;
  final VoidCallback onRequestBackgroundBattery;

  @override
  State<_FinalSetupPanel> createState() => _FinalSetupPanelState();
}

class _FinalSetupPanelState extends State<_FinalSetupPanel> {
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;

  bool _keyboardVisible = false;
  bool _isSaving = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: UserNameSettingsService.instance.current,
    );
    _nameFocusNode = FocusNode();
    _isSaved = _nameController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _showKeyboard() {
    if (_keyboardVisible) return;
    setState(() => _keyboardVisible = true);
    _nameFocusNode.requestFocus();
  }

  void _hideKeyboard() {
    if (!_keyboardVisible || _isSaving) return;
    _nameFocusNode.unfocus();
    setState(() => _keyboardVisible = false);
  }

  void _toggleKeyboard() {
    if (_keyboardVisible) {
      _hideKeyboard();
    } else {
      _showKeyboard();
    }
  }

  void _enterLetter(String letter) {
    if (_nameController.text.length >= 28) return;
    final current = _nameController.text;
    final shouldCapitalize =
        current.isEmpty || current.endsWith(' ') || current.endsWith('.');
    _setNameText(shouldCapitalize ? letter : letter.toLowerCase());
  }

  void _enterPeriod() {
    final current = _nameController.text;
    if (current.isEmpty ||
        current.endsWith(' ') ||
        current.endsWith('.') ||
        current.length >= 28) {
      return;
    }
    _setNameText('.');
  }

  void _enterSpace() {
    final current = _nameController.text;
    if (current.isEmpty || current.endsWith(' ') || current.length >= 28) {
      return;
    }
    _setNameText(' ');
  }

  void _backspace() {
    final current = _nameController.text;
    if (current.isEmpty) return;
    _nameController.value = TextEditingValue(
      text: current.substring(0, current.length - 1),
      selection: TextSelection.collapsed(offset: current.length - 1),
    );
    setState(() => _isSaved = false);
  }

  void _setNameText(String addition) {
    final updated = '${_nameController.text}$addition';
    _nameController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    setState(() => _isSaved = false);
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (_isSaving) return;
    setState(() => _isSaving = true);
    await Future.wait([
      UserNameSettingsService.instance.setUserName(name),
      Future<void>.delayed(const Duration(milliseconds: 360)),
    ]);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _nameFocusNode.unfocus();
    setState(() {
      _isSaving = false;
      _isSaved = name.isNotEmpty;
      _keyboardVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final gap = screenSize.height * 0.01;
    final permissionsEnabled = !_keyboardVisible && !_isSaving;

    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: constraints.maxWidth,
            maxWidth: constraints.maxWidth,
            minHeight: 0,
            maxHeight: double.infinity,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNameCard(theme, screenSize),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child: _keyboardVisible
                        ? Padding(
                            key: const ValueKey('name-keyboard-visible'),
                            padding: EdgeInsets.only(top: gap),
                            child: InlineNameKeyboard(
                              onLetter: _enterLetter,
                              onPeriod: _enterPeriod,
                              onSpace: _enterSpace,
                              onBackspace: _backspace,
                              onDone: _saveName,
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('name-keyboard-hidden'),
                            width: double.infinity,
                          ),
                  ),
                  SizedBox(height: gap),
                  AnimatedOpacity(
                    opacity: permissionsEnabled ? 1 : 0.28,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      ignoring: !permissionsEnabled,
                      child: Column(
                        children: [
                          _PermissionCard(
                            icon: CupertinoIcons.bell,
                            title: 'Notifications',
                            subtitle: 'Get updates when Budget AI finishes',
                            isGranted: widget.notificationGranted,
                            onRequest: widget.onRequestNotification,
                          ),
                          if (Platform.isAndroid) ...[
                            SizedBox(height: gap),
                            _PermissionCard(
                              icon: CupertinoIcons.bolt_horizontal_circle,
                              title: 'Background Service',
                              subtitle:
                                  'Keep Budget AI active in the background',
                              isGranted:
                                  widget.notificationGranted &&
                                  widget.backgroundBatteryGranted,
                              onRequest: widget.onRequestBackgroundBattery,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: permissionsEnabled
                        ? Padding(
                            padding: EdgeInsets.only(
                              top: gap * 1.5,
                              left: screenSize.width * 0.06,
                              right: screenSize.width * 0.06,
                            ),
                            child: Text(
                              'You can update your name and manage permissions anytime in app Settings.',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: AppTheme.bodySmall.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: screenSize.shortestSide * 0.031,
                                height: 1.45,
                              ),
                            ),
                          )
                        : const SizedBox(
                            width: double.infinity,
                            key: ValueKey('settings-reassurance-hidden'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNameCard(ThemeData theme, Size screenSize) {
    final horizontalInset = screenSize.width * 0.031;
    final iconContainerSize = screenSize.shortestSide * 0.123;
    final actionSize = screenSize.shortestSide * 0.097;
    final savedName = _nameController.text.trim();
    final firstName = savedName.split(RegExp(r'\s+')).firstOrNull ?? '';
    final showSavedSummary = _isSaved && !_keyboardVisible;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleKeyboard,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            Container(
              width: iconContainerSize,
              height: iconContainerSize,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                CupertinoIcons.person_fill,
                color: theme.colorScheme.onPrimary,
                size: screenSize.shortestSide * 0.048,
              ),
            ),
            SizedBox(width: horizontalInset),
            Expanded(
              child: SizedBox(
                height: iconContainerSize,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: showSavedSummary
                        ? Align(
                            key: const ValueKey('saved-name-summary'),
                            alignment: Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        savedName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.headingSmall.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          fontSize:
                                              screenSize.shortestSide * 0.04,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: screenSize.width * 0.01),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Icon(
                                        CupertinoIcons.pencil,
                                        color: theme.colorScheme.primary,
                                        size: screenSize.shortestSide * 0.04,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'I’ll call you $firstName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodySmall.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: screenSize.shortestSide * 0.032,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : TextField(
                            key: const ValueKey('name-edit-field'),
                            textAlign: TextAlign.left,
                            controller: _nameController,
                            focusNode: _nameFocusNode,
                            readOnly: true,
                            showCursor: _keyboardVisible,
                            enableInteractiveSelection: false,
                            onTap: _toggleKeyboard,
                            maxLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            cursorColor: theme.colorScheme.primary,
                            cursorWidth: screenSize.shortestSide * 0.0075,
                            cursorHeight: screenSize.shortestSide * 0.07,
                            cursorRadius: const Radius.circular(32),
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontFamily: 'Boldonse',
                              fontSize: screenSize.shortestSide * 0.046,
                            ),
                            decoration: InputDecoration(
                              hintText: 'What should I call you?',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.3,
                                ),
                                fontFamily: 'Boldonse',
                                fontSize: screenSize.shortestSide * 0.04,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.only(
                                top: 4,
                                bottom: 4,
                                left: 0,
                                right: 0,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            if (!showSavedSummary) ...[
              SizedBox(width: screenSize.width * 0.021),
              SizedBox(
                width: actionSize,
                height: actionSize,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _isSaving
                      ? Material(
                          key: const ValueKey('saving-name'),
                          color: theme.colorScheme.primary,
                          shape: const CircleBorder(),
                          child: Center(
                            child: SizedBox(
                              width: actionSize * 0.42,
                              height: actionSize * 0.42,
                              child: CircularProgressIndicator(
                                strokeWidth: screenSize.shortestSide * 0.005,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        )
                      : _keyboardVisible
                      ? Material(
                          key: const ValueKey('close-name-keyboard'),
                          color: theme.colorScheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: _hideKeyboard,
                            customBorder: const CircleBorder(),
                            child: Center(
                              child: Icon(
                                CupertinoIcons.xmark,
                                color: theme.colorScheme.onPrimary,
                                size: actionSize * 0.48,
                              ),
                            ),
                          ),
                        )
                      : Material(
                          key: const ValueKey('edit-name'),
                          color: theme.colorScheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: _showKeyboard,
                            customBorder: const CircleBorder(),
                            child: Center(
                              child: Icon(
                                CupertinoIcons.pencil,
                                color: theme.colorScheme.onPrimary,
                                size: actionSize * 0.48,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class InlineNameKeyboard extends StatelessWidget {
  const InlineNameKeyboard({
    super.key,
    required this.onLetter,
    required this.onPeriod,
    required this.onSpace,
    required this.onBackspace,
    required this.onDone,
  });

  static const _rows = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
  ];
  static const _lastLetterRow = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

  final ValueChanged<String> onLetter;
  final VoidCallback onPeriod;
  final VoidCallback onSpace;
  final VoidCallback onBackspace;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final keyGap = screenSize.width * 0.009;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, progress, keyboard) {
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * screenSize.height * 0.025),
            child: keyboard,
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resolver = _KeyboardTouchResolver(
            width: constraints.maxWidth,
            keyHeight: screenSize.shortestSide * 0.082,
            keyGap: keyGap,
          );

          void dispatch(String fallbackKey) {
            final key = resolver.resolve(fallbackKey);
            switch (key) {
              case _KeyboardTouchResolver.deleteKey:
                onBackspace();
                return;
              case _KeyboardTouchResolver.periodKey:
                onPeriod();
                return;
              case _KeyboardTouchResolver.spaceKey:
                onSpace();
                return;
              case _KeyboardTouchResolver.doneKey:
                onDone();
                return;
              default:
                onLetter(key);
                return;
            }
          }

          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: resolver.track,
            onPointerMove: resolver.track,
            onPointerUp: resolver.track,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in _rows) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < row.length; i++) ...[
                        if (i > 0) SizedBox(width: keyGap),
                        Expanded(
                          child: _InlineKeyboardKey(
                            label: row[i],
                            onTap: () => dispatch(row[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: keyGap),
                ],
                Row(
                  children: [
                    for (var i = 0; i < _lastLetterRow.length; i++) ...[
                      if (i > 0) SizedBox(width: keyGap),
                      Expanded(
                        child: _InlineKeyboardKey(
                          label: _lastLetterRow[i],
                          onTap: () => dispatch(_lastLetterRow[i]),
                        ),
                      ),
                    ],
                    SizedBox(width: keyGap),
                    Expanded(
                      child: _InlineKeyboardKey(
                        icon: CupertinoIcons.delete_left,
                        repeatOnLongPress: true,
                        onTap: () => dispatch(_KeyboardTouchResolver.deleteKey),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: keyGap),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _InlineKeyboardKey(
                        label: '.',
                        onTap: () => dispatch(_KeyboardTouchResolver.periodKey),
                      ),
                    ),
                    SizedBox(width: keyGap),
                    Expanded(
                      flex: 6,
                      child: _InlineKeyboardKey(
                        label: 'SPACE',
                        onTap: () => dispatch(_KeyboardTouchResolver.spaceKey),
                      ),
                    ),
                    SizedBox(width: keyGap),
                    Expanded(
                      flex: 2,
                      child: _InlineKeyboardKey(
                        icon: CupertinoIcons.check_mark,
                        emphasized: true,
                        onTap: () => dispatch(_KeyboardTouchResolver.doneKey),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KeyboardTouchResolver {
  _KeyboardTouchResolver({
    required this.width,
    required this.keyHeight,
    required this.keyGap,
  });

  static const deleteKey = '__delete__';
  static const periodKey = '.';
  static const spaceKey = '__space__';
  static const doneKey = '__done__';

  static const _keyRows = <List<String>>[
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M', deleteKey],
  ];

  final double width;
  final double keyHeight;
  final double keyGap;

  Offset? _touchPosition;
  double _reportedRadius = 0;

  void track(PointerEvent event) {
    _touchPosition = event.localPosition;
    _reportedRadius = math.max(event.radiusMajor, event.radiusMinor);
  }

  String resolve(String fallbackKey) {
    final position = _touchPosition;
    if (position == null) return fallbackKey;

    final keys = _buildKeyRects();
    final radius = _reportedRadius.clamp(keyHeight * 0.28, keyHeight * 1.35);
    final touchBounds = Rect.fromCenter(
      center: position,
      width: radius * 2,
      height: radius * 2,
    );
    final touchArea = touchBounds.width * touchBounds.height;

    String bestKey = fallbackKey;
    var bestOverlapPercent = -1.0;
    var bestDistance = double.infinity;
    for (final entry in keys.entries) {
      final overlap = entry.value.intersect(touchBounds);
      final overlapArea = overlap.isEmpty
          ? 0.0
          : overlap.width * overlap.height;
      final overlapPercent = overlapArea / touchArea;
      final distance = (entry.value.center - position).distanceSquared;
      // Compare every contacted key, not only the two nearest neighbors. This
      // lets a wide touch spanning three keys choose the highest-overlap key.
      if (overlapPercent > bestOverlapPercent ||
          (overlapPercent == bestOverlapPercent && distance < bestDistance)) {
        bestKey = entry.key;
        bestOverlapPercent = overlapPercent;
        bestDistance = distance;
      }
    }
    return bestKey;
  }

  Map<String, Rect> _buildKeyRects() {
    final rects = <String, Rect>{};
    for (var rowIndex = 0; rowIndex < _keyRows.length; rowIndex++) {
      final row = _keyRows[rowIndex];
      final keyWidth = (width - (keyGap * (row.length - 1))) / row.length;
      final top = rowIndex * (keyHeight + keyGap);
      for (var keyIndex = 0; keyIndex < row.length; keyIndex++) {
        final left = keyIndex * (keyWidth + keyGap);
        rects[row[keyIndex]] = Rect.fromLTWH(left, top, keyWidth, keyHeight);
      }
    }

    final bottomTop = 3 * (keyHeight + keyGap);
    final unit = (width - (keyGap * 2)) / 10;
    final periodWidth = unit * 2;
    final spaceWidth = unit * 6;
    final doneWidth = unit * 2;
    rects[periodKey] = Rect.fromLTWH(0, bottomTop, periodWidth, keyHeight);
    rects[spaceKey] = Rect.fromLTWH(
      periodWidth + keyGap,
      bottomTop,
      spaceWidth,
      keyHeight,
    );
    rects[doneKey] = Rect.fromLTWH(
      periodWidth + keyGap + spaceWidth + keyGap,
      bottomTop,
      doneWidth,
      keyHeight,
    );
    return rects;
  }
}

class _InlineKeyboardKey extends StatefulWidget {
  const _InlineKeyboardKey({
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
  State<_InlineKeyboardKey> createState() => _InlineKeyboardKeyState();
}

class _InlineKeyboardKeyState extends State<_InlineKeyboardKey> {
  bool _isPressed = false;
  bool _isRepeating = false;
  int _pressSequence = 0;
  Timer? _repeatTimer;

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    _pressSequence++;
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails _) {
    final sequence = _pressSequence;
    Future<void>.delayed(const Duration(milliseconds: 110), () {
      if (!mounted || sequence != _pressSequence) return;
      setState(() => _isPressed = false);
    });
  }

  void _handleTapCancel() {
    if (_isRepeating) return;
    _pressSequence++;
    if (_isPressed) setState(() => _isPressed = false);
  }

  void _handleLongPress() {
    if (!widget.repeatOnLongPress || _isRepeating) return;
    _pressSequence++;
    _isRepeating = true;
    if (!_isPressed) setState(() => _isPressed = true);
    HapticFeedback.selectionClick();
    widget.onTap();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      widget.onTap();
    });
  }

  void _stopRepeating() {
    if (!_isRepeating) return;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _pressSequence++;
    _isRepeating = false;
    if (mounted) setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final keyHeight = screenSize.shortestSide * 0.09;
    final popupGap = screenSize.shortestSide * 0.01;
    final popupExpansion = screenSize.shortestSide * 0.006;
    final foreground = widget.emphasized
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return SizedBox(
      height: keyHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -popupExpansion,
            right: -popupExpansion,
            bottom: keyHeight + popupGap,
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.18,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: screenSize.shortestSide * 0.026,
                          offset: Offset(0, screenSize.height * 0.005),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _buildKeyContent(
                        foreground: theme.colorScheme.onPrimary,
                        screenSize: screenSize,
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
                  borderRadius: BorderRadius.circular(
                    screenSize.shortestSide * 0.018,
                  ),
                  child: InkWell(
                    onTapDown: _handleTapDown,
                    onTapUp: _handleTapUp,
                    onTapCancel: _handleTapCancel,
                    onLongPress: widget.repeatOnLongPress
                        ? _handleLongPress
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTap();
                    },
                    borderRadius: BorderRadius.circular(
                      screenSize.shortestSide * 0.018,
                    ),
                    child: Center(
                      child: _buildKeyContent(
                        foreground: foreground,
                        screenSize: screenSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyContent({
    required Color foreground,
    required Size screenSize,
    bool preview = false,
  }) {
    if (widget.icon != null) {
      return Icon(
        widget.icon,
        color: foreground,
        size: screenSize.shortestSide * (preview ? 0.052 : 0.041),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        widget.label!,
        style: TextStyle(
          color: foreground,
          fontFamily: 'Boldonse',
          fontSize: screenSize.shortestSide * (preview ? 0.034 : 0.026),
          height: 1,
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isGranted,
    required this.onRequest,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isGranted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalInset = screenSize.width * 0.031;
    final iconContainerSize = screenSize.shortestSide * 0.123;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted
              ? Colors.green.withValues(alpha: 0.5)
              : theme.colorScheme.outline,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(
              color: isGranted ? Colors.green : theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isGranted ? Colors.white : theme.colorScheme.onPrimary,
              size: screenSize.shortestSide * 0.051,
            ),
          ),
          SizedBox(width: horizontalInset),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.headingSmall.copyWith(
                    fontSize: screenSize.shortestSide * 0.04,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: screenSize.shortestSide * 0.032,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: screenSize.width * 0.021),
          if (isGranted)
            SizedBox.shrink()
          else
            SizedBox(
              height: screenSize.shortestSide * 0.097,
              child: ElevatedButton(
                onPressed: onRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(
                    horizontal: screenSize.width * 0.041,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      screenSize.shortestSide * 0.082,
                    ),
                  ),
                ),
                child: Text(
                  'Allow',
                  style: TextStyle(fontSize: screenSize.shortestSide * 0.036),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
