import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/chat_activity_sections.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/chat/unified_chat_screen.dart';
import 'package:budget_ai/src/settings/currency_display_card.dart';
import 'package:budget_ai/src/settings/currency_picker_sheet.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const _onboardingCompletedKey = 'onboarding_completed';
const _onboardingCompletedAtKey = 'onboarding_completed_at';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.isReplay = false});

  /// When true the screen is opened from Settings as a tour replay: it pops
  /// back instead of navigating to chat and never rewrites onboarding state.
  final bool isReplay;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _pageCount = 6;

  final PageController _pageController = PageController();
  int _currentPage = 0;
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

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    try {
      if (widget.isReplay) {
        Navigator.of(context).pop();
        return;
      }
      final preferences = SharedPreferencesAsync();
      await preferences.setBool(_onboardingCompletedKey, true);
      await preferences.setString(
        _onboardingCompletedAtKey,
        DateTime.now().toIso8601String(),
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => UnifiedChatScreen(config: ChatModelConfig.deepseek),
        ),
      );
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

    return Scaffold(
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1100),
          child: PageView(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (page) {
              HapticFeedback.selectionClick();
              setState(() => _currentPage = page);
            },
            children: [
              _buildWelcomePage(theme),
              _buildCurrencyPage(theme),
              _buildTrackPage(theme),
              _buildChatPage(theme),
              _buildModelPage(theme),
              _buildPermissionsPage(theme),
            ],
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
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.05),
                Opacity(
                  opacity: heroT,
                  child: _buildHeroArea(theme, introT: t),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: pageView!),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: footerT,
                          child: Transform.translate(
                            offset: Offset(0, (1 - footerT) * 16),
                            child: _buildFooter(theme),
                          ),
                        ),
                      ),
                    ],
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
  Widget _buildHeroArea(ThemeData theme, {required double introT}) {
    return SizedBox(
      height: 132,
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
  }) {
    final presence = (1 - shift.abs()).clamp(0.0, 1.0);
    // Position/scale settle smoothly while opacity ramps in late, so the
    // incoming mark reveals faintly from afar and solidifies as it arrives.
    final settle = Curves.easeOutCubic.transform(presence);
    final fade = Curves.easeInQuad.transform(presence);
    return Opacity(
      opacity: fade,
      child: Transform.translate(
        offset: Offset(shift * 118, shift.abs() * 46),
        child: Transform.rotate(
          angle: shift * 0.85,
          child: Transform.scale(
            scale: 0.55 + 0.45 * settle,
            child: index == 0
                ? CustomPaint(
                    size: const Size(122, 122),
                    painter: BudgetMarkPainter(
                      progress: introT,
                      primary: theme.colorScheme.primary,
                      surface: theme.scaffoldBackgroundColor,
                      accent: AppTheme.highlight,
                      isDark: theme.brightness == Brightness.dark,
                    ),
                  )
                : _HeroIcon(
                    icon: _heroIcons[index],
                    progress: introT,
                    theme: theme,
                  ),
          ),
        ),
      ),
    );
  }

  static const _heroIcons = <IconData>[
    CupertinoIcons.sparkles, // index 0 unused — welcome uses the brand mark
    CupertinoIcons.money_dollar_circle,
    CupertinoIcons.money_dollar,
    CupertinoIcons.chat_bubble_2,
    CupertinoIcons.slider_horizontal_3,
    CupertinoIcons.checkmark_shield,
  ];

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        children: [
          if (widget.isReplay)
            IconButton(
              onPressed: Navigator.of(context).pop,
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            ),
          const Spacer(),
          AnimatedOpacity(
            opacity: _isLastPage ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: TextButton(
              onPressed: _isLastPage ? null : () => _goToPage(_pageCount - 1),
              child: Text(
                'Skip',
                style: AppTheme.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _pageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentPage ? 24 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: _currentPage > 0 ? 1 : 0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
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
                    width: 56,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _currentPage == 0
                                ? null
                                : () => _goToPage(_currentPage - 1),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.primary,
                              backgroundColor: Colors.transparent,
                              side: BorderSide(
                                color: theme.colorScheme.primary,
                                width: 1.4,
                              ),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new,
                              size: 17,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isFinishing ? null : _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    child: _isFinishing
                        ? SizedBox(
                            width: 20,
                            height: 20,
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
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
      description:
          'Money, clarity and momentum — a personal finance companion powered by AI.',
      items: const [],
      extra: const _AppShowcase(showDynamicIsland: false),
    );
  }

  Widget _buildCurrencyPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'MAKE IT YOURS',
      title: 'Choose currency\ndisplay',
      description:
          'Budget AI will use this everywhere — in your finances, insights, tool results and AI responses.',
      items: const [],
      extra: _CurrencySelectorPanel(
        selectedCurrency: CurrencySettingsService.instance.current,
        onCustomRequested: _showOnboardingCurrencySheet,
      ),
    );
  }

  Widget _buildTrackPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'STAY ON TOP',
      title: 'Track every expense,\nincome and loan',
      description:
          'Log expenses and income, manage borrowed and lent money, and see where your month went.',
      items: const [],
      extra: _InsightsShowcase(
        currency: CurrencySettingsService.instance.current,
      ),
    );
  }

  Widget _buildChatPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'YOUR AI CHAT',
      title: 'Just say it,\nBudget AI does it',
      description:
          'Chat naturally — the AI adds entries, searches your history and builds summaries for you in seconds.',
      items: const [],
      extra: _ChatPreview(currency: CurrencySettingsService.instance.current),
    );
  }

  Widget _buildModelPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'CHOOSE YOUR PACE',
      title: 'Flash or Pro,\nyou decide',
      description:
          'Pick the model that fits how you work. Your choice is saved and can be changed anytime from chat or Settings.',
      items: const [],
      extra: _ModelSelectorPanel(
        selectedModel: ModelSettingsService.instance.current,
        onSelected: (value) => unawaited(_selectOnboardingModel(value)),
      ),
    );
  }

  Future<void> _selectOnboardingCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    await CurrencySettingsService.instance.setCurrency(normalized);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _showOnboardingCurrencySheet() async {
    final selected = await CurrencyPickerSheet.show(context);
    if (selected == null) return;
    await _selectOnboardingCurrency(selected);
  }

  Future<void> _selectOnboardingModel(String modelId) async {
    await ModelSettingsService.instance.setModel(modelId);
    if (mounted) setState(() {});
  }

  Widget _buildPermissionsPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'ONE LAST THING',
      title: 'Let Budget AI\nwork for you',
      description: Platform.isAndroid
          ? 'Notifications and background access keep Budget AI running and reporting even when the app is closed.'
          : 'Notifications let Budget AI report back to you when it finishes working.',
      items: const [],
      extra: Column(
        children: [
          _PermissionCard(
            icon: CupertinoIcons.bell,
            title: 'Notifications',
            subtitle: 'Get updates when Budget AI finishes',
            isGranted: _notificationGranted ?? false,
            onRequest: _requestNotificationPermission,
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 8),
            _PermissionCard(
              icon: CupertinoIcons.bolt_horizontal_circle,
              title: 'Background Service',
              subtitle: 'Keep Budget AI active in the background',
              isGranted:
                  (_notificationGranted ?? false) &&
                  (_backgroundBatteryGranted ?? false),
              onRequest: _requestBackgroundBatteryPermission,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'You can change these anytime in Settings → Permissions.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
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
    return Column(
      children: [
        CurrencyDisplayCard(
          currency: selectedCurrency,
          onTap: onCustomRequested,
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
    );
  }
}

class _ModelSelectorPanel extends StatelessWidget {
  const _ModelSelectorPanel({
    required this.selectedModel,
    required this.onSelected,
  });

  final String selectedModel;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < AIModels.deepseekModels.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _OnboardingModelCard(
            model: AIModels.deepseekModels[i],
            selected: AIModels.deepseekModels[i].id == selectedModel,
            onTap: () => onSelected(AIModels.deepseekModels[i].id),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'This selection is used for new chats and stays selected after restart.',
          textAlign: TextAlign.center,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _OnboardingModelCard extends StatelessWidget {
  const _OnboardingModelCard({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final AIModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPro = model.id.toLowerCase().contains('pro');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.55),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Icon(
                  isPro ? CupertinoIcons.sparkles : Icons.bolt_rounded,
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  size: 21,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPro ? 'Pro' : 'Flash',
                      textAlign: TextAlign.center,
                      style: AppTheme.headingSmall.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      isPro
                          ? 'Deeper, multi-step analysis'
                          : 'Fast, everyday budgeting',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.circle,
                    key: ValueKey(selected),
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
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
  });

  final String kicker;
  final String title;
  final String description;
  final List<(IconData, String, String)> items;
  final Widget? extra;

  double _stagger(double t, double start, double end) {
    return Curves.easeOutCubic.transform(
      ((t - start) / (end - start)).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 124),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 820),
            builder: (context, t, _) {
              final headT = _stagger(t, 0.08, 0.42);
              final bodyT = _stagger(t, 0.14, 0.5);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: headT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - headT) * 10),
                      child: Column(
                        children: [
                          Text(
                            kicker,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.highlight,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTheme.headingLarge.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: bodyT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - bodyT) * 10),
                      child: Text(
                        description,
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyMedium.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < items.length; i++)
                    _FeatureCard(
                      icon: items[i].$1,
                      title: items[i].$2,
                      subtitle: items[i].$3,
                      reveal: _stagger(t, 0.2 + i * 0.06, 0.55 + i * 0.06),
                    ),
                  if (extra != null)
                    Opacity(
                      opacity: _stagger(t, 0.18, 0.55),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _stagger(t, 0.18, 0.55)) * 14),
                        child: extra,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({
    required this.icon,
    required this.progress,
    required this.theme,
  });

  final IconData icon;
  final double progress;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final entry = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final isDark = theme.brightness == Brightness.dark;
    return Transform.scale(
      scale: 0.85 + 0.15 * entry,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
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
        child: Icon(icon, size: 42, color: theme.colorScheme.onPrimary),
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
  int _front = 0;
  int _left = 1;
  int _right = 2;
  Timer? _rotationTimer;

  @override
  void initState() {
    super.initState();
    _rotationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _rotateForward();
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

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

  void _rotateForward() {
    setState(() {
      final previousLeft = _left;
      _left = _front;
      _front = _right;
      _right = previousLeft;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 242,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideShift = constraints.maxWidth * 0.29;
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              _buildCard(_left, -sideShift),
              _buildCard(_right, sideShift),
              _buildCard(_front, 0),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(int item, double dx) {
    final isFront = item == _front;
    return AnimatedContainer(
      key: ValueKey(item),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
      transformAlignment: Alignment.topCenter,
      transform: Matrix4.identity()
        ..translateByDouble(dx, isFront ? 0 : 10, 0, 1)
        ..rotateZ(isFront ? 0 : (dx < 0 ? -0.13 : 0.13))
        ..scaleByDouble(isFront ? 1 : 0.92, isFront ? 1 : 0.92, 1, 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _bringToFront(item),
        child: SizedBox(
          width: 184,
          height: 222,
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
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
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, size: 17, color: theme.colorScheme.primary),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : 1, end: 1),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          final onCard = theme.colorScheme.onPrimary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEMO · THIS MONTH',
                style: AppTheme.bodySmall.copyWith(
                  color: onCard.withValues(alpha: 0.62),
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                CurrencySettingsService.instance.formatAmount(42800 * value),
                style: AppTheme.headingSmall.copyWith(
                  color: onCard,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  _OverviewStat(
                    label: 'Entries',
                    value: '${(18 * value).round()}',
                  ),
                  _OverviewStat(
                    label: 'Days',
                    value: '${(11 * value).round()}',
                  ),
                  _OverviewStat(
                    label: 'Avg',
                    value: CurrencySettingsService.instance.formatAmount(
                      2380 * value,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onCard = Theme.of(context).colorScheme.onPrimary;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(
              color: onCard,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: onCard.withValues(alpha: 0.58),
              fontSize: 7,
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
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 1900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final level in _levels)
            Container(
              width: 14,
              height: 13,
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
    );
  }
}

class _RecentDaysGraphic extends StatelessWidget {
  const _RecentDaysGraphic({required this.animate});

  final bool animate;

  static const _values = [0.42, 0.76, 0.3, 0.92, 0.58, 0.68, 0.48];
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
                                      alpha: 0.28,
                                    ),
                              borderRadius: BorderRadius.circular(5),
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

class _ChatPreview extends StatelessWidget {
  const _ChatPreview({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;
    final amount = CurrencySettingsService.instance.formatAmount(500);
    final toolCall = ToolCall(
      id: 'onboarding-finance-add',
      name: 'finance_add',
      arguments: {
        'amount': 500,
        'category': 'Groceries',
        'description': 'Groceries',
      },
      result: jsonEncode({
        'ok': true,
        'message': 'Expense added successfully',
        'amount': amount,
        'category': 'Groceries',
      }),
      isComplete: true,
      status: ToolCallStatus.completed,
    );

    return Container(
      key: ValueKey(currency),
      width: double.infinity,

      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? AppTheme.highlight.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(7),
                  ),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  'Spent $amount on groceries',
                  style: AppTheme.bodyMedium.copyWith(
                    color: onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'I’ll add this as today’s grocery expense.',
              style: AppTheme.bodyMedium.copyWith(
                color: onSurface,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),

          ChatToolCallSection(
            toolCall: toolCall,
            themeColor: theme.colorScheme.primary,
            isInProgress: false,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text:
                        'I categorized this as Groceries and recorded it for today.\n'
                        'It will appear in your spending totals and upcoming insights.\n'
                        'You can ask me to edit or remove it anytime.\n\n',
                  ),
                  TextSpan(
                    text: 'Done — I added $amount to Groceries for today.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: AppTheme.bodyMedium.copyWith(
                color: onSurface,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  child: Icon(CupertinoIcons.plus, size: 28, color: onSurface),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: Text(
                      'Ask Budget AI',
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.72,
                        ),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.arrow_up,
                    size: 24,
                    color: theme.colorScheme.primary.withValues(alpha: 0.56),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: isGranted
              ? Colors.green.withValues(alpha: 0.5)
              : theme.colorScheme.outline,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isGranted ? Colors.green : theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Icon(
              icon,
              color: isGranted ? Colors.white : theme.colorScheme.onPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.headingSmall.copyWith(
                    fontSize: 15,
                    color: theme.colorScheme.onSurface,
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
          const SizedBox(width: 8),
          if (isGranted)
            const Icon(
              CupertinoIcons.check_mark_circled,
              color: Colors.green,
              size: 24,
            )
          else
            SizedBox(
              height: 38,
              child: ElevatedButton(
                onPressed: onRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                child: const Text('Allow'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShowcaseItem {
  const _ShowcaseItem(this.asset);

  final String asset;
}

/// A fanned deck of three app-UI videos on the welcome page: one front and
/// center, two tilted behind it. Tapping a back card swaps it with the front
/// one — both travel to each other's slot at the same time.
class _AppShowcase extends StatefulWidget {
  const _AppShowcase({this.showDynamicIsland = true});

  /// Whether the iPhone frame draws the Dynamic Island pill over the screen.
  final bool showDynamicIsland;

  @override
  State<_AppShowcase> createState() => _AppShowcaseState();
}

class _AppShowcaseState extends State<_AppShowcase> {
  static const _items = <_ShowcaseItem>[
    _ShowcaseItem('assets/onboarding/1.mp4'),
    _ShowcaseItem('assets/onboarding/2.mp4'),
    _ShowcaseItem('assets/onboarding/3.mp4'),
  ];

  late final List<VideoPlayerController> _videoControllers;
  final List<bool> _videoReady = [false, false, false];

  int _front = 0;
  int _left = 1;
  int _right = 2;

  @override
  void initState() {
    super.initState();
    _videoControllers = [
      for (final item in _items) VideoPlayerController.asset(item.asset),
    ];
    _initVideos();
  }

  Future<void> _initVideos() async {
    // Prioritize the visible card, then warm both side cards together. Each
    // card becomes live as soon as its own controller is ready instead of
    // waiting for the slowest asset.
    await _initializeVideo(_front);
    await Future.wait([_initializeVideo(_left), _initializeVideo(_right)]);
  }

  Future<void> _initializeVideo(int index) async {
    try {
      final controller = _videoControllers[index];
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) return;
      setState(() => _videoReady[index] = true);
    } catch (e) {
      debugPrint(
        '[Onboarding] Showcase video ${_items[index].asset} failed: $e',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _videoControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _bringToFront(int item) {
    if (item == _front) return;
    HapticFeedback.lightImpact();
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
    final height = (MediaQuery.sizeOf(context).height * 0.34).clamp(
      220.0,
      360.0,
    );
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Match the showcase videos' aspect ratio (400x880) so nothing
          // gets cropped by BoxFit.cover.
          const gifAspect = 400 / 880;
          final h = constraints.maxHeight;
          final w = constraints.maxWidth;
          var cardH = h * 0.94;
          var cardW = cardH * gifAspect;
          final maxW = w * 0.42;
          if (cardW > maxW) {
            cardW = maxW;
            cardH = cardW / gifAspect;
          }
          final sideShift = cardW * 0.85;

          return Stack(
            alignment: Alignment.center,
            children: [
              _buildCard(_left, cardW, cardH, -sideShift, h),
              _buildCard(_right, cardW, cardH, sideShift, h),
              _buildCard(_front, cardW, cardH, 0, h),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(
    int item,
    double cardW,
    double cardH,
    double dx,
    double areaH,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isFront = item == _front;
    final rotation = isFront ? 0.0 : (dx < 0 ? -0.22 : 0.22);
    final scale = isFront ? 1.0 : 0.8;
    final dy = isFront ? 0.0 : areaH * 0.05;
    final bezel = cardW * 0.01;

    // Keyed by item so the same element travels between slots when _front
    // changes — that is what makes both cards animate across on a swap.
    return AnimatedContainer(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      key: ValueKey(item),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      transformAlignment: Alignment.center,
      transform: Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..rotateZ(rotation)
        ..scaleByDouble(scale, scale, scale, 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _bringToFront(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubic,
          width: cardW + bezel * 2,
          height: cardH + bezel * 2,
          padding: EdgeInsets.all(bezel),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF17171A),
            borderRadius: BorderRadius.circular(16 + bezel),
            border: Border.all(color: const Color(0xFF3E3E42), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? AppTheme.highlight.withValues(
                        alpha: isFront ? 0.12 : 0.05,
                      )
                    : Colors.black.withValues(alpha: isFront ? 0.16 : 0.08),
                blurRadius: isFront ? 18 : 10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  _items[item].asset.replaceFirst('.mp4', '-poster.jpg'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
                if (_videoReady[item])
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 180),
                    builder: (context, opacity, video) =>
                        Opacity(opacity: opacity, child: video),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _videoControllers[item].value.size.width,
                        height: _videoControllers[item].value.size.height,
                        child: VideoPlayer(_videoControllers[item]),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (widget.showDynamicIsland)
                  // Dynamic Island
                  Positioned(
                    top: cardW * 0.04,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: cardW * 0.30,
                        height: cardW * 0.085,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
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
