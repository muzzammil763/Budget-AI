import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/widgets/budget_home_widget_sync.dart';
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
  'Loan',
  'Savings',
  'Balance Rollover',
  'Work',
];

const List<String> kIncomeCategories = [
  'Salary',
  'Freelance',
  'Business',
  'Bonus',
  'Refund',
  'Gift',
  'Loan',
  'Savings',
];

enum FinanceEntryType {
  expense,
  income;

  String get storageValue => name;

  static FinanceEntryType fromJson(String? value) {
    return switch ((value ?? '').toLowerCase().trim()) {
      'income' => FinanceEntryType.income,
      _ => FinanceEntryType.expense,
    };
  }
}

enum FinanceEntrySource {
  manual,
  bank;

  static FinanceEntrySource fromJson(String? value) =>
      value == 'bank' ? FinanceEntrySource.bank : FinanceEntrySource.manual;
}

enum BankTransactionState {
  pending,
  posted,
  removed;

  static BankTransactionState? fromJson(String? value) => switch (value) {
    'pending' => BankTransactionState.pending,
    'posted' => BankTransactionState.posted,
    'removed' => BankTransactionState.removed,
    _ => null,
  };
}

class FinanceEntry {
  final String id;
  final FinanceEntryType type;
  final DateTime date;
  final bool hasTime;
  final String description;
  final double amount;
  final String category;
  final DateTime createdAt;
  final FinanceEntrySource source;
  final String? provider;
  final String? connectionId;
  final String? accountId;
  final String? externalTransactionId;
  final String? pendingTransactionId;
  final String? merchantName;
  final String? currencyCode;
  final BankTransactionState? bankState;
  final bool excludedFromBudget;
  final bool userModified;

  const FinanceEntry({
    required this.id,
    this.type = FinanceEntryType.expense,
    required this.date,
    required this.hasTime,
    required this.description,
    required this.amount,
    required this.category,
    required this.createdAt,
    this.source = FinanceEntrySource.manual,
    this.provider,
    this.connectionId,
    this.accountId,
    this.externalTransactionId,
    this.pendingTransactionId,
    this.merchantName,
    this.currencyCode,
    this.bankState,
    this.excludedFromBudget = false,
    this.userModified = false,
  });

  factory FinanceEntry.create({
    FinanceEntryType type = FinanceEntryType.expense,
    required DateTime date,
    required bool hasTime,
    required String description,
    required double amount,
    required String category,
  }) => FinanceEntry(
    id: _generateId(),
    type: type,
    date: date,
    hasTime: hasTime,
    description: description,
    amount: amount,
    category: category,
    createdAt: DateTime.now(),
  );

  factory FinanceEntry.fromJson(Map<String, dynamic> json) => FinanceEntry(
    id: json['id'] as String? ?? _generateId(),
    type: FinanceEntryType.fromJson(json['type'] as String?),
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    hasTime: json['has_time'] as bool? ?? false,
    description: json['description'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    category: json['category'] as String? ?? 'Other',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    source: FinanceEntrySource.fromJson(json['source'] as String?),
    provider: json['provider'] as String?,
    connectionId: json['connection_id'] as String?,
    accountId: json['account_id'] as String?,
    externalTransactionId: json['external_transaction_id'] as String?,
    pendingTransactionId: json['pending_transaction_id'] as String?,
    merchantName: json['merchant_name'] as String?,
    currencyCode: json['currency_code'] as String?,
    bankState: BankTransactionState.fromJson(json['bank_state'] as String?),
    excludedFromBudget: json['excluded_from_budget'] as bool? ?? false,
    userModified: json['user_modified'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.storageValue,
    'date': date.toIso8601String(),
    'has_time': hasTime,
    'description': description,
    'amount': amount,
    'category': category,
    'created_at': createdAt.toIso8601String(),
    'source': source.name,
    if (provider != null) 'provider': provider,
    if (connectionId != null) 'connection_id': connectionId,
    if (accountId != null) 'account_id': accountId,
    if (externalTransactionId != null)
      'external_transaction_id': externalTransactionId,
    if (pendingTransactionId != null)
      'pending_transaction_id': pendingTransactionId,
    if (merchantName != null) 'merchant_name': merchantName,
    if (currencyCode != null) 'currency_code': currencyCode,
    if (bankState != null) 'bank_state': bankState!.name,
    'excluded_from_budget': excludedFromBudget,
    'user_modified': userModified,
  };

  FinanceEntry copyWith({
    FinanceEntryType? type,
    DateTime? date,
    bool? hasTime,
    String? description,
    double? amount,
    String? category,
    FinanceEntrySource? source,
    String? provider,
    String? connectionId,
    String? accountId,
    String? externalTransactionId,
    String? pendingTransactionId,
    String? merchantName,
    String? currencyCode,
    BankTransactionState? bankState,
    bool? excludedFromBudget,
    bool? userModified,
  }) => FinanceEntry(
    id: id,
    type: type ?? this.type,
    date: date ?? this.date,
    hasTime: hasTime ?? this.hasTime,
    description: description ?? this.description,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    createdAt: createdAt,
    source: source ?? this.source,
    provider: provider ?? this.provider,
    connectionId: connectionId ?? this.connectionId,
    accountId: accountId ?? this.accountId,
    externalTransactionId: externalTransactionId ?? this.externalTransactionId,
    pendingTransactionId: pendingTransactionId ?? this.pendingTransactionId,
    merchantName: merchantName ?? this.merchantName,
    currencyCode: currencyCode ?? this.currencyCode,
    bankState: bankState ?? this.bankState,
    excludedFromBudget: excludedFromBudget ?? this.excludedFromBudget,
    userModified: userModified ?? this.userModified,
  );

  bool get isBankImported => source == FinanceEntrySource.bank;

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

  String get displayAmount => money(amount);
  String get displaySignedAmount {
    final signed = type == FinanceEntryType.income ? amount : -amount;
    if (isBankImported && currencyCode != null) {
      final sign = signed < 0 ? '-' : '+';
      return '$sign$currencyCode ${signed.abs().toStringAsFixed(2)}';
    }
    return money(signed);
  }

  static String money(double amount, {bool forceSign = false}) {
    return CurrencySettingsService.instance.formatAmount(
      amount,
      forceSign: forceSign,
    );
  }

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
      final store = LocalFinanceStore.instance;
      if (await store.isEmpty()) {
        final file = await _storageFile();
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.trim().isNotEmpty) {
            final legacy = (jsonDecode(raw) as List<dynamic>)
                .map((entry) => Map<String, dynamic>.from(entry as Map))
                .toList(growable: false);
            await store.replaceActive(legacy);
          }
        }
      }
      _cache = (await store.readActive()).map(FinanceEntry.fromJson).toList();
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

  Future<List<FinanceEntry>> getExpensesByDateRange(
    DateTime from,
    DateTime to,
  ) async {
    final entries = await getByDateRange(from, to);
    return entries
        .where((entry) => entry.type == FinanceEntryType.expense)
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

  Future<List<FinanceEntry>> getExpensesByMonth(int year, int month) async {
    final entries = await getByMonth(year, month);
    return entries
        .where((entry) => entry.type == FinanceEntryType.expense)
        .toList();
  }

  Future<List<FinanceEntry>> getIncomeByMonth(int year, int month) async {
    final entries = await getByMonth(year, month);
    return entries
        .where((entry) => entry.type == FinanceEntryType.income)
        .toList();
  }

  // ── Write ─────────────────────────────────────────────────────

  Future<FinanceEntry> add(FinanceEntry entry) async {
    await getAll(); // ensure cache loaded
    // Guard against duplicate tool calls executing the same add twice in one
    // tool loop iteration: match on description+amount+date within 10s.
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
    final existing = entries[index];
    if (existing.isBankImported) {
      updated = updated.copyWith(
        type: existing.type,
        date: existing.date,
        hasTime: existing.hasTime,
        amount: existing.amount,
        source: existing.source,
        provider: existing.provider,
        connectionId: existing.connectionId,
        accountId: existing.accountId,
        externalTransactionId: existing.externalTransactionId,
        pendingTransactionId: existing.pendingTransactionId,
        merchantName: existing.merchantName,
        currencyCode: existing.currencyCode,
        bankState: existing.bankState,
        userModified: true,
      );
    }
    entries[index] = updated;
    entries.sort((a, b) => b.date.compareTo(a.date));
    _cache = entries;
    await _persist();
    return updated;
  }

  /// Reconciles an authoritative batch (for example Plaid cursor updates) in
  /// one SQLite write so observers never see a half-applied bank update.
  Future<void> replaceAll(List<FinanceEntry> entries) async {
    _cache = List<FinanceEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));
    await _persist();
  }

  Future<bool> delete(String id) async {
    final entries = List<FinanceEntry>.from(await getAll());
    if (entries.any((entry) => entry.id == id && entry.isBankImported)) {
      return false;
    }
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
    entries.removeWhere((e) => idSet.contains(e.id) && !e.isBankImported);
    final removed = before - entries.length;
    if (removed == 0) return 0;
    _cache = entries;
    await _persist();
    return removed;
  }

  void invalidateCache() {
    _cache = null;
    LocalFinanceStore.instance.resetVolatileFallback();
  }

  void invalidateCacheFromSync() {
    _cache = null;
  }

  Future<void> clearLocalData() async {
    _cache = const [];
    await LocalFinanceStore.instance.clearAll();
    final legacyFile = await _storageFile();
    if (await legacyFile.exists()) await legacyFile.delete();
    await BudgetHomeWidgetSync.clearPendingEntries();
    await syncHomeWidget();
  }

  Future<void> _persist() async {
    try {
      final entries = List<FinanceEntry>.from(_cache!);
      await LocalFinanceStore.instance.replaceActive(
        entries.map((entry) => entry.toJson()).toList(growable: false),
      );
      unawaited(_syncHomeWidgetInBackground(entries));
    } catch (e) {
      debugPrint('[FinanceService] Failed to persist finances: $e');
    }
  }

  Future<void> _syncHomeWidgetInBackground(List<FinanceEntry> entries) async {
    try {
      await BudgetHomeWidgetSync.syncEntries(
        entries.map(
          (entry) => BudgetWidgetFinanceEntry(
            id: entry.id,
            type: entry.type.storageValue,
            date: entry.date,
            hasTime: entry.hasTime,
            description: entry.description,
            amount: entry.amount,
            category: entry.category,
            createdAt: entry.createdAt,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FinanceService] Failed to sync the home widget: $e');
    }
  }

  Future<void> syncHomeWidget() async {
    final entries = await getAll();
    await BudgetHomeWidgetSync.syncEntries(
      entries.map(
        (entry) => BudgetWidgetFinanceEntry(
          id: entry.id,
          type: entry.type.storageValue,
          date: entry.date,
          hasTime: entry.hasTime,
          description: entry.description,
          amount: entry.amount,
          category: entry.category,
          createdAt: entry.createdAt,
        ),
      ),
    );
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
          .replaceAll(',', '')
          .replaceAll(RegExp(r'[^0-9.\-]'), '')
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

  // ── Savings Rollover ──────────────────────────────────────────

  static const String savingsCategory = 'Savings';
  static const String balanceRolloverCategory = 'Balance Rollover';

  static const List<String> _rolloverMonthNames = [
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

  static String rolloverEntryIdForMonth(DateTime sourceMonth) {
    final targetMonth = DateTime(sourceMonth.year, sourceMonth.month + 1);
    String part(DateTime value) =>
        '${value.year}_${value.month.toString().padLeft(2, '0')}';
    return 'fin_rollover_${part(sourceMonth)}_to_${part(targetMonth)}';
  }

  static bool hasRolloverForMonth(
    List<FinanceEntry> entries,
    DateTime sourceMonth,
  ) {
    final source = DateTime(sourceMonth.year, sourceMonth.month);
    final target = DateTime(source.year, source.month + 1);
    final sourceLabel =
        '${_rolloverMonthNames[source.month - 1]} ${source.year}'.toLowerCase();
    final deterministicId = rolloverEntryIdForMonth(source);

    return entries.any((entry) {
      if (entry.id == deterministicId) return true;
      final category = entry.category.toLowerCase();
      final isRolloverCategory =
          category == savingsCategory.toLowerCase() ||
          category == balanceRolloverCategory.toLowerCase();
      if (!isRolloverCategory ||
          entry.date.year != target.year ||
          entry.date.month != target.month) {
        return false;
      }
      final description = entry.description.toLowerCase();
      return (description.startsWith('savings from ') ||
              description.startsWith('overspending from ') ||
              description.startsWith('deficit carried from ')) &&
          description.endsWith(sourceLabel);
    });
  }

  @visibleForTesting
  static FinanceEntry? buildRolloverEntry({
    required DateTime sourceMonth,
    required double closingBalance,
    DateTime? createdAt,
  }) {
    if (closingBalance == 0) return null;
    final source = DateTime(sourceMonth.year, sourceMonth.month);
    final target = DateTime(source.year, source.month + 1);
    final isSaved = closingBalance > 0;
    return FinanceEntry(
      id: rolloverEntryIdForMonth(source),
      type: isSaved ? FinanceEntryType.income : FinanceEntryType.expense,
      date: target,
      hasTime: true,
      description: isSaved
          ? 'Savings From ${_rolloverMonthNames[source.month - 1]} ${source.year}'
          : 'Deficit Carried From ${_rolloverMonthNames[source.month - 1]} ${source.year}',
      amount: closingBalance.abs(),
      category: isSaved ? savingsCategory : balanceRolloverCategory,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  /// Carries a month's closing result into the next month at midnight.
  /// Positive results become Savings income; negative results become a
  /// Balance Rollover expense. A deterministic ID makes every month transition
  /// independently idempotent while allowing later months to roll forward.
  Future<int> applySavingsRollover({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final all = await getAll();
    if (all.isEmpty) return 0;

    final firstEntryDate = all.last.date; // entries are sorted newest first
    var month = DateTime(firstEntryDate.year, firstEntryDate.month + 1);
    final currentMonth = DateTime(current.year, current.month);
    var added = 0;

    while (!month.isAfter(currentMonth)) {
      final rolloverMoment = DateTime(month.year, month.month, 1);
      if (current.isBefore(rolloverMoment)) break;

      final prev = DateTime(month.year, month.month - 1);
      final alreadyRolled = hasRolloverForMonth(_cache!, prev);
      if (!alreadyRolled) {
        final prevEntries = _cache!
            .where(
              (e) => e.date.year == prev.year && e.date.month == prev.month,
            )
            .toList();
        final closingBalance =
            totalAmount(prevEntries, type: FinanceEntryType.income) -
            totalAmount(prevEntries, type: FinanceEntryType.expense);
        final rollover = buildRolloverEntry(
          sourceMonth: prev,
          closingBalance: closingBalance,
        );
        if (prevEntries.isNotEmpty && rollover != null) {
          _cache!.add(rollover);
          added++;
        }
      }
      month = DateTime(month.year, month.month + 1);
    }

    if (added > 0) {
      _cache!.sort((a, b) => b.date.compareTo(a.date));
      await _persist();
    }
    return added;
  }

  // ── Analytics ─────────────────────────────────────────────────

  double totalAmount(List<FinanceEntry> entries, {FinanceEntryType? type}) =>
      entries
          .where(
            (entry) =>
                !entry.excludedFromBudget &&
                (type == null || entry.type == type),
          )
          .fold(0.0, (sum, e) => sum + e.amount);

  Map<String, double> categorySummary(
    List<FinanceEntry> entries, {
    FinanceEntryType type = FinanceEntryType.expense,
  }) {
    final map = <String, double>{};
    for (final e in entries.where(
      (entry) => !entry.excludedFromBudget && entry.type == type,
    )) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  /// Short finance summary injected into the chat system context.
  String buildContextText(
    List<FinanceEntry> todayEntries,
    List<FinanceEntry> monthEntries,
  ) {
    final lines = <String>[];

    if (todayEntries.isNotEmpty) {
      final todayExpenseEntries = todayEntries
          .where((entry) => entry.type == FinanceEntryType.expense)
          .toList();
      final todayTotal = totalAmount(
        todayEntries,
        type: FinanceEntryType.expense,
      );
      final todayIncome = totalAmount(
        todayEntries,
        type: FinanceEntryType.income,
      );
      if (todayExpenseEntries.isNotEmpty) {
        lines.add(
          'Today spent: ${FinanceEntry.money(todayTotal)} '
          '(${todayExpenseEntries.length} item${todayExpenseEntries.length == 1 ? '' : 's'})',
        );
      }
      if (todayIncome > 0) {
        lines.add('Today income: ${FinanceEntry.money(todayIncome)}');
      }
    }

    if (monthEntries.isNotEmpty) {
      final monthExpenseEntries = monthEntries
          .where((entry) => entry.type == FinanceEntryType.expense)
          .toList();
      final monthTotal = totalAmount(
        monthEntries,
        type: FinanceEntryType.expense,
      );
      final monthIncome = totalAmount(
        monthEntries,
        type: FinanceEntryType.income,
      );
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
      if (monthExpenseEntries.isNotEmpty) {
        lines.add(
          'Current month (${monthNames[now.month - 1]} ${now.year}) total: '
          '${FinanceEntry.money(monthTotal)} '
          '(${monthExpenseEntries.length} expense entries)',
        );
      }
      if (monthIncome > 0) {
        lines.add('Current month income: ${FinanceEntry.money(monthIncome)}');
      }
      final byCat = categorySummary(monthEntries);
      if (byCat.isNotEmpty) {
        final countsByCat = <String, int>{};
        for (final e in monthExpenseEntries) {
          countsByCat[e.category] = (countsByCat[e.category] ?? 0) + 1;
        }
        lines.add('Current month category breakdown:');
        for (final e in byCat.entries) {
          final count = countsByCat[e.key] ?? 0;
          lines.add(
            '  - ${e.key}: ${FinanceEntry.money(e.value)} '
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
