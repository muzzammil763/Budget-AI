enum BankConnectionStatus { healthy, syncing, attention, disconnected }

class BankAccountSummary {
  const BankAccountSummary({
    required this.id,
    required this.name,
    required this.mask,
    required this.type,
    required this.currencyCode,
    required this.selected,
  });

  final String id;
  final String name;
  final String? mask;
  final String type;
  final String? currencyCode;
  final bool selected;

  factory BankAccountSummary.fromJson(Map<String, dynamic> json) =>
      BankAccountSummary(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Bank account',
        mask: json['mask'] as String?,
        type: json['type'] as String? ?? 'account',
        currencyCode: json['currency_code'] as String?,
        selected: json['selected'] as bool? ?? true,
      );
}

class BankConnection {
  const BankConnection({
    required this.id,
    required this.institutionName,
    required this.countryCode,
    required this.status,
    required this.accounts,
    this.lastSyncedAt,
    this.syncRequired = false,
  });

  final String id;
  final String institutionName;
  final String countryCode;
  final BankConnectionStatus status;
  final List<BankAccountSummary> accounts;
  final DateTime? lastSyncedAt;
  final bool syncRequired;

  factory BankConnection.fromJson(Map<String, dynamic> json) => BankConnection(
    id: json['id'] as String,
    institutionName: json['institution_name'] as String? ?? 'Connected bank',
    countryCode: json['country_code'] as String? ?? '',
    status: BankConnectionStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => BankConnectionStatus.attention,
    ),
    accounts: (json['accounts'] as List<dynamic>? ?? const [])
        .map(
          (value) => BankAccountSummary.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false),
    lastSyncedAt: DateTime.tryParse(json['last_synced_at'] as String? ?? ''),
    syncRequired: json['sync_required'] as bool? ?? false,
  );
}

class BankSyncRecord {
  const BankSyncRecord({
    required this.id,
    required this.connectionId,
    required this.institutionName,
    required this.startedAt,
    required this.status,
    required this.added,
    required this.modified,
    required this.removed,
  });

  final String id;
  final String connectionId;
  final String institutionName;
  final DateTime startedAt;
  final String status;
  final int added;
  final int modified;
  final int removed;

  int get totalChanges => added + modified + removed;

  factory BankSyncRecord.fromJson(Map<String, dynamic> json) => BankSyncRecord(
    id: json['id'] as String,
    connectionId: json['connection_id'] as String,
    institutionName: json['institution_name'] as String? ?? 'Connected bank',
    startedAt: DateTime.parse(json['started_at'] as String),
    status: json['status'] as String? ?? 'completed',
    added: json['added_count'] as int? ?? 0,
    modified: json['modified_count'] as int? ?? 0,
    removed: json['removed_count'] as int? ?? 0,
  );
}

class BankDashboardData {
  const BankDashboardData({required this.connections, required this.history});

  final List<BankConnection> connections;
  final List<BankSyncRecord> history;
}
