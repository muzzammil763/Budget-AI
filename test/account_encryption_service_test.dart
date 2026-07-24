import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // In-memory fake for the flutter_secure_storage platform channel, so
  // methods that cache/read the account data key (create, wrap/unwrap) can
  // run in a plain unit test without a real keychain/keystore.
  final secureStorage = <String, String>{};
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      final key = args?['key'] as String?;
      switch (call.method) {
        case 'containsKey':
          return secureStorage.containsKey(key);
        case 'read':
          return secureStorage[key];
        case 'write':
          secureStorage[key!] = args!['value'] as String;
          return null;
        case 'delete':
          secureStorage.remove(key);
          return null;
        default:
          return null;
      }
    });
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

  test('password wrap round-trips the account data key', () async {
    final service = AccountEncryptionService.instance;
    const userId = 'password-wrap-user';
    await service.createDataKey(userId);
    final fingerprint = await service.fingerprint(userId);

    final wrapped = await service.wrapKeyWithPassword(
      userId,
      'correct horse battery staple',
    );
    await service.unwrapKeyWithPassword(
      userId,
      'correct horse battery staple',
      wrapped,
      fingerprint!,
    );

    expect(await service.fingerprint(userId), fingerprint);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('password wrap rejects the wrong password', () async {
    final service = AccountEncryptionService.instance;
    const userId = 'password-wrap-wrong-password-user';
    await service.createDataKey(userId);
    final fingerprint = await service.fingerprint(userId);
    final wrapped = await service.wrapKeyWithPassword(userId, 'right-password');

    await expectLater(
      service.unwrapKeyWithPassword(
        userId,
        'wrong-password',
        wrapped,
        fingerprint!,
      ),
      throwsA(anything),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('createDataKey is a no-op when a key already exists', () async {
    final service = AccountEncryptionService.instance;
    const userId = 'create-data-key-idempotent-user';
    await service.createDataKey(userId);
    final firstFingerprint = await service.fingerprint(userId);

    await service.createDataKey(userId);
    expect(await service.fingerprint(userId), firstFingerprint);
  });

  test('rotateDataKey always replaces the existing key', () async {
    final service = AccountEncryptionService.instance;
    const userId = 'rotate-data-key-user';
    await service.createDataKey(userId);
    final firstFingerprint = await service.fingerprint(userId);

    await service.rotateDataKey(userId);
    expect(await service.fingerprint(userId), isNot(firstFingerprint));
  });
}
