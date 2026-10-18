import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CrashNotificationService {
  CrashNotificationService._();

  static final instance = CrashNotificationService._();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize({
    required void Function() onPromptOpened,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == 'crash_prompt') onPromptOpened();
      },
    );
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'roadrescue_crash_alerts',
        'Crash alerts',
        description: 'Urgent crash confirmation prompts.',
        importance: Importance.max,
      ),
    );
  }

  Future<void> requestFullScreenPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestFullScreenIntentPermission();
    if (granted == false) {
      throw StateError(
        'Allow RoadRescue full-screen notifications to show crash prompts over the lock screen.',
      );
    }
  }

  Future<void> showCircleCrashNotification(RemoteMessage message) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _notifications.show(
      id: 4103,
      title: message.notification?.title ?? 'Crash detected in your Circle',
      body: message.notification?.body ??
          'A Circle member may need help. Open RoadRescue.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'roadrescue_crash_alerts',
          'Crash alerts',
          channelDescription: 'Urgent crash confirmation prompts.',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          enableVibration: true,
          playSound: true,
        ),
      ),
      payload: 'circle_crash',
    );
  }

  Future<void> clearCrashPrompt() => _notifications.cancel(id: 4102);
}
