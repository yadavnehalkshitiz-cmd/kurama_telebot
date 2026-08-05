import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/services/vault_cipher.dart';

void main() {
  late Directory tempDirectory;
  final key = SecretKey(List<int>.generate(32, (index) => index));

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('kurama-vault-test-');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('encrypts and decrypts a file across multiple chunks', () async {
    final clearFile = File('${tempDirectory.path}/clear.bin');
    final encryptedFile = File('${tempDirectory.path}/private.kv');
    final restoredFile = File('${tempDirectory.path}/restored.bin');
    final clearBytes = List<int>.generate(97, (index) => (index * 17) % 256);
    await clearFile.writeAsBytes(clearBytes);

    final cipher = VaultCipher(chunkSize: 16);
    await cipher.encryptFile(clearFile, encryptedFile, key);
    await cipher.decryptFile(encryptedFile, restoredFile, key);

    expect(await restoredFile.readAsBytes(), clearBytes);
    expect(await encryptedFile.readAsBytes(), isNot(contains(clearBytes)));
  });

  test('rejects a tampered encrypted file and removes partial output', () async {
    final clearFile = File('${tempDirectory.path}/clear.bin');
    final encryptedFile = File('${tempDirectory.path}/private.kv');
    final restoredFile = File('${tempDirectory.path}/restored.bin');
    await clearFile.writeAsString('Kurama private media');

    final cipher = VaultCipher(chunkSize: 8);
    await cipher.encryptFile(clearFile, encryptedFile, key);
    final bytes = await encryptedFile.readAsBytes();
    bytes[bytes.length - 1] ^= 0xff;
    await encryptedFile.writeAsBytes(bytes);

    await expectLater(
      cipher.decryptFile(encryptedFile, restoredFile, key),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    expect(await restoredFile.exists(), isFalse);
  });

  test('rejects the wrong key', () async {
    final clearFile = File('${tempDirectory.path}/clear.bin');
    final encryptedFile = File('${tempDirectory.path}/private.kv');
    final restoredFile = File('${tempDirectory.path}/restored.bin');
    await clearFile.writeAsString('protected');

    final cipher = VaultCipher();
    await cipher.encryptFile(clearFile, encryptedFile, key);

    await expectLater(
      cipher.decryptFile(
        encryptedFile,
        restoredFile,
        SecretKey(List<int>.filled(32, 9)),
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
