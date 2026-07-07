import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/platform/android_background_agent_service.dart';
import 'package:budget_ai/core/widgets/budget_mark.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/features/chat/domain/chat_model_config.dart';
import 'package:budget_ai/features/chat/presentation/screens/unified_chat_screen.dart';
import 'package:budget_ai/features/onboarding/data/onboarding_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

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
          await AndroidBackgroundAgentService.isBatteryOptimizationIgnored();
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
    await AndroidBackgroundAgentService.requestBatteryOptimizationExemption();
    final granted =
        await AndroidBackgroundAgentService.isBatteryOptimizationIgnored();
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
      await OnboardingService.instance.markCompleted();
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
              _buildAgentPage(theme),
              _buildPermissionsPage(theme),
            ],
          ),
          builder: (context, t, pageView) {
            final headerT = _introStagger(t, 0.35, 0.75);
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

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
                  width: i == _currentPage ? 22 : 7,
                  height: 7,
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
      hero: (t) => CustomPaint(
        size: const Size(120, 120),
        painter: BudgetMarkPainter(
          progress: t,
          primary: theme.colorScheme.primary,
          surface: theme.scaffoldBackgroundColor,
          accent: AppTheme.highlight,
          isDark: theme.brightness == Brightness.dark,
        ),
      ),
      kicker: 'WELCOME TO',
      title: 'Budget AI',
      description:
          'Money, memory and momentum — a personal finance companion powered by AI.',
      items: const [],
    );
  }

  Widget _buildTrackPage(ThemeData theme) {
    return _OnboardingPage(
      hero: (t) => _HeroIcon(
        icon: CupertinoIcons.money_dollar_circle,
        progress: t,
        theme: theme,
      ),
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

  Widget _buildAgentPage(ThemeData theme) {
    return _OnboardingPage(
      hero: (t) =>
          _HeroIcon(icon: CupertinoIcons.sparkles, progress: t, theme: theme),
      kicker: 'YOUR AI AGENT',
      title: 'Just say it,\nthe agent does it',
      description:
          'Chat naturally — the AI adds entries, searches your history and builds summaries for you in seconds.',
      items: const [
        (
          Icons.chat_bubble_outline_rounded,
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
      hero: (t) => _HeroIcon(
        icon: CupertinoIcons.checkmark_shield,
        progress: t,
        theme: theme,
      ),
      kicker: 'ONE LAST THING',
      title: 'Let the agent\nwork for you',
      description: Platform.isAndroid
          ? 'Notifications and background access keep the agent running and reporting even when the app is closed.'
          : 'Notifications let the agent report back to you when it finishes working.',
      items: const [],
      extra: Column(
        children: [
          _PermissionCard(
            icon: CupertinoIcons.bell,
            title: 'Notifications',
            subtitle: 'Get updates when the agent finishes',
            isGranted: _notificationGranted ?? false,
            onRequest: _requestNotificationPermission,
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 8),
            _PermissionCard(
              icon: CupertinoIcons.bolt_horizontal_circle,
              title: 'Background Service',
              subtitle: 'Keep the agent alive for background',
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
    required this.hero,
    required this.kicker,
    required this.title,
    required this.description,
    required this.items,
    this.extra,
  });

  final Widget Function(double t) hero;
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                  Opacity(opacity: _stagger(t, 0.0, 0.55), child: hero(t)),
                  const SizedBox(height: 20),
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
