import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/download_task.dart';
import '../models/media_file_type.dart';
import '../models/playback_entry.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../services/media_library.dart';
import '../services/storage_manager.dart';
import '../services/vault_cipher.dart';
import '../services/vault_key_store.dart';
import '../services/vault_service.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  String _query = '';
  String _formatFilter = 'all'; // all | video | audio | doc
  bool _newestFirst = true;
  bool _searchOpen = false;
  StorageSummary? _storage;

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    StorageSummary? summary;
    try {
      summary = await StorageManager.scan(context.read<AppState>().downloads);
    } catch (_) {
      // A failed scan shouldn't break the Downloads tab.
    }
    if (mounted) setState(() => _storage = summary);
  }

  bool get _hasOffloadable {
    final downloads = context.read<AppState>().downloads;
    return downloads.any((t) =>
        !t.isPrivate &&
        !t.taskId.startsWith('local_') &&
        t.localPath != null &&
        t.localPath!.isNotEmpty &&
        File(t.localPath!).existsSync());
  }

  List<DownloadTask> get _visibleDownloads {
    final all = context
        .watch<AppState>()
        .downloads
        .where((task) => !task.isPrivate)
        .toList();
    final q = _query.trim().toLowerCase();
    final filtered = all.where((task) {
      if (_formatFilter != 'all' && task.format != _formatFilter) return false;
      if (q.isEmpty) return true;
      return task.title.toLowerCase().contains(q) ||
          task.platform.toLowerCase().contains(q);
    }).toList();
    filtered.sort((a, b) => _newestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));
    return filtered;
  }

  int get _failedCount {
    final all = context.read<AppState>().downloads;
    return all.where((t) => t.status == DownloadStatus.failed).length;
  }

  @override
  Widget build(BuildContext context) {
    final downloads = _visibleDownloads;
    final failedCount = _failedCount;
    final allCount = context.watch<AppState>().downloads.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          allCount == 0 ? 'Downloads' : 'Downloads ($allCount)',
        ),
        centerTitle: true,
        actions: [
          if (failedCount > 0)
            TextButton.icon(
              onPressed: () => _clearFailed(context),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text('Clear $failedCount failed'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          IconButton(
            tooltip: 'Import local file',
            icon: const Icon(Icons.library_add_outlined),
            onPressed: () => _importLocalFile(context),
          ),
          IconButton(
            tooltip: 'Search',
            icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _query = '';
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search downloads…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          if (downloads.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            selected: _formatFilter == 'all',
                            onTap: () => setState(() => _formatFilter = 'all'),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: '🎬 Video',
                            selected: _formatFilter == 'video',
                            onTap: () =>
                                setState(() => _formatFilter = 'video'),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: '🎵 Audio',
                            selected: _formatFilter == 'audio',
                            onTap: () =>
                                setState(() => _formatFilter = 'audio'),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: '📦 Doc',
                            selected: _formatFilter == 'doc',
                            onTap: () => setState(() => _formatFilter = 'doc'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _newestFirst ? 'Newest first' : 'Oldest first',
                    icon: Icon(
                      _newestFirst
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _newestFirst = !_newestFirst),
                  ),
                ],
              ),
            ),
          if (_storage != null &&
              (_storage!.usedBytes > 0 || _storage!.hasCleanup)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _StorageCard(
                summary: _storage!,
                onSweep: _storage!.hasCleanup
                    ? () => _sweepOrphans(context)
                    : null,
                onOffload: _hasOffloadable
                    ? () => _offloadFiles(context)
                    : null,
              ),
            ),
          ],
          Expanded(
            child: downloads.isEmpty
                ? _EmptyState(queryActive: _query.isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: downloads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = downloads[index];
                      return _DownloadCard(
                        task: task,
                        onPlayQueue: () => _playQueue(context, task),
                        onLibraryChanged: _loadStorage,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _clearFailed(BuildContext context) {
    final state = context.read<AppState>();
    final failed = state.downloads
        .where((t) => t.status == DownloadStatus.failed)
        .toList();
    for (final task in failed) {
      state.removeDownload(task.taskId);
      // Best-effort: drop any partial transfer left on disk.
      state.client
          .deletePartialFile(filename: task.filename, taskId: task.taskId);
    }
    _loadStorage();
  }

  Future<void> _sweepOrphans(BuildContext context) async {
    final summary = _storage;
    final count = summary?.orphanCount ?? 0;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sweep orphan files?'),
            content: Text(
              'Deletes $count unreferenced file${count == 1 ? '' : 's'} '
              '(${formatBytes(summary?.orphanBytes ?? 0)}) left over from '
              'interrupted or deleted downloads.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sweep'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final freed = await StorageManager.cleanupOrphans(
        context.read<AppState>().downloads);
    if (!mounted) return;
    _message(context,
        freed > 0 ? '🧹 Freed ${formatBytes(freed)}' : 'Nothing to sweep');
    _loadStorage();
  }

  Future<void> _offloadFiles(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Offload media files?'),
            content: const Text(
              'Deletes the downloaded media files but keeps them in your '
              'history so you can re-download any of them later. Private '
              'vault items and locally imported originals are kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Offload'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final state = context.read<AppState>();
    final removed = await StorageManager.offloadSavedFiles(state.downloads);
    for (final task in removed) {
      state.updateDownload(task.taskId, task);
    }
    if (!mounted) return;
    _message(
      context,
      removed.isEmpty
          ? 'No files to offload'
          : '🗑 Offloaded ${removed.length} file${removed.length == 1 ? '' : 's'} — history kept',
    );
    _loadStorage();
  }

  /// Builds a playback queue from all playable downloads, starting at [task].
  void _playQueue(BuildContext context, DownloadTask task) {
    final playable = context
        .read<AppState>()
        .downloads
        .where((t) =>
            !t.isPrivate &&
            t.status == DownloadStatus.completed &&
            t.localPath != null &&
            File(t.localPath!).existsSync())
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final index = playable.indexWhere((t) => t.taskId == task.taskId);
    if (index < 0) {
      _message(context, 'File not found on this device');
      return;
    }
    final entries = playable
        .map((t) => PlaybackEntry(
              path: t.localPath!,
              title: t.title,
              format: t.format,
              artist: t.format == 'audio' ? t.platform : null,
              artworkUrl: t.thumbnailUrl,
            ))
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          filePath: entries[index].path,
          title: entries[index].title,
          format: entries[index].format,
          artist: entries[index].artist,
          artworkUrl: entries[index].artworkUrl,
          entries: entries,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _importLocalFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const [
        'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma',
        'mp4', 'mkv', 'webm', 'mov', 'avi', '3gp', 'm4v',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      _message(context, 'Could not read that file');
      return;
    }
    final state = context.read<AppState>();
    final task = await importLocalFile(state, path);
    if (!mounted) return;
    if (task == null) {
      _message(context, 'Unsupported file type');
      return;
    }
    _loadStorage();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Imported ${task.title}'),
        action: SnackBarAction(
          label: 'Play',
          onPressed: () => _playQueue(context, task),
        ),
      ),
    );
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? primary
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool queryActive;

  const _EmptyState({this.queryActive = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            queryActive ? Icons.search_off_rounded : Icons.download_outlined,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 20),
          Text(
            queryActive ? 'No matches' : 'No downloads yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            queryActive
                ? 'Try a different search or filter'
                : 'Paste a link on Home, or import a local file with the + button',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPlayQueue;

  /// Refreshes the storage summary after file-affecting actions.
  final VoidCallback onLibraryChanged;

  const _DownloadCard({
    required this.task,
    required this.onPlayQueue,
    required this.onLibraryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusIcon) = switch (task.status) {
      DownloadStatus.completed => (const Color(0xFF4CAF50), Icons.check_circle),
      DownloadStatus.failed => (const Color(0xFFEF5350), Icons.error),
      DownloadStatus.downloading => (const Color(0xFFFF9800), Icons.downloading),
      DownloadStatus.pending => (Colors.grey, Icons.hourglass_empty),
    };

    final dateStr = DateFormat('MMM d · h:mm a').format(task.createdAt.toLocal());

    return Dismissible(
      key: Key(task.taskId),
      direction: (task.status == DownloadStatus.completed ||
              task.status == DownloadStatus.failed)
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) {
        context.read<AppState>().removeDownload(task.taskId);
        // Drop any partial transfer left on disk.
        context.read<AppState>().client.deletePartialFile(
              filename: task.filename,
              taskId: task.taskId,
            );
        onLibraryChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _CardThumbnail(task: task, statusColor: statusColor, statusIcon: statusIcon),
          title: Text(
            task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(task.icon ?? task.platform,
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(
                    task.statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  if (task.fileSizeStr != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '· ${task.fileSizeStr}',
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
              // Inline progress bar for active downloads
              if (task.status == DownloadStatus.downloading &&
                  task.progress > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.progress / 100,
                    minHeight: 4,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ],
          ),
          trailing: _buildTrailing(context, statusColor),
        ),
      ),
    );
  }

  Widget _buildTrailing(BuildContext context, Color statusColor) {
    if (task.status == DownloadStatus.completed) {
      final saved = task.localPath != null &&
          File(task.localPath!).existsSync();
      // Completed on the server but not on this device (interrupted save):
      // offer a resume action that continues the transfer via Range requests
      // instead of forcing a full re-download.
      if (!saved) {
        return IconButton(
          icon: const Icon(Icons.download_for_offline_outlined),
          color: const Color(0xFFFF8A65),
          tooltip: 'Save / Resume download',
          onPressed: () => _saveToDevice(context),
        );
      }
      return PopupMenuButton<String>(
        tooltip: 'Media actions',
        onSelected: (action) => _handleAction(context, action),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'play', child: Text('Play offline')),
          const PopupMenuItem(value: 'share', child: Text('Share')),
          if (supportsGalleryExport(task.format))
            const PopupMenuItem(
              value: 'gallery',
              child: Text('Save to Gallery'),
            ),
          const PopupMenuItem(
            value: 'vault',
            child: Text('Move to private vault'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
    }
    if (task.status == DownloadStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: const Color(0xFFFF8A65),
            tooltip: 'Retry download',
            onPressed: () => _retry(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.red,
            onPressed: () => context.read<AppState>().removeDownload(task.taskId),
            tooltip: 'Remove',
          ),
        ],
      );
    }
    // Pending / downloading — spinner
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        value: task.progress > 0 ? task.progress / 100 : null,
        color: statusColor,
      ),
    );
  }

  /// Re-runs a failed download on the server.
  Future<void> _retry(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    try {
      await state.client.retryDownload(task.taskId);
      if (!context.mounted) return;
      task
        ..status = DownloadStatus.pending
        ..progress = 0
        ..error = null;
      state.updateDownload(task.taskId, task);
      messenger.showSnackBar(
        const SnackBar(content: Text('🔄 Retrying download…')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ ${e.message}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Retry failed: ${e.toString()}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  /// Saves (or resumes) the completed download to the device. Interrupted
  /// transfers continue from their partial file via HTTP Range requests.
  Future<void> _saveToDevice(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = context.read<AppState>().client;
      final path = await api.downloadFile(task.taskId, filename: task.filename);
      if (!context.mounted) return;
      task
        ..localPath = path
        ..isSavedLocally = true;
      context.read<AppState>().updateDownload(task.taskId, task);
      onLibraryChanged();
      messenger.showSnackBar(
        const SnackBar(content: Text('✅ Saved to device')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ ${e.message}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Save failed: ${e.toString()}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    if (action == 'share') return _shareFile(context, task);
    if (action == 'gallery') return _saveToGallery(context, task);
    if (action == 'play') {
      final path = task.localPath;
      if (path == null || !File(path).existsSync()) {
        _message(context, 'File not found on this device');
        return;
      }
      onPlayQueue();
      return;
    }
    if (action == 'vault') {
      try {
        final keys = VaultKeyStore(FlutterSecureSecretStore());
        if (!await keys.hasPin()) {
          if (!context.mounted || !await _createVaultPin(context, keys)) return;
        }
        final vault = VaultService(
          VaultCipher(),
          keys,
        );
        final path = await vault.protect(task);
        if (!context.mounted) return;
        await context.read<AppState>().moveToVault(task.taskId, path);
        if (context.mounted) _message(context, 'Encrypted and moved to vault');
      } catch (error) {
        if (context.mounted) _message(context, 'Vault move failed: $error');
      }
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete download?'),
              content: const Text('This removes the local file and history entry.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !context.mounted) return;
      final state = context.read<AppState>();
      final path = task.localPath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      // Drop any partial transfer left on disk too.
      await state.client.deletePartialFile(
        filename: task.filename,
        taskId: task.taskId,
      );
      if (context.mounted) state.removeDownload(task.taskId);
      onLibraryChanged();
    }
  }

  Future<bool> _createVaultPin(
    BuildContext context,
    VaultKeyStore keys,
  ) async {
    Future<String?> ask(String title) async {
      final controller = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '6-digit PIN'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      controller.dispose();
      return value;
    }

    final first = await ask('Create vault PIN');
    if (first == null || !context.mounted) return false;
    final confirmation = await ask('Confirm vault PIN');
    if (confirmation != first) {
      if (context.mounted) _message(context, 'PINs did not match');
      return false;
    }
    try {
      await keys.setPin(first);
      return true;
    } on ArgumentError {
      if (context.mounted) _message(context, 'Use exactly six digits');
      return false;
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _shareFile(BuildContext context, DownloadTask task) async {
    final filePath = task.localPath;
    if (filePath == null || !File(filePath).existsSync()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ File not found on device. Save it first.'),
          backgroundColor: Color(0xFFC62828),
        ),
      );
      return;
    }
    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: task.title,
        text: '📥 Downloaded via KuramaBot',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Share failed: ${e.toString()}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _saveToGallery(BuildContext context, DownloadTask task) async {
    final filePath = task.localPath;
    if (filePath == null || !File(filePath).existsSync()) {
      if (!context.mounted) return;
      _message(context, '❌ File not found on device. Save it first.');
      return;
    }

    if (!supportsGalleryExport(task.format)) {
      if (context.mounted) {
        _message(
          context,
          'Gallery export is available for videos only. Use Share for this file.',
        );
      }
      return;
    }

    try {
      // Check permissions
      var status = await Permission.storage.status;
      if (status.isDenied) {
        status = await Permission.storage.request();
        if (status.isDenied && context.mounted) {
          _message(context, '⚠️ Storage permission denied');
          return;
        }
      }

      if (!context.mounted) return;
      _message(context, '⏳ Saving to Gallery…');

      await Gal.putVideo(filePath);

      if (context.mounted) {
        _message(context, '✅ Saved to Gallery!');
      }
    } catch (e) {
      if (context.mounted) {
        _message(context, '❌ Gallery save failed: ${e.toString()}');
      }
    }
  }
}

class _StorageCard extends StatelessWidget {
  final StorageSummary summary;
  final VoidCallback? onSweep;
  final VoidCallback? onOffload;

  const _StorageCard({
    required this.summary,
    this.onSweep,
    this.onOffload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sd_storage_rounded,
                    size: 20, color: Color(0xFFFF8A65)),
                const SizedBox(width: 8),
                Text(
                  'Storage',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  formatBytes(summary.usedBytes),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFFA060),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.downloadCount} downloaded file'
              '${summary.downloadCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
            if (summary.orphanCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                '🧹 ${summary.orphanCount} orphan'
                '${summary.orphanCount == 1 ? '' : 's'} · '
                '${formatBytes(summary.orphanBytes)} can be swept',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFFFB74D)),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onSweep,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: Text(summary.orphanCount > 0
                      ? 'Sweep orphans'
                      : 'Sweep'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onOffload,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('Offload files'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardThumbnail extends StatelessWidget {
  final DownloadTask task;
  final Color statusColor;
  final IconData statusIcon;

  const _CardThumbnail({
    required this.task,
    required this.statusColor,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = task.thumbnailUrl;
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: thumbnail != null
          ? Image.network(
              thumbnail,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Icon(statusIcon, color: statusColor, size: 22);
}
