import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/settings/admin_service.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<List<AdminUserInfo>> _users = AdminService.instance.listUsers();

  Future<void> _reload() async {
    setState(() => _users = AdminService.instance.listUsers());
    await _users;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Admin Controls')),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _actionTile(
            icon: CupertinoIcons.device_phone_portrait,
            title: 'Local Preferences',
            subtitle: 'Inspect or delete settings stored on this device',
            onTap: _showLocalPreferences,
          ),
          const SizedBox(height: 16),
          Text('Users', style: AppTheme.headingSmall),
          const SizedBox(height: 8),
          FutureBuilder<List<AdminUserInfo>>(
            future: _users,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Text('Could not load users: ${snapshot.error}');
              }
              return Column(
                children: [for (final user in snapshot.data!) _userTile(user)],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
      onTap: onTap,
    ),
  );

  Widget _userTile(AdminUserInfo user) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      title: Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${user.role.label} · Requests ${(user.requestsFraction * 100).round()}%'
        ' · Tokens ${(user.tokensFraction * 100).round()}%\n'
        'Fast ${user.fastRequestsUsed}/${user.fastRequestsLimit}'
        '${user.aiEnabled ? '' : ' · AI BLOCKED'}',
      ),
      isThreeLine: true,
      trailing: Icon(
        user.aiEnabled
            ? CupertinoIcons.chevron_right
            : CupertinoIcons.exclamationmark_octagon_fill,
        color: user.aiEnabled ? null : Theme.of(context).colorScheme.error,
        size: 18,
      ),
      onTap: () => _editUser(user),
    ),
  );

  Future<void> _editUser(AdminUserInfo user) async {
    final requests = TextEditingController(text: '${user.requestsLimit}');
    final tokens = TextEditingController(text: '${user.tokensLimit}');
    final fast = TextEditingController(text: '${user.fastRequestsLimit}');
    var enabled = user.aiEnabled;
    var selectedRole = user.role;
    final isSuperadmin =
        AdminService.instance.role.value == AppUserRole.superadmin;
    final selfId = Supabase.instance.client.auth.currentUser?.id;

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(user.email, style: AppTheme.headingSmall),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI access'),
                  value: enabled,
                  onChanged: (value) => setSheetState(() => enabled = value),
                ),
                _numberField(requests, 'Monthly requests'),
                _numberField(tokens, 'Monthly tokens'),
                _numberField(fast, 'Monthly Fast requests'),
                if (isSuperadmin)
                  DropdownButtonFormField<AppUserRole>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: AppUserRole.values
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(role.label),
                          ),
                        )
                        .toList(),
                    onChanged:
                        selfId == user.id && user.role == AppUserRole.superadmin
                        ? null
                        : (value) => setSheetState(
                            () => selectedRole = value ?? selectedRole,
                          ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Review Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (save != true || !mounted) return;
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Update User?',
      message: 'Apply the new AI access, monthly limits, and role settings?',
      icon: CupertinoIcons.person_crop_circle_badge_checkmark,
      confirmLabel: 'Update',
    );
    if (confirmed != true) return;
    await AdminService.instance.updateUser(
      user.id,
      enabled: enabled,
      requestLimit: int.tryParse(requests.text),
      tokenLimit: int.tryParse(tokens.text),
      fastRequestLimit: int.tryParse(fast.text),
      role: isSuperadmin ? selectedRole : null,
    );
    await _reload();
  }

  Widget _numberField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> _showLocalPreferences() async {
    final sqlite = await LocalSettingsStore.instance.getAll();
    final shared = await SharedPreferencesAsync().getAll();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Local Preferences', style: AppTheme.headingSmall),
            const SizedBox(height: 8),
            for (final entry in {...sqlite, ...shared}.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key),
                subtitle: Text(_displayPreference(entry.key, entry.value)),
                trailing: IconButton(
                  icon: const Icon(CupertinoIcons.delete),
                  onPressed: () => _confirmDeletePreference(entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePreference(String key) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Delete Preference?',
      message: 'Delete “$key” from this device? This can change app behavior.',
      icon: CupertinoIcons.delete,
      confirmLabel: 'Delete',
    );
    if (confirmed != true) return;
    await LocalSettingsStore.instance.remove(key);
    await SharedPreferencesAsync().remove(key);
    if (mounted) Navigator.pop(context);
  }

  String _displayPreference(String key, Object? value) {
    final sensitive = RegExp(
      r'(token|session|secret|password|supabase.*auth)',
      caseSensitive: false,
    ).hasMatch(key);
    return sensitive ? '•••••••• (sensitive value hidden)' : '$value';
  }
}
