import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';
import 'package:toastification/toastification.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  List<MemoryItem> _memories = [];
  bool _isLoading = true;
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  List<MemoryItem> get _filteredMemories {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _memories;
    return _memories
        .where(
          (m) =>
              m.title.toLowerCase().contains(query) ||
              m.content.toLowerCase().contains(query) ||
              m.key.toLowerCase().contains(query) ||
              m.type.toLowerCase().contains(query),
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
    MemoryService.instance.invalidateCache();
    final memories = await MemoryService.instance.getAll();
    if (mounted) {
      setState(() {
        _memories = List.from(memories);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filteredMemories = _filteredMemories;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: _isSearchMode
            ? _buildSearchField()
            : Text('Memories'),
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
          : filteredMemories.isEmpty
          ? _buildEmpty(theme)
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: filteredMemories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _buildDismissibleMemory(filteredMemories[index], theme),
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
        hintText: 'Search memories',
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

  Widget _buildDismissibleMemory(MemoryItem memory, ThemeData theme) {
    return Dismissible(
      key: ValueKey('memory-${memory.id}'),
      direction: DismissDirection.endToStart,
      background: _buildDeleteBackground(theme),
      confirmDismiss: (_) => _confirmAndDeleteMemory(memory),
      onDismissed: (_) => _removeDeletedMemory(memory),
      child: _buildMemoryCard(memory, theme),
    );
  }

  Widget _buildDeleteBackground(ThemeData theme) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(CupertinoIcons.trash, color: theme.colorScheme.onError),
    );
  }

  Future<bool> _confirmAndDeleteMemory(MemoryItem memory) async {
    final theme = Theme.of(context);
    final confirmed = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Delete Memory?',
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
          'Delete "${memory.title}"?',
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
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    if (confirmed != true) return false;

    final deleted = await MemoryService.instance.delete(memory.id);
    if (!mounted) return false;
    if (!deleted) {
      showAppToast(
        context,
        message: 'Memory could not be deleted',
        type: ToastificationType.error,
      );
      return false;
    }

    return true;
  }

  void _removeDeletedMemory(MemoryItem memory) {
    if (!mounted) return;
    setState(() => _memories.removeWhere((item) => item.id == memory.id));
    showAppToast(
      context,
      message: 'Memory deleted',
      type: ToastificationType.success,
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _memories.isEmpty
                ? CupertinoIcons.memories
                : CupertinoIcons.doc_text_search,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            _memories.isEmpty ? 'No memories saved yet' : 'No matches found',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _memories.isEmpty
                ? 'Ask the assistant to remember something\nand it will appear here.'
                : 'Try a different title, content, or key search.',
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

  Widget _buildMemoryCard(MemoryItem memory, ThemeData theme) {
    final typeColor = _typeColor(memory.type, theme);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                memory.type.toUpperCase(),
                style: TextStyle(
                  color: typeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  memory.title,
                  style: AppTheme.headingSmall.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            memory.content,
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                CupertinoIcons.clock,
                size: 11,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _formatDate(memory.updatedAt),
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                'ID: ${memory.id}',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type, ThemeData theme) {
    switch (type.toLowerCase()) {
      case 'preference':
        return const Color.fromARGB(255, 47, 161, 255);
      case 'fact':
        return const Color.fromARGB(255, 15, 201, 21);
      case 'name':
        return const Color.fromARGB(255, 220, 66, 247);
      case 'project':
        return const Color.fromARGB(255, 223, 142, 21);
      case 'instruction':
        return const Color.fromARGB(255, 255, 59, 45);
      default:
        return theme.colorScheme.primary;
    }
  }

  String _formatDate(DateTime dt) {
    final hour = dt.hour == 0
        ? 12
        : dt.hour > 12
        ? dt.hour - 12
        : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
