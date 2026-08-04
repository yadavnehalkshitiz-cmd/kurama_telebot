import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/models/download_task.dart';

void main() {
  test('download status exposes an uppercase display label', () {
    expect(DownloadStatus.completed.displayLabel, 'COMPLETED');
    expect(DownloadStatus.downloading.displayLabel, 'DOWNLOADING');
  });

  test('download transfer and vault fields survive JSON persistence', () {
    final original = DownloadTask(
      taskId: 'task-7',
      url: 'https://example.com/watch/7',
      platform: 'Example',
      title: 'Night drive',
      format: 'audio',
      status: DownloadStatus.downloading,
      progress: 42,
      speedBytesPerSecond: 1572864,
      speedLabel: '1.5 MB/s',
      etaSeconds: 18,
      isPrivate: true,
      vaultPath: '/vault/task-7.kvault',
    );

    final restored = DownloadTask.fromJson(original.toJson());

    expect(restored.speedBytesPerSecond, 1572864);
    expect(restored.speedLabel, '1.5 MB/s');
    expect(restored.etaSeconds, 18);
    expect(restored.isPrivate, isTrue);
    expect(restored.vaultPath, '/vault/task-7.kvault');
  });
}
