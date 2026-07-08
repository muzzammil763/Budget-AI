import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/src/finances/finance_service.dart';

ToolDefinition buildFinanceUpdateTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_update',
  description:
      'Edit an existing finance entry by ID, including income or expense entries. Use finance_list first if you need to find the ID. Only provided fields are changed.',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': 'Finance entry ID.'},
      'description': {'type': 'string'},
      'amount': {'type': 'number'},
      'category': {'type': 'string'},
      'date': {
        'type': 'string',
        'description': 'Date in ISO 8601 format (YYYY-MM-DD).',
      },
      'time': {
        'type': 'string',
        'description':
            'Time in HH:MM 24-hour format. Omit to preserve current time setting.',
      },
      'clear_time': {'type': 'boolean'},
    },
    'required': ['id'],
  },
  handler: handler,
);

mixin FinanceUpdateToolHandler {
  Future<dynamic> handleFinanceUpdateRequest(Map<String, dynamic> args) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return {'error': 'id is required'};

    try {
      final entries = await FinanceService.instance.getAll();
      final index = entries.indexWhere((entry) => entry.id == id);
      if (index < 0) return {'ok': false, 'error': 'Finance entry not found'};
      final existing = entries[index];

      var date = existing.date;
      var hasTime = existing.hasTime;
      final dateStr = (args['date'] as String? ?? '').trim();
      final timeStr = (args['time'] as String? ?? '').trim();
      if (dateStr.isNotEmpty) {
        final parsed = DateTime.tryParse(dateStr);
        if (parsed != null) {
          date = DateTime(
            parsed.year,
            parsed.month,
            parsed.day,
            hasTime ? existing.date.hour : 0,
            hasTime ? existing.date.minute : 0,
          );
        }
      }
      if (args['clear_time'] == true) {
        date = DateTime(date.year, date.month, date.day);
        hasTime = false;
      } else if (timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? date.hour;
          final minute = int.tryParse(parts[1]) ?? date.minute;
          date = DateTime(date.year, date.month, date.day, hour, minute);
          hasTime = true;
        }
      }

      final updated = existing.copyWith(
        date: date,
        hasTime: hasTime,
        description: (args['description'] as String?)?.trim().isNotEmpty == true
            ? (args['description'] as String).trim()
            : null,
        amount: (args['amount'] as num?)?.toDouble(),
        category: (args['category'] as String?)?.trim().isNotEmpty == true
            ? (args['category'] as String).trim()
            : null,
      );
      final saved = await FinanceService.instance.update(updated);
      return {
        'ok': saved != null,
        'id': updated.id,
        'description': updated.description,
        'amount': updated.displayAmount,
        'category': updated.category,
        'date': updated.displayDate,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
