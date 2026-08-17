import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/settings/admin_service.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(_rebuild);
    if (AdminService.instance.users.value == null) {
      AdminService.instance.preload();
    }
  }

  @override
  void dispose() {
    _search.removeListener(_rebuild);
    _search.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Admin Controls'),
        actions: [
          IconButton(
            tooltip: 'Refresh users',
            onPressed: () => AdminService.instance.preload(force: true),
            icon: const Icon(CupertinoIcons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => AdminService.instance.preload(force: true),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            _introCard(theme),
            const SizedBox(height: 20),
            _heading(theme, 'DEVICE', 'Local App Data'),
            const SizedBox(height: 8),
            _navCard(
              theme,
              icon: CupertinoIcons.device_phone_portrait,
              title: 'Local Preferences',
              subtitle: 'Inspect or remove settings on this device',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const _LocalPreferencesScreen(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _heading(theme, 'USERS', 'Access & Monthly Limits'),
            const SizedBox(height: 8),
            _searchField(theme),
            const SizedBox(height: 10),
            ValueListenableBuilder<List<AdminUserInfo>?>(
              valueListenable: AdminService.instance.users,
              builder: (context, users, _) {
                if (users == null) return _loadingCards(theme);
                final query = _search.text.trim().toLowerCase();
                final filtered = users
                    .where((user) => user.email.toLowerCase().contains(query))
                    .toList(growable: false);
                if (filtered.isEmpty) return _emptySearch(theme);
                return Column(
                  children: [
                    for (final user in filtered) _userCard(theme, user),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _introCard(ThemeData theme) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: theme.colorScheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.3),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            CupertinoIcons.person_2_fill,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AdminService.instance.role.value.label,
                style: AppTheme.headingSmall.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 3),
              Text(
                'Manage AI access, roles, and monthly allowances.',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _heading(ThemeData theme, String eyebrow, String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: AppTheme.bodySmall.copyWith(
          color: theme.colorScheme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.3,
        ),
      ),
      const SizedBox(height: 3),
      Text(title, style: AppTheme.headingSmall.copyWith(fontSize: 17)),
    ],
  );

  Widget _navCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(CupertinoIcons.chevron_right, size: 16),
        ],
      ),
    ),
  );

  Widget _searchField(ThemeData theme) => TextField(
    controller: _search,
    decoration: InputDecoration(
      hintText: 'Search users by email',
      prefixIcon: const Icon(CupertinoIcons.search),
      suffixIcon: _search.text.isEmpty
          ? null
          : IconButton(
              onPressed: _search.clear,
              icon: const Icon(CupertinoIcons.xmark_circle_fill),
            ),
      filled: true,
      fillColor: theme.colorScheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
    ),
  );

  Widget _userCard(ThemeData theme, AdminUserInfo user) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _editUser(user),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: user.aiEnabled
                ? theme.colorScheme.outline.withValues(alpha: 0.4)
                : theme.colorScheme.error.withValues(alpha: 0.42),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    user.aiEnabled
                        ? CupertinoIcons.person_fill
                        : CupertinoIcons.exclamationmark_octagon_fill,
                    size: 20,
                    color: user.aiEnabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        user.aiEnabled
                            ? user.role.label
                            : '${user.role.label} · AI Blocked',
                        style: AppTheme.bodySmall.copyWith(
                          color: user.aiEnabled
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_right, size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quota(theme, 'Requests', user.requestsFraction),
                ),
                const SizedBox(width: 10),
                Expanded(child: _quota(theme, 'Tokens', user.tokensFraction)),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _quota(ThemeData theme, String label, double fraction) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.bodySmall),
          Text(
            '${(fraction * 100).round()}%',
            style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      const SizedBox(height: 5),
      LinearProgressIndicator(
        value: fraction,
        minHeight: 5,
        borderRadius: BorderRadius.circular(8),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
    ],
  );

  Widget _loadingCards(ThemeData theme) => Column(
    children: List.generate(
      3,
      (_) => Container(
        height: 112,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );

  Widget _emptySearch(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Column(
      children: [
        Icon(
          CupertinoIcons.search,
          size: 38,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 10),
        Text('No users found', style: AppTheme.headingSmall),
      ],
    ),
  );

  Future<void> _editUser(AdminUserInfo user) async {
    final updated = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Manage User',
      headerIcon: Icon(
        CupertinoIcons.person_crop_circle_badge_checkmark,
        size: 30,
        color: AppTheme.readableOn(Theme.of(context).colorScheme.primary),
      ),
      gradientColors: [
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [_UserEditor(user: user)],
    );
    if (updated == true) await AdminService.instance.listUsers();
  }
}

class _UserEditor extends StatefulWidget {
  const _UserEditor({required this.user});
  final AdminUserInfo user;

  @override
  State<_UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends State<_UserEditor> {
  late final TextEditingController _requests;
  late final TextEditingController _tokens;
  late final TextEditingController _fast;
  late bool _enabled;
  late AppUserRole _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _requests = TextEditingController(text: '${user.requestsLimit}');
    _tokens = TextEditingController(text: '${user.tokensLimit}');
    _fast = TextEditingController(text: '${user.fastRequestsLimit}');
    _enabled = user.aiEnabled;
    _role = user.role;
  }

  @override
  void dispose() {
    _requests.dispose();
    _tokens.dispose();
    _fast.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuperadmin =
        AdminService.instance.role.value == AppUserRole.superadmin;
    final cannotDemoteSelf =
        Supabase.instance.client.auth.currentUser?.id == widget.user.id &&
        widget.user.role == AppUserRole.superadmin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.user.email,
          textAlign: TextAlign.center,
          style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: SwitchListTile.adaptive(
            title: const Text('AI access'),
            subtitle: Text(
              _enabled
                  ? 'Chat requests are allowed'
                  : 'Chat requests are blocked',
            ),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
        ),
        const SizedBox(height: 12),
        _field(_requests, 'Monthly requests', CupertinoIcons.bolt),
        const SizedBox(height: 10),
        _field(_tokens, 'Monthly tokens', CupertinoIcons.textformat_123),
        const SizedBox(height: 10),
        _field(_fast, 'Monthly Fast requests', CupertinoIcons.bolt_fill),
        if (isSuperadmin) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<AppUserRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Account role'),
            items: AppUserRole.values
                .map(
                  (role) =>
                      DropdownMenuItem(value: role, child: Text(role.label)),
                )
                .toList(),
            onChanged: cannotDemoteSelf
                ? null
                : (value) => setState(() => _role = value ?? _role),
          ),
        ],
        const SizedBox(height: 16),
        AppButton(text: 'Review & Save', isLoading: _saving, onPressed: _save),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon,
  ) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );

  Future<void> _save() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Update User?',
      message: 'Apply these AI access, monthly limit, and role settings?',
      icon: CupertinoIcons.check_mark_circled_solid,
      confirmLabel: 'Update',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await AdminService.instance.updateUser(
        widget.user.id,
        enabled: _enabled,
        requestLimit: int.tryParse(_requests.text),
        tokenLimit: int.tryParse(_tokens.text),
        fastRequestLimit: int.tryParse(_fast.text),
        role: AdminService.instance.role.value == AppUserRole.superadmin
            ? _role
            : null,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LocalPreferencesScreen extends StatefulWidget {
  const _LocalPreferencesScreen();

  @override
  State<_LocalPreferencesScreen> createState() =>
      _LocalPreferencesScreenState();
}

class _LocalPreferencesScreenState extends State<_LocalPreferencesScreen> {
  late Future<Map<String, Object?>> _preferences = _load();

  Future<Map<String, Object?>> _load() async => {
    ...await LocalSettingsStore.instance.getAll(),
    ...await SharedPreferencesAsync().getAll(),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: Navigator.of(context).pop,
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      ),
      title: const Text('Local Preferences'),
    ),
    body: FutureBuilder<Map<String, Object?>>(
      future: _preferences,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            Text(
              'Only preferences stored on this device are shown. Sensitive values stay hidden.',
              style: AppTheme.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in entries) _preferenceCard(entry),
          ],
        );
      },
    ),
  );

  Widget _preferenceCard(MapEntry<String, Object?> entry) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _display(entry.key, entry.value),
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete preference',
            onPressed: () => _delete(entry.key),
            icon: Icon(CupertinoIcons.delete, color: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }

  String _display(String key, Object? value) =>
      RegExp(
        r'(token|session|secret|password|supabase.*auth)',
        caseSensitive: false,
      ).hasMatch(key)
      ? '•••••••• (sensitive value hidden)'
      : '$value';

  Future<void> _delete(String key) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Delete Preference?',
      message: 'Delete “$key” from this device? This can change app behavior.',
      icon: CupertinoIcons.delete,
      confirmLabel: 'Delete',
      isRed: true,
    );
    if (confirmed != true) return;
    await LocalSettingsStore.instance.remove(key);
    await SharedPreferencesAsync().remove(key);
    if (mounted) setState(() => _preferences = _load());
  }
}
