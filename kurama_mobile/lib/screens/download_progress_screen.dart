import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/download_task.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import 'home_screen.dart';

class DownloadProgressScreen extends StatefulWidget {
  final String taskId;
  final DownloadTask task;

  const DownloadProgressScreen({
    super.key,
    required this.taskId,
    required this.task,
  });

  @override
  State<DownloadProgressScreen> createState() =>
      _DownloadProgressScreenState();
}

class _DownloadProgressScreenState extends State<DownloadProgressScreen> {
  Timer? _pollTimer;
  DownloadTask? _currentTask;
  bool _isSaving = false;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
    _startPolling();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    try {
      final api = context.read<ApiClient>();
      final updated = await api.getDownloadStatus(
        widget.taskId,
        url: widget.task.url,
      );
      if (!mounted) return;

      setState(() => _currentTask = updated);

      // Update the provider list
      context
          .read<AppState>()
          .updateDownload(widget.taskId, updated);

      // Stop polling on terminal states
      if (updated.status == DownloadStatus.completed ||
          updated.status == DownloadStatus.failed) {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // Polling error — just retry next cycle
    }
  }

  Future<void> _saveToDevice() async {
    setState(() => _isSaving = true);
    try {
      final api = context.read<ApiClient>();
      final path = await api.downloadFile(widget.taskId);
      if (!mounted) return;

      // Store the path in the download task so the downloads screen can share it
      final task = _currentTask;
      if (task != null) {
        task.localPath = path;
        task.isSavedLocally = true;
        context.read<AppState>().updateDownload(widget.taskId, task);
      }

      setState(() {
        _savedPath = path;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Save failed: ${e.toString()}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _shareFile(
      BuildContext context, String filePath, String title) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ File not found'),
          backgroundColor: Color(0xFFC62828),
        ),
      );
      return;
    }
    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: title,
        text: '📥 Downloaded via KuramaBot',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Share failed: ${e.toString()}'),
          backgroundColor: Color(0xFFC62828),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = _currentTask;
    if (task == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Download'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Status icon ──────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _buildStatusIcon(task, theme),
              ),

              const SizedBox(height: 24),

              // ── Progress bar ─────────────────────────────
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.pending) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: task.progress / 100,
                    minHeight: 12,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${task.progress}%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                if (task.progress > 0)
                  Text(
                    'Downloading from ${task.platform}...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],

              if (task.status == DownloadStatus.completed) ...[
                const SizedBox(height: 8),
                Text(
                  task.title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.fileSizeStr != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '📦 ${task.fileSizeStr}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                if (_savedPath != null) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: const Text('Saved to device'),
                      subtitle: Text(
                        _savedPath!.split('/').last,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.share, color: Colors.blue),
                        onPressed: () => _shareFile(context, _savedPath!, task.title),
                        tooltip: 'Share',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const HomeScreen()),
                            (route) => false,
                          ),
                          icon: const Icon(Icons.home_outlined),
                          label: const Text('Home'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              _shareFile(context, _savedPath!, task.title),
                          icon: const Icon(Icons.share),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveToDevice,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: Text(_isSaving ? 'Saving...' : 'Save to Device'),
                    ),
                  ),
                ],
              ],

              if (task.status == DownloadStatus.failed) ...[
                const SizedBox(height: 8),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            task.error ?? 'Unknown error',
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  ),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Back to Home'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(DownloadTask task, ThemeData theme) {
    switch (task.status) {
      case DownloadStatus.pending:
        return const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(strokeWidth: 4),
        );
      case DownloadStatus.downloading:
        return SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: task.progress / 100,
                  strokeWidth: 5,
                ),
              ),
              Text(
                '${task.progress}%',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, size: 80, color: Colors.green);
      case DownloadStatus.failed:
        return const Icon(Icons.error, size: 80, color: Colors.red);
    }
  }
}
