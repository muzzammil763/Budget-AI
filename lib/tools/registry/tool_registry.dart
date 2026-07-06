import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/tool_modules.dart';

class ToolRegistry
    with
        MemoryWriteToolHandler,
        MemoryEditToolHandler,
        MemoryDeleteToolHandler,
        MemoryListToolHandler,
        MemorySearchToolHandler,
        FinanceAddToolHandler,
        FinanceListToolHandler,
        FinanceSummaryToolHandler,
        FinanceUpdateToolHandler,
        FinanceDeleteToolHandler {
  List<ToolDefinition>? _toolsCache;

  bool get githubModeActive => false;

  ToolRegistry({Object? dio});

  void setActiveProviderInfo({
    required String modelId,
    required String apiKey,
    required String baseUrl,
  }) {}

  void setActiveMessageImagePaths(List<String>? imagePaths) {
    // No-op for Budget AI (no image attachments)
  }

  void cancelActiveRequests() {
    // No cancellable local tool requests are currently active.
  }

  List<ToolDefinition> getAvailableTools({
    bool includeWorkspaceTools = true,
    bool includeGithubModeTools = false,
  }) {
    _toolsCache ??= _buildTools();
    return _filterEnabledTools(_toolsCache!);
  }

  List<ToolDefinition> _filterEnabledTools(List<ToolDefinition> tools) {
    return tools;
  }

  List<ToolDefinition> _buildTools() {
    return List.unmodifiable([
      buildMemoryWriteTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryWriteRequest,
      ),
      buildMemoryEditTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryEditRequest,
      ),
      buildMemoryDeleteTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryDeleteRequest,
      ),
      buildMemoryListTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryListRequest,
      ),
      buildMemorySearchTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemorySearchRequest,
      ),
      buildFinanceAddTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceAddRequest,
      ),
      buildFinanceListTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceListRequest,
      ),
      buildFinanceSummaryTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceSummaryRequest,
      ),
      buildFinanceUpdateTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceUpdateRequest,
      ),
      buildFinanceDeleteTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceDeleteRequest,
      ),
    ]);
  }

  Future<dynamic> executeTool(
    String name,
    Map<String, dynamic> arguments, {
    bool bypassToolManagerApproval = false,
  }) async {
    debugPrint('[ToolRegistry] Executing tool: $name with args: $arguments');

    final disabledResult = _disabledToolResult(name);
    if (disabledResult != null) {
      return disabledResult;
    }

    final tool = _filterEnabledTools(_toolsCache ?? _buildTools()).firstWhere(
      (t) => t.name == name,
      orElse: () => throw Exception('Tool not found: $name'),
    );

    if (tool.handler == null) {
      throw Exception('Tool $name has no handler');
    }

    try {
      final result = await tool.handler!(arguments);
      debugPrint('[ToolRegistry] Tool $name result: $result');
      return result;
    } catch (e) {
      return {'error': e.toString(), 'tool': name};
    }
  }

  Stream<ToolExecutionEvent> executeToolStream(
    String name,
    Map<String, dynamic> arguments, {
    bool bypassToolManagerApproval = false,
  }) async* {
    final result = await executeTool(
      name,
      arguments,
      bypassToolManagerApproval: bypassToolManagerApproval,
    );
    yield ToolExecutionEvent(
      result: result,
      isComplete: true,
      isError: result is Map && result['error'] != null,
    );
  }

  Map<String, dynamic>? _disabledToolResult(String name) {
    return null;
  }
}
