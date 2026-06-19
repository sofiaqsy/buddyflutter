import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // App is in background/terminated — system shows notification automatically
  debugPrint('[Push] Background message: ${message.messageId}');
}

class PushService {
  PushService._();
  static final shared = PushService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Called once after Firebase.initializeApp()
  Future<void> init() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Request permission (iOS + Android 13+)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: false,
    );
    debugPrint('[Push] Permission: ${settings.authorizationStatus}');

    // iOS: show notification banner even when app is in foreground
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Setup local notifications for foreground display
    await _setupLocalNotifications();

    // Get token and register with backend
    await _registerToken();

    // Listen for token refreshes
    _fcm.onTokenRefresh.listen(_sendTokenToServer);

    // Foreground messages — show local notification
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // App opened from notification (background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTapped);

    // App launched from terminated state via notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _onNotificationTapped(initial);
  }

  Future<void> _setupLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false, // already requested via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (details) {
        // Handle tap on local notification
        _handlePayload(details.payload);
      },
    );

    // Android notification channel — high importance for urgent alerts
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'buddy_requests',
        'Solicitudes de viajeros',
        description: 'Notificaciones urgentes cuando un viajero necesita tu ayuda',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _sendTokenToServer(token);
    } catch (e) {
      debugPrint('[Push] Could not get token: $e');
    }
  }

  Future<void> _sendTokenToServer(String token) async {
    try {
      await ApiClient.shared.post('/notifications/fcm-token', {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      debugPrint('[Push] Token registered ✓');
    } catch (e) {
      debugPrint('[Push] Failed to register token: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    // Una oferta de ayuda llegó con la app abierta → avisa para refrescar la lista
    if (message.data['type'] == 'help_offer') {
      offerReceivedStream.add(message.data['request_id'] ?? '');
    }

    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'buddy_requests',
          'Solicitudes de viajeros',
          channelDescription: 'Notificaciones urgentes cuando un viajero necesita tu ayuda',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['request_id'],
    );
  }

  void _onNotificationTapped(RemoteMessage message) {
    _handlePayload(message.data['request_id']);
  }

  void _handlePayload(String? requestId) {
    if (requestId == null) return;
    debugPrint('[Push] Tapped notification for request: $requestId');
    // Navigate to the request — emit event that HomeScreen listens to
    pushNotificationStream.add(requestId);
  }

  // Stream that HomeScreen listens to for navigation (on tap)
  final pushNotificationStream = _SimpleStream<String>();
  // Stream que avisa cuando llega una oferta en foreground (para refrescar la lista)
  final offerReceivedStream = _SimpleStream<String>();
}

// Minimal broadcast stream wrapper
class _SimpleStream<T> {
  final List<void Function(T)> _listeners = [];
  void listen(void Function(T) fn) => _listeners.add(fn);
  void add(T value) { for (final l in _listeners) l(value); }
}
