import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full screen for picking the chat model. Applies the selection in place
/// and pops, matching the currency and bubble style pickers.
class ModelPickerScreen extends StatelessWidget {
  const ModelPickerScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const ModelPickerScreen()));
  }

  /// Short tier badge for GPT-5.6 family models, or null.
  static String? badgeForModelId(String modelId) {
    final id = modelId.toLowerCase();
    if (id.endsWith('-luna')) return 'VALUE';
    if (id.endsWith('-terra')) return 'BALANCED';
    if (id.endsWith('-sol')) return 'FRONTIER';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Choose Model'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const _ModelPickerContent(),
          ),
        ),
      ),
    );
  }
}

class _ModelPickerContent extends StatelessWidget {
  const _ModelPickerContent();

  Future<void> _select(BuildContext context, String modelId) async {
    if (ModelSettingsService.instance.current == modelId) {
      Navigator.of(context).pop();
      return;
    }
    HapticFeedback.selectionClick();
    await ModelSettingsService.instance.setModel(modelId);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const models = AIModels.openAIModels;
    return ValueListenableBuilder<String>(
      valueListenable: ModelSettingsService.instance.modelId,
      builder: (context, selectedId, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Choose which OpenAI model powers your chat. Higher tiers are '
              'more capable; lighter tiers are faster and cheaper.',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final model in models)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ModelOption(
                model: model,
                selected: model.id == selectedId,
                onTap: () => _select(context, model.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelOption extends StatelessWidget {
  const _ModelOption({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final AIModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = ModelPickerScreen.badgeForModelId(model.id);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                size: 24,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyMedium.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            badge,
                            style: AppTheme.bodySmall.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    model.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  if (model.contextLength != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Context: ${_formatContext(model.contextLength!)}',
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatContext(int length) {
    if (length >= 1000000) {
      return '${(length / 1000000).toStringAsFixed(length % 1000000 == 0 ? 0 : 1)} M';
    }
    return '${(length / 1000).round()} K';
  }
}
