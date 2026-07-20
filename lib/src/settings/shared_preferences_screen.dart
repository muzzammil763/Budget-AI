import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesScreen extends StatefulWidget {
  const SharedPreferencesScreen({super.key});

  @override
  State<SharedPreferencesScreen> createState() =>
      _SharedPreferencesScreenState();
}

class _SharedPreferencesScreenState extends State<SharedPreferencesScreen> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  late Future<Map<String, Object?>> _entries = _loadEntries();

  Future<Map<String, Object?>> _loadEntries() async {
    final entries = await _preferences.getAll();
    return Map.fromEntries(
      entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  Future<void> _refresh() async {
    setState(() => _entries = _loadEntries());
    await _entries;
  }

  Future<void> _delete(String key) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Delete preference?',
      message: 'Delete “$key”? This change cannot be undone.',
      icon: CupertinoIcons.trash,
      confirmLabel: 'Delete',
    );
    if (confirmed != true) return;

    await _preferences.remove(key);
    if (mounted) await _refresh();
  }

  String _valueText(Object? value) {
    if (value is List<String>) return value.join(', ');
    return value?.toString() ?? 'null';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Preferences'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(CupertinoIcons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, Object?>>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load preferences: ${snapshot.error}'),
              ),
            );
          }

          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('No shared preferences saved.'));
          }

          return ListView.separated(
            
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {

              final entry = entries.entries.elementAt(index);
              return ListTile(
                title: Text(
                  entry.key,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${entry.value.runtimeType}: ${_valueText(entry.value)}',
                ),
                trailing: IconButton(
                  tooltip: 'Delete ${entry.key}',
                  onPressed: () => _delete(entry.key),
                  icon: Icon(
                    CupertinoIcons.trash,
                    color: theme.colorScheme.error,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
