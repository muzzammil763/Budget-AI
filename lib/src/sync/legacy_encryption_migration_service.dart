import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// The account data key, encrypted ("wrapped") under a key derived from the
/// account password. Lets a device unlock the same data key a normal
/// email/password login would produce, without ever transferring the key
/// itself between devices.
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

class AccountEncryptionService {
  AccountEncryptionService._();

  static final AccountEncryptionService instance = AccountEncryptionService._();
  static const _keyPrefix = 'budget_ai_account_data_key_v1_';

  final AesGcm _cipher = AesGcm.with256bits();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  // OWASP-recommended Argon2id parameters for interactive password hashing:
  // https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
  final Argon2id _passwordKdf = Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  );

  Future<bool> hasKey(String userId) async {
    return await _secureStorage.containsKey(key: '$_keyPrefix$userId');
  }

  Future<void> clearDataKey(String userId) {
    return _secureStorage.delete(key: '$_keyPrefix$userId');
  }

  /// Creates this account's data key on first-time setup, if one doesn't
  /// already exist locally. A no-op on a device that already holds one.
  Future<void> createDataKey(String userId) async {
    final existing = await _readKeyBytes(userId);
    if (existing != null) return;
    await _writeKeyBytes(userId, await _newKeyBytes());
  }

  /// Always generates a brand-new key and overwrites whatever is stored for
  /// this account, even if one already exists. Used when resetting
  /// encryption — previously synced ciphertext under the old key becomes
  /// permanently unreadable.
  Future<void> rotateDataKey(String userId) async {
    await _writeKeyBytes(userId, await _newKeyBytes());
  }

  /// Wraps this device's already-cached data key under a key derived from
  /// [password], so any device that knows the account password can later
  /// unwrap the same data key via [unwrapKeyWithPassword] instead of
  /// requiring a manually copied recovery key. Requires the data key to
  /// already exist locally (call after setup/restore, or right after a
  /// password change while this device still holds the key).
  Future<WrappedKeyPayload> wrapKeyWithPassword(
    String userId,
    String password,
  ) async {
    final dataKey = await _requiredKeyBytes(userId);
    final salt = _randomBytes(16);
    final passwordKey = await _derivePasswordKey(password, salt);
    final wrapped = await encryptWithKey(passwordKey, {
      'key': base64UrlEncode(dataKey),
    });
    return WrappedKeyPayload(
      salt: base64UrlEncode(salt).replaceAll('=', ''),
      ciphertext: wrapped.ciphertext,
      nonce: wrapped.nonce,
      mac: wrapped.mac,
    );
  }

  /// Recovers the data key from [password] and this account's stored
  /// [wrapped] envelope, verifies it against [expectedFingerprint], and
  /// caches it locally on success. Throws if the password is wrong or the
  /// envelope doesn't match this account.
  Future<void> unwrapKeyWithPassword(
    String userId,
    String password,
    WrappedKeyPayload wrapped,
    String expectedFingerprint,
  ) async {
    final salt = base64Url.decode(_padded(wrapped.salt));
    final passwordKey = await _derivePasswordKey(password, salt);
    final decoded = await decryptWithKey(
      passwordKey,
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
    await _writeKeyBytes(userId, dataKey);
  }

  Future<List<int>> _derivePasswordKey(String password, List<int> salt) async {
    final derived = await _passwordKdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return derived.extractBytes();
  }

  List<int> _randomBytes(int length) {
    final random = math.Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  Future<String?> fingerprint(String userId) async {
    final keyBytes = await _readKeyBytes(userId);
    return keyBytes == null ? null : fingerprintForKey(keyBytes);
  }

  Future<EncryptedPayload> encrypt(
    String userId,
    Map<String, dynamic> value,
  ) async {
    final keyBytes = await _requiredKeyBytes(userId);
    return encryptWithKey(keyBytes, value);
  }

  @visibleForTesting
  Future<EncryptedPayload> encryptWithKey(
    List<int> keyBytes,
    Map<String, dynamic> value,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: SecretKeyData(keyBytes),
    );
    return EncryptedPayload(
      ciphertext: base64UrlEncode(box.cipherText),
      nonce: base64UrlEncode(box.nonce),
      mac: base64UrlEncode(box.mac.bytes),
    );
  }

  Future<Map<String, dynamic>> decrypt(
    String userId,
    EncryptedPayload payload,
  ) async {
    if (payload.version != 1) {
      throw const FormatException('Unsupported encryption version.');
    }
    final keyBytes = await _requiredKeyBytes(userId);
    return decryptWithKey(keyBytes, payload);
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

  Future<List<int>> _newKeyBytes() async {
    final key = await _cipher.newSecretKey();
    return key.extractBytes();
  }

  Future<List<int>> _requiredKeyBytes(String userId) async {
    final bytes = await _readKeyBytes(userId);
    if (bytes == null) {
      throw StateError('Encrypted sync needs this account recovery key.');
    }
    return bytes;
  }

  Future<List<int>?> _readKeyBytes(String userId) async {
    final encoded = await _secureStorage.read(key: '$_keyPrefix$userId');
    if (encoded == null) return null;
    final bytes = base64Url.decode(_padded(encoded));
    return bytes.length == 32 ? bytes : null;
  }

  Future<void> _writeKeyBytes(String userId, List<int> keyBytes) async {
    if (keyBytes.length != 32) {
      throw const FormatException('Account data key must contain 256 bits.');
    }
    await _secureStorage.write(
      key: '$_keyPrefix$userId',
      value: base64UrlEncode(keyBytes).replaceAll('=', ''),
    );
  }

  static String fingerprintForKey(List<int> keyBytes) {
    final digest = hashes.sha256.convert(keyBytes).bytes.take(18).toList();
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  static String _padded(String value) {
    return value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
  }
}
