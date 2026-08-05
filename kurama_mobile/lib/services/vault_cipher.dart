import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Chunked, authenticated file encryption for private media.
class VaultCipher {
  static final List<int> _magic = ascii.encode('KURAMAV1');
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  final int chunkSize;
  final AesGcm _algorithm;

  VaultCipher({this.chunkSize = 1024 * 1024})
      : assert(chunkSize > 0),
        _algorithm = AesGcm.with256bits();

  Future<void> encryptFile(
    File source,
    File destination,
    SecretKey key,
  ) async {
    await destination.parent.create(recursive: true);
    final input = await source.open();
    final output = await destination.open(mode: FileMode.write);
    try {
      await output.writeFrom(_magic);
      while (true) {
        final clearBytes = await input.read(chunkSize);
        if (clearBytes.isEmpty) break;
        final nonce = _algorithm.newNonce();
        final box = await _algorithm.encrypt(
          clearBytes,
          secretKey: key,
          nonce: nonce,
        );
        final length = ByteData(4)..setUint32(0, clearBytes.length);
        await output.writeFrom(length.buffer.asUint8List());
        await output.writeFrom(box.nonce);
        await output.writeFrom(box.cipherText);
        await output.writeFrom(box.mac.bytes);
      }
      await output.flush();
    } catch (_) {
      await output.close();
      await input.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    await output.close();
    await input.close();
  }

  Future<void> decryptFile(
    File source,
    File destination,
    SecretKey key,
  ) async {
    await destination.parent.create(recursive: true);
    final input = await source.open();
    final output = await destination.open(mode: FileMode.write);
    try {
      final magic = await input.read(_magic.length);
      if (!_constantTimeEquals(magic, _magic)) {
        throw const FormatException('Not a Kurama vault file');
      }
      while (true) {
        final lengthBytes = await input.read(4);
        if (lengthBytes.isEmpty) break;
        if (lengthBytes.length != 4) {
          throw const FormatException('Truncated vault chunk header');
        }
        final length = ByteData.sublistView(Uint8List.fromList(lengthBytes))
            .getUint32(0);
        if (length <= 0 || length > chunkSize) {
          throw const FormatException('Invalid vault chunk length');
        }
        final nonce = await input.read(_nonceLength);
        final cipherText = await input.read(length);
        final mac = await input.read(_macLength);
        if (nonce.length != _nonceLength ||
            cipherText.length != length ||
            mac.length != _macLength) {
          throw const FormatException('Truncated vault chunk');
        }
        final clearBytes = await _algorithm.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
          secretKey: key,
        );
        await output.writeFrom(clearBytes);
      }
      await output.flush();
    } catch (_) {
      await output.close();
      await input.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    await output.close();
    await input.close();
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
