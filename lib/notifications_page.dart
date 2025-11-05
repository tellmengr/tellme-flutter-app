import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_provider.dart';
import 'celebration_theme_provider.dart';

/// 🎨 Brand Colors (Fallbacks)
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);
const kLightGray = Color(0xFFF7F9FC);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('notif_list') ?? [];
    setState(() {
      _notifications = stored
          .map((json) => jsonDecode(json) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    });
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notif_list');
    await context.read<NotificationProvider>().markAllRead();
    setState(() => _notifications.clear());
  }

  @override
  Widget build(BuildContext context) {
    // 🎨 Theme-aware colors
    final theme = context.watch<CelebrationThemeProvider?>();
    final primaryColor = theme?.activeTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = theme?.activeTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = theme?.activeTheme?.secondaryColor ?? Colors.white;
    final gradient = theme?.activeTheme?.gradient ?? [kPrimaryBlue, kAccentBlue];
    final backgroundColor = theme?.activeTheme?.backgroundColor ?? kLightGray;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: AppBar(
          title: Text(
            'Notifications',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          actions: [
            if (_notifications.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Clear all',
                onPressed: _clearAll,
              ),
          ],
        ),
      ),
      body: _notifications.isEmpty
          ? _emptyState(primaryColor: primaryColor)
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              color: accentColor,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _notifications.length,
                itemBuilder: (_, i) => _buildNotificationCard(_notifications[i], primaryColor: primaryColor, accentColor: accentColor),
              ),
            ),
    );
  }

  // 🧩 Notification Card
  Widget _buildNotificationCard(Map<String, dynamic> n, {required Color primaryColor, required Color accentColor}) {
    final title = n['title'] ?? 'New Notification';
    final body = n['body'] ?? '';
    final image = n['image'];
    final date = _formatDate(n['timestamp'] ?? '');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: image != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  image,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.notifications_active,
                    color: primaryColor,
                    size: 38,
                  ),
                ),
              )
            : Icon(Icons.notifications_active,
                color: primaryColor, size: 38),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        trailing: Text(
          date,
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ),
    );
  }

  // 🕓 Format timestamp
  String _formatDate(String timestamp) {
    try {
      final t = DateTime.tryParse(timestamp);
      if (t != null) {
        final now = DateTime.now();
        if (now.difference(t).inDays == 0) {
          return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
        } else {
          return "${t.day}/${t.month}/${t.year}";
        }
      }
    } catch (_) {}
    return '';
  }

  // 💭 Empty State
  Widget _emptyState({required Color primaryColor}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              'No notifications yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You\'ll see your updates and alerts here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}