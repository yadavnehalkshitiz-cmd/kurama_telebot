import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FlutterSecureSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  FlutterSecureSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class VaultKeyStore {
  static const _keyName = 'vault.aes_key.v1';
  static const _pinSaltName = 'vault.pin_salt.v1';
  static const _pinHashName = 'vault.pin_hash.v1';

  final SecretStore _secrets;
  final Random _random;
  final Argon2id _argon2;

  VaultKeyStore(SecretStore secrets, {Random? random})
      : _secrets = secrets,
        _random = random ?? Random.secure(),
        _argon2 = Argon2id(
          parallelism: 1,
          memory: 19456,
          iterations: 2,
          hashLength: 32,
        );

  Future<SecretKey> getOrCreateKey() async {
    final existing = await _secrets.read(_keyName);
    if (existing != null) return SecretKey(base64Decode(existing));
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    await _secrets.write(_keyName, base64Encode(bytes));
    return SecretKey(bytes);
  }

  Future<bool> hasPin() async =>
      await _secrets.read(_pinSaltName) != null &&
      await _secrets.read(_pinHashName) != null;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN must contain six digits');
    }
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final hash = await _derive(pin, salt);
    await _secrets.write(_pinSaltName, base64Encode(salt));
    await _secrets.write(_pinHashName, base64Encode(hash));
  }

  Future<bool> verifyPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return false;
    final saltValue = await _secrets.read(_pinSaltName);
    final hashValue = await _secrets.read(_pinHashName);
    if (saltValue == null || hashValue == null) return false;
    final expected = base64Decode(hashValue);
    final actual = await _derive(pin, base64Decode(saltValue));
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0;
  }

  Future<List<int>> _derive(String pin, List<int> salt) async {
    final key = await _argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }
}
