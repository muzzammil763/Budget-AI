import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/settings/data/api_key_storage_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:toastification/toastification.dart';

class APIKeysScreen extends StatefulWidget {
  const APIKeysScreen({super.key});

  @override
  State<APIKeysScreen> createState() => _APIKeysScreenState();
}

class _APIKeysScreenState extends State<APIKeysScreen> {
  final TextEditingController _deepseekApiController = TextEditingController();
  List<String> _deepseekApiKeys = [];
  bool _deepseekObscure = true;
  bool _isLoading = true;
  bool _deepseekSaving = false;

  @override
  void initState() {
    super.initState();
    _loadApiKeys();
  }

  @override
  void dispose() {
    _deepseekApiController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKeys() async {
    setState(() => _isLoading = true);

    final deepseekKeys = await ApiKeyStorageService.getDeepSeekApiKeys();

    _deepseekApiController.clear();

    if (mounted) {
      setState(() {
        _deepseekApiKeys = List.from(deepseekKeys);
        _isLoading = false;
      });
    }
  }

  Future<void> _saveDeepSeekApiKey() async {
    final key = _deepseekApiController.text.trim();
    if (key.isEmpty) return;

    setState(() => _deepseekSaving = true);
    await ApiKeyStorageService.addApiKey('deepseek', key);
    _deepseekApiController.clear();
    await _loadApiKeys();
    if (mounted) {
      setState(() => _deepseekSaving = false);
      showAppToast(
        context,
        message: 'DeepSeek API key saved',
        type: ToastificationType.success,
      );
    }
  }

  Future<void> _deleteApiKey(String service, String key) async {
    final authenticated = await _confirmDelete(context, service);
    if (!authenticated) return;

    if (service == 'deepseek') {
      final updated = _deepseekApiKeys.where((k) => k != key).toList();
      await ApiKeyStorageService.saveApiKeys('deepseek', updated);
    }

    await _loadApiKeys();
    if (mounted) {
      showAppToast(
        context,
        message: 'API key deleted',
        type: ToastificationType.success,
      );
    }
  }

  Future<bool> _confirmDelete(BuildContext context, String service) async {
    final theme = Theme.of(context);
    return await ResponsiveInfoSheet.show<bool>(
          context,
          title: 'Delete $service API Key?',
          headerIcon: Icon(
            CupertinoIcons.trash,
            size: 30,
            color: AppTheme.readableOn(theme.colorScheme.error),
          ),
          gradientColors: [
            theme.colorScheme.error,
            theme.colorScheme.error.withValues(alpha: 0.78),
          ],
          contentWidgets: [
            Text(
              'This will remove the API key. You will need to re-enter it to use $service.',
              style: AppTheme.bodyMedium.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface,
                        foregroundColor: theme.colorScheme.onSurface,
                        elevation: 0,
                        side: BorderSide(color: theme.colorScheme.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ) ??
        false;
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
        title: const Text('API Keys'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildApiKeySection(
                  theme,
                  service: 'deepseek',
                  title: 'DeepSeek',
                  icon: 'assets/icons/deepseek.svg',
                  controller: _deepseekApiController,
                  keys: _deepseekApiKeys,
                  obscure: _deepseekObscure,
                  saving: _deepseekSaving,
                  onToggleObscure: () =>
                      setState(() => _deepseekObscure = !_deepseekObscure),
                  onSave: _saveDeepSeekApiKey,
                  onDelete: (key) => _deleteApiKey('deepseek', key),
                  hintText: 'Enter DeepSeek API key',
                ),
              ],
            ),
    );
  }

  Widget _buildApiKeySection(
    ThemeData theme, {
    required String service,
    required String title,
    required String icon,
    required TextEditingController controller,
    required List<String> keys,
    required bool obscure,
    required bool saving,
    required VoidCallback onToggleObscure,
    required VoidCallback onSave,
    required void Function(String key) onDelete,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SvgPicture.asset(
              icon,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                theme.colorScheme.primary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: AppTheme.headingSmall.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (keys.isNotEmpty) ...[
          ...keys.map(
            (key) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  color: theme.colorScheme.surface,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        key,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        CupertinoIcons.trash,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                      onPressed: () => onDelete(key),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              flex: 4,
              child: TextField(
                controller: controller,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                    fontSize: 13,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1,
                    ),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => onSave(),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 48,
                child: IconButton(
                  onPressed: saving ? null : onSave,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(CupertinoIcons.check_mark),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
