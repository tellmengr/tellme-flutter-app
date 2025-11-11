import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wordpress_blog_service.dart';
import 'wp_post.dart';

class BlogNotificationProvider extends ChangeNotifier {
  final WordPressBlogService _service;

  bool _hasNewPost = false;
  int? _lastSeenPostId;
  bool _initialized = false;

  BlogNotificationProvider({WordPressBlogService? service})
      : _service = service ?? WordPressBlogService();

  /// Getter used in home_page.dart
  bool get hasNewPost => _hasNewPost;

  /// Call once at startup (e.g., inside main() or an init provider)
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _lastSeenPostId = prefs.getInt('last_seen_post_id');

    await checkForNewPosts();
  }

  /// Fetch latest post from WordPress and flag if it’s new
  Future<void> checkForNewPosts() async {
    try {
      final List<WpPost> posts =
          await _service.fetchPosts(page: 1, perPage: 1); // latest only

      if (posts.isEmpty) {
        _hasNewPost = false;
      } else {
        final latestId = posts.first.id;
        _hasNewPost = _lastSeenPostId == null || latestId != _lastSeenPostId;
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ BlogNotificationProvider.checkForNewPosts error: $e');
      }
    }
  }

  /// Mark the latest post as “seen” (clear red NEW badge)
  Future<void> markAllRead([int? latestPostId]) async {
    if (latestPostId != null) _lastSeenPostId = latestPostId;
    _hasNewPost = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (_lastSeenPostId != null) {
      await prefs.setInt('last_seen_post_id', _lastSeenPostId!);
    }
  }
}
