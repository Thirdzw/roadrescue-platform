import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'crash_notification_service.dart';
import 'firestore_service.dart';

class PushTokenService {
  PushTokenService._();

  static final instance = PushTokenService._();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  Future<void> start() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Crash push notifications are disabled by the user.');
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('Firebase Messaging did not return a push token.');
      return;
    }

    _tokenSubscription ??=
        FirebaseMessaging.instance.onTokenRefresh.listen((refreshedToken) {
      unawaited(_saveRefreshedToken(refreshedToken));
    }, onError: (Object error) {
      debugPrint('Firebase Messaging token refresh failed: $error');
    });
    _messageSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] != 'crash') return;
      unawaited(
        CrashNotificationService.instance
            .showCircleCrashNotification(message)
            .catchError((Object error) {
          debugPrint('Displaying Circle crash notification failed: $error');
        }),
      );
    }, onError: (Object error) {
      debugPrint('Firebase Messaging foreground stream failed: $error');
    });
    await FirestoreService().saveCurrentUserFcmToken(token);
  }

  Future<void> _saveRefreshedToken(String token) async {
    try {
      await FirestoreService().saveCurrentUserFcmToken(token);
    } catch (error) {
      debugPrint('Saving refreshed Firebase Messaging token failed: $error');
    }
  }
}
