import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/download_task.dart';
import '../services/app_state.dart';
import '../services/vault_cipher.dart';
import '../services/vault_key_store.dart';
import '../services/vault_service.dart';
import 'player_screen.dart';
import 'package:intl/intl.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context
        .watch<AppState>()
        .downloads
        .where((task) => !task.isPrivate)
        .toList();
    final failedCount = downloads.where((t) => t.status == DownloadStatus.failed).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          downloads.isEmpty
              ? 'Downloads'
              : 'Downloads (${downloads.length})',
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
        ],
      ),
      body: downloads.isEmpty
          ? _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: downloads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final task = downloads[index];
                return _DownloadCard(task: task);
              },
            ),
    );
  }

  void _clearFailed(BuildContext context) {
    final state = context.read<AppState>();
    final failed = state.downloads
        .where((t) => t.status == DownloadStatus.failed)
        .map((t) => t.taskId)
        .toList();
    for (final id in failed) {
      state.removeDownload(id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_outlined,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 20),
          Text(
            'No downloads yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste a link on the home screen to start',
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

  const _DownloadCard({required this.task});

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
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
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
      return PopupMenuButton<String>(
        tooltip: 'Media actions',
        onSelected: (action) => _handleAction(context, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'play', child: Text('Play offline')),
          PopupMenuItem(value: 'share', child: Text('Share')),
          PopupMenuItem(value: 'vault', child: Text('Move to private vault')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
    }
    if (task.status == DownloadStatus.failed) {
      return IconButton(
        icon: const Icon(Icons.delete_outline),
        color: Colors.red,
        onPressed: () => context.read<AppState>().removeDownload(task.taskId),
        tooltip: 'Remove',
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

  Future<void> _handleAction(BuildContext context, String action) async {
    if (action == 'share') return _shareFile(context, task);
    if (action == 'play') {
      final path = task.localPath;
      if (path == null || !File(path).existsSync()) {
        _message(context, 'File not found on this device');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            filePath: path,
            title: task.title,
            format: task.format,
          ),
        ),
      );
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
      final path = task.localPath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      if (context.mounted) context.read<AppState>().removeDownload(task.taskId);
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
}
