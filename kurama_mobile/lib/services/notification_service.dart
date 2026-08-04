import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static String? pendingLaunchPath;

  static Future<void> initialize({void Function(String path)? onOpen}) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onOpen?.call(payload);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      pendingLaunchPath = launch?.notificationResponse?.payload;
    }
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> showProgress({
    required String taskId,
    required String title,
    required int progress,
    String? speed,
  }) =>
      _plugin.show(
        _notificationId(taskId),
        title,
        speed == null ? '$progress%' : '$progress% • $speed',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'kurama_downloads',
            'Kurama downloads',
            channelDescription: 'Live video and audio download progress',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: 100,
            progress: progress,
            ongoing: true,
          ),
          iOS: const DarwinNotificationDetails(presentSound: false),
        ),
      );

  static Future<void> showComplete({
    required String taskId,
    required String title,
    required String filePath,
  }) =>
      _plugin.show(
        _notificationId(taskId),
        'Download complete',
        'Tap to open $title',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'kurama_downloads',
            'Kurama downloads',
            channelDescription: 'Video and audio download status',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: filePath,
      );

  static Future<void> showFailed(String taskId, String message) => _plugin.show(
        _notificationId(taskId),
        'Download failed',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'kurama_downloads',
            'Kurama downloads',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );

  static int _notificationId(String taskId) => taskId.hashCode & 0x7fffffff;
}
