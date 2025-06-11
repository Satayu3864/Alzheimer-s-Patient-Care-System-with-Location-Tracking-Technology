import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'; // ✅ เพิ่ม import นี้
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class FirebaseNotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // ✅ ตรวจสอบก่อนใช้ Local Notifications
  final FlutterLocalNotificationsPlugin? _flutterLocalNotificationsPlugin =
  (kIsWeb || !isPlatformSupported())
      ? null
      : FlutterLocalNotificationsPlugin();

  static bool isPlatformSupported() {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      print("📢 Web ไม่รองรับ Local Notifications");
      return;
    }

    NotificationSettings settings = await _firebaseMessaging.requestPermission();
    print("User granted permission: ${settings.authorizationStatus}");

    if (_flutterLocalNotificationsPlugin != null) {
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      final InitializationSettings initializationSettings =
      InitializationSettings(android: androidSettings);

      await _flutterLocalNotificationsPlugin!.initialize(initializationSettings);
    }

    String? token = await _firebaseMessaging.getToken();
    print("FCM Token: $token");

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("📩 Foreground Message: ${message.notification?.title}");
      if (_flutterLocalNotificationsPlugin != null) {
        _showNotification(message);
      }
    });
  }

  void _showNotification(RemoteMessage message) async {
    if (_flutterLocalNotificationsPlugin == null) return;

    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidDetails);

    await _flutterLocalNotificationsPlugin!.show(
      0,
      message.notification?.title ?? 'ไม่มีหัวข้อ',
      message.notification?.body ?? 'ไม่มีเนื้อหา',
      platformChannelSpecifics,
    );
  }
}
