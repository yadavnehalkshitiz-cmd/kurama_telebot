class VideoInfo {
  final String url;
  final String platform;
  final String icon;
  final String title;
  final String uploader;
  final int? duration;
  final String durationStr;
  final int? filesize;
  final String filesizeStr;
  final int? views;
  final String? thumbnail;
  final String? uploadDate;
  final bool isPlaylist;
  final int playlistCount;

  VideoInfo({
    required this.url,
    required this.platform,
    required this.icon,
    required this.title,
    required this.uploader,
    this.duration,
    required this.durationStr,
    this.filesize,
    required this.filesizeStr,
    this.views,
    this.thumbnail,
    this.uploadDate,
    this.isPlaylist = false,
    this.playlistCount = 0,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      url: json['url'] as String? ?? '',
      platform: json['platform'] as String? ?? 'Unknown',
      icon: json['icon'] as String? ?? '🔗',
      title: json['title'] as String? ?? 'Unknown',
      uploader: json['uploader'] as String? ?? 'Unknown',
      duration: json['duration'] as int?,
      durationStr: json['duration_str'] as String? ?? 'Unknown',
      filesize: json['filesize'] as int?,
      filesizeStr: json['filesize_str'] as String? ?? 'Unknown',
      views: json['views'] as int?,
      thumbnail: json['thumbnail'] as String?,
      uploadDate: json['upload_date'] as String?,
      isPlaylist: json['is_playlist'] as bool? ?? false,
      playlistCount: json['playlist_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'platform': platform,
        'icon': icon,
        'title': title,
        'uploader': uploader,
        'duration': duration,
        'duration_str': durationStr,
        'filesize': filesize,
        'filesize_str': filesizeStr,
        'views': views,
        'thumbnail': thumbnail,
        'upload_date': uploadDate,
        'is_playlist': isPlaylist,
        'playlist_count': playlistCount,
      };
}
