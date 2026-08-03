enum DownloadStatus { pending, downloading, completed, failed }

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
  final DateTime createdAt;
  bool isSavedLocally;
  String? localPath;

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
    DateTime? createdAt,
    this.isSavedLocally = false,
    this.localPath,
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
      createdAt: parsedDate,
      isSavedLocally: json['is_saved_locally'] as bool? ?? false,
      localPath: json['local_path'] as String?,
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
        'created_at': createdAt.toIso8601String(),
        'is_saved_locally': isSavedLocally,
        'local_path': localPath,
      };
}
