import 'package:budget_ai/features/chat/domain/models/ai_models.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum _ModelFilter { all, tools, thinking }

class ModelSelectorScreen extends StatefulWidget {
  final String modelType;
  final Color themeColor;
  final String selectedModel;
  final String? iconPath;

  const ModelSelectorScreen({
    super.key,
    required this.modelType,
    required this.themeColor,
    required this.selectedModel,
    this.iconPath,
  });

  @override
  State<ModelSelectorScreen> createState() => _ModelSelectorScreenState();
}

class _ModelSelectorScreenState extends State<ModelSelectorScreen>
    with SingleTickerProviderStateMixin {
  _ModelFilter _activeFilter = _ModelFilter.all;
  bool _isSearchMode = false;
  String _searchQuery = '';
  late final TextEditingController _searchController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _enterSearch() => setState(() => _isSearchMode = true);

  void _exitSearch() => setState(() {
        _isSearchMode = false;
        _searchController.clear();
        _searchQuery = '';
      });

  String _getProviderDisplayName() {
    switch (widget.modelType) {
      case 'deepseek':
        return 'DeepSeek';
      case 'firepass':
        return 'Firepass';
      case 'xiaomimimo':
        return 'Xiaomi';
      default:
        return 'Models';
    }
  }

  List<AIModel> _getFilteredModels() {
    final all = AIModels.getModelsForType(widget.modelType);
    final q = _searchQuery.toLowerCase();

    return all.where((model) {
      if (q.isNotEmpty) {
        final matches = [
          model.name,
          model.description,
          model.id,
        ].any((v) => v.toLowerCase().contains(q));
        if (!matches) return false;
      }
      switch (_activeFilter) {
        case _ModelFilter.all:
          return true;
        case _ModelFilter.tools:
          return model.supportsToolCall;
        case _ModelFilter.thinking:
          return model.supportsThinking;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final models = _getFilteredModels();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: _isSearchMode ? _buildAppBarSearchField() : Text(_getProviderDisplayName()),
        actions: _isSearchMode
            ? [
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: _exitSearch,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(CupertinoIcons.search),
                  onPressed: _enterSearch,
                ),
              ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              // Capability filter chips
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _buildFilterChip(_ModelFilter.all, 'All'),
                    const SizedBox(width: 8),
                    _buildFilterChip(_ModelFilter.tools, 'Tools'),
                    const SizedBox(width: 8),
                    _buildFilterChip(_ModelFilter.thinking, 'Thinking'),
                  ],
                ),
              ),
              // Flat model list
              Expanded(
                child: models.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        itemCount: models.length,
                        itemBuilder: (context, index) =>
                            _buildModelCard(models[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarSearchField() {
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
        hintText: 'Search models',
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

  Widget _buildFilterChip(_ModelFilter filter, String label) {
    final theme = Theme.of(context);
    final isSelected = _activeFilter == filter;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _activeFilter = filter),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelCard(AIModel model) {
    final theme = Theme.of(context);
    final isSelected = model.id == widget.selectedModel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, model.id),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isSelected
                      ? Icon(
                          CupertinoIcons.check_mark_circled_solid,
                          size: 28,
                          color: theme.colorScheme.primary,
                        )
                      : Icon(
                          CupertinoIcons.circle,
                          size: 28,
                          color: theme.colorScheme.outline,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      model.description,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      spacing: 6,
                      children: [
                        _buildInputModalityRow(model),
                        if (model.outputModalities.isNotEmpty) ...[
                          Container(
                            width: 1,
                            height: 12,
                            color: theme.dividerColor,
                          ),
                          _buildOutputModalityRow(model),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (model.supportsThinking)
                          _buildBadge('Thinking'),
                        if (model.supportsToolCall) _buildBadge('Tools'),

                      ],
                    ),
                    if (model.contextLength != null) ...[
                      const SizedBox(height: 6),
                      _buildContextLengthRow(model),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputModalityRow(AIModel model) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'IN',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        _buildModalityIcon(Icons.text_fields_rounded, model.supportsInput('text')),
        _buildModalityIcon(Icons.image_outlined, model.supportsInput('image')),
        _buildModalityIcon(Icons.videocam_outlined, model.supportsInput('video')),
        _buildModalityIcon(Icons.picture_as_pdf_outlined, model.supportsInput('pdf')),
        _buildModalityIcon(Icons.mic_outlined, model.supportsInput('audio')),
      ],
    );
  }

  Widget _buildOutputModalityRow(AIModel model) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'OUT',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        _buildModalityIcon(Icons.text_fields_rounded, model.supportsOutput('text')),
        _buildModalityIcon(Icons.image_outlined, model.supportsOutput('image')),
        _buildModalityIcon(Icons.mic_outlined, model.supportsOutput('audio')),
      ],
    );
  }

  Widget _buildModalityIcon(IconData icon, bool supported) {
    if (!supported) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(icon, size: 12, color: Theme.of(context).colorScheme.primary),
    );
  }

  Widget _buildContextLengthRow(AIModel model) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.memory_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          'Context: ${model.formattedContextLength}',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        if (model.maxOutput != null && model.maxOutput! > 0) ...[
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Max Out: ${_formatTokens(model.maxOutput!)}',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  String _formatTokens(int limit) {
    if (limit >= 1000000) return '${(limit / 1000000).toStringAsFixed(1)}M';
    if (limit >= 1000) return '${(limit / 1000).round()}K';
    return limit.toString();
  }

  Widget _buildBadge(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outline, width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No models found',
              style: AppTheme.bodyLarge.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term.'
                  : 'No models match the selected filter.',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
