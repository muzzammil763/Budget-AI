import 'package:budget_ai/src/tools/tools.dart';
import 'package:budget_ai/src/finances/finance_service.dart';

ToolDefinition buildFinanceListTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'finance_list',
  description:
      'List finance entries with optional date, keyword, type, category, and amount filters. Can sort by largest amount for biggest or heavy expense questions. Use keywords to search for entries matching any of several words (e.g. "find expenses for coffee, uber, or netflix between Jan 1 and today"). Use this before finance_update or finance_delete when you need to find an entry ID.',
  parameters: {
    'type': 'object',
    'properties': {
      'from_date': {
        'type': 'string',
        'description': 'Start date filter in YYYY-MM-DD format (inclusive).',
      },
      'to_date': {
        'type': 'string',
        'description':
            'End date filter in YYYY-MM-DD format (inclusive). Defaults to today.',
      },
      'keywords': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Optional list of search words or phrases. Matches entries whose description or category contains ANY of these words (case-insensitive, OR match). Use this for requests like "expenses about X, Y, or Z".',
      },
      'category': {
        'type': 'string',
        'description':
            'Filter by category name (case-insensitive). Omit to include all categories.',
      },
      'type': {
        'type': 'string',
        'description':
            'Optional entry type filter: expense or income. Omit to include both income and expenses.',
        'enum': ['expense', 'income'],
      },
      'amount_greater_than': {
        'type': 'number',
        'description':
            'Return only entries whose amount is strictly greater than this value. For example, use 1000 for "expenses more than 1000".',
      },
      'sort_by': {
        'type': 'string',
        'description':
            'Sort matching entries by newest date or by largest amount. Use amount_desc for heavy, biggest, largest, or highest expenses.',
        'enum': ['date_desc', 'amount_desc'],
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum number of entries to return. Defaults to 50.',
      },
    },
    'required': [],
  },
  handler: handler,
);

mixin FinanceListToolHandler {
  Future<dynamic> handleFinanceListRequest(Map<String, dynamic> args) async {
    final fromStr = (args['from_date'] as String? ?? '').trim();
    final toStr = (args['to_date'] as String? ?? '').trim();
    final keywords = _parseKeywords(args['keywords']);
    final category = (args['category'] as String? ?? '').trim().toLowerCase();
    final typeRaw = (args['type'] as String? ?? '').trim();
    final type = typeRaw.isNotEmpty ? FinanceEntryType.fromJson(typeRaw) : null;
    final amountGreaterThan = (args['amount_greater_than'] as num?)?.toDouble();
    final sortBy = (args['sort_by'] as String? ?? 'date_desc').trim();
    final limit = ((args['limit'] as num?)?.toInt() ?? 50).clamp(1, 200);

    try {
      if (amountGreaterThan != null && amountGreaterThan < 0) {
        return {'error': 'amount_greater_than must be zero or greater'};
      }
      if (sortBy != 'date_desc' && sortBy != 'amount_desc') {
        return {'error': 'sort_by must be date_desc or amount_desc'};
      }

      List<FinanceEntry> entries;

      if (fromStr.isNotEmpty) {
        final from = DateTime.tryParse(fromStr) ?? DateTime.now();
        final to = toStr.isNotEmpty
            ? DateTime.tryParse(toStr) ?? DateTime.now()
            : DateTime.now();
        entries = await FinanceService.instance.getByDateRange(from, to);
      } else {
        entries = List.from(await FinanceService.instance.getAll());
      }

      entries = filterFinanceEntriesForList(
        entries,
        keywords: keywords,
        category: category,
        type: type,
        amountGreaterThan: amountGreaterThan,
        sortBy: sortBy,
      );

      final limited = entries.take(limit).toList();
      final total = FinanceService.instance.totalAmount(entries);

      return {
        'ok': true,
        'count': limited.length,
        'matched_count': entries.length,
        'total': FinanceEntry.money(total),
        'entries': limited
            .map(
              (e) => {
                'id': e.id,
                'type': e.type.storageValue,
                'date': e.displayDate,
                'description': e.description,
                'amount': e.displaySignedAmount,
                'category': e.category,
              },
            )
            .toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}

List<String> _parseKeywords(dynamic raw) {
  Iterable<String> pieces;
  if (raw is List) {
    pieces = raw.map((e) => e.toString());
  } else if (raw is String) {
    pieces = raw.split(',');
  } else {
    pieces = const [];
  }
  return pieces
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
}

List<FinanceEntry> filterFinanceEntriesForList(
  Iterable<FinanceEntry> source, {
  List<String> keywords = const [],
  String category = '',
  FinanceEntryType? type,
  double? amountGreaterThan,
  String sortBy = 'date_desc',
}) {
  var entries = source.toList();
  if (keywords.isNotEmpty) {
    entries = entries.where((entry) {
      final haystack = '${entry.description} ${entry.category}'.toLowerCase();
      return keywords.any((keyword) => haystack.contains(keyword));
    }).toList();
  }
  if (category.isNotEmpty) {
    final normalizedCategory = category.trim().toLowerCase();
    entries = entries
        .where((entry) => entry.category.toLowerCase() == normalizedCategory)
        .toList();
  }
  if (type != null) {
    entries = entries.where((entry) => entry.type == type).toList();
  }
  if (amountGreaterThan != null) {
    entries = entries
        .where((entry) => entry.amount > amountGreaterThan)
        .toList();
  }

  entries.sort(
    sortBy == 'amount_desc'
        ? (a, b) {
            final amountOrder = b.amount.compareTo(a.amount);
            return amountOrder != 0 ? amountOrder : b.date.compareTo(a.date);
          }
        : (a, b) => b.date.compareTo(a.date),
  );
  return entries;
}
