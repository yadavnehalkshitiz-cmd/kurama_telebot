import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/download_task.dart';
import 'api_client.dart';
import 'download_storage.dart';
import 'notification_service.dart';

const _backgroundDownloadTask = 'kurama.background.download';

@pragma('vm:entry-point')
void backgroundDownloadDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _backgroundDownloadTask || inputData == null) return false;
    await NotificationService.initialize();
    final taskId = inputData['taskId'] as String;
    final title = inputData['title'] as String? ?? 'Kurama download';
    final format = inputData['format'] as String? ?? 'video';
    final client = ApiClient(
      baseUrl: inputData['baseUrl'] as String,
      apiKey: inputData['apiKey'] as String,
    );
    try {
      DownloadTask? status;
      for (var attempt = 0; attempt < 150; attempt++) {
        status = await client.getDownloadStatus(
          taskId,
          url: inputData['url'] as String? ?? '',
        );
        await NotificationService.showProgress(
          taskId: taskId,
          title: title,
          progress: status.progress,
          speed: status.speedLabel,
        );
        if (status.status == DownloadStatus.completed) break;
        if (status.status == DownloadStatus.failed) {
          throw ApiException(status.error ?? 'Server download failed');
        }
        await Future<void>.delayed(const Duration(seconds: 4));
      }
      if (status?.status != DownloadStatus.completed) {
        throw ApiException('Background download timed out');
      }
      final extension = format == 'audio' ? 'mp3' : 'mp4';
      final path = await client.downloadFile(
        taskId,
        filename: 'download_$taskId.$extension',
      );
      status!
        ..localPath = path
        ..isSavedLocally = true;
      final storage = DownloadStorage(await SharedPreferences.getInstance());
      final downloads = storage.loadDownloads();
      final index = downloads.indexWhere((task) => task.taskId == taskId);
      if (index >= 0) downloads[index] = status;
      await storage.saveDownloads(downloads);
      await NotificationService.showComplete(
        taskId: taskId,
        title: title,
        filePath: path,
      );
      return true;
    } catch (error) {
      await NotificationService.showFailed(taskId, error.toString());
      return false;
    }
  });
}

class BackgroundDownloadService {
  static Future<void> initialize() =>
      Workmanager().initialize(backgroundDownloadDispatcher);

  static Future<void> schedule({
    required DownloadTask task,
    required ApiClient client,
  }) =>
      Workmanager().registerOneOffTask(
        Platform.isIOS ? _backgroundDownloadTask : 'kurama-${task.taskId}',
        _backgroundDownloadTask,
        inputData: {
          'taskId': task.taskId,
          'title': task.title,
          'url': task.url,
          'format': task.format,
          'baseUrl': client.baseUrl,
          'apiKey': client.apiKey,
        },
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        foregroundServiceConfig: ForegroundServiceConfig(
          notificationTitle: task.title,
          notificationText: 'Preparing download…',
          notificationChannelId: 'kurama_downloads',
          notificationChannelName: 'Kurama downloads',
          foregroundServiceType: ForegroundServiceType.dataSync,
        ),
      );
}
