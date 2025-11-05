import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'woocommerce_service.dart';

// ✅ RTDB for admin checks
import 'package:firebase_database/firebase_database.dart';

class UserProvider with ChangeNotifier {
  Map<String, dynamic>? _user;
  bool _isAdmin = false;
  final WooCommerceService _wooService = WooCommerceService();

  // -------------------- GETTERS --------------------
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _isAdmin;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get currentUser => _user; // ✅ Backward compatibility
  String get userEmail => _user?['email'] ?? '';
  int? get userId => _user?['id'];

  String get userDisplayName {
    if (_user == null) return 'Guest';
    final firstName = _user!['first_name'] ?? '';
    final lastName  = _user!['last_name']  ?? '';
    final username  = _user!['username']   ?? '';
    final email     = _user!['email']      ?? '';
    if (firstName.isNotEmpty) return lastName.isNotEmpty ? '$firstName $lastName' : firstName;
    if (username.isNotEmpty) return username;
    return email.isNotEmpty ? email : 'User';
  }

  // -------------------- INITIALIZE --------------------
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_data');
      final isAdminSaved = prefs.getBool('is_admin') ?? false;

      if (userJson != null) {
        _user = json.decode(userJson);
        _isAdmin = isAdminSaved;
        debugPrint('✅ User loaded: ${_user!['email']} (Admin: $_isAdmin)');
        notifyListeners();
      }

      // ✅ Check admin status from RTDB after loading user
      await checkAdminStatus();
    } catch (e) {
      debugPrint('❌ Error loading user data: $e');
    }
  }

  // -------------------- ADMIN CHECK (RTDB) --------------------

  // 🔐 Utility to sanitize Firebase keys (Firebase paths cannot include '.', '#', '$', '[', or ']')
String safeKey(String email) =>
    email.replaceAll('.', ',')
         .replaceAll('#', '_')
         .replaceAll('\$', '_')
         .replaceAll('[', '_')
         .replaceAll(']', '_');



  Future<void> checkAdminStatus() async {
    try {
      if (_user == null || _user!['email'] == null) {
        if (_isAdmin != false) {
          _isAdmin = false;
          notifyListeners();
        }
        return;
      }

      final email = (_user!['email'] as String).toLowerCase().trim();
      if (email.isEmpty) {
        if (_isAdmin != false) {
          _isAdmin = false;
          notifyListeners();
        }
        return;
      }

      final db = FirebaseDatabase.instance;

      // ✅ Use safeKey for valid RTDB paths
      final refByEmail = db.ref('app_settings/admins_by_email/${safeKey(email)}');
      final refList = db.ref('app_settings/admins/allowed_emails');

      bool isAdminFound = false;

      // A) direct key
      final snapA = await refByEmail.get();
      if (snapA.exists && snapA.value == true) {
        isAdminFound = true;
      } else {
        // B) list membership
        final snapB = await refList.get();
        if (snapB.exists && snapB.value is List) {
          final list = (snapB.value as List)
              .map((e) => e.toString().toLowerCase())
              .toList();
          isAdminFound = list.contains(email);
        } else if (snapB.exists && snapB.value is Map) {
          final m = snapB.value as Map;
          final list =
              m.values.map((e) => e.toString().toLowerCase()).toList();
          isAdminFound = list.contains(email);
        }
      }

      if (_isAdmin != isAdminFound) {
        _isAdmin = isAdminFound;
        await _persistUserAndFlags();
        debugPrint('👑 Admin status updated: $_isAdmin for $email');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error checking admin status (RTDB): $e');
      if (_isAdmin != false) {
        _isAdmin = false;
        notifyListeners();
      }
    }
  }


  // -------------------- SETTERS --------------------
  Future<void> _persistUserAndFlags() async {
    final prefs = await SharedPreferences.getInstance();
    if (_user != null) {
      await prefs.setString('user_data', json.encode(_user));
    } else {
      await prefs.remove('user_data');
    }
    await prefs.setBool('is_admin', _isAdmin);
  }

  /// Optional: write admin flag into RTDB under admins_by_email (for a quick toggle UI)
  Future<void> setAdminFlag(bool isAdmin) async {
    try {
      _isAdmin = isAdmin;
      if (_user != null) _user!['isAdmin'] = isAdmin;
      await _persistUserAndFlags();

      final email = (_user?['email'] ?? '').toString().toLowerCase().trim();
      if (email.isNotEmpty) {
        final ref = FirebaseDatabase.instance
            .ref('app_settings/admins_by_email/${safeKey(email)}');
        await ref.set(isAdmin);
      }

      debugPrint('👑 Admin flag set (local + RTDB-by-email): $_isAdmin');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error setting admin flag: $e');
    }
  }

  Future<void> setAdminUser(Map<String, dynamic> adminData) async {
    try {
      _user = adminData;
      _isAdmin = true;
      await _persistUserAndFlags();

      final email = (_user?['email'] ?? '').toString().toLowerCase().trim();
      if (email.isNotEmpty) {
        final ref = FirebaseDatabase.instance
            .ref('app_settings/admins_by_email/${safeKey(email)}');
        await ref.set(true);
      }

      debugPrint('✅ Admin user set: ${adminData['email']}');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error setting admin user: $e');
    }
  }


  Future<void> setLoggedInCustomer(Map<String, dynamic> customer, {String? sessionToken}) async {
    try {
      _user = customer;
      _isAdmin = false; // Start as non-admin; then check RTDB

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', json.encode(customer));
      await prefs.setBool('is_admin', false);

      if (sessionToken != null && sessionToken.isNotEmpty) {
        await prefs.setString('tellme_session', sessionToken);
      }

      debugPrint('✅ Logged-in customer stored: ${customer['email']}');
      notifyListeners();

      await checkAdminStatus();
    } catch (e) {
      debugPrint('❌ Error setting logged-in customer: $e');
    }
  }

  // -------------------- AUTH OPERATIONS --------------------
  Future<bool> signIn(String email, String password) async {
    try {
      debugPrint('🔐 Attempting sign-in for: $email');
      final result = await _wooService.signInCustomer(email, password);

      if (result != null) {
        final userData = result['user'] as Map<String, dynamic>;
        final session  = (result['session'] ?? '').toString();
        await setLoggedInCustomer(userData, sessionToken: session);
        debugPrint('✅ Sign-in successful');
        return true;
      }

      debugPrint('❌ Sign-in failed (bad credentials)');
      return false;
    } catch (e) {
      debugPrint('❌ Sign-in error: $e');
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      debugPrint('📝 Registering customer: $email');
      final userData = await _wooService.createCustomer(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );

      if (userData != null) {
        await setLoggedInCustomer(userData);
        debugPrint('✅ Sign-up successful');
        return true;
      }

      debugPrint('❌ Sign-up failed');
      return false;
    } catch (e) {
      debugPrint('❌ Sign-up error: $e');
      return false;
    }
  }

  Future<void> signOut({bool revokeServer = false}) async {
    try {
      if (revokeServer) {
        await _wooService.logoutAllSessions().catchError((_) {});
      }

      _user = null;
      _isAdmin = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('is_admin');
      await prefs.remove('tellme_session');

      debugPrint('✅ User signed out');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Sign-out error: $e');
    }
  }

  // -------------------- PROFILE --------------------
  Future<bool> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    if (_user == null || _isAdmin) {
      debugPrint('❌ Cannot update profile: No valid WooCommerce user.');
      return false;
    }

    try {
      final userId = _user!['id'];
      final updatedData = await _wooService.updateCustomer(
        userId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
      );

      if (updatedData != null) {
        _user = updatedData;
        await _persistUserAndFlags();
        debugPrint('✅ Profile updated');
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Profile update error: $e');
      return false;
    }
  }

  Future<void> refreshUserData() async {
    if (_user == null) return;

    try {
      if (_isAdmin) {
        debugPrint('ℹ️ Skipping admin refresh (WordPress only)');
        return;
      }

      final userId = _user!['id'];
      final updatedData = await _wooService.getCustomer(userId);

      if (updatedData != null) {
        _user = updatedData;
        await _persistUserAndFlags();
        debugPrint('✅ User data refreshed');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error refreshing user data: $e');
    }
  }

  // -------------------- HELPERS --------------------
  Future<void> handlePasswordChanged() async {
    await signOut(revokeServer: true);
  }

  // Compatibility helpers
  Future<bool> login(String email, String password) async => await signIn(email, password);
  Future<void> logout() async => await signOut();
}
