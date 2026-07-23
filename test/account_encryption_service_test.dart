import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery key round-trips a 256-bit account key', () {
    final keyBytes = List<int>.generate(32, (index) => index);
    final recoveryKey = AccountEncryptionService.formatRecoveryKey(keyBytes);

    expect(recoveryKey, startsWith('BAI1-'));
    expect(AccountEncryptionService.parseRecoveryKey(recoveryKey), keyBytes);
    expect(AccountEncryptionService.fingerprintForKey(keyBytes), hasLength(24));
  });

  test('recovery key checksum rejects a changed character', () {
    final recoveryKey = AccountEncryptionService.formatRecoveryKey(
      List<int>.filled(32, 7),
    );
    final replacement = recoveryKey.endsWith('A') ? 'B' : 'A';
    final changed =
        '${recoveryKey.substring(0, recoveryKey.length - 1)}$replacement';

    expect(
      () => AccountEncryptionService.parseRecoveryKey(changed),
      throwsFormatException,
    );
  });

  test('finance payload uses authenticated encryption', () async {
    final keyBytes = List<int>.generate(32, (index) => index + 10);
    final service = AccountEncryptionService.instance;
    final encrypted = await service.encryptWithKey(keyBytes, {
      'description': 'Private groceries',
      'amount': 1250,
    });

    expect(encrypted.ciphertext, isNot(contains('Private groceries')));
    expect(await service.decryptWithKey(keyBytes, encrypted), {
      'description': 'Private groceries',
      'amount': 1250,
    });

    final changedMac = encrypted.mac.endsWith('A')
        ? '${encrypted.mac.substring(0, encrypted.mac.length - 1)}B'
        : '${encrypted.mac.substring(0, encrypted.mac.length - 1)}A';
    expect(
      () => service.decryptWithKey(
        keyBytes,
        EncryptedPayload(
          ciphertext: encrypted.ciphertext,
          nonce: encrypted.nonce,
          mac: changedMac,
        ),
      ),
      throwsA(anything),
    );
  });
}
