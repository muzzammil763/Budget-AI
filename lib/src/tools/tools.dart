import 'dart:async';

import 'package:budget_ai/src/tools/finance_add.dart';
import 'package:budget_ai/src/tools/finance_delete.dart';
import 'package:budget_ai/src/tools/finance_income_add.dart';
import 'package:budget_ai/src/tools/finance_list.dart';
import 'package:budget_ai/src/tools/finance_summary.dart';
import 'package:budget_ai/src/tools/finance_update.dart';
import 'package:flutter/foundation.dart';

enum ToolDefinitionContext { standard }

typedef ToolHandler = Future<dynamic> Function(Map<String, dynamic>);

class ToolDefinition {
  ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final ToolHandler handler;

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };

  Map<String, dynamic> toResponsesJson() => {
    'type': 'function',
    'name': name,
    'description': description,
    'parameters': parameters,
    'strict': false,
  };
}

class ToolExecutionEvent {
  const ToolExecutionEvent({
    required this.result,
    this.isComplete = false,
    this.isError = false,
  });

  final dynamic result;
  final bool isComplete;
  final bool isError;
}

class ToolRegistry
    with
        FinanceAddToolHandler,
        FinanceIncomeAddToolHandler,
        FinanceListToolHandler,
        FinanceSummaryToolHandler,
        FinanceUpdateToolHandler,
        FinanceDeleteToolHandler {
  List<ToolDefinition> getAvailableTools() {
    return List.unmodifiable([
      buildFinanceAddTool(handler: handleFinanceAddRequest),
      buildFinanceListTool(handler: handleFinanceListRequest),
      buildFinanceIncomeAddTool(handler: handleFinanceIncomeAddRequest),
      buildFinanceSummaryTool(handler: handleFinanceSummaryRequest),
      buildFinanceUpdateTool(handler: handleFinanceUpdateRequest),
      buildFinanceDeleteTool(handler: handleFinanceDeleteRequest),
    ]);
  }

  Future<dynamic> executeTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    debugPrint('[ToolRegistry] Executing tool: $name with args: $arguments');

    final tool = getAvailableTools().firstWhere(
      (tool) => tool.name == name,
      orElse: () => throw Exception('Tool not found: $name'),
    );

    try {
      final result = await tool.handler(arguments);
      debugPrint('[ToolRegistry] Tool $name result: $result');
      return result;
    } catch (error) {
      return {'error': error.toString(), 'tool': name};
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
}
