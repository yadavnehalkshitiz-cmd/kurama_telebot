enum DownloadStatus { pending, downloading, completed, failed }

extension DownloadStatusDisplay on DownloadStatus {
  String get displayLabel => name.toUpperCase();
}

class DownloadTask {
  final String taskId;
  final String url;
  final String platform;
  final String? icon;
  final String title;
  final String format;
  final String quality;
  DownloadStatus status;
  int progress;
  int? fileSize;
  String? fileSizeStr;
  String? error;
  int? speedBytesPerSecond;
  String? speedLabel;
  int? etaSeconds;
  final DateTime createdAt;
  bool isSavedLocally;
  String? localPath;
  String? filename;

  /// Artwork URL captured at download time, shown in the media player.
  String? thumbnailUrl;
  bool isPrivate;
  String? vaultPath;

  DownloadTask({
    required this.taskId,
    required this.url,
    required this.platform,
    this.icon,
    required this.title,
    this.format = 'video',
    this.quality = 'best',
    this.status = DownloadStatus.pending,
    this.progress = 0,
    this.fileSize,
    this.fileSizeStr,
    this.error,
    this.speedBytesPerSecond,
    this.speedLabel,
    this.etaSeconds,
    DateTime? createdAt,
    this.isSavedLocally = false,
    this.localPath,
    this.filename,
    this.thumbnailUrl,
    this.isPrivate = false,
    this.vaultPath,
  }) : createdAt = createdAt ?? DateTime.now();

  String get statusLabel {
    switch (status) {
      case DownloadStatus.pending:
        return 'Queued';
      case DownloadStatus.downloading:
        return 'Downloading $progress%';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.failed:
        return 'Failed';
    }
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json,
      {String? taskId, String? url}) {
    DateTime? parsedDate;
    final raw = json['created_at'] as String?;
    if (raw != null) {
      parsedDate = DateTime.tryParse(raw);
    }

    return DownloadTask(
      taskId: taskId ?? json['task_id'] as String? ?? '',
      url: url ?? json['url'] as String? ?? '',
      platform: json['platform'] as String? ?? 'Unknown',
      icon: json['icon'] as String?,
      title: json['title'] as String? ?? 'Unknown',
      format: json['format'] as String? ?? 'video',
      quality: json['quality'] as String? ?? 'best',
      status: _parseStatus(json['status'] as String?),
      progress: json['progress'] as int? ?? 0,
      fileSize: json['file_size'] as int?,
      fileSizeStr: json['file_size_str'] as String?,
      error: json['error'] as String?,
      speedBytesPerSecond:
          (json['speed_bytes_per_second'] as num?)?.toInt(),
      speedLabel: json['speed_label'] as String?,
      etaSeconds: (json['eta_seconds'] as num?)?.toInt(),
      createdAt: parsedDate,
      isSavedLocally: json['is_saved_locally'] as bool? ?? false,
      localPath: json['local_path'] as String?,
      filename: json['filename'] as String?,
      thumbnailUrl: json['thumbnail'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      vaultPath: json['vault_path'] as String?,
    );
  }

  static DownloadStatus _parseStatus(String? s) {
    switch (s) {
      case 'pending':
        return DownloadStatus.pending;
      case 'downloading':
        return DownloadStatus.downloading;
      case 'completed':
        return DownloadStatus.completed;
      case 'failed':
        return DownloadStatus.failed;
      default:
        return DownloadStatus.pending;
    }
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'url': url,
        'platform': platform,
        'icon': icon,
        'title': title,
        'format': format,
        'quality': quality,
        'status': status.name,
        'progress': progress,
        'file_size': fileSize,
        'file_size_str': fileSizeStr,
        'error': error,
        'speed_bytes_per_second': speedBytesPerSecond,
        'speed_label': speedLabel,
        'eta_seconds': etaSeconds,
        'created_at': createdAt.toIso8601String(),
        'is_saved_locally': isSavedLocally,
        'local_path': localPath,
        'filename': filename,
        'thumbnail': thumbnailUrl,
        'is_private': isPrivate,
        'vault_path': vaultPath,
      };
}
