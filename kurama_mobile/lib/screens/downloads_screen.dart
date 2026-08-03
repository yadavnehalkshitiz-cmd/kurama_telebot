import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/download_task.dart';
import '../services/app_state.dart';
import 'home_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<AppState>().downloads;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        centerTitle: true,
      ),
      body: downloads.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No downloads yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paste a link on the home screen to start',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
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
}

class _DownloadCard extends StatelessWidget {
  final DownloadTask task;

  const _DownloadCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    IconData statusIcon;
    switch (task.status) {
      case DownloadStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case DownloadStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case DownloadStatus.downloading:
        statusColor = Colors.orange;
        statusIcon = Icons.downloading;
        break;
      case DownloadStatus.pending:
        statusColor = Colors.grey;
        statusIcon = Icons.hourglass_empty;
        break;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Text(task.icon ?? task.platform),
            const SizedBox(width: 6),
            Text(
              task.statusLabel,
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
            if (task.fileSizeStr != null) ...[
              const SizedBox(width: 8),
              Text(
                '• ${task.fileSizeStr}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: task.status == DownloadStatus.completed
            ? IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _shareFile(context, task),
                tooltip: 'Share',
              )
            : task.status == DownloadStatus.failed
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      context
                          .read<AppState>()
                          .removeDownload(task.taskId);
                    },
                    tooltip: 'Remove',
                  )
                : SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: task.progress > 0 ? task.progress / 100 : null,
                    ),
                  ),
      ),
    );
  }

  Future<void> _shareFile(BuildContext context, DownloadTask task) async {
    final filePath = task.localPath;
    if (filePath == null || !File(filePath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ File not found on device'),
          backgroundColor: Color(0xFFC62828),
        ),
      );
      return;
    }
    try {
      final xFile = XFile(filePath);
      await Share.shareXFiles(
        [xFile],
        subject: task.title,
        text: '📥 Downloaded via KuramaBot',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Share failed: ${e.toString()}'),
          backgroundColor: Color(0xFFC62828),
        ),
      );
    }
  }
}
