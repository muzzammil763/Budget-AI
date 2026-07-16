import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/finances/finances_screen.dart';
import 'package:budget_ai/src/loan/loans_screen.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/settings/app_backup_service.dart';
import 'package:budget_ai/src/settings/currency_picker_sheet.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/model_picker_sheet.dart';
import 'package:budget_ai/src/settings/permissions_screen.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:toastification/toastification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
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
          if (_packageInfo != null) ...[
            Text(
              '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          const _SettingsNameEditor(),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.money_dollar_circle,
            title: 'Finances',
            subtitle: 'View and manage finances data',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinancesScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: Icons.handshake_outlined,
            title: 'Loans',
            subtitle: 'Borrowed and lent money with repayments',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoansScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: Icons.insights_rounded,
            title: 'Finance Insights',
            subtitle: 'Overall and monthly spending insights',
            onTap: _openInsights,
          ),
          ValueListenableBuilder<String>(
            valueListenable: CurrencySettingsService.instance.currency,
            builder: (context, currency, _) {
              return _buildNavTile(
                theme,
                icon: CupertinoIcons.money_dollar,
                title: 'Currency display',
                subtitle:
                    'Amounts display as ${CurrencySettingsService.instance.formatAmount(1200)} using $currency',
                onTap: _showCurrencySheet,
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: ModelSettingsService.instance.modelId,
            builder: (context, modelId, _) {
              final model = AIModels.getModelById(modelId);
              return _buildNavTile(
                theme,
                icon: CupertinoIcons.sparkles,
                title: 'AI Model',
                subtitle: model?.name ?? modelId,
                onTap: _showModelSheet,
              );
            },
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.checkmark_shield,
            title: 'Permissions',
            subtitle: 'Notifications and background mode',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PermissionsScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.archivebox,
            title: 'Backup & Restore',
            subtitle: 'Backup & Restore finances data',
            onTap: _showBackupRestoreSheet,
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.sparkles,
            title: 'Onboarding',
            subtitle: 'Replay the welcome tour',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const OnboardingScreen(isReplay: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ],
          ),
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

  Future<void> _showCurrencySheet() async {
    final selected = await CurrencyPickerSheet.show(context);
    if (selected == null) return;
    await _selectCurrency(selected);
  }

  Future<void> _showModelSheet() async {
    final selected = await ModelPickerSheet.show(
      context,
      selectedModel: ModelSettingsService.instance.current,
    );
    if (selected == null) return;
    await ModelSettingsService.instance.setModel(selected);
  }

  Future<void> _selectCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    await CurrencySettingsService.instance.setCurrency(normalized);
    if (!mounted) return;
    showAppToast(
      context,
      message:
          'Currency set to ${CurrencySettingsService.instance.formatAmount(1200)}',
      type: ToastificationType.success,
    );
  }

  Future<void> _showBackupRestoreSheet() async {
    final theme = Theme.of(context);
    await ResponsiveInfoSheet.show<void>(
      context,
      title: 'Backup & Restore',
      headerIcon: Icon(
        CupertinoIcons.archivebox,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _buildSheetAction(
          theme,
          icon: CupertinoIcons.cloud_upload,
          title: 'Backup',
          subtitle: 'Create a dated JSON backup file',
          onTap: () {
            Navigator.pop(context);
            _exportBackup();
          },
        ),
        const SizedBox(height: 8),
        _buildSheetAction(
          theme,
          icon: CupertinoIcons.cloud_download,
          title: 'Restore',
          subtitle: 'Pick a JSON backup file to restore',
          onTap: () {
            Navigator.pop(context);
            _restoreBackup();
          },
        ),
      ],
    );
  }

  Widget _buildSheetAction(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
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
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      await AppBackupService.instance.shareBackup();
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Backup Failed: $e',
        type: ToastificationType.error,
      );
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null) return;

      final file = File(result.path!);
      if (!await file.exists()) {
        if (!mounted) return;
        showAppToast(
          context,
          message: 'File Not Found',
          type: ToastificationType.error,
        );
        return;
      }

      final restoreResult = await AppBackupService.instance.restoreFromFile(
        file,
      );

      if (!mounted) return;
      if (restoreResult['ok'] == true) {
        showAppToast(
          context,
          message:
              restoreResult['message']?.toString() ??
              'Backup Restored Successfully!',
          type: ToastificationType.success,
        );
      } else {
        showAppToast(
          context,
          message: restoreResult['error']?.toString() ?? 'Restore Failed',
          type: ToastificationType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Restore Failed: $e',
        type: ToastificationType.error,
      );
    }
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
                borderRadius: BorderRadius.circular(screenSize.shortestSide),
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
