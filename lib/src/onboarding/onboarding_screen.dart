import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/unified_chat_screen.dart';
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
  static const _pageCount = 4;

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
    final status = await Permission.notification.request();
    if (mounted) {
      setState(() => _notificationGranted = status.isGranted);
      if (!status.isGranted) {
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
              _buildTrackPage(theme),
              _buildChatPage(theme),
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

  /// A shared hero slot above the PageView. The four page marks live here in
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
    CupertinoIcons.money_dollar,
    CupertinoIcons.sparkles,
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
                        ? AppTheme.highlight
                        : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
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
                  : Text(
                      _isLastPage
                          ? (widget.isReplay ? 'Done' : 'Get Started')
                          : 'Next',
                      style: AppTheme.bodyLarge.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
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

  Widget _buildTrackPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'STAY ON TOP',
      title: 'Track every expense,\nincome and loan',
      description:
          'Log expenses and income, manage borrowed and lent money, and see where your month went.',
      items: const [
        (
          Icons.pie_chart_outline_rounded,
          'Finances',
          'Expenses and income in one place',
        ),
        (
          Icons.handshake_outlined,
          'Loans',
          'Borrowed and lent money with repayments',
        ),
        (
          Icons.insights_rounded,
          'Insights',
          'Overall and monthly spending breakdowns',
        ),
      ],
    );
  }

  Widget _buildChatPage(ThemeData theme) {
    return _OnboardingPage(
      kicker: 'YOUR AI CHAT',
      title: 'Just say it,\nBudget AI does it',
      description:
          'Chat naturally — the AI adds entries, searches your history and builds summaries for you in seconds.',
      items: const [
        (
          CupertinoIcons.chat_bubble_2,
          'Natural language',
          '"Spent 500 on groceries" — done',
        ),
        (
          Icons.manage_search_rounded,
          'Smart search',
          'Find any entry or unusual spending',
        ),
        (
          Icons.query_stats_rounded,
          'Summaries',
          'Compare months and plan budgets',
        ),
      ],
    );
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            builder: (context, t, _) {
              final headT = _stagger(t, 0.15, 0.6);
              final bodyT = _stagger(t, 0.25, 0.7);
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
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
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
                      reveal: _stagger(t, 0.38 + i * 0.08, 0.72 + i * 0.08),
                    ),
                  if (extra != null)
                    Opacity(
                      opacity: _stagger(t, 0.38, 0.75),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _stagger(t, 0.38, 0.75)) * 14),
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
                    fontSize: 11,
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
  const _ShowcaseItem(this.asset, this.icon, this.label);

  final String asset;
  final IconData icon;
  final String label;
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
    _ShowcaseItem(
      'assets/onboarding/1.mp4',
      CupertinoIcons.chat_bubble_2,
      'AI Chat',
    ),
    _ShowcaseItem(
      'assets/onboarding/2.mp4',
      CupertinoIcons.money_dollar_circle,
      'Finances',
    ),
    _ShowcaseItem(
      'assets/onboarding/3.mp4',
      Icons.insights_rounded,
      'Insights',
    ),
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

  /// Initializes every controller first, then starts them all in the same
  /// frame so the three videos begin playing together instead of each one
  /// starting whenever its own file happens to finish loading.
  Future<void> _initVideos() async {
    final ready = List<bool>.filled(_videoControllers.length, false);

    await Future.wait([
      for (var i = 0; i < _videoControllers.length; i++)
        () async {
          try {
            final controller = _videoControllers[i];
            await controller.initialize();
            await controller.setLooping(true);
            await controller.setVolume(0);
            ready[i] = true;
          } catch (e) {
            // Missing/broken asset: the branded placeholder stays visible.
            debugPrint(
              '[Onboarding] Showcase video ${_items[i].asset} failed: $e',
            );
          }
        }(),
    ]);

    if (!mounted) return;
    for (var i = 0; i < _videoControllers.length; i++) {
      if (ready[i]) _videoControllers[i].play();
    }
    setState(() {
      for (var i = 0; i < ready.length; i++) {
        _videoReady[i] = ready[i];
      }
    });
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
                if (_videoReady[item])
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _videoControllers[item].value.size.width,
                      height: _videoControllers[item].value.size.height,
                      child: VideoPlayer(_videoControllers[item]),
                    ),
                  )
                else
                  _buildPlaceholder(theme, _items[item]),
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

  Widget _buildPlaceholder(ThemeData theme, _ShowcaseItem item) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            Color.lerp(theme.colorScheme.primary, AppTheme.highlight, 0.35)!,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: theme.colorScheme.onPrimary, size: 30),
          const SizedBox(height: 8),
          Text(
            item.label,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
