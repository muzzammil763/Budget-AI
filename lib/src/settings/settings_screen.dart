import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/finances_screen.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart'
    show InlineNameKeyboard;
import 'package:budget_ai/src/settings/bubble_style_screen.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/currency_picker_screen.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/local_speech_models_screen.dart';
import 'package:budget_ai/src/settings/permission_preferences_service.dart';
import 'package:budget_ai/src/speech/local_speech_model.dart';
import 'package:budget_ai/src/speech/local_speech_model_manager.dart';
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
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          const _AiUsageCard(),
          const _SettingsNameEditor(),
          _navTile(
            theme,
            icon: CupertinoIcons.money_dollar_circle,
            title: 'Finances',
            subtitle: 'View and manage finance data',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinancesScreen()),
            ),
          ),
          _navTile(
            theme,
            leading: const BudgetMarkIcon(size: 30),
            title: 'Finance Insights',
            subtitle: 'Overall and monthly spending insights',
            onTap: _openInsights,
          ),
          ValueListenableBuilder<String>(
            valueListenable: CurrencySettingsService.instance.currency,
            builder: (context, currency, _) => _navTile(
              theme,
              leading: _currencyLeading(theme, currency),
              title: 'Currency display',
              subtitle:
                  'Amounts display as ${CurrencySettingsService.instance.formatAmount(1200)} using $currency',
              onTap: () => CurrencyPickerScreen.show(context),
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: LocalSpeechModelManager.instance.selectedSttId,
            builder: (context, sttId, _) => ValueListenableBuilder<String>(
              valueListenable: LocalSpeechModelManager.instance.selectedTtsId,
              builder: (context, ttsId, _) => _navTile(
                theme,
                icon: CupertinoIcons.waveform,
                title: 'Offline Speech Models',
                subtitle:
                    '${LocalSpeechModels.byId(sttId)?.name ?? sttId} · '
                    '${LocalSpeechModels.byId(ttsId)?.name ?? ttsId}',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LocalSpeechModelsScreen(),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<UserBubbleStyle>(
            valueListenable: BubbleStyleSettingsService.instance.style,
            builder: (context, style, _) => _navTile(
              theme,
              icon: CupertinoIcons.chat_bubble_2_fill,
              title: 'Message bubble',
              subtitle: '${style.label} style for your messages',
              onTap: () => BubbleStyleScreen.show(context),
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
            icon: CupertinoIcons.square_arrow_right,
            title: 'Sign out',
            subtitle: AuthService.instance.user?.email ?? 'Signed in',
            foregroundColor: Colors.red,
            onTap: _signOut,
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Sign out?',
      message:
          'Your finance data stays on this device. You will need to sign in again to use AI chat.',
      icon: CupertinoIcons.square_arrow_right,
      confirmLabel: 'Sign out',
      isRed: true,
      onConfirm: () async {
        try {
          await AuthService.instance.signOut();
        } catch (error) {
          if (mounted) {
            showAppToast(
              context,
              message: friendlyAuthError(error),
              type: ToastificationType.error,
            );
          }
          rethrow;
        }
      },
    );
    if (confirmed == true && mounted) Navigator.of(context).pop();
  }

  Widget _navTile(
    ThemeData theme, {
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

class _SettingsNameEditor extends StatefulWidget {
  const _SettingsNameEditor();

  @override
  State<_SettingsNameEditor> createState() => _SettingsNameEditorState();
}

class _SettingsNameEditorState extends State<_SettingsNameEditor> {
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
    final screenSize = MediaQuery.sizeOf(context);
    final savedName = UserNameSettingsService.instance.current;
    final firstName = savedName.split(RegExp(r'\s+')).firstOrNull ?? '';
    final showSavedSummary = savedName.isNotEmpty && !_isEditing;
    final iconContainerSize = screenSize.shortestSide * 0.123;
    final actionSize = screenSize.shortestSide * 0.097;
    final horizontalInset = screenSize.width * 0.031;
    final verticalInset = screenSize.height * 0.014;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleKeyboard,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalInset,
                vertical: verticalInset,
              ),
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
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.person_fill,
                      size: screenSize.shortestSide * 0.051,
                      color: theme.colorScheme.onPrimary,
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
                                  key: const ValueKey(
                                    'settings-saved-name-summary',
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              savedName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTheme.headingSmall
                                                  .copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface,
                                                    fontSize:
                                                        screenSize
                                                            .shortestSide *
                                                        0.04,
                                                  ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: screenSize.width * 0.01,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            child: Icon(
                                              CupertinoIcons.pencil,
                                              color: theme.colorScheme.primary,
                                              size:
                                                  screenSize.shortestSide *
                                                  0.04,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'I’ll call you $firstName',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.bodySmall.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize:
                                              screenSize.shortestSide * 0.032,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : TextField(
                                  key: const ValueKey(
                                    'settings-name-edit-field',
                                  ),
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  readOnly: true,
                                  showCursor: _isEditing,
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
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.3),
                                      fontFamily: 'Boldonse',
                                      fontSize: screenSize.shortestSide * 0.04,
                                    ),
                                    isDense: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 4,
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
                                key: const ValueKey('settings-name-saving'),
                                color: theme.colorScheme.primary,
                                shape: const CircleBorder(),
                                child: Center(
                                  child: SizedBox(
                                    width: actionSize * 0.42,
                                    height: actionSize * 0.42,
                                    child: CircularProgressIndicator(
                                      strokeWidth:
                                          screenSize.shortestSide * 0.005,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              )
                            : Material(
                                key: ValueKey(
                                  _isEditing
                                      ? 'settings-name-close'
                                      : 'settings-name-edit',
                                ),
                                color: theme.colorScheme.primary,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: _isEditing
                                      ? _closeKeyboard
                                      : _startEditing,
                                  customBorder: const CircleBorder(),
                                  child: Center(
                                    child: Icon(
                                      _isEditing
                                          ? CupertinoIcons.xmark
                                          : CupertinoIcons.pencil,
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

class _AiUsageCard extends StatefulWidget {
  const _AiUsageCard();

  @override
  State<_AiUsageCard> createState() => _AiUsageCardState();
}

class _AiUsageCardState extends State<_AiUsageCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    // Every time this card is mounted (i.e. every time Settings is opened),
    // re-fetch so the numbers never go stale, showing the skeleton below
    // for the duration of that fetch rather than popping content in.
    AiUsageService.instance.refresh();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            AiUsageService.instance.isLoading,
            AiUsageService.instance.usage,
            _pulseController,
          ]),
          builder: (context, _) {
            final isLoading = AiUsageService.instance.isLoading.value;
            final info = AiUsageService.instance.usage.value;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: isLoading || info == null
                  ? _buildSkeleton(theme, key: const ValueKey('skeleton'))
                  : _buildContent(theme, info, key: const ValueKey('data')),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, AiUsageInfo info, {Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              CupertinoIcons.speedometer,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'AI Usage This Month',
              style: AppTheme.bodyMedium.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (!info.enabled)
              Text(
                'Disabled',
                style: AppTheme.bodySmall.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _usageRow(
          theme,
          label: 'Requests',
          used: info.requestsUsed,
          limit: info.requestsLimit,
          fraction: info.requestsFraction,
        ),
        const SizedBox(height: 10),
        _usageRow(
          theme,
          label: 'Tokens',
          used: info.tokensUsed,
          limit: info.tokensLimit,
          fraction: info.tokensFraction,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              CupertinoIcons.calendar,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              'Renews ${_formatRenewDate(info.renewsOn)}',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _monthAbbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatRenewDate(DateTime date) {
    final month = _monthAbbreviations[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  Widget _usageRow(
    ThemeData theme, {
    required String label,
    required int used,
    required int limit,
    required double fraction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              '${_formatCount(used)} / ${_formatCount(limit)}',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              fraction >= 1
                  ? Colors.red
                  : fraction >= 0.85
                  ? Colors.orange
                  : theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton(ThemeData theme, {Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _skeletonBar(theme, width: 20, height: 20, radius: 6),
            const SizedBox(width: 8),
            _skeletonBar(theme, width: 120, height: 14),
          ],
        ),
        const SizedBox(height: 14),
        _skeletonUsageRow(theme),
        const SizedBox(height: 12),
        _skeletonUsageRow(theme),
        const SizedBox(height: 12),
        _skeletonBar(theme, width: 96, height: 11),
      ],
    );
  }

  Widget _skeletonUsageRow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _skeletonBar(theme, width: 56, height: 11),
            const Spacer(),
            _skeletonBar(theme, width: 72, height: 11),
          ],
        ),
        const SizedBox(height: 8),
        _skeletonBar(theme, width: double.infinity, height: 6, radius: 6),
      ],
    );
  }

  Widget _skeletonBar(
    ThemeData theme, {
    required double width,
    required double height,
    double radius = 4,
  }) {
    final alpha = 0.06 + (_pulseController.value * 0.1);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  String _formatCount(int value) {
    final str = value.toString();
    if (str.length <= 3) return str;
    final buf = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    return buf.toString();
  }
}
