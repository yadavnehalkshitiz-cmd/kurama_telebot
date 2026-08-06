import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/download_task.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import 'home_screen.dart';
import 'player_screen.dart';

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

class _DownloadProgressScreenState extends State<DownloadProgressScreen>
    with TickerProviderStateMixin {
  Timer? _pollTimer;
  StreamSubscription<DownloadTask>? _statusSub;
  bool _usingStream = false;
  DownloadTask? _currentTask;
  bool _isSaving = false;
  String? _savedPath;
  String? _fatalError;
  DateTime? _downloadStarted;

  // Success animation controller
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
    _downloadStarted = DateTime.now();
    _startPolling();

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(
      parent: _successCtrl,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _statusSub?.cancel();
    _successCtrl.dispose();
    super.dispose();
  }

  /// Live updates via SSE when available; a 3s polling timer stays on as a
  /// fallback (and takes over automatically if the stream drops).
  void _startPolling() {
    _connectStream();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_usingStream) _pollStatus();
    });
  }

  void _connectStream() {
    try {
      final api = context.read<AppState>().client;
      _statusSub = api
          .getDownloadStatusStream(widget.taskId, url: widget.task.url)
          .listen(
        _onStatus,
        onError: (Object error) {
          if (!mounted) return;
          _usingStream = false;
          // Auth failures are fatal — stop and tell the user how to fix it.
          if (error is ApiException && error.isAuthError) {
            _pollTimer?.cancel();
            _statusSub?.cancel();
            setState(() => _fatalError = error.message);
            _showError('Connection issue', error);
          }
        },
        onDone: () => _usingStream = false,
      );
      _usingStream = true;
    } catch (_) {
      _usingStream = false;
    }
  }

  void _onStatus(DownloadTask updated) {
    if (!mounted) return;
    if (_fatalError != null) setState(() => _fatalError = null);

    final wasNotCompleted = _currentTask?.status != DownloadStatus.completed;
    // Older servers don't echo the thumbnail — keep the one captured when
    // the download was started so the player artwork survives.
    if (updated.thumbnailUrl == null) {
      updated.thumbnailUrl = widget.task.thumbnailUrl;
    }
    setState(() => _currentTask = updated);
    context.read<AppState>().updateDownload(widget.taskId, updated);

    if (updated.status == DownloadStatus.completed ||
        updated.status == DownloadStatus.failed) {
      _pollTimer?.cancel();
      _statusSub?.cancel();
      if (wasNotCompleted && updated.status == DownloadStatus.completed) {
        _successCtrl.forward();
      }
      // The background worker may have already saved the file while the
      // foreground screen was polling — surface it instead of re-downloading.
      if (updated.status == DownloadStatus.completed && _savedPath == null) {
        final alreadySaved = context
            .read<AppState>()
            .downloads
            .where((t) =>
                t.taskId == widget.taskId && t.localPath != null)
            .firstOrNull;
        if (alreadySaved?.localPath != null) {
          setState(() => _savedPath = alreadySaved!.localPath);
        }
      }
    }
  }

  Future<void> _pollStatus() async {
    try {
      final api = context.read<AppState>().client;
      final updated = await api.getDownloadStatus(
        widget.taskId,
        url: widget.task.url,
      );
      if (!mounted) return;
      _onStatus(updated);
    } on ApiException catch (error) {
      // Auth failures are fatal — stop the silent retry loop.
      if (error.isAuthError) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() => _fatalError = error.message);
          _showError('Connection issue', error);
        }
      }
      // Other transient errors — retry next cycle
    } catch (_) {
      // Polling error — retry next cycle
    }
  }

  /// Re-run a failed download on the server and resume watching it.
  Future<void> _retryDownload() async {
    setState(() => _fatalError = null);
    try {
      final api = context.read<AppState>().client;
      await api.retryDownload(widget.taskId);
      if (!mounted) return;
      setState(() {
        _currentTask?.status = DownloadStatus.pending;
        _currentTask?.progress = 0;
        _currentTask?.error = null;
      });
      _startPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _fatalError = e.message);
      _showError('Retry failed', e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fatalError = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Retry failed: ${e.toString()}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _saveToDevice() async {
    setState(() => _isSaving = true);
    try {
      final api = context.read<AppState>().client;
      // Server-provided filename keeps the real extension (mp3/mp4/webm...)
      // so the saved file plays correctly in the media player.
      final path = await api.downloadFile(
        widget.taskId,
        filename: _currentTask?.filename,
      );
      if (!mounted) return;

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
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Save failed', e);
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

  /// Human-friendly error with an action when the fix is a UI decision.
  void _showError(String title, ApiException error) {
    final String message;
    final String? actionLabel;
    final VoidCallback? action;
    if (error.isAuthError) {
      message =
          'API key rejected by the server. Update it in Home → ⚙️ Server Settings.';
      actionLabel = 'Back';
      action = () => Navigator.pop(context);
    } else if (error.isOutOfCredits) {
      message = 'No credits left — claim your daily reward in the Profile tab.';
      actionLabel = 'Back';
      action = () => Navigator.pop(context);
    } else {
      message = error.message;
      actionLabel = null;
      action = null;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $title: $message'),
        backgroundColor: const Color(0xFFC62828),
        action: action == null
            ? null
            : SnackBarAction(label: actionLabel!, onPressed: action),
      ),
    );
  }

  Future<void> _openPlayer(String path, DownloadTask task) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          filePath: path,
          title: task.title,
          format: task.format,
          artist: task.format == 'audio' ? task.platform : null,
          artworkUrl: task.thumbnailUrl,
        ),
      ),
    );
  }

  Future<void> _shareFile(String filePath, String title) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ File not found on device'),
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
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  String get _elapsedTime {
    if (_downloadStarted == null) return '';
    final elapsed =
        DateTime.now().difference(_downloadStarted!).inSeconds;
    if (elapsed < 60) return '${elapsed}s';
    return '${elapsed ~/ 60}m ${elapsed % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final task = _currentTask;
    if (task == null) return const Scaffold();

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloading'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Status icon ──────────────────────────────
              _buildStatusWidget(task, theme, primary),

              if (_fatalError != null) ...[
                const SizedBox(height: 20),
                _InlineError(message: _fatalError!),
              ],

              const SizedBox(height: 28),

              // ── Title ────────────────────────────────────
              Text(
                task.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),
              Text(
                '${task.icon ?? ''} ${task.platform} · ${task.format.toUpperCase()} · ${task.quality}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              // ── Progress / status area ───────────────────
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.pending) ...[
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: task.status == DownloadStatus.pending
                        ? null
                        : task.progress / 100,
                    minHeight: 10,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(primary),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      task.status == DownloadStatus.pending
                          ? 'Starting...'
                          : '${task.progress}%',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    Text(
                      _elapsedTime,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (task.fileSizeStr != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '📦 ${task.fileSizeStr}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (task.speedLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${task.speedLabel}${task.etaSeconds == null ? '' : ' • ${task.etaSeconds}s left'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],

              // ── Completed ────────────────────────────────
              if (task.status == DownloadStatus.completed) ...[
                const SizedBox(height: 24),
                if (task.fileSizeStr != null)
                  Text(
                    '📦 ${task.fileSizeStr}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 24),
                if (_savedPath != null) ...[
                  _SavedCard(
                    path: _savedPath!,
                    onPlay: () => _openPlayer(_savedPath!, task),
                    onShare: () =>
                        _shareFile(_savedPath!, task.title),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.pushAndRemoveUntil(
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
                              _openPlayer(_savedPath!, task),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveToDevice,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.download_rounded),
                      label:
                          Text(_isSaving ? 'Saving...' : 'Save to Device'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HomeScreen()),
                      (route) => false,
                    ),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Back to Home'),
                  ),
                ],
              ],

              // ── Failed ───────────────────────────────────
              if (task.status == DownloadStatus.failed) ...[
                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.errorContainer
                      .withValues(alpha: 0.5),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _retryDownload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry download'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const HomeScreen()),
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

  Widget _buildStatusWidget(
      DownloadTask task, ThemeData theme, Color primary) {
    switch (task.status) {
      case DownloadStatus.pending:
        return SizedBox(
          width: 90,
          height: 90,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: primary,
          ),
        );

      case DownloadStatus.downloading:
        return SizedBox(
          width: 90,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(
                  value: task.progress / 100,
                  strokeWidth: 6,
                  color: primary,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${task.progress}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                  Text(
                    '%',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: primary),
                  ),
                ],
              ),
            ],
          ),
        );

      case DownloadStatus.completed:
        return ScaleTransition(
          scale: _successScale,
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.15),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded,
                size: 52, color: Colors.green),
          ),
        );

      case DownloadStatus.failed:
        return Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.15),
          ),
          child: const Icon(Icons.error_rounded,
              size: 52, color: Colors.red),
        );
    }
  }
}

// ── Inline fatal error ─────────────────────────────────────
class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFC62828).withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.key_off_rounded,
                size: 20, color: Color(0xFFFF8A65)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Saved card ────────────────────────────────────────────
class _SavedCard extends StatelessWidget {
  final String path;
  final VoidCallback onPlay;
  final VoidCallback onShare;

  const _SavedCard({
    required this.path,
    required this.onPlay,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final filename = path.split('/').last;
    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.check_rounded,
              color: Colors.green, size: 22),
        ),
        title: const Text('Saved to device',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          filename,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_fill_rounded,
                  color: Color(0xFFFF8A65)),
              onPressed: onPlay,
              tooltip: 'Play',
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.blue),
              onPressed: onShare,
              tooltip: 'Share',
            ),
          ],
        ),
      ),
    );
  }
}
