import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/platform_badge.dart';
import 'download_progress_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${info.icon} ${info.platform}',
          style: const TextStyle(fontSize: 16),
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
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Image.network(
                  info.thumbnail!,
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 140,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.movie_outlined, size: 48),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 120,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.movie_outlined, size: 48),
                ),
              ),

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
                  Row(
                    children: [
                      _buildStatChip(Icons.timer_outlined, info.durationStr),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.storage_outlined, info.filesizeStr),
                      if (info.views != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip(
                            Icons.visibility_outlined, '${info.views} views'),
                      ],
                    ],
                  ),

                  const Divider(height: 32),

                  // ── Format selection ─────────────────────
                  Text(
                    'Format',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'video', label: Text('🎬 Video')),
                      ButtonSegment(value: 'audio', label: Text('🎵 Audio')),
                      ButtonSegment(
                          value: 'doc', label: Text('📄 File (no encode)')),
                    ],
                    selected: {_selectedFormat},
                    onSelectionChanged: (v) =>
                        setState(() => _selectedFormat = v.first),
                  ),

                  const SizedBox(height: 24),

                  // ── Quality selection ────────────────────
                  if (_selectedFormat == 'video') ...[
                    Text(
                      'Video Quality',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _qualityChip('best', '🎯 Best'),
                        _qualityChip('1080p', '1080p'),
                        _qualityChip('720p', '720p'),
                        _qualityChip('480p', '480p'),
                      ],
                    ),
                  ],

                  if (_selectedFormat == 'audio') ...[
                    Text(
                      'Audio Bitrate',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _qualityChip('best', '🎯 Best'),
                        _qualityChip('320k', '320kbps'),
                        _qualityChip('192k', '192kbps'),
                        _qualityChip('128k', '128kbps'),
                      ],
                    ),
                  ],

                  const SizedBox(height: 32),

                  // ── Download button ──────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.download, size: 24),
                      label: const Text(
                        'Download',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Downloads are saved to your device and can be shared from the Downloads tab.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _qualityChip(String value, String label) {
    final isSelected = (_selectedFormat == 'audio'
            ? _selectedAudioQuality
            : _selectedVideoQuality) ==
        value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          if (_selectedFormat == 'audio') {
            _selectedAudioQuality = value;
          } else {
            _selectedVideoQuality = value;
          }
        });
      },
    );
  }

  Future<void> _startDownload() async {
    try {
      final api = context.read<ApiClient>();
      final taskId = await api.startDownload(
        url: widget.info.url,
        format: _selectedFormat,
        videoQuality: _selectedVideoQuality,
        audioQuality: _selectedAudioQuality,
      );

      // Add to download list in app state
      final task = DownloadTask(
        taskId: taskId,
        url: widget.info.url,
        platform: widget.info.platform,
        icon: widget.info.icon,
        title: widget.info.title,
        format: _selectedFormat,
        quality: _selectedFormat == 'audio'
            ? _selectedAudioQuality
            : _selectedVideoQuality,
      );
      Provider.of<AppState>(context, listen: false).addDownload(task);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DownloadProgressScreen(
            taskId: taskId,
            task: task,
          ),
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


