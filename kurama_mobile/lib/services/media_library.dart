import 'dart:io';

import '../models/download_task.dart';
import 'app_state.dart';

const _audioExts = {
  'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'aiff',
};
const _videoExts = {
  'mp4', 'mkv', 'webm', 'mov', 'avi', '3gp', 'm4v', 'mpeg', 'mpg',
};

/// Lowercased extension of [path] (no dot), or null when none.
String? mediaFileExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return null;
  final ext = path.substring(dot + 1).toLowerCase();
  if (ext.isEmpty || ext.contains(RegExp(r'[/\\\s]'))) return null;
  return ext;
}

/// 'audio', 'video', or null when the file is not a playable media type.
String? mediaFormatFor(String path) {
  final ext = mediaFileExtension(path);
  if (ext == null) return null;
  if (_audioExts.contains(ext)) return 'audio';
  if (_videoExts.contains(ext)) return 'video';
  return null;
}

bool isMediaFile(String path) => mediaFormatFor(path) != null;

String fileNameFromPath(String path) => path.split(RegExp(r'[/\\]')).last;

/// Imports a local media file into the download library so it can be played,
/// queued, shared, or moved to the vault. Returns the (possibly existing) task,
/// or null when the path is not a playable media file.
Future<DownloadTask?> importLocalFile(AppState state, String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final format = mediaFormatFor(path);
  if (format == null) return null;

  // Deduplicate: the same physical file is already in the library.
  for (final task in state.downloads) {
    if (task.localPath == path) return task;
  }

  final task = DownloadTask(
    taskId: 'local_${DateTime.now().millisecondsSinceEpoch}',
    url: path,
    platform: 'Local',
    icon: format == 'audio' ? '🎵' : '🎬',
    title: fileNameFromPath(path),
    format: format,
    quality: 'local',
    status: DownloadStatus.completed,
    isSavedLocally: true,
    localPath: path,
  );
  state.addDownload(task);
  return task;
}
