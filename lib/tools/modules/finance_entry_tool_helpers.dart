import 'package:budget_ai/src/finances/finance_service.dart';

Future<dynamic> addFinanceEntryFromToolArgs(
  Map<String, dynamic> args, {
  required FinanceEntryType type,
}) async {
  final description = (args['description'] as String? ?? '').trim();
  final amount = (args['amount'] as num?)?.toDouble() ?? 0.0;
  final category = (args['category'] as String? ?? '').trim();
  final dateStr = (args['date'] as String? ?? '').trim();
  final timeStr = (args['time'] as String? ?? '').trim();

  if (description.isEmpty) return {'error': 'description is required'};
  if (amount <= 0) return {'error': 'amount must be greater than 0'};
  if (category.isEmpty) return {'error': 'category is required'};

  try {
    final date = _toolEntryDate(dateStr: dateStr, timeStr: timeStr);
    final entry = FinanceEntry.create(
      type: type,
      date: date,
      hasTime: true,
      description: description,
      amount: amount,
      category: category,
    );
    await FinanceService.instance.add(entry);

    return {
      'ok': true,
      'id': entry.id,
      if (type != FinanceEntryType.expense) 'type': entry.type.storageValue,
      'description': entry.description,
      'amount': entry.amount,
      'display_amount': type == FinanceEntryType.expense
          ? entry.displayAmount
          : entry.displaySignedAmount,
      'category': entry.category,
      'date': entry.displayDate,
    };
  } catch (e) {
    return {'error': e.toString()};
  }
}

DateTime _toolEntryDate({required String dateStr, required String timeStr}) {
  var date = dateStr.isNotEmpty
      ? DateTime.tryParse(dateStr) ?? DateTime.now()
      : DateTime.now();

  if (timeStr.isNotEmpty) {
    final parts = timeStr.split(':');
    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      date = DateTime(date.year, date.month, date.day, hour, minute);
    }
  } else {
    final now = DateTime.now();
    date = DateTime(date.year, date.month, date.day, now.hour, now.minute);
  }

  return date;
}
