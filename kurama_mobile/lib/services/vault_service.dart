import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/download_task.dart';
import 'vault_cipher.dart';
import 'vault_key_store.dart';

class VaultService {
  final VaultCipher _cipher;
  final VaultKeyStore _keys;

  VaultService(this._cipher, this._keys);

  Future<String> protect(DownloadTask task) async {
    final localPath = task.localPath;
    if (localPath == null || localPath.isEmpty) {
      throw StateError('The download is not stored on this device');
    }
    final source = File(localPath);
    if (!await source.exists()) throw StateError('The media file is missing');
    final support = await getApplicationSupportDirectory();
    final vaultDirectory = Directory('${support.path}/private_vault');
    await vaultDirectory.create(recursive: true);
    final destination = File('${vaultDirectory.path}/${task.taskId}.kurama');
    final staging = File('${destination.path}.tmp');
    if (await staging.exists()) await staging.delete();
    await _cipher.encryptFile(source, staging, await _keys.getOrCreateKey());
    if (await destination.exists()) await destination.delete();
    await staging.rename(destination.path);
    await source.delete();
    return destination.path;
  }

  Future<File> openForPlayback(DownloadTask task) async {
    final vaultPath = task.vaultPath;
    if (vaultPath == null || vaultPath.isEmpty) {
      throw StateError('The encrypted media is missing');
    }
    final source = File(vaultPath);
    if (!await source.exists()) throw StateError('The encrypted media is missing');
    final temp = await getTemporaryDirectory();
    final extension = task.format == 'audio' ? 'mp3' : 'mp4';
    final destination = File('${temp.path}/vault_${task.taskId}.$extension');
    if (await destination.exists()) await destination.delete();
    await _cipher.decryptFile(source, destination, await _keys.getOrCreateKey());
    return destination;
  }

  Future<void> removePlaybackCopy(File file) async {
    if (await file.exists()) await file.delete();
  }
}
