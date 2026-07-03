import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/tool_modules.dart';

class ToolCatalog {
  const ToolCatalog._();

  static List<ToolDefinition> build({
    required ToolHandler readHandler,
    required ToolHandler writeHandler,
    required ToolHandler editHandler,
    required ToolHandler webSearchHandler,
    required ToolHandler webPageFetchHandler,
  }) {
    return <ToolDefinition>[
      buildReadTool(
        context: ToolDefinitionContext.standard,
        handler: readHandler,
      ),
      buildEditTool(
        context: ToolDefinitionContext.standard,
        handler: editHandler,
      ),
      buildWriteTool(
        context: ToolDefinitionContext.standard,
        handler: writeHandler,
      ),
      buildWebSearchTool(
        context: ToolDefinitionContext.standard,
        handler: webSearchHandler,
      ),
      buildWebPageFetchTool(
        context: ToolDefinitionContext.standard,
        handler: webPageFetchHandler,
      ),
    ];
  }
}
