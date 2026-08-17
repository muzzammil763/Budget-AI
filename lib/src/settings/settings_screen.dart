import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/finances_screen.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/settings/bubble_style_screen.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/ai_response_settings_service.dart';
import 'package:budget_ai/src/settings/currency_picker_screen.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/local_speech_models_screen.dart';
import 'package:budget_ai/src/settings/permission_preferences_service.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:toastification/toastification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  PackageInfo? _packageInfo;

  // OS-level permission status, refreshed on open and whenever the app comes
  // back from the system settings screen. The soft on/off the user controls
  // lives in PermissionPreferencesService; a feature only counts as "on"
  // when both are true.
  bool _notificationPermissionGranted = false;
  bool _backgroundPermissionGranted = false;
  bool _busyNotifications = false;
  bool _busyBackground = false;
  bool _isSendingReset = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissionStatus();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissionStatus();
  }

  Future<void> _refreshPermissionStatus() async {
    final notificationGranted = await Permission.notification.status;
    var backgroundGranted = false;
    if (Platform.isAndroid) {
      backgroundGranted =
          await AndroidBackgroundChatService.isBatteryOptimizationIgnored();
    }
    if (!mounted) return;
    setState(() {
      _notificationPermissionGranted = notificationGranted.isGranted;
      _backgroundPermissionGranted = backgroundGranted;
    });
    // If the OS permission disappeared (revoked from system settings) while
    // the soft toggle was still on, drop the soft toggle so the two stay
    // consistent and the feature genuinely stops.
    if (!_notificationPermissionGranted &&
        PermissionPreferencesService.instance.notificationsEnabled.value) {
      await PermissionPreferencesService.instance.setNotificationsEnabled(
        false,
      );
    }
    if (Platform.isAndroid &&
        !_backgroundPermissionGranted &&
        PermissionPreferencesService.instance.backgroundEnabled.value) {
      await PermissionPreferencesService.instance.setBackgroundEnabled(false);
    }
  }

  Future<void> _onNotificationsToggled(bool value) async {
    if (_busyNotifications) return;
    if (!value) {
      await PermissionPreferencesService.instance.setNotificationsEnabled(
        false,
      );
      await NotificationService.instance.cancelAll();
      return;
    }
    setState(() => _busyNotifications = true);
    try {
      var granted = _notificationPermissionGranted;
      if (!granted) {
        granted = Platform.isIOS
            ? await NotificationService.instance.requestPermission()
            : (await Permission.notification.request()).isGranted;
        granted = granted || (await Permission.notification.status).isGranted;
      }
      if (!mounted) return;
      setState(() => _notificationPermissionGranted = granted);
      if (granted) {
        await PermissionPreferencesService.instance.setNotificationsEnabled(
          true,
        );
      } else {
        await PermissionPreferencesService.instance.setNotificationsEnabled(
          false,
        );
        await _showPermissionDeniedSheet('Notifications');
      }
    } finally {
      if (mounted) setState(() => _busyNotifications = false);
    }
  }

  Future<void> _onBackgroundToggled(bool value) async {
    if (_busyBackground) return;
    if (!value) {
      await PermissionPreferencesService.instance.setBackgroundEnabled(false);
      return;
    }
    setState(() => _busyBackground = true);
    try {
      var granted = _backgroundPermissionGranted;
      if (!granted) {
        await AndroidBackgroundChatService.requestBatteryOptimizationExemption();
        granted =
            await AndroidBackgroundChatService.isBatteryOptimizationIgnored();
      }
      if (!mounted) return;
      setState(() => _backgroundPermissionGranted = granted);
      if (granted) {
        await PermissionPreferencesService.instance.setBackgroundEnabled(true);
      } else {
        await _showPermissionDeniedSheet('Background Service');
      }
    } finally {
      if (mounted) setState(() => _busyBackground = false);
    }
  }

  Future<void> _showPermissionDeniedSheet(String permissionName) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: '$permissionName Permission Needed',
      message:
          'Budget AI needs $permissionName permission for this. Open system '
          'settings to allow it, then come back and turn it on.',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      confirmLabel: 'Open Settings',
    );
    if (confirmed == true) await AppSettings.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        actions: [
          if (_packageInfo != null)
            Text(
              '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          const SizedBox(width: 8),
        ],
        title: const Text('Budget Hub'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          _sectionHeading(
            theme,
            eyebrow: 'QUICK ACTIONS',
            title: 'Your Money, One Tap Away',
          ),
          const SizedBox(height: 8),
          _buildQuickActions(theme),
          const SizedBox(height: 20),
          _sectionHeading(
            theme,
            eyebrow: 'ACCOUNT',
            title: 'Profile & Security',
          ),
          const SizedBox(height: 8),
          const _AccountNameEditor(),
          _accountInfoTile(
            theme,
            icon: CupertinoIcons.envelope,
            title: 'Email',
            value: AuthService.instance.user?.email ?? 'Email unavailable',
          ),
          _navTile(
            theme,
            icon: CupertinoIcons.lock,
            title: 'Change Password',
            subtitle: _isSendingReset
                ? 'Sending secure reset link…'
                : 'Send a secure reset link to your email',
            onTap: _isSendingReset ? () {} : _sendPasswordReset,
          ),
          const SizedBox(height: 12),
          _sectionHeading(
            theme,
            eyebrow: 'PREFERENCES',
            title: 'Make Budget AI Yours',
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: CurrencySettingsService.instance.currency,
            builder: (context, currency, _) => _navTile(
              theme,
              leading: _currencyLeading(theme, currency),
              title: 'Currency Display',
              subtitle:
                  'Amounts display as ${CurrencySettingsService.instance.formatAmount(1200)} using $currency',
              onTap: () => CurrencyPickerScreen.show(context),
            ),
          ),
          _navTile(
            theme,
            icon: CupertinoIcons.waveform,
            title: 'Offline Speech Model',
            subtitle: 'Whisper Small English',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LocalSpeechModelsScreen(),
              ),
            ),
          ),
          ValueListenableBuilder<UserBubbleStyle>(
            valueListenable: BubbleStyleSettingsService.instance.style,
            builder: (context, style, _) => _navTile(
              theme,
              icon: CupertinoIcons.chat_bubble_2,
              title: 'Message Bubble',
              subtitle:
                  '${BubbleStyleSettingsService.instance.currentLabel} style '
                  'for your messages',
              onTap: () => BubbleStyleScreen.show(context),
            ),
          ),
          const SizedBox(height: 12),
          _sectionHeading(
            theme,
            eyebrow: 'APP BEHAVIOR',
            title: 'Responses & Background',
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable:
                AiResponseSettingsService.instance.fastResponsesEnabled,
            builder: (context, enabled, _) => _toggleTile(
              theme,
              icon: CupertinoIcons.bolt_fill,
              title: 'Fast Responses',
              subtitle: 'Lower latency with higher OpenAI token pricing',
              value: enabled,
              busy: false,
              onChanged:
                  AiResponseSettingsService.instance.setFastResponsesEnabled,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable:
                PermissionPreferencesService.instance.notificationsEnabled,
            builder: (context, enabled, _) => _toggleTile(
              theme,
              icon: CupertinoIcons.bell,
              title: 'Notifications',
              subtitle: 'Get notified when a response is ready',
              value: enabled && _notificationPermissionGranted,
              busy: _busyNotifications,
              onChanged: _onNotificationsToggled,
            ),
          ),
          if (Platform.isAndroid)
            ValueListenableBuilder<bool>(
              valueListenable:
                  PermissionPreferencesService.instance.backgroundEnabled,
              builder: (context, enabled, _) => _toggleTile(
                theme,
                icon: CupertinoIcons.bolt_horizontal_circle,
                title: 'Background Service',
                subtitle: 'Keep replies coming while the app is in background',
                value: enabled && _backgroundPermissionGranted,
                busy: _busyBackground,
                onChanged: _onBackgroundToggled,
              ),
            ),
          _navTile(
            theme,
            key: const ValueKey('replay-onboarding'),
            icon: CupertinoIcons.restart,
            title: 'Replay Onboarding',
            subtitle: 'Revisit the complete Budget AI introduction and setup',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const OnboardingScreen(isRevisit: true),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeading(
            theme,
            eyebrow: 'DANGER ZONE',
            title: 'Account Actions',
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 8),
          _dangerAction(
            theme,
            key: const ValueKey('settings-sign-out'),
            icon: CupertinoIcons.square_arrow_right,
            title: 'Sign Out',
            subtitle: 'Leave this account on this device',
            onTap: _signOut,
          ),
          _dangerAction(
            theme,
            key: const ValueKey('settings-delete-account'),
            icon: CupertinoIcons.delete,
            title: _isDeletingAccount ? 'Deleting Account …' : 'Delete Account',
            subtitle: 'Permanently delete your account and synced data',
            onTap: _isDeletingAccount ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(
    ThemeData theme, {
    required String eyebrow,
    required String title,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: AppTheme.bodySmall.copyWith(
            color: color ?? theme.colorScheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: AppTheme.headingSmall.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 17,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    return SizedBox(
      height: 154,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _quickActionCard(
              theme,
              title: 'Finances',
              subtitle: 'Add, search, and edit entries',
              icon: CupertinoIcons.money_dollar_circle,
              color: Colors.transparent,
              foreground: theme.colorScheme.onSurface,
              borderColor: theme.colorScheme.primary.withValues(alpha: 0.35),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FinancesScreen()),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _quickActionCard(
              theme,
              title: 'Insights',
              subtitle: 'Trends, activity & more',
              leading: const BudgetMarkIcon(size: 31),
              color: Colors.transparent,
              foreground: theme.colorScheme.onSurface,
              borderColor: theme.colorScheme.primary.withValues(alpha: 0.35),
              onTap: _openInsights,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    IconData? icon,
    Widget? leading,
    required Color color,
    required Color foreground,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor ?? color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: leading ?? Icon(icon, size: 26, color: foreground),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.headingSmall.copyWith(
                        color: foreground,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    CupertinoIcons.arrow_up_right,
                    size: 16,
                    color: foreground.withValues(alpha: 0.78),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall.copyWith(
                  color: foreground.withValues(alpha: 0.74),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountInfoTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      key: const ValueKey('settings-account-email'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: _tileDecoration(theme),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Icon(icon, size: 24, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: _tileText(theme, title, value)),
          Icon(
            CupertinoIcons.lock_fill,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _dangerAction(
    ThemeData theme, {
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final error = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: error.withValues(alpha: 0.42)),
          ),
          child: Row(
            children: [
              SizedBox(width: 32, child: Icon(icon, color: error, size: 23)),
              const SizedBox(width: 12),
              Expanded(
                child: _tileText(
                  theme,
                  title,
                  subtitle,
                  foregroundColor: error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navTile(
    ThemeData theme, {
    Key? key,
    IconData? icon,
    Widget? leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? foregroundColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: foregroundColor == null
              ? _tileDecoration(theme)
              : BoxDecoration(
                  color: foregroundColor.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: foregroundColor.withValues(alpha: 0.3),
                  ),
                ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child:
                    leading ??
                    Icon(
                      icon,
                      size: 24,
                      color: foregroundColor ?? theme.colorScheme.primary,
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tileText(
                  theme,
                  title,
                  subtitle,
                  foregroundColor: foregroundColor,
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: (foregroundColor ?? theme.colorScheme.onSurfaceVariant)
                    .withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool busy,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: _tileDecoration(theme),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Icon(icon, size: 24, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(child: _tileText(theme, title, subtitle)),
            const SizedBox(width: 8),
            // Fixed footprint so swapping the spinner in and out never
            // changes the tile height — the earlier jank came from the
            // spinner and the Switch having different intrinsic sizes.
            SizedBox(
              width: 52,
              height: 32,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: busy
                      ? SizedBox(
                          key: const ValueKey('busy'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : CupertinoSwitch(
                          key: const ValueKey('switch'),
                          value: value,
                          activeTrackColor: Colors.green,
                          onChanged: onChanged,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tileText(
    ThemeData theme,
    String title,
    String subtitle, {
    Color? foregroundColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.bodyMedium.copyWith(
            color: foregroundColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppTheme.bodySmall.copyWith(
            color:
                foregroundColor?.withValues(alpha: 0.76) ??
                theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  BoxDecoration _tileDecoration(ThemeData theme) => BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
  );

  Widget _currencyLeading(ThemeData theme, String currency) {
    return SizedBox(
      width: 32,
      child: AutoSizeText(
        currency,
        maxLines: 1,
        maxFontSize: 22,
        minFontSize: 14,
        textAlign: TextAlign.center,
        style: AppTheme.bodySmall.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _sendPasswordReset() async {
    final email = AuthService.instance.user?.email;
    if (email == null || email.isEmpty) {
      showAppToast(
        context,
        message: 'No account email is available',
        type: ToastificationType.error,
      );
      return;
    }
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Change Password?',
      message:
          'Budget AI will email a secure password-reset link to $email. '
          'Open that link on this device to choose a new password.',
      icon: CupertinoIcons.lock_rotation,
      confirmLabel: 'Send Email',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSendingReset = true);
    try {
      await AuthService.instance.sendPasswordRecovery(email);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Password reset email sent to $email',
        type: ToastificationType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        message: friendlyAuthError(error),
        type: ToastificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Sign Out?',
      message:
          'Your finance data stays on this device. You will need to sign in '
          'again to use AI chat.',
      icon: CupertinoIcons.square_arrow_right,
      confirmLabel: 'Sign Out',
      isRed: true,
      onConfirm: AuthService.instance.signOut,
    );
    if (confirmed == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteAccount() async {
    final theme = Theme.of(context);
    final firstConfirmation = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Delete Account?',
      headerIcon: Icon(
        CupertinoIcons.delete,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.error),
      ),
      gradientColors: [
        theme.colorScheme.error,
        theme.colorScheme.error.withValues(alpha: 0.78),
      ],
      contentWidgets: const [_DeleteAccountPhraseConfirmation()],
    );
    if (firstConfirmation != true || !mounted) return;
    final finalConfirmation = await ResponsiveInfoSheet.confirm(
      context,
      title: 'This Cannot Be Undone',
      message:
          'Your recovery key cannot restore an account after deletion. Are '
          'you absolutely sure you want to permanently delete it?',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      confirmLabel: 'Confirm Delete',
      isRed: true,
    );
    if (finalConfirmation != true || !mounted) return;
    setState(() => _isDeletingAccount = true);
    try {
      await AuthService.instance.deleteAccount();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        message: friendlyAuthError(error),
        type: ToastificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  Future<void> _openInsights() async {
    final entries = await FinanceService.instance.getAll();
    if (!mounted) return;
    final now = DateTime.now();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinanceInsightsScreen(
          entries: List.from(entries),
          selectedMonth: DateTime(now.year, now.month),
        ),
      ),
    );
  }
}

class _DeleteAccountPhraseConfirmation extends StatefulWidget {
  const _DeleteAccountPhraseConfirmation();

  @override
  State<_DeleteAccountPhraseConfirmation> createState() =>
      _DeleteAccountPhraseConfirmationState();
}

class _DeleteAccountPhraseConfirmationState
    extends State<_DeleteAccountPhraseConfirmation>
    with SingleTickerProviderStateMixin {
  static const requiredPhrase = 'DELETE MY ACCOUNT';
  String _enteredPhrase = '';
  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
      lowerBound: 0.15,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  bool get _matches => _enteredPhrase == requiredPhrase;

  void _enterLetter(String letter) {
    if (_enteredPhrase.length >= requiredPhrase.length) return;
    setState(() => _enteredPhrase += letter.toUpperCase());
  }

  void _enterSpace() {
    if (_enteredPhrase.isEmpty ||
        _enteredPhrase.endsWith(' ') ||
        _enteredPhrase.length >= requiredPhrase.length) {
      return;
    }
    setState(() => _enteredPhrase += ' ');
  }

  void _backspace() {
    if (_enteredPhrase.isEmpty) return;
    setState(
      () => _enteredPhrase = _enteredPhrase.substring(
        0,
        _enteredPhrase.length - 1,
      ),
    );
  }

  void _continue() {
    if (_matches) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This permanently deletes your Budget AI account, encrypted cloud '
          'finance data, synced preferences, encryption recovery data, and AI '
          'usage records. Data remaining only on this device is not removed.',
          textAlign: TextAlign.center,
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Enter $requiredPhrase to continue',
          textAlign: TextAlign.center,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('delete-account-phrase-field'),
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _matches
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
              width: _matches ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_enteredPhrase.isNotEmpty)
                Text(
                  _enteredPhrase,
                  maxLines: 1,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              FadeTransition(
                opacity: _cursorController,
                child: Container(
                  key: const ValueKey('delete-account-phrase-cursor'),
                  width: 2,
                  height: 23,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (_enteredPhrase.isEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  'DELETE MY ACCOUNT',
                  maxLines: 1,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.35,
                    ),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        InlineNameKeyboard(
          onLetter: _enterLetter,
          onPeriod: () {},
          onSpace: _enterSpace,
          onBackspace: _backspace,
          onDone: _continue,
        ),
        const SizedBox(height: 12),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: AppButton(
                text: 'Cancel',
                variant: AppButtonVariant.outlined,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            Expanded(
              child: AppButton(
                key: const ValueKey('confirm-delete-account-phrase'),
                text: 'Delete',
                isRed: true,
                onPressed: _matches ? _continue : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccountNameEditor extends StatefulWidget {
  const _AccountNameEditor();

  @override
  State<_AccountNameEditor> createState() => _AccountNameEditorState();
}

class _AccountNameEditorState extends State<_AccountNameEditor> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: UserNameSettingsService.instance.current,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (_isEditing || _isSaving) return;
    final currentName = UserNameSettingsService.instance.current;
    _controller.value = TextEditingValue(
      text: currentName,
      selection: TextSelection.collapsed(offset: currentName.length),
    );
    setState(() => _isEditing = true);
    _focusNode.requestFocus();
  }

  void _closeKeyboard() {
    if (!_isEditing || _isSaving) return;
    _focusNode.unfocus();
    setState(() => _isEditing = false);
  }

  void _toggleKeyboard() {
    if (_isEditing) {
      _closeKeyboard();
    } else {
      _startEditing();
    }
  }

  void _enterLetter(String letter) {
    if (_controller.text.length >= 28) return;
    final current = _controller.text;
    final shouldCapitalize =
        current.isEmpty || current.endsWith(' ') || current.endsWith('.');
    _appendText(shouldCapitalize ? letter : letter.toLowerCase());
  }

  void _enterPeriod() {
    final current = _controller.text;
    if (current.isEmpty ||
        current.endsWith(' ') ||
        current.endsWith('.') ||
        current.length >= 28) {
      return;
    }
    _appendText('.');
  }

  void _enterSpace() {
    final current = _controller.text;
    if (current.isEmpty || current.endsWith(' ') || current.length >= 28) {
      return;
    }
    _appendText(' ');
  }

  void _backspace() {
    final current = _controller.text;
    if (current.isEmpty) return;
    final updated = current.substring(0, current.length - 1);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    setState(() {});
  }

  void _appendText(String addition) {
    final updated = '${_controller.text}$addition';
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    setState(() {});
  }

  Future<void> _saveName() async {
    if (_isSaving) return;
    final name = _controller.text.trim();
    setState(() => _isSaving = true);
    await Future.wait([
      UserNameSettingsService.instance.setUserName(name),
      Future<void>.delayed(const Duration(milliseconds: 280)),
    ]);
    if (!mounted) return;
    _focusNode.unfocus();
    setState(() {
      _isSaving = false;
      _isEditing = false;
    });
    HapticFeedback.lightImpact();
    showAppToast(
      context,
      message: name.isEmpty ? 'Name cleared' : 'Name updated to $name',
      type: ToastificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedName = UserNameSettingsService.instance.current;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            key: const ValueKey('settings-account-name'),
            borderRadius: BorderRadius.circular(12),
            onTap: _toggleKeyboard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Icon(
                      CupertinoIcons.person,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _isEditing
                        ? TextField(
                            key: const ValueKey('settings-name-edit-field'),
                            controller: _controller,
                            focusNode: _focusNode,
                            readOnly: true,
                            showCursor: true,
                            enableInteractiveSelection: false,
                            onTap: () {},
                            maxLines: 1,
                            cursorColor: theme.colorScheme.primary,
                            decoration: const InputDecoration(
                              fillColor: Colors.transparent,
                              hintText: 'What should I call you?',
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),

                            style: AppTheme.bodyMedium.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          )
                        : Column(
                            key: const ValueKey('settings-saved-name-summary'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Name',
                                style: AppTheme.bodyMedium.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                savedName.isEmpty ? 'Add your name' : savedName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.bodySmall.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (_isSaving)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  else
                    Icon(
                      _isEditing ? CupertinoIcons.xmark : CupertinoIcons.pencil,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _isEditing
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InlineNameKeyboard(
                      onLetter: _enterLetter,
                      onPeriod: _enterPeriod,
                      onSpace: _enterSpace,
                      onBackspace: _backspace,
                      onDone: _saveName,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
