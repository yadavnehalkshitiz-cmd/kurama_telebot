import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/download_task.dart';
import '../services/app_state.dart';
import 'package:intl/intl.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<AppState>().downloads;
    final failedCount = downloads.where((t) => t.status == DownloadStatus.failed).length;
    final theme = Theme.of(context);

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
    final theme = Theme.of(context);

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
      return IconButton(
        icon: const Icon(Icons.share),
        color: Colors.blue,
        onPressed: () => _shareFile(context, task),
        tooltip: 'Share',
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
