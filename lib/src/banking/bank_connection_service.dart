import 'dart:async';

import 'package:budget_ai/src/banking/bank_models.dart';
import 'package:budget_ai/src/banking/bank_transaction_mapper.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:plaid_flutter/plaid_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BankConnectionService {
  BankConnectionService._();

  static final instance = BankConnectionService._();

  final changes = StreamController<void>.broadcast();

  Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    final response = await Supabase.instance.client.functions.invoke(
      'plaid-banking',
      body: {'action': action, ...body},
    );
    if (response.data is! Map) throw StateError('Invalid banking response.');
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['error'] != null) throw StateError(result['error'] as String);
    return result;
  }

  Future<BankDashboardData> dashboard() async {
    final json = await _invoke('dashboard');
    return BankDashboardData(
      connections: (json['connections'] as List<dynamic>? ?? const [])
          .map(
            (value) => BankConnection.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
      history: (json['history'] as List<dynamic>? ?? const [])
          .map(
            (value) => BankSyncRecord.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> connect({
    required String countryCode,
    required DateTime importStart,
    required DateTime importEnd,
    void Function()? onLinkOpened,
  }) async {
    final daysRequested = importEnd
        .difference(importStart)
        .inDays
        .clamp(30, 730);
    final token = await _invoke('create_link_token', {
      'country_code': countryCode,
      'days_requested': daysRequested,
    });
    final completer = Completer<void>();
    late final StreamSubscription<LinkSuccess> successSubscription;
    late final StreamSubscription<LinkExit> exitSubscription;

    Future<void> finish() async {
      await successSubscription.cancel();
      await exitSubscription.cancel();
    }

    successSubscription = PlaidLink.onSuccess.listen((event) async {
      try {
        await _invoke('exchange_public_token', {
          'public_token': event.publicToken,
          'country_code': countryCode,
          'institution_id': event.metadata.institution?.id,
          'institution_name': event.metadata.institution?.name,
          'import_start_date': _dateOnly(importStart),
          'import_end_date': _dateOnly(importEnd),
          'accounts': event.metadata.accounts
              .map(
                (account) => {
                  'id': account.id,
                  'name': account.name,
                  'mask': account.mask,
                  'type': account.type,
                  'subtype': account.subtype,
                },
              )
              .toList(growable: false),
        });
        changes.add(null);
        if (!completer.isCompleted) completer.complete();
      } catch (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      } finally {
        await finish();
      }
    });
    exitSubscription = PlaidLink.onExit.listen((_) async {
      if (!completer.isCompleted) completer.complete();
      await finish();
    });

    await PlaidLink.create(
      configuration: LinkTokenConfiguration(
        token: token['link_token'] as String,
      ),
    );
    await PlaidLink.open();
    onLinkOpened?.call();
    return completer.future;
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<int> sync(String connectionId) async {
    final response = await _invoke('sync_transactions', {
      'connection_id': connectionId,
    });
    final all = (await FinanceService.instance.getAll()).toList();
    final byExternalId = <String, FinanceEntry>{
      for (final entry in all)
        if (entry.externalTransactionId != null)
          entry.externalTransactionId!: entry,
    };
    final removed = Set<String>.from(
      (response['removed'] as List<dynamic>? ?? const []).map(
        (value) => (value as Map)['transaction_id'] as String,
      ),
    );
    all.removeWhere(
      (entry) =>
          entry.externalTransactionId != null &&
          removed.contains(entry.externalTransactionId),
    );

    final updates = <FinanceEntry>[];
    for (final raw in [
      ...response['added'] as List<dynamic>? ?? const [],
      ...response['modified'] as List<dynamic>? ?? const [],
    ]) {
      final incoming = BankTransactionMapper.fromPlaid(
        Map<String, dynamic>.from(raw as Map),
        connectionId: connectionId,
      );
      final pendingId = incoming.pendingTransactionId;
      if (pendingId != null) {
        all.removeWhere((entry) => entry.externalTransactionId == pendingId);
      }
      updates.add(
        BankTransactionMapper.mergeProviderUpdate(
          incoming,
          byExternalId[incoming.externalTransactionId],
        ),
      );
    }
    final updateIds = updates.map((entry) => entry.id).toSet();
    all.removeWhere((entry) => updateIds.contains(entry.id));
    all.addAll(updates);
    await FinanceService.instance.replaceAll(all);
    changes.add(null);
    return updates.length + removed.length;
  }

  Future<int> syncPendingConnections() async {
    try {
      final data = await dashboard();
      var changesApplied = 0;
      for (final connection in data.connections.where(
        (connection) => connection.syncRequired,
      )) {
        changesApplied += await sync(connection.id);
      }
      return changesApplied;
    } catch (_) {
      // Banking is optional and may not be configured for this deployment.
      return 0;
    }
  }

  Future<void> disconnect(String connectionId) async {
    await _invoke('disconnect', {'connection_id': connectionId});
    changes.add(null);
  }
}
