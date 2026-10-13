import 'dart:async';
import 'dart:convert';

import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:budget_ai/src/sync/finance_sync_service.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum LegacyMigrationStatus { complete, needsPassword }

class EncryptedPayload {
  const EncryptedPayload({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
    this.version = 1,
  });

  final String ciphertext;
  final String nonce;
  final String mac;
  final int version;
}

/// The retired account data key, encrypted under a key derived from the
/// account password.
class WrappedKeyPayload {
  const WrappedKeyPayload({
    required this.salt,
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  final String salt;
  final String ciphertext;
  final String nonce;
  final String mac;
}

/// One-time conversion from the retired end-to-end encrypted sync to plain
/// `finance_entries` rows. Unlocks the old AES-256-GCM data key from this
/// device's keychain, or from the account password, decrypts every legacy
/// row, copies it into `finance_entries`, then deletes the legacy rows, the
/// key metadata, and the device key.
class LegacyEncryptionMigrationService {
  LegacyEncryptionMigrationService._();

  static final LegacyEncryptionMigrationService instance =
      LegacyEncryptionMigrationService._();
  static const legacyEntriesTable = 'legacy_encrypted_finance_entries';
  static const legacyKeyTable = 'legacy_user_encryption';
  static const _keyPrefix = 'budget_ai_account_data_key_v1_';
  // v2: the first release read only the first 1000 legacy rows, so every
  // account converts again with paged reads. Already-copied ids are skipped.
  static const _completedKeyPrefix = 'legacy_encryption_migrated_v2_';
  static const _insertBatchSize = 100;

  final AesGcm _cipher = AesGcm.with256bits();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  final Argon2id _passwordKdf = Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  );
  final Set<String> _completed = {};
  Future<void> _queue = Future<void>.value();

  SupabaseClient get _client => Supabase.instance.client;

  /// Whether this account was already converted, or this device still holds
  /// the old key and can convert without asking for anything.
  Future<bool> canMigrateSilently(String userId) async {
    if (await _isComplete(userId)) return true;
    return await _readLocalKey(userId) != null;
  }

  /// Converts this account's legacy encrypted rows. Returns
  /// [LegacyMigrationStatus.needsPassword] when legacy rows exist but
  /// neither this device's key nor [password] can unlock them. Calls are
  /// serialized so the gate and the sync service never convert twice.
  Future<LegacyMigrationStatus> migrate(String userId, {String? password}) {
    final result = _queue.then((_) => _migrate(userId, password));
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Gives up on legacy rows that can no longer be unlocked, such as after
  /// a password reset. Only the unreadable cloud copy is removed.
  Future<void> discardLegacyData(String userId) {
    final result = _queue.then((_) => _deleteLegacy(userId));
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> clearLocalKey(String userId) {
    _completed.remove(userId);
    return _secureStorage.delete(key: '$_keyPrefix$userId');
  }

  Future<LegacyMigrationStatus> _migrate(
    String userId,
    String? password,
  ) async {
    if (await _isComplete(userId)) return LegacyMigrationStatus.complete;

    final metadata = await _client
        .from(legacyKeyTable)
        .select(
          'key_fingerprint,password_salt,wrapped_key_ciphertext,'
          'wrapped_key_nonce,wrapped_key_mac',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (metadata == null) {
      await _markComplete(userId);
      return LegacyMigrationStatus.complete;
    }

    final fingerprint = metadata['key_fingerprint']! as String;
    final key = await _unlockKey(userId, fingerprint, metadata, password);
    if (key == null) return LegacyMigrationStatus.needsPassword;

    final legacyRows = await FinanceSyncService.readAllRows(
      _client,
      table: legacyEntriesTable,
      userId: userId,
      orderBy: 'entry_id',
    );
    final existingRows = await FinanceSyncService.readAllRows(
      _client,
      table: FinanceSyncService.table,
      userId: userId,
      orderBy: 'id',
      columns: 'id',
    );
    final existingIds = existingRows.map((row) => row['id'] as String).toSet();

    final plainRows = <Map<String, dynamic>>[];
    var failures = 0;
    for (final legacy in legacyRows) {
      final entryId = legacy['entry_id']! as String;
      if (existingIds.contains(entryId)) continue;
      try {
        final payload = await decryptWithKey(
          key,
          EncryptedPayload(
            ciphertext: legacy['ciphertext']! as String,
            nonce: legacy['nonce']! as String,
            mac: legacy['mac']! as String,
            version: legacy['encryption_version']! as int,
          ),
        );
        payload['id'] = entryId;
        plainRows.add(
          FinanceSyncService.remoteRow(
            userId: userId,
            payload: payload,
            revision: legacy['revision']! as int,
            isDeleted: legacy['is_deleted'] == true,
            clientUpdatedAt: DateTime.parse(
              legacy['client_updated_at']! as String,
            ),
          ),
        );
      } catch (error) {
        failures++;
        debugPrint(
          '[LegacyEncryptionMigration] Skipped unreadable $entryId: $error',
        );
      }
    }

    for (
      var offset = 0;
      offset < plainRows.length;
      offset += _insertBatchSize
    ) {
      final end = (offset + _insertBatchSize).clamp(0, plainRows.length);
      await _client
          .from(FinanceSyncService.table)
          .upsert(
            plainRows.sublist(offset, end),
            onConflict: 'user_id,id',
            ignoreDuplicates: true,
          );
    }

    // Delete the legacy copy only once the server confirms every legacy id
    // exists in finance_entries; keep unreadable ciphertext otherwise.
    if (failures == 0) {
      final copiedRows = await FinanceSyncService.readAllRows(
        _client,
        table: FinanceSyncService.table,
        userId: userId,
        orderBy: 'id',
        columns: 'id',
      );
      final copiedIds = copiedRows.map((row) => row['id'] as String).toSet();
      final allCopied = legacyRows.every(
        (row) => copiedIds.contains(row['entry_id']),
      );
      if (allCopied) {
        await _deleteLegacy(userId);
        return LegacyMigrationStatus.complete;
      }
    }
    // Something was not copied: keep the legacy rows and the device key,
    // let sync continue for this session, and retry on the next launch.
    _completed.add(userId);
    return LegacyMigrationStatus.complete;
  }

  Future<List<int>?> _unlockKey(
    String userId,
    String fingerprint,
    Map<String, dynamic> metadata,
    String? password,
  ) async {
    final localKey = await _readLocalKey(userId);
    if (localKey != null && fingerprintForKey(localKey) == fingerprint) {
      return localKey;
    }
    if (password == null) return null;
    final salt = metadata['password_salt'] as String?;
    final ciphertext = metadata['wrapped_key_ciphertext'] as String?;
    final nonce = metadata['wrapped_key_nonce'] as String?;
    final mac = metadata['wrapped_key_mac'] as String?;
    if (salt == null || ciphertext == null || nonce == null || mac == null) {
      return null;
    }
    final List<int> key;
    try {
      key = await unwrapKeyWithPassword(
        password,
        WrappedKeyPayload(
          salt: salt,
          ciphertext: ciphertext,
          nonce: nonce,
          mac: mac,
        ),
        fingerprint,
      );
    } catch (_) {
      return null;
    }
    // Cache it so an interrupted conversion can retry without the password.
    await _secureStorage.write(
      key: '$_keyPrefix$userId',
      value: base64UrlEncode(key).replaceAll('=', ''),
    );
    return key;
  }

  Future<void> _deleteLegacy(String userId) async {
    await _client.from(legacyEntriesTable).delete().eq('user_id', userId);
    await _client.from(legacyKeyTable).delete().eq('user_id', userId);
    await _markComplete(userId);
  }

  Future<bool> _isComplete(String userId) async {
    if (_completed.contains(userId)) return true;
    final stored = await LocalSettingsStore.instance.getBool(
      '$_completedKeyPrefix$userId',
    );
    if (stored == true) _completed.add(userId);
    return stored == true;
  }

  Future<void> _markComplete(String userId) async {
    _completed.add(userId);
    await LocalSettingsStore.instance.setBool(
      '$_completedKeyPrefix$userId',
      true,
    );
    await _secureStorage.delete(key: '$_keyPrefix$userId');
  }

  Future<List<int>?> _readLocalKey(String userId) async {
    final encoded = await _secureStorage.read(key: '$_keyPrefix$userId');
    if (encoded == null) return null;
    final bytes = base64Url.decode(_padded(encoded));
    return bytes.length == 32 ? bytes : null;
  }

  /// Recovers the data key from [password] and verifies it against
  /// [expectedFingerprint]. Throws if the password is wrong.
  @visibleForTesting
  Future<List<int>> unwrapKeyWithPassword(
    String password,
    WrappedKeyPayload wrapped,
    String expectedFingerprint,
  ) async {
    final salt = base64Url.decode(_padded(wrapped.salt));
    final derived = await _passwordKdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final decoded = await decryptWithKey(
      await derived.extractBytes(),
      EncryptedPayload(
        ciphertext: wrapped.ciphertext,
        nonce: wrapped.nonce,
        mac: wrapped.mac,
      ),
    );
    final dataKey = base64Url.decode(_padded(decoded['key']! as String));
    if (dataKey.length != 32 ||
        fingerprintForKey(dataKey) != expectedFingerprint) {
      throw StateError('The derived key does not match this account.');
    }
    return dataKey;
  }

  @visibleForTesting
  Future<Map<String, dynamic>> decryptWithKey(
    List<int> keyBytes,
    EncryptedPayload payload,
  ) async {
    if (payload.version != 1) {
      throw const FormatException('Unsupported encryption version.');
    }
    final clearBytes = await _cipher.decrypt(
      SecretBox(
        base64Url.decode(_padded(payload.ciphertext)),
        nonce: base64Url.decode(_padded(payload.nonce)),
        mac: Mac(base64Url.decode(_padded(payload.mac))),
      ),
      secretKey: SecretKeyData(keyBytes),
    );
    final decoded = jsonDecode(utf8.decode(clearBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Encrypted finance payload is invalid.');
    }
    return decoded;
  }

  static String fingerprintForKey(List<int> keyBytes) {
    final digest = hashes.sha256.convert(keyBytes).bytes.take(18).toList();
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  static String _padded(String value) {
    return value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
  }
}
