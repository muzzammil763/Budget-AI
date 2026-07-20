import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Bottom sheet for picking the chat model, shared by the chat screen's
/// model button and the settings screen tile. Resolves with the picked
/// model id, or null when dismissed.
class ModelPickerSheet {
  const ModelPickerSheet._();

  /// Short tier badge for GPT-5.6 family models, or null.
  static String? badgeForModelId(String modelId) {
    final id = modelId.toLowerCase();
    if (id.endsWith('-luna')) return 'VALUE';
    if (id.endsWith('-terra')) return 'BALANCED';
    if (id.endsWith('-sol')) return 'FRONTIER';
    return null;
  }

  static Future<String?> show(
    BuildContext context, {
    required String selectedModel,
  }) {
    final theme = Theme.of(context);
    const models = AIModels.openAIModels;

    return ResponsiveInfoSheet.show<String>(
      context,
      title: 'Choose Model',
      headerIcon: Icon(
        CupertinoIcons.slider_horizontal_3,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        for (var i = 0; i < models.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildModelOption(
            context,
            theme,
            models[i],
            models[i].id == selectedModel,
          ),
        ],
      ],
    );
  }

  static Widget _buildModelOption(
    BuildContext context,
    ThemeData theme,
    AIModel model,
    bool isSelected,
  ) {
    final badge = badgeForModelId(model.id);
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: () => Navigator.pop(context, model.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                size: 24,
                color: isSelected
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
                            borderRadius: BorderRadius.circular(100),
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
