import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/services/vault_key_store.dart';

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<String?> read(String key) async => values[key];
}

void main() {
  test('creates and then reuses a 256-bit vault key', () async {
    final secrets = MemorySecretStore();
    final store = VaultKeyStore(secrets);

    final first = await (await store.getOrCreateKey()).extractBytes();
    final second = await (await store.getOrCreateKey()).extractBytes();

    expect(first, hasLength(32));
    expect(second, first);
  });

  test('stores only a salted PIN verifier', () async {
    final secrets = MemorySecretStore();
    final store = VaultKeyStore(secrets);

    await store.setPin('123456');

    expect(secrets.values.values, isNot(contains('123456')));
    expect(await store.hasPin(), isTrue);
    expect(await store.verifyPin('123456'), isTrue);
    expect(await store.verifyPin('654321'), isFalse);
  });

  test('requires exactly six PIN digits', () async {
    final store = VaultKeyStore(MemorySecretStore());

    await expectLater(store.setPin('12345'), throwsArgumentError);
    await expectLater(store.setPin('12345x'), throwsArgumentError);
  });
}
