import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/pill_nav_bar.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/tools/settings/tool_settings.dart';
import 'package:budget_ai/tools/settings/tool_name_formatter.dart';

class ToolManagerScreen extends StatefulWidget {
  const ToolManagerScreen({super.key});

  @override
  State<ToolManagerScreen> createState() => _ToolManagerScreenState();
}

class _ToolManagerScreenState extends State<ToolManagerScreen> {
  late Map<String, bool> _enabledTools;
  late Map<String, ToolAccessMode> _accessModes;
  bool _isSearchMode = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _reloadState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadState() {
    _enabledTools = {
      for (final tool in _allTools)
        tool.name: ToolSettings.isIndividualToolEnabled(tool.name),
    };
    _accessModes = {
      for (final tool in _allTools)
        tool.name: ToolSettings.accessModeForTool(tool.name),
    };
  }

  List<ToolItemDefinition> get _allTools {
    final tools = [...ToolSettings.tools];
    tools.sort((a, b) {
      final left = formatToolNameForUi(a.name).toLowerCase();
      final right = formatToolNameForUi(b.name).toLowerCase();
      final byTitle = left.compareTo(right);
      return byTitle == 0 ? a.name.compareTo(b.name) : byTitle;
    });
    return tools;
  }

  int get _enabledToolCount {
    return _allTools.where((tool) => _enabledTools[tool.name] == true).length;
  }

  int get _totalToolCount => _allTools.length;

  bool get _hasChanges {
    return _allTools.any((tool) => !ToolSettings.isToolAtDefault(tool.name));
  }

  Future<void> _setToolEnabled(ToolItemDefinition tool, bool value) async {
    setState(() => _enabledTools[tool.name] = value);
    await ToolSettings.setIndividualToolEnabled(tool.name, value);
    if (mounted) setState(() {});
  }

  Future<void> _setToolAccessMode(
    ToolItemDefinition tool,
    ToolAccessMode mode,
  ) async {
    setState(() => _accessModes[tool.name] = mode);
    await ToolSettings.setToolAccessMode(tool.name, mode);
    if (mounted) setState(() {});
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await _showResetDialog();
    if (confirmed != true) return;

    for (final tool in ToolSettings.tools) {
      await ToolSettings.resetToolToDefault(tool.name);
    }

    if (!mounted) return;
    setState(_reloadState);
  }

  Future<bool?> _showResetDialog() {
    return ResponsiveInfoSheet.confirm(
      context,
      title: 'Reset Tool Defaults',
      message:
          'This will restore all tool enablement and access modes to their default settings.',
      icon: CupertinoIcons.arrow_counterclockwise,
      confirmLabel: 'Reset',
    );
  }

  List<ToolItemDefinition> get _visibleTools {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _allTools;
    return ToolSettings.tools.where((tool) {
      return tool.title.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query) ||
          tool.name.toLowerCase().contains(query);
    }).toList()..sort((a, b) {
      final left = formatToolNameForUi(a.name).toLowerCase();
      final right = formatToolNameForUi(b.name).toLowerCase();
      final byTitle = left.compareTo(right);
      return byTitle == 0 ? a.name.compareTo(b.name) : byTitle;
    });
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      autofocus: true,
      onChanged: (value) => setState(() => _searchQuery = value),
      style: AppTheme.bodyLarge.copyWith(
        color: theme.colorScheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Search tools',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleTools = _visibleTools;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: _isSearchMode
            ? _buildSearchField()
            : Text('Tool Manager ($_enabledToolCount/$_totalToolCount)'),
        actions: _isSearchMode
            ? [
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => setState(() {
                    _isSearchMode = false;
                    _searchController.clear();
                    _searchQuery = '';
                  }),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(CupertinoIcons.search),
                  onPressed: () => setState(() => _isSearchMode = true),
                ),
                if (_hasChanges)
                  IconButton(
                    tooltip: 'Reset defaults',
                    onPressed: _resetToDefaults,
                    icon: const Icon(
                      CupertinoIcons.arrow_counterclockwise,
                      size: 20,
                    ),
                  ),
              ],
      ),
      body: visibleTools.isEmpty
          ? _buildEmpty(theme)
          : _buildList(theme, visibleTools),
    );
  }

  Widget _buildList(ThemeData theme, List<ToolItemDefinition> visibleTools) {
    return CustomScrollView(
      scrollCacheExtent: const ScrollCacheExtent.pixels(300),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          sliver: SliverList.separated(
            itemCount: visibleTools.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
            itemBuilder: (context, index) {
              final tool = visibleTools[index];
              return RepaintBoundary(
                child: _ToolRow(
                  tool: tool,
                  enabled: _enabledTools[tool.name] ?? true,
                  accessMode: _accessModes[tool.name] ?? tool.defaultAccessMode,
                  onEnabledChanged: (value) => _setToolEnabled(tool, value),
                  onAccessChanged: (mode) => _setToolAccessMode(tool, mode),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.search,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          Text(
            'No tools found',
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term.',
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

}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.tool,
    required this.enabled,
    required this.accessMode,
    required this.onEnabledChanged,
    required this.onAccessChanged,
  });

  final ToolItemDefinition tool;
  final bool enabled;
  final ToolAccessMode accessMode;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<ToolAccessMode> onAccessChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accessColor = _accessColor(accessMode);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                accessMode.label.toUpperCase(),
                style: TextStyle(
                  color: accessColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatToolNameForUi(tool.name),
                  style: AppTheme.headingSmall.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(value: enabled, onChanged: onEnabledChanged),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${tool.description} • ${tool.name}',
            style: AppTheme.bodySmall.copyWith(color: muted, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          NavBar(
            items: const [
              NavBarItem(
                label: 'Approval Required',
                selectedIcon: CupertinoIcons.lock,
                unselectedIcon: CupertinoIcons.lock,
              ),
              NavBarItem(
                label: 'Full Access',
                selectedIcon: CupertinoIcons.lock_open,
                unselectedIcon: CupertinoIcons.lock_open,
              ),
            ],
            initialIndex: accessMode == ToolAccessMode.approvalRequired ? 0 : 1,
            onIndexChanged: (index) => onAccessChanged(
              index == 0 ? ToolAccessMode.approvalRequired : ToolAccessMode.fullAccess,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            topMargin: 0,
          ),
        ],
      ),
    );
  }

  static Color _accessColor(ToolAccessMode mode) {
    switch (mode) {
      case ToolAccessMode.approvalRequired:
        return const Color.fromARGB(255, 223, 142, 21);
      case ToolAccessMode.fullAccess:
        return const Color.fromARGB(255, 47, 161, 255);
    }
  }
}
