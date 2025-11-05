import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Handlers used in `main.dart`
/// - [onTap]: when user taps an FCM-delivered notification (background/terminated)
/// - [onLocalTap]: when user taps a locally-shown notification (foreground banner)
typedef NotificationTapHandler = void Function(RemoteMessage message);
typedef LocalTapHandler = void Function(Map<String, dynamic> data);

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _fln = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _highChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'For important alerts.',
    importance: Importance.high,
  );

  /// Initializes FCM + local notifications.
  static Future<void> init({
    required NotificationTapHandler onTap,
    required LocalTapHandler onLocalTap,
  }) async {
    // iOS foreground presentation
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    // Initialize local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        // Handle taps on foreground local notifications
        if (resp.payload != null && resp.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
            onLocalTap(data);
          } catch (e) {
            debugPrint('⚠️ Error decoding local payload: $e');
          }
        }
      },
    );

    // Create the Android channel
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_highChannel);

    // Ask for notification permission
    await _requestPermissions();

    // Print FCM token for manual testing
    final token = await _messaging.getToken();
    debugPrint('🔑 FCM Token: $token');

    // Handle app opened from terminated state
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) onTap(initial);

    // Foreground messages → show a local banner
    FirebaseMessaging.onMessage.listen(_showLocal);

    // Background messages → open app on tap
    FirebaseMessaging.onMessageOpenedApp.listen(onTap);
  }

  static Future<void> _requestPermissions() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    if (Platform.isAndroid) {
      await _fln
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  /// Displays a local banner notification with optional image support.
  static Future<void> _showLocal(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    // Check for image in notification or data payload
    final imageUrl = message.notification?.android?.imageUrl ??
        message.notification?.apple?.imageUrl ??
        message.data['image'] ??
        message.data['imageUrl'];

    AndroidNotificationDetails androidDetails;

    if (imageUrl != null && imageUrl.toString().isNotEmpty) {
      final filePath = await _downloadToFile(imageUrl);
      if (filePath != null) {
        androidDetails = AndroidNotificationDetails(
          _highChannel.id,
          _highChannel.name,
          channelDescription: _highChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigPictureStyleInformation(
            FilePathAndroidBitmap(filePath),
            contentTitle: n.title,
            summaryText: n.body,
          ),
          icon: n.android?.smallIcon ?? '@mipmap/ic_launcher',
        );
      } else {
        androidDetails = AndroidNotificationDetails(
          _highChannel.id,
          _highChannel.name,
          channelDescription: _highChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: n.android?.smallIcon ?? '@mipmap/ic_launcher',
        );
      }
    } else {
      androidDetails = AndroidNotificationDetails(
        _highChannel.id,
        _highChannel.name,
        channelDescription: _highChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: n.android?.smallIcon ?? '@mipmap/ic_launcher',
      );
    }

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    // Store data payload so tap can deep-link correctly
    final payload = jsonEncode(message.data);

    await _fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      n.title,
      n.body,
      details,
      payload: payload,
    );
  }

  /// Downloads image for BigPicture notification style
  static Future<String?> _downloadToFile(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/notif_${DateTime.now().millisecondsSinceEpoch}.img');
        await f.writeAsBytes(res.bodyBytes);
        return f.path;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download image: $e');
    }
    return null;
  }
}

// MUST be top-level
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // For background tasks if needed later
}
