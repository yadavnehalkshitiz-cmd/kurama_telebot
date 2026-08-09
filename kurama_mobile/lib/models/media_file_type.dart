enum MediaFileType { video, audio, other }

const _audioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'wav',
  'flac',
};

const _videoExtensions = {
  'mp4',
  'mkv',
  'mov',
  'webm',
  'avi',
  'm4v',
};

MediaFileType classifyMediaFile({
  required String format,
  String? path,
}) {
  final normalizedFormat = format.trim().toLowerCase();
  if (normalizedFormat == 'audio') return MediaFileType.audio;

  final normalizedPath = path?.trim().toLowerCase() ?? '';
  final dot = normalizedPath.lastIndexOf('.');
  final extension = dot >= 0 ? normalizedPath.substring(dot + 1) : '';
  if (_audioExtensions.contains(extension)) return MediaFileType.audio;
  if (_videoExtensions.contains(extension)) return MediaFileType.video;

  if (normalizedFormat == 'video') return MediaFileType.video;
  return MediaFileType.other;
}

bool supportsGalleryExport(String format) =>
    format.trim().toLowerCase() == 'video';
