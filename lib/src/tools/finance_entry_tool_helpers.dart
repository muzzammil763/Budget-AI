import 'package:budget_ai/src/finances/finance_service.dart';

Future<dynamic> addFinanceEntryFromToolArgs(
  Map<String, dynamic> args, {
  required FinanceEntryType type,
}) async {
  final rawDescription = (args['description'] as String? ?? '').trim();
  final amount = (args['amount'] as num?)?.toDouble() ?? 0.0;
  final rawCategory = (args['category'] as String? ?? '').trim();
  final dateStr = (args['date'] as String? ?? '').trim();
  final timeStr = (args['time'] as String? ?? '').trim();

  if (rawDescription.isEmpty) return {'error': 'description is required'};
  if (amount <= 0) return {'error': 'amount must be greater than 0'};
  if (rawCategory.isEmpty) return {'error': 'category is required'};

  try {
    final description = normalizeNewFinanceLabel(rawDescription);
    final category = normalizeNewFinanceCategory(
      rawCategory,
      description: description,
    );
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
      'time': _displayClockTime(entry.date),
    };
  } catch (e) {
    return {'error': e.toString()};
  }
}

String _displayClockTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

String normalizeNewFinanceLabel(String value) {
  final withAmpersand = value.replaceAll(
    RegExp(r'\band\b', caseSensitive: false),
    '&',
  );
  final words = withAmpersand.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
  return words
      .map((word) {
        if (word.isEmpty || word == '&') return word;
        return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
      })
      .join(' ');
}

String normalizeNewFinanceCategory(
  String value, {
  required String description,
}) {
  final category = normalizeNewFinanceLabel(value);
  final normalized = category.toLowerCase();
  return normalized == 'other' || normalized == 'others'
      ? description
      : category;
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
