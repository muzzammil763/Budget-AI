import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const List<String> kFinanceCategories = [
  'Food',
  'Groceries',
  'Household',
  'Bills',
  'Transportation',
  'Healthcare',
  'Personal Care',
  'Clothing',
  'Shopping',
  'Entertainment',
  'Sports',
  'Mobile',
  'Home',
  'Kitchen',
  'Bike',
  'Vehicle',
  'Baby Supplies',
  'Wife',
  'Family',
  'Gift',
  'Charity',
  'Banking',
  'Savings',
  'Work',
  'Others',
];

class FinanceEntry {
  final String id;
  final DateTime date;
  final bool hasTime;
  final String description;
  final double amount;
  final String category;
  final DateTime createdAt;

  const FinanceEntry({
    required this.id,
    required this.date,
    required this.hasTime,
    required this.description,
    required this.amount,
    required this.category,
    required this.createdAt,
  });

  factory FinanceEntry.create({
    required DateTime date,
    required bool hasTime,
    required String description,
    required double amount,
    required String category,
  }) => FinanceEntry(
    id: _generateId(),
    date: date,
    hasTime: hasTime,
    description: description,
    amount: amount,
    category: category,
    createdAt: DateTime.now(),
  );

  factory FinanceEntry.fromJson(Map<String, dynamic> json) => FinanceEntry(
    id: json['id'] as String? ?? _generateId(),
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    hasTime: json['has_time'] as bool? ?? false,
    description: json['description'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    category: json['category'] as String? ?? 'Other',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'has_time': hasTime,
    'description': description,
    'amount': amount,
    'category': category,
    'created_at': createdAt.toIso8601String(),
  };

  FinanceEntry copyWith({
    DateTime? date,
    bool? hasTime,
    String? description,
    double? amount,
    String? category,
  }) => FinanceEntry(
    id: id,
    date: date ?? this.date,
    hasTime: hasTime ?? this.hasTime,
    description: description ?? this.description,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    createdAt: createdAt,
  );

  String get displayDate {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final day = date.day.toString().padLeft(2, '0');
    final month = months[date.month - 1];
    final year = date.year;
    if (!hasTime) return '$day $month, $year';
    final rawHour = date.hour;
    final hour = rawHour == 0
        ? 12
        : rawHour > 12
        ? rawHour - 12
        : rawHour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = rawHour >= 12 ? 'PM' : 'AM';
    return '$day $month, $year - ${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String get displayAmount => '${formatAmount(amount)} Rs';

  static String formatAmount(double amount) {
    final intPart = amount.toInt();
    final str = intPart.toString();
    if (str.length <= 3) return str;
    final buf = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  static String _generateId() {
    return 'fin_${DateTime.now().microsecondsSinceEpoch}';
  }
}

class FinanceService {
  FinanceService._();
  static final FinanceService instance = FinanceService._();

  static const _storageFileName = 'finances.json';

  List<FinanceEntry>? _cache;

  Future<File> _storageFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_storageFileName');
  }

  // ── Read ──────────────────────────────────────────────────────

  Future<List<FinanceEntry>> getAll() async {
    if (_cache != null) return List.unmodifiable(_cache!);
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        _cache = [];
        return const [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cache = [];
        return const [];
      }
      final list = jsonDecode(raw) as List<dynamic>;
      _cache = list
          .map((e) => FinanceEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache!.sort((a, b) => b.date.compareTo(a.date));
      return List.unmodifiable(_cache!);
    } catch (e) {
      debugPrint('[FinanceService] Failed to read finances: $e');
      _cache = [];
      return const [];
    }
  }

  Future<List<FinanceEntry>> getByDateRange(DateTime from, DateTime to) async {
    final all = await getAll();
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return all
        .where((e) => !e.date.isBefore(fromDay) && !e.date.isAfter(toDay))
        .toList();
  }

  Future<List<FinanceEntry>> getByMonth(int year, int month) async {
    final from = DateTime(year, month, 1);
    final to = DateTime(
      year,
      month + 1,
      1,
    ).subtract(const Duration(seconds: 1));
    return getByDateRange(from, to);
  }

  // ── Write ─────────────────────────────────────────────────────

  Future<FinanceEntry> add(FinanceEntry entry) async {
    await getAll(); // ensure cache loaded
    // Guard against duplicate tool calls executing the same add twice in one
    // agentic loop iteration — match on description+amount+date within 10s.
    final existing = _cache!.where(
      (e) =>
          e.description.toLowerCase() == entry.description.toLowerCase() &&
          e.amount == entry.amount &&
          e.date.year == entry.date.year &&
          e.date.month == entry.date.month &&
          e.date.day == entry.date.day &&
          entry.createdAt.difference(e.createdAt).abs().inSeconds < 10,
    );
    if (existing.isNotEmpty) return existing.first;
    _cache!.add(entry);
    _cache!.sort((a, b) => b.date.compareTo(a.date));
    await _persist();
    return entry;
  }

  Future<FinanceEntry?> update(FinanceEntry updated) async {
    final entries = List<FinanceEntry>.from(await getAll());
    final index = entries.indexWhere((e) => e.id == updated.id);
    if (index < 0) return null;
    entries[index] = updated;
    entries.sort((a, b) => b.date.compareTo(a.date));
    _cache = entries;
    await _persist();
    return updated;
  }

  Future<bool> delete(String id) async {
    final entries = List<FinanceEntry>.from(await getAll());
    final before = entries.length;
    entries.removeWhere((e) => e.id == id);
    if (entries.length == before) return false;
    _cache = entries;
    await _persist();
    return true;
  }

  /// Deletes multiple entries in a single persist call.
  /// Returns the count of entries actually removed.
  Future<int> deleteMany(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final idSet = ids.toSet();
    final entries = List<FinanceEntry>.from(await getAll());
    final before = entries.length;
    entries.removeWhere((e) => idSet.contains(e.id));
    final removed = before - entries.length;
    if (removed == 0) return 0;
    _cache = entries;
    await _persist();
    return removed;
  }

  void invalidateCache() => _cache = null;

  Future<void> _persist() async {
    try {
      final file = await _storageFile();
      final json = jsonEncode(_cache!.map((e) => e.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('[FinanceService] Failed to persist finances: $e');
    }
  }

  // ── CSV Import ────────────────────────────────────────────────

  /// Parses CSV files matching the user's finance format:
  /// date,description,amount,category
  /// "06 April, 2026","Bread","60 Rs","Food"
  Future<int> importFromCsv(String csvContent) async {
    await getAll(); // ensure cache loaded
    final lines = csvContent
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 0;

    // Skip header row if present
    final startIndex =
        lines.first.toLowerCase().startsWith('date') ||
            lines.first.toLowerCase().startsWith('"date')
        ? 1
        : 0;

    final incoming = <FinanceEntry>[];
    for (final line in lines.sublist(startIndex)) {
      final entry = _parseCsvLine(line);
      if (entry != null) incoming.add(entry);
    }

    if (incoming.isEmpty) return 0;

    final existing = _cache!;
    var added = 0;
    for (final entry in incoming) {
      // Deduplicate by date + description + amount
      final isDup = existing.any(
        (e) =>
            e.description.toLowerCase() == entry.description.toLowerCase() &&
            e.amount == entry.amount &&
            e.date.year == entry.date.year &&
            e.date.month == entry.date.month &&
            e.date.day == entry.date.day,
      );
      if (!isDup) {
        _cache!.add(entry);
        added++;
      }
    }

    if (added > 0) {
      _cache!.sort((a, b) => b.date.compareTo(a.date));
      await _persist();
    }
    return added;
  }

  FinanceEntry? _parseCsvLine(String line) {
    try {
      final fields = _parseCsvFields(line);
      if (fields.length < 3) return null;

      final dateStr = fields[0].trim();
      final description = fields[1].trim();
      final amountStr = fields[2]
          .trim()
          .replaceAll(RegExp(r'\s*Rs\.?', caseSensitive: false), '')
          .replaceAll(',', '')
          .trim();
      final category = fields.length >= 4
          ? _capitalize(fields[3].trim())
          : 'Other';

      if (description.isEmpty) return null;
      final amount = double.tryParse(amountStr);
      if (amount == null) return null;

      final parsed = _parseFinanceDate(dateStr);
      if (parsed == null) return null;

      return FinanceEntry(
        id: FinanceEntry._generateId(),
        date: parsed.date,
        hasTime: parsed.hasTime,
        description: description,
        amount: amount,
        category: category.isEmpty ? 'Other' : category,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _parseCsvFields(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++; // skip escaped quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    fields.add(buf.toString());
    return fields;
  }

  static const _monthMap = {
    // Full names
    'january': 1, 'february': 2, 'march': 3, 'april': 4,
    'may': 5, 'june': 6, 'july': 7, 'august': 8,
    'september': 9, 'october': 10, 'november': 11, 'december': 12,
    // Abbreviated
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
    'jun': 6, 'jul': 7, 'aug': 8,
    'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  ({DateTime date, bool hasTime})? _parseFinanceDate(String raw) {
    final trimmed = raw.trim();

    // Strip optional time suffix " - HH:MM AM/PM" or " HH:MM:SS" first
    String datePart = trimmed;
    bool hasTime = false;

    // Pattern: "... - 12:12 PM"
    final timeSepIdx = trimmed.indexOf(' - ');
    if (timeSepIdx >= 0) {
      datePart = trimmed.substring(0, timeSepIdx).trim();
      final timePart = trimmed.substring(timeSepIdx + 3).trim();
      final timeMatch = RegExp(
        r'(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?',
        caseSensitive: false,
      ).firstMatch(timePart);
      if (timeMatch != null) {
        var hour = int.parse(timeMatch.group(1)!);
        final minute = int.parse(timeMatch.group(2)!);
        final period = timeMatch.group(3)?.toUpperCase();
        if (period == 'PM' && hour != 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;
        hasTime = true;
        // timeResult will be constructed after we get the date
        final d = _parseDateOnly(datePart);
        if (d == null) return null;
        return (
          date: DateTime(d.year, d.month, d.day, hour, minute),
          hasTime: true,
        );
      }
      hasTime = true;
    }

    final date = _parseDateOnly(datePart);
    if (date == null) return null;
    return (date: date, hasTime: hasTime);
  }

  DateTime? _parseDateOnly(String part) {
    // 1. ISO format: 2026-04-06
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(part);
    if (iso != null) {
      final y = int.tryParse(iso.group(1)!);
      final m = int.tryParse(iso.group(2)!);
      final d = int.tryParse(iso.group(3)!);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }

    // 2. "06 April, 2026" or "06 Apr 2026" (day first, then month name)
    final dayFirst = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]+),?\s+(\d{4})$',
    ).firstMatch(part);
    if (dayFirst != null) {
      final d = int.tryParse(dayFirst.group(1)!);
      final m = _monthMap[dayFirst.group(2)!.toLowerCase()];
      final y = int.tryParse(dayFirst.group(3)!);
      if (d != null && m != null && y != null) return DateTime(y, m, d);
    }

    // 3. "April 6, 2026" or "Apr 06 2026" (month name first, then day)
    final monthFirst = RegExp(
      r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$',
    ).firstMatch(part);
    if (monthFirst != null) {
      final m = _monthMap[monthFirst.group(1)!.toLowerCase()];
      final d = int.tryParse(monthFirst.group(2)!);
      final y = int.tryParse(monthFirst.group(3)!);
      if (m != null && d != null && y != null) return DateTime(y, m, d);
    }

    // 4. Slash or dot separated: DD/MM/YYYY or MM/DD/YYYY or DD.MM.YYYY
    final slashed = RegExp(
      r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})$',
    ).firstMatch(part);
    if (slashed != null) {
      final a = int.tryParse(slashed.group(1)!);
      final b = int.tryParse(slashed.group(2)!);
      final y = int.tryParse(slashed.group(3)!);
      if (a != null && b != null && y != null) {
        // Assume DD/MM if first number > 12, else DD/MM (local convention)
        final d = a > 12 ? a : a;
        final m = a > 12 ? b : b;
        return DateTime(y, m, d);
      }
    }

    return null;
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  // ── Analytics ─────────────────────────────────────────────────

  double totalAmount(List<FinanceEntry> entries) =>
      entries.fold(0.0, (sum, e) => sum + e.amount);

  Map<String, double> categorySummary(List<FinanceEntry> entries) {
    final map = <String, double>{};
    for (final e in entries) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  /// Short finance summary injected into the agent's system context.
  String buildContextText(
    List<FinanceEntry> todayEntries,
    List<FinanceEntry> monthEntries,
  ) {
    final lines = <String>[];

    if (todayEntries.isNotEmpty) {
      final todayTotal = totalAmount(todayEntries);
      lines.add(
        'Today spent: ${FinanceEntry.formatAmount(todayTotal)} Rs '
        '(${todayEntries.length} item${todayEntries.length == 1 ? '' : 's'})',
      );
    }

    if (monthEntries.isNotEmpty) {
      final monthTotal = totalAmount(monthEntries);
      final now = DateTime.now();
      const monthNames = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      lines.add(
        'Current month (${monthNames[now.month - 1]} ${now.year}) total: '
        '${FinanceEntry.formatAmount(monthTotal)} Rs '
        '(${monthEntries.length} entries)',
      );
      final byCat = categorySummary(monthEntries);
      if (byCat.isNotEmpty) {
        final countsByCat = <String, int>{};
        for (final e in monthEntries) {
          countsByCat[e.category] = (countsByCat[e.category] ?? 0) + 1;
        }
        lines.add('Current month category breakdown:');
        for (final e in byCat.entries) {
          final count = countsByCat[e.key] ?? 0;
          lines.add(
            '  - ${e.key}: ${FinanceEntry.formatAmount(e.value)} Rs '
            '($count ${count == 1 ? 'entry' : 'entries'})',
          );
        }
      }
    }

    return lines.join('\n');
  }

  // ── Backup / Export ───────────────────────────────────────────

  String buildExportJson(List<FinanceEntry> entries) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'finances': entries.map((e) => e.toJson()).toList(),
    });
  }

  Future<int> importFromJson(String rawJson) async {
    await getAll(); // ensure cache loaded
    final decoded = jsonDecode(rawJson);
    final List<dynamic> rawList;
    if (decoded is Map && decoded['finances'] is List) {
      rawList = decoded['finances'] as List<dynamic>;
    } else if (decoded is List) {
      rawList = decoded;
    } else {
      throw const FormatException('Invalid finance bundle format');
    }

    final incoming = rawList
        .map((e) => FinanceEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    var affected = 0;
    for (final entry in incoming) {
      final existingIndex = _cache!.indexWhere((e) => e.id == entry.id);
      if (existingIndex >= 0) {
        // Overwrite existing entry with new data
        _cache![existingIndex] = entry;
        affected++;
      } else {
        _cache!.add(entry);
        affected++;
      }
    }

    if (affected > 0) {
      _cache!.sort((a, b) => b.date.compareTo(a.date));
      await _persist();
    }
    return affected;
  }

  Future<void> shareExportFile(List<FinanceEntry> entries) async {
    final json = buildExportJson(entries);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/OpenGate_Finances_Export.json');
    await file.writeAsString(json, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'OpenGate Finances Export',
      ),
    );
  }
}
