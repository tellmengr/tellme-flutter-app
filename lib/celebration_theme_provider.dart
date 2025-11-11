import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ✅ Firebase Core (to check initialization state)
import 'package:firebase_core/firebase_core.dart';
// ✅ Realtime Database
import 'package:firebase_database/firebase_database.dart';

import 'celebration_theme.dart';

/// 🎨 GLOBAL Theme Provider - Manages celebration themes app-wide with Firebase RTDB
class CelebrationThemeProvider extends ChangeNotifier {
  CelebrationTheme _currentTheme = defaultTheme;
  static const String _themeKey = 'celebration_theme_id';

  // RTDB path: /app_settings/celebration_theme
  static const String _rtdbPath = 'app_settings/celebration_theme';
  static const String _rtdbField = 'themeId';

  FirebaseDatabase? _db;
  DatabaseReference? _docRef;
  StreamSubscription<DatabaseEvent>? _sub;

  CelebrationTheme get currentTheme => _currentTheme;

  // Quick access to theme colors/props
  Color get primaryColor => _currentTheme.primaryColor;
  Color get accentColor => _currentTheme.accentColor;
  Color get secondaryColor => _currentTheme.secondaryColor;
  LinearGradient get gradient => _currentTheme.gradient;
  String get greetingText => _currentTheme.greetingText;
  String get bannerText => _currentTheme.bannerText;
  String get iconEmoji => _currentTheme.iconEmoji;
  bool get showSpecialBadge => _currentTheme.showSpecialBadge;
  String get badgeText => _currentTheme.badgeText;
  Color get badgeColor => _currentTheme.badgeColor;

  CelebrationThemeProvider() {
    _initializeGlobalTheme();
  }

  /// Initialize global theme system (RTDB)
  Future<void> _initializeGlobalTheme() async {
    debugPrint('🎨 Initializing global celebration theme (RTDB)…');

    // 1️⃣ Always try to load cached theme first (no Firebase needed)
    await _loadCachedTheme();

    // 2️⃣ If Firebase is not initialized, skip RTDB safely
    if (Firebase.apps.isEmpty) {
      debugPrint(
        '⚠️ Firebase not initialized in CelebrationThemeProvider, '
        'skipping RTDB and using cached/default theme.',
      );
      // We keep _currentTheme from cache/default and do NOT crash.
      return;
    }

    // 3️⃣ Prepare RTDB (google-services.json provides databaseURL)
    _db = FirebaseDatabase.instance;

    // Enable offline cache (these are synchronous; do NOT await)
    try {
      _db!.setPersistenceEnabled(true);
      _db!.setPersistenceCacheSizeBytes(10 * 1024 * 1024); // 10 MB
    } catch (_) {
      // If already enabled, Firebase may throw; ignore.
    }

    _docRef = _db!.ref(_rtdbPath);

    // 4️⃣ Fetch current global theme from RTDB
    await _fetchGlobalTheme();

    // 5️⃣ Listen to live changes
    _listenToGlobalThemeChanges();
  }

  /// Load cached theme from local storage (fast startup)
  Future<void> _loadCachedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeId = prefs.getString(_themeKey);
      if (themeId != null && themeId.isNotEmpty) {
        final theme = _byId(themeId) ?? defaultTheme;
        _currentTheme = theme;
        notifyListeners();
        debugPrint('✅ Loaded cached theme: ${theme.name}');
      }
    } catch (e) {
      debugPrint('❌ Error loading cached theme: $e');
    }
  }

  /// Fetch global theme from RTDB
  Future<void> _fetchGlobalTheme() async {
    if (_docRef == null) {
      debugPrint('⚠️ _fetchGlobalTheme called but _docRef is null (no RTDB).');
      return;
    }

    try {
      debugPrint('🌍 Fetching global theme from RTDB…');
      final snap = await _docRef!.get();
      if (!snap.exists) return;

      final themeId = _extractThemeId(snap.value);
      if (themeId == null) return;

      final theme = _byId(themeId) ?? defaultTheme;

      if (_currentTheme.id != theme.id) {
        _currentTheme = theme;
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_themeKey, theme.id);
      }
      debugPrint('✅ Global theme loaded (RTDB): ${theme.name}');
    } catch (e) {
      debugPrint('❌ Error fetching global theme (RTDB): $e');
    }
  }

  /// Listen for real-time global theme changes (RTDB)
  void _listenToGlobalThemeChanges() {
    if (_docRef == null) {
      debugPrint(
          '⚠️ _listenToGlobalThemeChanges called but _docRef is null (no RTDB).');
      return;
    }

    debugPrint('👂 Listening for global theme changes (RTDB)…');

    _sub?.cancel();
    _sub = _docRef!.onValue.listen((event) async {
      final themeId = _extractThemeId(event.snapshot.value);
      if (themeId == null || themeId == _currentTheme.id) return;

      final theme = _byId(themeId) ?? defaultTheme;
      _currentTheme = theme;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, theme.id);

      debugPrint('🔥 Global theme updated from RTDB: ${theme.name}');
    }, onError: (error) {
      debugPrint('❌ Error listening to RTDB theme changes: $error');
    });
  }

  /// ✅ GLOBAL: Set theme globally for all users (Admin only)
  Future<void> setGlobalTheme(String themeId) async {
    // If Firebase is not ready / RTDB not wired, don't crash.
    if (Firebase.apps.isEmpty || _docRef == null) {
      debugPrint(
        '⚠️ setGlobalTheme called but Firebase/RTDB not ready. '
        'Skipping global write and applying locally only.',
      );
      await setTheme(_byId(themeId) ?? defaultTheme);
      return;
    }

    try {
      debugPrint('🔥 Setting global theme (RTDB) to: $themeId');

      // Write to RTDB (this triggers listeners on all devices)
      await _docRef!.set({
        _rtdbField: themeId,
        'updatedAt': ServerValue.timestamp,
      });

      // Update local state immediately
      final theme = _byId(themeId) ?? defaultTheme;
      _currentTheme = theme;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, themeId);

      debugPrint('✅ Theme set globally via RTDB: ${theme.name}');
    } catch (e) {
      debugPrint('❌ Error setting global theme (RTDB): $e');
      rethrow;
    }
  }

  /// LOCAL ONLY: Set theme locally (for testing)
  Future<void> setTheme(CelebrationTheme theme) async {
    try {
      _currentTheme = theme;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, theme.id);
      debugPrint('✅ Local theme changed to: ${theme.name}');
    } catch (e) {
      debugPrint('❌ Error saving local theme: $e');
    }
  }

  /// Reset to default theme globally
  Future<void> resetToDefault() async => setGlobalTheme('default');

  /// Get theme by ID
  CelebrationTheme? getThemeById(String id) => _byId(id);

  /// Check if current theme is default
  bool get isDefaultTheme => _currentTheme.id == 'default';

  // ---------- Helpers ----------
  CelebrationTheme? _byId(String id) {
    try {
      return predefinedThemes.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Accepts either:
  /// { "themeId": "christmas", "updatedAt": 123 }  OR  "christmas"
  String? _extractThemeId(Object? value) {
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    if (value is Map) {
      final raw = value[_rtdbField];
      return (raw is String && raw.trim().isNotEmpty) ? raw.trim() : null;
    }
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
