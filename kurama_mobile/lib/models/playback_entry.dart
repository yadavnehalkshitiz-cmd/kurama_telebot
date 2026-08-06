/// A single item in the media player queue. Points at a file on device
/// (downloaded, imported, or decrypted-vault) plus display metadata.
class PlaybackEntry {
  final String path;
  final String title;
  final String format; // video | audio
  final String? artist;
  final String? artworkUrl;

  const PlaybackEntry({
    required this.path,
    required this.title,
    this.format = 'video',
    this.artist,
    this.artworkUrl,
  });

  bool get isAudio => format == 'audio';
}
