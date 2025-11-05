// lib/notification_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Handles in-app notification state (badge count, persistence, etc.)
/// Works with `notification_service.dart`, `AppHeader`, and `notifications_page.dart`.
class NotificationProvider extends ChangeNotifier {
  static const _storageKey = 'notif_unread_count';
  static const _lastPayloadKey = 'notif_last_payload';
  static const _listKey = 'notif_list';

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  Map<String, dynamic>? _lastPayload;
  Map<String, dynamic>? get lastPayload => _lastPayload;

  /// ✅ Load persisted badge, last payload, and list count on app start.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _unreadCount = prefs.getInt(_storageKey) ?? 0;

    final raw = prefs.getString(_lastPayloadKey);
    if (raw != null) {
      try {
        _lastPayload = Map<String, dynamic>.from(Uri.splitQueryString(raw));
      } catch (_) {
        _lastPayload = null;
      }
    }

    notifyListeners();
  }

  Future<void> _saveCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, _unreadCount);
  }

  /// ✅ Increment unread badge count.
  Future<void> increment() async {
    _unreadCount++;
    await _saveCount();
    notifyListeners();
  }

  /// ✅ Mark all notifications as read.
  Future<void> markAllRead() async {
    _unreadCount = 0;
    await _saveCount();
    notifyListeners();
  }

  /// ✅ Save the last received payload for quick debugging or reprocessing.
  Future<void> _savePayload(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = data.entries.map((e) => '${e.key}=${e.value}').join('&');
    await prefs.setString(_lastPayloadKey, encoded);
  }

  /// ✅ Save each notification into a persistent list for NotificationsPage.
  Future<void> _storeNotification(RemoteMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_listKey) ?? [];

    final item = {
      'title': message.notification?.title ?? 'Notification',
      'body': message.notification?.body ?? '',
      'image': message.notification?.android?.imageUrl ??
          message.notification?.apple?.imageUrl ??
          message.data['image'] ??
          message.data['imageUrl'],
      'data': message.data,
      'timestamp': DateTime.now().toIso8601String(),
    };

    stored.add(jsonEncode(item));
    await prefs.setStringList(_listKey, stored);
  }

  /// ✅ Core handler called from main.dart or notification_service.
  /// Stores, increments badge, and syncs with list.
  Future<void> handleMessage(RemoteMessage message, {required bool fromTap}) async {
    try {
      _lastPayload = message.data;
      await _savePayload(message.data);
      await _storeNotification(message);

      if (!fromTap) {
        await increment(); // Foreground message → increase badge
      } else {
        await markAllRead(); // Tapped notification → reset badge
      }

      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ handleMessage error: $e');
    }
  }

  /// ✅ Get all stored notifications (for NotificationsPage)
  Future<List<Map<String, dynamic>>> getAllNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_listKey) ?? [];
    return stored.map((e) => jsonDecode(e) as Map<String, dynamic>).toList().reversed.toList();
  }

  /// ✅ Clear all notifications and reset everything.
  Future<void> reset() async {
    _unreadCount = 0;
    _lastPayload = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_lastPayloadKey);
    await prefs.remove(_listKey);
    notifyListeners();
  }
}
