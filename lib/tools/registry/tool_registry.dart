import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/tool_modules.dart';

class ToolRegistry
    with
        FinanceAddToolHandler,
        FinanceIncomeAddToolHandler,
        FinanceListToolHandler,
        FinanceSummaryToolHandler,
        FinanceUpdateToolHandler,
        FinanceDeleteToolHandler,
        LoanToolHandler {
  List<ToolDefinition>? _toolsCache;

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

  List<ToolDefinition> getAvailableTools() {
    _toolsCache ??= _buildTools();
    return _filterEnabledTools(_toolsCache!);
  }

  List<ToolDefinition> _filterEnabledTools(List<ToolDefinition> tools) {
    return tools;
  }

  List<ToolDefinition> _buildTools() {
    return List.unmodifiable([
      buildFinanceAddTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceAddRequest,
      ),
      buildFinanceListTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceListRequest,
      ),
      buildFinanceIncomeAddTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceIncomeAddRequest,
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
      buildLoanAddTool(
        context: ToolDefinitionContext.standard,
        handler: handleLoanAddRequest,
      ),
      buildLoanPaymentAddTool(
        context: ToolDefinitionContext.standard,
        handler: handleLoanPaymentAddRequest,
      ),
      buildLoanUpdateTool(
        context: ToolDefinitionContext.standard,
        handler: handleLoanUpdateRequest,
      ),
      buildLoanPaymentUpdateTool(
        context: ToolDefinitionContext.standard,
        handler: handleLoanPaymentUpdateRequest,
      ),
      buildLoanPaymentDeleteTool(
        context: ToolDefinitionContext.standard,
        handler: handleLoanPaymentDeleteRequest,
      ),
      buildLoanDeleteTool(
        context: ToolDefinitionContext.standard,
        handler: handleLoanDeleteRequest,
      ),
      buildLoanListTool(
        context: ToolDefinitionContext.standard,
        handler: handleLoanListRequest,
      ),
    ]);
  }

  Future<dynamic> executeTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
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
    Map<String, dynamic> arguments,
  ) async* {
    final result = await executeTool(name, arguments);
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
