import 'dart:convert';

import 'package:budget_ai/src/sync/finance_sync_service.dart';
import 'package:budget_ai/src/sync/legacy_encryption_migration_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// Produces ciphertext exactly as the retired AccountEncryptionService did.
Future<EncryptedPayload> _legacyEncrypt(
  List<int> keyBytes,
  Map<String, dynamic> value,
) async {
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(value)),
    secretKey: SecretKeyData(keyBytes),
  );
  return EncryptedPayload(
    ciphertext: base64UrlEncode(box.cipherText),
    nonce: base64UrlEncode(box.nonce),
    mac: base64UrlEncode(box.mac.bytes),
  );
}

Future<WrappedKeyPayload> _legacyWrap(
  List<int> dataKey,
  String password,
) async {
  final salt = List<int>.generate(16, (index) => index + 1);
  final derived = await Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  final wrapped = await _legacyEncrypt(await derived.extractBytes(), {
    'key': base64UrlEncode(dataKey),
  });
  return WrappedKeyPayload(
    salt: base64UrlEncode(salt).replaceAll('=', ''),
    ciphertext: wrapped.ciphertext,
    nonce: wrapped.nonce,
    mac: wrapped.mac,
  );
}

void main() {
  final service = LegacyEncryptionMigrationService.instance;
  final dataKey = List<int>.generate(32, (index) => index + 10);

  test('decrypts legacy finance payloads and rejects tampering', () async {
    final encrypted = await _legacyEncrypt(dataKey, {
      'description': 'Private groceries',
      'amount': 1250,
    });

    expect(await service.decryptWithKey(dataKey, encrypted), {
      'description': 'Private groceries',
      'amount': 1250,
    });

    final changedMac = encrypted.mac.endsWith('A')
        ? '${encrypted.mac.substring(0, encrypted.mac.length - 1)}B'
        : '${encrypted.mac.substring(0, encrypted.mac.length - 1)}A';
    expect(
      () => service.decryptWithKey(
        dataKey,
        EncryptedPayload(
          ciphertext: encrypted.ciphertext,
          nonce: encrypted.nonce,
          mac: changedMac,
        ),
      ),
      throwsA(anything),
    );
  });

  test(
    'password unwraps the legacy data key and rejects a wrong password',
    () async {
      final fingerprint = LegacyEncryptionMigrationService.fingerprintForKey(
        dataKey,
      );
      final wrapped = await _legacyWrap(dataKey, 'correct horse');

      expect(
        await service.unwrapKeyWithPassword(
          'correct horse',
          wrapped,
          fingerprint,
        ),
        dataKey,
      );
      await expectLater(
        service.unwrapKeyWithPassword('wrong horse', wrapped, fingerprint),
        throwsA(anything),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('finance rows round-trip through plain sync columns', () {
    final payload = {
      'id': 'fin_1',
      'type': 'income',
      'date': DateTime(2026, 10, 12, 14, 30).toIso8601String(),
      'has_time': true,
      'description': 'Salary',
      'amount': 1250.5,
      'category': 'Salary',
      'created_at': DateTime(2026, 10, 12, 14, 31).toIso8601String(),
    };
    final row = FinanceSyncService.remoteRow(
      userId: 'user',
      payload: payload,
      revision: 3,
      isDeleted: false,
      clientUpdatedAt: DateTime.utc(2026, 10, 12),
    );

    expect(row['id'], 'fin_1');
    expect(row['type'], 'income');
    expect(row['amount'], 1250.5);
    expect(row['revision'], 3);
    // PostgREST returns `timestamp` columns without fractional zeros.
    final returned = {
      ...row,
      'date': '2026-10-12T14:30:00',
      'created_at': '2026-10-12T14:31:00',
    };
    expect(FinanceSyncService.payloadFromRemote(returned), payload);
  });
}
