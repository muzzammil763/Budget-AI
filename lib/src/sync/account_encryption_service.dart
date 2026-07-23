import 'dart:convert';

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

class AccountEncryptionService {
  AccountEncryptionService._();

  static final AccountEncryptionService instance = AccountEncryptionService._();
  static const _keyPrefix = 'budget_ai_account_data_key_v1_';
  static const _recoveryPrefix = 'BAI1';

  final AesGcm _cipher = AesGcm.with256bits();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  Future<bool> hasKey(String userId) async {
    return await _secureStorage.containsKey(key: '$_keyPrefix$userId');
  }

  Future<String> createRecoveryKey(String userId) async {
    final existing = await _readKeyBytes(userId);
    final keyBytes = existing ?? await _newKeyBytes();
    if (existing == null) await _writeKeyBytes(userId, keyBytes);
    return formatRecoveryKey(keyBytes);
  }

  Future<void> restoreRecoveryKey(String userId, String recoveryKey) async {
    final keyBytes = parseRecoveryKey(recoveryKey);
    await _writeKeyBytes(userId, keyBytes);
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
      throw const FormatException('Recovery key must contain 256 bits.');
    }
    await _secureStorage.write(
      key: '$_keyPrefix$userId',
      value: base64UrlEncode(keyBytes).replaceAll('=', ''),
    );
  }

  static String formatRecoveryKey(List<int> keyBytes) {
    if (keyBytes.length != 32) {
      throw const FormatException('Recovery key must contain 256 bits.');
    }
    final checksum = hashes.sha256.convert(keyBytes).bytes.take(4);
    final encoded = base64UrlEncode([
      ...keyBytes,
      ...checksum,
    ]).replaceAll('=', '');
    final groups = <String>[];
    for (var offset = 0; offset < encoded.length; offset += 6) {
      groups.add(
        encoded.substring(offset, (offset + 6).clamp(0, encoded.length)),
      );
    }
    return '$_recoveryPrefix-${groups.join('-')}';
  }

  static List<int> parseRecoveryKey(String value) {
    final compact = value.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (!compact.startsWith(_recoveryPrefix)) {
      throw const FormatException('This is not a Budget AI recovery key.');
    }
    final decoded = base64Url.decode(_padded(compact.substring(4)));
    if (decoded.length != 36) {
      throw const FormatException('The recovery key has an invalid length.');
    }
    final keyBytes = decoded.sublist(0, 32);
    final expected = hashes.sha256.convert(keyBytes).bytes.take(4).toList();
    final actual = decoded.sublist(32);
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected[index] ^ actual[index];
    }
    if (difference != 0) {
      throw const FormatException('The recovery key checksum is invalid.');
    }
    return keyBytes;
  }

  static String fingerprintForKey(List<int> keyBytes) {
    final digest = hashes.sha256.convert(keyBytes).bytes.take(18).toList();
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  static String _padded(String value) {
    return value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
  }
}
