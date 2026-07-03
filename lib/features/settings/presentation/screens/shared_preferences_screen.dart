import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';

class SharedPreferencesScreen extends StatefulWidget {
  const SharedPreferencesScreen({super.key});

  @override
  State<SharedPreferencesScreen> createState() =>
      _SharedPreferencesScreenState();
}

class _SharedPreferencesScreenState extends State<SharedPreferencesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<_SharedPreferenceItem> _items = const [];
  String _query = '';
  bool _isLoading = true;
  bool _isSearchMode = false;

  List<_SharedPreferenceItem> get _filteredItems {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items
        .where(
          (item) =>
              item.key.toLowerCase().contains(query) ||
              item.typeLabel.toLowerCase().contains(query) ||
              item.previewValue.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final prefs = SharedPrefsService.instance;
    final keys = prefs.getKeys().toList()..sort();
    final items = keys
        .map((key) => _SharedPreferenceItem(key: key, value: prefs.get(key)))
        .toList(growable: false);

    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<bool?> _showDeleteDialog(_SharedPreferenceItem item) async {
    final theme = Theme.of(context);
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Delete Preference',
      headerIcon: Icon(
        CupertinoIcons.trash_fill,
        color: theme.colorScheme.onPrimary,
        size: 28,
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.error.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Delete "${item.key}"?',
          style: AppTheme.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This removes the stored value from SharedPreferences. App features using this key may reset to their defaults.',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(color: theme.colorScheme.outline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Delete'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteItem(_SharedPreferenceItem item) async {
    await SharedPrefsService.instance.remove(item.key);
    if (!mounted) return;
    setState(() {
      _items = _items.where((i) => i.key != item.key).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredItems = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: _isSearchMode
            ? _buildSearchField()
            : Text('Shared Preferences (${_items.length})'),
        actions: _isSearchMode
            ? [
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => setState(() {
                    _isSearchMode = false;
                    _searchController.clear();
                    _query = '';
                  }),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(CupertinoIcons.search),
                  onPressed: () => setState(() => _isSearchMode = true),
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredItems.isEmpty
          ? _buildEmpty(theme)
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: filteredItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = filteredItems[index];
                return _buildDismissibleItem(item, theme);
              },
            ),
    );
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      autofocus: true,
      onChanged: (value) => setState(() => _query = value),
      style: AppTheme.bodyLarge.copyWith(
        color: theme.colorScheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Search preferences',
        hintStyle: AppTheme.bodyLarge.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
      ),
    );
  }

  Widget _buildDismissibleItem(_SharedPreferenceItem item, ThemeData theme) {
    return Dismissible(
      key: Key(item.key),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _showDeleteDialog(item),
      onDismissed: (_) => _deleteItem(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          CupertinoIcons.trash_fill,
          color: theme.colorScheme.onError,
          size: 22,
        ),
      ),
      child: _buildPreferenceCard(item, theme),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.doc_text_search,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            _items.isEmpty ? 'No shared preferences found' : 'No matches found',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _items.isEmpty
                ? 'Stored app preferences will appear here.'
                : 'Try a different key, type, or value search.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceCard(_SharedPreferenceItem item, ThemeData theme) {
    final typeColor = _prefTypeColor(item.typeLabel, theme);

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _PreferenceDetailScreen(item: item),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    item.typeLabel.toUpperCase(),
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.key,
                      style: AppTheme.headingSmall.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatCompactCount(item.valueLength),
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.previewValue,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.35,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferenceDetailScreen extends StatelessWidget {
  final _SharedPreferenceItem item;

  const _PreferenceDetailScreen({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _prefTypeColor(item.typeLabel, theme);
    final displayValue = item.displayValue;
    final visibleValue = item.detailVisibleValue;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Preference Detail'),
        actions: [
          IconButton(
            tooltip: 'Copy value',
            icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: displayValue));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Row(
            children: [
              Text(
                item.typeLabel.toUpperCase(),
                style: TextStyle(
                  color: typeColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.valueLength} characters',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.key,
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          if (item.isDetailTruncated) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Text(
                'Large value previewed for smooth scrolling. Use the copy button to copy the full value.',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
            ),
            child: SelectableText(
              visibleValue,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 12,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _prefTypeColor(String type, ThemeData theme) {
  switch (type) {
    case 'bool':
      return const Color.fromARGB(255, 47, 161, 255);
    case 'int':
    case 'double':
      return const Color.fromARGB(255, 15, 201, 21);
    case 'list':
      return const Color.fromARGB(255, 220, 66, 247);
    case 'string':
      return const Color.fromARGB(255, 223, 142, 21);
    default:
      return theme.colorScheme.primary;
  }
}

String _formatCompactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}

class _SharedPreferenceItem {
  final String key;
  final Object? value;

  const _SharedPreferenceItem({required this.key, required this.value});

  String get typeLabel {
    final raw = value;
    if (raw is bool) return 'bool';
    if (raw is int) return 'int';
    if (raw is double) return 'double';
    if (raw is List<String>) return 'list';
    if (raw is String) return 'string';
    return 'unknown';
  }

  String get rawValue {
    final raw = value;
    if (raw is List<String>) return raw.join('\n');
    return raw?.toString() ?? 'null';
  }

  int get valueLength => rawValue.length;

  String get previewValue {
    final raw = rawValue.replaceAll('\n', ' ');
    if (raw.length <= 180) return raw;
    return '${raw.substring(0, 180)}...';
  }

  String get displayValue {
    final raw = value;
    if (raw is List<String>) {
      return const JsonEncoder.withIndent('  ').convert(raw);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
        } catch (_) {
          return raw;
        }
      }
      return raw;
    }
    return raw?.toString() ?? 'null';
  }

  bool get isDetailTruncated => displayValue.length > 20000;

  String get detailVisibleValue {
    final value = displayValue;
    if (value.length <= 20000) return value;
    return '${value.substring(0, 20000)}\n\n... truncated preview ...';
  }
}
