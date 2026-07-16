import 'package:budget_ai/src/tools/tools.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/tools/finance_entry_tool_helpers.dart';

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
      'type': {
        'type': 'string',
        'enum': ['income', 'expense'],
        'description': 'Change the entry between income and expense.',
      },
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

      final typeRaw = (args['type'] as String? ?? '').trim().toLowerCase();
      if (typeRaw.isNotEmpty && typeRaw != 'income' && typeRaw != 'expense') {
        return {'ok': false, 'error': 'type must be income or expense'};
      }
      final updatedType = typeRaw.isEmpty
          ? existing.type
          : FinanceEntryType.fromJson(typeRaw);
      final requestedAmount = (args['amount'] as num?)?.toDouble();
      if (requestedAmount != null && requestedAmount <= 0) {
        return {'ok': false, 'error': 'amount must be greater than zero'};
      }

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
        type: updatedType,
        date: date,
        hasTime: hasTime,
        description: (args['description'] as String?)?.trim().isNotEmpty == true
            ? normalizeNewFinanceLabel((args['description'] as String).trim())
            : null,
        amount: requestedAmount,
        category: (args['category'] as String?)?.trim().isNotEmpty == true
            ? normalizeNewFinanceCategory(
                (args['category'] as String).trim(),
                description:
                    (args['description'] as String?)?.trim().isNotEmpty == true
                    ? normalizeNewFinanceLabel(
                        (args['description'] as String).trim(),
                      )
                    : existing.description,
              )
            : null,
      );
      final saved = await FinanceService.instance.update(updated);
      return {
        'ok': saved != null,
        'id': updated.id,
        'type': updated.type.storageValue,
        'description': updated.description,
        'amount': updated.amount,
        'category': updated.category,
        'date': updated.displayDate,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
