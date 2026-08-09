import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';
import '../services/app_state.dart';
import '../services/background_download_service.dart';
import '../widgets/platform_badge.dart';
import 'download_progress_screen.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

class VideoInfoScreen extends StatefulWidget {
  final VideoInfo info;

  const VideoInfoScreen({super.key, required this.info});

  @override
  State<VideoInfoScreen> createState() => _VideoInfoScreenState();
}

class _VideoInfoScreenState extends State<VideoInfoScreen> {
  String _selectedFormat = 'video';
  String _selectedVideoQuality = 'best';
  String _selectedAudioQuality = 'best';
  bool _downloadPlaylist = false;
  bool _isMobileData = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isMobileData = connectivity.contains(ConnectivityResult.mobile);
          // Suggest 720p on mobile data to save space/data
          if (_isMobileData && _selectedVideoQuality == 'best') {
            _selectedVideoQuality = '720p';
          }
        });
      }
    } catch (_) {}
  }

  static const _videoQualities = [
    ('best', '🎯 Best'),
    ('1080p', '1080p FHD'),
    ('720p', '720p HD'),
    ('480p', '480p SD'),
  ];

  static const _audioQualities = [
    ('best', '🎯 Best'),
    ('320k', '320 kbps'),
    ('192k', '192 kbps'),
    ('128k', '128 kbps'),
  ];

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${info.icon} ${info.platform}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ──────────────────────────────────
            if (info.thumbnail != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: Image.network(
                  info.thumbnail!,
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const _ThumbnailShimmer(height: 220);
                  },
                  errorBuilder: (_, __, ___) =>
                      const _ThumbnailPlaceholder(height: 140),
                ),
              )
            else
              const _ThumbnailPlaceholder(height: 140),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Platform badge ───────────────────────
                  PlatformBadge(icon: info.icon, name: info.platform),
                  const SizedBox(height: 12),

                  // ── Title ────────────────────────────────
                  Text(
                    info.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '👤 ${info.uploader}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Stats row ────────────────────────────
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(Icons.timer_outlined, info.durationStr),
                      _StatChip(Icons.storage_outlined, info.filesizeStr),
                      if (info.views != null)
                        _StatChip(Icons.visibility_outlined,
                            '${_formatViews(info.views!)} views'),
                      if (info.uploadDate != null)
                        _StatChip(
                            Icons.calendar_today_outlined, info.uploadDate!),
                    ],
                  ),

                  if (info.isPlaylist) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.playlist_play, size: 16, color: primary),
                          const SizedBox(width: 6),
                          Text(
                            'Playlist · ${info.playlistCount} videos',
                            style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Download all videos'),
                      subtitle: Text(
                        'Bundles up to ${info.playlistCount} videos into a ZIP file',
                      ),
                      value: _downloadPlaylist,
                      activeThumbColor: primary,
                      onChanged: (v) => setState(() => _downloadPlaylist = v),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Playlist ZIPs keep the original files — find them in '
                      'the Downloads tab after saving.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],

                  const Divider(height: 36),

                  // ── Format selection ─────────────────────
                  const _SectionLabel('Format'),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'video',
                          icon: Icon(Icons.videocam_outlined, size: 16),
                          label: Text('Video')),
                      ButtonSegment(
                          value: 'audio',
                          icon: Icon(Icons.music_note_outlined, size: 16),
                          label: Text('Audio')),
                      ButtonSegment(
                          value: 'doc',
                          icon: Icon(Icons.folder_zip_outlined, size: 16),
                          label: Text('Raw File')),
                    ],
                    selected: {_selectedFormat},
                    onSelectionChanged: (v) =>
                        setState(() => _selectedFormat = v.first),
                    style: ButtonStyle(
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      )),
                    ),
                  ),
                  if (_selectedFormat == 'doc') ...[
                    const SizedBox(height: 8),
                    Text(
                      '📄 Downloads the original file without re-encoding.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Quality selection ────────────────────
                  if (_selectedFormat == 'video') ...[
                    Row(
                      children: [
                        const _SectionLabel('Video Quality'),
                        if (_isMobileData) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.signal_cellular_alt,
                                    size: 10, color: Colors.orangeAccent),
                                SizedBox(width: 4),
                                Text(
                                  'Data Saver Active',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.orangeAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    _QualityGrid(
                      qualities: _videoQualities,
                      selected: _selectedVideoQuality,
                      onSelect: (v) =>
                          setState(() => _selectedVideoQuality = v),
                      primary: primary,
                    ),
                  ],

                  if (_selectedFormat == 'audio') ...[
                    const _SectionLabel('Audio Bitrate'),
                    const SizedBox(height: 10),
                    _QualityGrid(
                      qualities: _audioQualities,
                      selected: _selectedAudioQuality,
                      onSelect: (v) =>
                          setState(() => _selectedAudioQuality = v),
                      primary: primary,
                    ),
                  ],

                  const SizedBox(height: 32),

                  // ── Download button ──────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.download_rounded, size: 22),
                      label: const Text(
                        'Start Download',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Saved to device · Share from Downloads tab',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }

  Future<void> _startDownload() async {
    // Already downloaded this URL? Offer to open it instead of paying again.
    final existing = context
        .read<AppState>()
        .downloads
        .where((t) =>
            t.url == widget.info.url && t.status == DownloadStatus.completed)
        .firstOrNull;
    if (existing != null) {
      final open = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Already downloaded'),
              content: Text('“${existing.title}” is already in your downloads.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Download again'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open it'),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted) return;
      if (open) {
        if (existing.localPath != null &&
            File(existing.localPath!).existsSync()) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                filePath: existing.localPath!,
                title: existing.title,
                format: existing.format,
                artist: existing.format == 'audio' ? existing.platform : null,
                artworkUrl: existing.thumbnailUrl,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DownloadsScreen()),
          );
        }
        return;
      }
    }

    try {
      // ✅ FIX: access ApiClient through AppState — it's not provided separately
      final api = context.read<AppState>().client;
      final taskId = await api.startDownload(
        url: widget.info.url,
        userId: context.read<AppState>().userId,
        format: _selectedFormat,
        videoQuality: _selectedVideoQuality,
        audioQuality: _selectedAudioQuality,
        thumbnail: widget.info.thumbnail,
        playlist: _downloadPlaylist,
      );
      if (!mounted) return;

      final task = DownloadTask(
        taskId: taskId,
        url: widget.info.url,
        platform: widget.info.platform,
        icon: widget.info.icon,
        title: widget.info.title,
        // Playlist bundles are ZIP archives — label them as documents.
        format: _downloadPlaylist ? 'doc' : _selectedFormat,
        quality: _selectedFormat == 'audio'
            ? _selectedAudioQuality
            : _selectedVideoQuality,
        thumbnailUrl: widget.info.thumbnail,
      );
      Provider.of<AppState>(context, listen: false).addDownload(task);
      try {
        await BackgroundDownloadService.schedule(task: task, client: api);
      } catch (error) {
        debugPrint('[BackgroundDownload] Scheduling failed: $error');
      }
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DownloadProgressScreen(taskId: taskId, task: task),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.toString()}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }
}

// ── Quality grid ──────────────────────────────────────────
class _QualityGrid extends StatelessWidget {
  final List<(String, String)> qualities;
  final String selected;
  final ValueChanged<String> onSelect;
  final Color primary;

  const _QualityGrid({
    required this.qualities,
    required this.selected,
    required this.onSelect,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: qualities.map((q) {
        final (value, label) = q;
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onSelect(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? primary.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isSelected ? primary : Colors.white.withValues(alpha: 0.12),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? primary : Colors.white70,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatChip(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ThumbnailShimmer extends StatelessWidget {
  final double height;
  const _ThumbnailShimmer({required this.height});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: Colors.white.withValues(alpha: 0.06),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  final double height;
  const _ThumbnailPlaceholder({required this.height});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: Colors.white.withValues(alpha: 0.04),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 48, color: Colors.white24),
      ),
    );
  }
}
