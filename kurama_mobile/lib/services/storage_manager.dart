import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/download_task.dart';
import 'api_client.dart';

/// Human-readable byte size ("1.2 GB", "340 MB"…).
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Snapshot of on-device storage used by downloaded media.
class StorageSummary {
  /// Total bytes in the app's media folder (files + orphans).
  final int usedBytes;

  /// Number of download entries that have a local file.
  final int downloadCount;

  /// Unreferenced `.part` files (interrupted transfers with no matching task).
  final int orphanPartCount;
  final int orphanPartBytes;

  /// Files in the folder not referenced by any download entry.
  final int staleCount;
  final int staleBytes;

  const StorageSummary({
    required this.usedBytes,
    required this.downloadCount,
    required this.orphanPartCount,
    required this.orphanPartBytes,
    required this.staleCount,
    required this.staleBytes,
  });

  bool get hasCleanup => orphanPartCount > 0 || staleCount > 0;

  int get orphanCount => orphanPartCount + staleCount;
  int get orphanBytes => orphanPartBytes + staleBytes;

  static const empty = StorageSummary(
    usedBytes: 0,
    downloadCount: 0,
    orphanPartCount: 0,
    orphanPartBytes: 0,
    staleCount: 0,
    staleBytes: 0,
  );
}

class _ScanResult {
  final StorageSummary summary;
  final List<File> orphanPartFiles;
  final List<File> staleFiles;

  const _ScanResult(this.summary, this.orphanPartFiles, this.staleFiles);
}

/// Inspects and cleans the app's media folder (`<documents>/KuramaBot`).
class StorageManager {
  /// A `.part` younger than this is considered an active transfer, not an
  /// orphan — protects downloads whose filename wasn't known in advance.
  static const _activePartGrace = Duration(minutes: 10);

  static Future<Directory?> _downloadDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/KuramaBot');
    return await dir.exists() ? dir : null;
  }

  static String _norm(String path) => path.replaceAll('\\', '/');

  static Future<_ScanResult> _classify(List<DownloadTask> downloads) async {
    final dir = await _downloadDir();
    if (dir == null) {
      return const _ScanResult(StorageSummary.empty, [], []);
    }
    final base = _norm(dir.path);
    final knownFiles = <String>{};
    final knownPartBases = <String>{};
    var downloadCount = 0;
    for (final task in downloads) {
      final name = task.filename;
      if (name != null && name.trim().isNotEmpty) {
        knownPartBases.add('$base/${ApiClient.sanitizeFilename(name)}.part');
      }
      final local = task.localPath;
      if (local != null && local.isNotEmpty) {
        knownFiles.add(_norm(local));
        downloadCount++;
      }
      final vault = task.vaultPath;
      if (vault != null && vault.isNotEmpty) knownFiles.add(_norm(vault));
    }

    final cutoff = DateTime.now().subtract(_activePartGrace);
    var used = 0;
    var orphanPartCount = 0;
    var orphanPartBytes = 0;
    var staleCount = 0;
    var staleBytes = 0;
    final orphanParts = <File>[];
    final staleFiles = <File>[];

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      FileStat stat;
      try {
        stat = await entity.stat();
      } catch (_) {
        continue;
      }
      if (stat.type != FileSystemEntityType.file) continue;
      used += stat.size;
      final path = _norm(entity.path);
      // Both branches apply the grace cutoff: a fresh file may belong to a
      // transfer that just renamed its `.part` but hasn't written the task's
      // localPath yet — sweeping it would destroy a completed download.
      if (path.endsWith('.part')) {
        if (!knownPartBases.contains(path) && stat.modified.isBefore(cutoff)) {
          orphanPartCount++;
          orphanPartBytes += stat.size;
          orphanParts.add(entity);
        }
      } else if (!knownFiles.contains(path) && stat.modified.isBefore(cutoff)) {
        staleCount++;
        staleBytes += stat.size;
        staleFiles.add(entity);
      }
    }

    return _ScanResult(
      StorageSummary(
        usedBytes: used,
        downloadCount: downloadCount,
        orphanPartCount: orphanPartCount,
        orphanPartBytes: orphanPartBytes,
        staleCount: staleCount,
        staleBytes: staleBytes,
      ),
      orphanParts,
      staleFiles,
    );
  }

  static Future<StorageSummary> scan(List<DownloadTask> downloads) async =>
      (await _classify(downloads)).summary;

  /// Deletes orphaned `.part` files and unreferenced leftover files.
  /// Returns the number of bytes freed.
  static Future<int> cleanupOrphans(List<DownloadTask> downloads) async {
    final result = await _classify(downloads);
    var freed = 0;
    for (final file in [...result.orphanPartFiles, ...result.staleFiles]) {
      try {
        freed += await file.length();
        await file.delete();
      } catch (_) {}
    }
    return freed;
  }

  /// Deletes the media files of saved downloads while keeping their history
  /// (they can be re-downloaded later). Skips private vault items and locally
  /// imported files (the user's own originals). Returns the tasks whose files
  /// were removed; the caller should persist the changes.
  static Future<List<DownloadTask>> offloadSavedFiles(
      List<DownloadTask> downloads) async {
    final removed = <DownloadTask>[];
    for (final task in downloads) {
      if (task.isPrivate || task.taskId.startsWith('local_')) continue;
      final path = task.localPath;
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        // Drop any resume partial for the same file too.
        final name = task.filename;
        if (name != null && name.trim().isNotEmpty) {
          final dir = await _downloadDir();
          if (dir != null) {
            final partial = File(
                '${dir.path}/${ApiClient.sanitizeFilename(name)}.part');
            if (await partial.exists()) await partial.delete();
          }
        }
        task
          ..localPath = null
          ..isSavedLocally = false;
        removed.add(task);
      } catch (_) {}
    }
    return removed;
  }
}
