import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'woocommerce_service.dart';

class UserProvider with ChangeNotifier {
  Map<String, dynamic>? _user;
  bool _isAdmin = false;
  final WooCommerceService _wooService = WooCommerceService();

  bool get isLoggedIn => _user != null;
  bool get isAdmin => _isAdmin;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get currentUser => _user;

  String get userEmail => (_user?['email'] ?? '').toString();

  int? get userId => _parseIntId(_user?['id']);

  String get userIdText => (_user?['id'] ?? '').toString();

  String get userDisplayName {
    if (_user == null) return 'Guest';

    final firstName =
        (_user!['first_name'] ?? _user!['firstName'] ?? '').toString();
    final lastName =
        (_user!['last_name'] ?? _user!['lastName'] ?? '').toString();
    final username = (_user!['username'] ?? '').toString();
    final email = (_user!['email'] ?? '').toString();

    if (firstName.isNotEmpty) {
      return lastName.isNotEmpty ? '$firstName $lastName' : firstName;
    }

    if (username.isNotEmpty) return username;
    return email.isNotEmpty ? email : 'User';
  }

  int? _parseIntId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    return int.tryParse(text);
  }

  String safeKey(String email) {
    return email
        .replaceAll('.', ',')
        .replaceAll('#', '_')
        .replaceAll(r'$', '_')
        .replaceAll('[', '_')
        .replaceAll(']', '_');
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_data');
      final isAdminSaved = prefs.getBool('is_admin') ?? false;
      final session = (prefs.getString('tellme_session') ??
              prefs.getString('tm_customer_session') ??
              prefs.getString('customer_session') ??
              '')
          .trim();

      if (userJson != null) {
        if (session.isEmpty) {
          await prefs.remove('user_data');
          await prefs.remove('is_admin');
          _user = null;
          _isAdmin = false;
          debugPrint('Cleared stale saved user: missing TellMe session token.');
          notifyListeners();
          return;
        }

        final decoded = json.decode(userJson);
        if (decoded is Map) {
          _user = decoded.cast<String, dynamic>();
          _isAdmin = isAdminSaved;
          debugPrint('User loaded: ${_user!['email']} (Admin: $_isAdmin)');
          notifyListeners();
        }
      }

      Future<void>.microtask(checkAdminStatus);
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> checkAdminStatus() async {
    try {
      final email = userEmail.toLowerCase().trim();

      if (_user == null || email.isEmpty) {
        if (_isAdmin != false) {
          _isAdmin = false;
          notifyListeners();
        }
        return;
      }

      final db = FirebaseDatabase.instance;
      final refByEmail =
          db.ref('app_settings/admins_by_email/${safeKey(email)}');
      final refList = db.ref('app_settings/admins/allowed_emails');

      bool isAdminFound = false;

      final snapA = await refByEmail.get().timeout(const Duration(seconds: 3));
      if (snapA.exists && snapA.value == true) {
        isAdminFound = true;
      } else {
        final snapB = await refList.get().timeout(const Duration(seconds: 3));

        if (snapB.exists && snapB.value is List) {
          final list = (snapB.value as List)
              .map((item) => item.toString().toLowerCase())
              .toList();
          isAdminFound = list.contains(email);
        } else if (snapB.exists && snapB.value is Map) {
          final map = snapB.value as Map;
          final list =
              map.values.map((item) => item.toString().toLowerCase()).toList();
          isAdminFound = list.contains(email);
        }
      }

      if (_isAdmin != isAdminFound) {
        _isAdmin = isAdminFound;
        await _persistUserAndFlags();
        debugPrint('Admin status updated: $_isAdmin for $email');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error checking admin status (RTDB): $e');

      if (_isAdmin != false) {
        _isAdmin = false;
        notifyListeners();
      }
    }
  }

  Future<void> _persistUserAndFlags() async {
    final prefs = await SharedPreferences.getInstance();

    if (_user != null) {
      await prefs.setString('user_data', json.encode(_user));
    } else {
      await prefs.remove('user_data');
    }

    await prefs.setBool('is_admin', _isAdmin);
  }

  Future<void> setAdminFlag(bool isAdmin) async {
    try {
      _isAdmin = isAdmin;
      if (_user != null) _user!['isAdmin'] = isAdmin;

      await _persistUserAndFlags();

      final email = userEmail.toLowerCase().trim();
      if (email.isNotEmpty) {
        final ref = FirebaseDatabase.instance
            .ref('app_settings/admins_by_email/${safeKey(email)}');
        await ref.set(isAdmin).timeout(const Duration(seconds: 3));
      }

      debugPrint('Admin flag set: $_isAdmin');
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting admin flag: $e');
    }
  }

  Future<void> setAdminUser(Map<String, dynamic> adminData) async {
    try {
      _user = Map<String, dynamic>.from(adminData);
      _isAdmin = true;

      await _persistUserAndFlags();

      final email = userEmail.toLowerCase().trim();
      if (email.isNotEmpty) {
        final ref = FirebaseDatabase.instance
            .ref('app_settings/admins_by_email/${safeKey(email)}');
        await ref.set(true).timeout(const Duration(seconds: 3));
      }

      debugPrint('Admin user set: ${adminData['email']}');
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting admin user: $e');
    }
  }

  Future<void> setLoggedInCustomer(
    Map<String, dynamic> customer, {
    String? sessionToken,
  }) async {
    try {
      _user = Map<String, dynamic>.from(customer);
      _isAdmin = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', json.encode(_user));
      await prefs.setBool('is_admin', false);

      if (sessionToken != null && sessionToken.isNotEmpty) {
        await prefs.setString('tellme_session', sessionToken);
      }

      debugPrint('Logged-in customer stored: ${_user?['email']}');
      notifyListeners();

      Future<void>.microtask(checkAdminStatus);
    } catch (e) {
      debugPrint('Error setting logged-in customer: $e');
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      debugPrint('Attempting sign-in for: $email');
      final result = await _wooService.signInCustomer(email, password);

      if (result != null) {
        final rawUser = result['user'];
        if (rawUser is! Map) return false;

        final userData = rawUser.cast<String, dynamic>();
        final session = (result['session'] ?? '').toString();

        if (session.isEmpty) {
          debugPrint('Sign-in failed: missing TellMe session token.');
          return false;
        }

        await setLoggedInCustomer(userData, sessionToken: session);
        debugPrint('Sign-in successful');
        return true;
      }

      debugPrint('Sign-in failed');
      return false;
    } catch (e) {
      debugPrint('Sign-in error: $e');
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
      debugPrint('Registering customer: $email');

      final userData = await _wooService.createCustomer(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );

      if (userData != null) {
        await setLoggedInCustomer(userData);
        debugPrint('Sign-up successful');
        return true;
      }

      debugPrint('Sign-up failed');
      return false;
    } catch (e) {
      debugPrint('Sign-up error: $e');
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

      debugPrint('User signed out');
      notifyListeners();
    } catch (e) {
      debugPrint('Sign-out error: $e');
    }
  }

  Future<bool> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    if (_user == null || _isAdmin) {
      debugPrint('Cannot update profile: no valid customer.');
      return false;
    }

    final parsedUserId = userId;
    if (parsedUserId == null) {
      debugPrint('Cannot update profile: user id is not numeric.');
      return false;
    }

    try {
      final updatedData = await _wooService.updateCustomer(
        parsedUserId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
      );

      if (updatedData != null) {
        _user = updatedData;
        await _persistUserAndFlags();
        debugPrint('Profile updated');
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Profile update error: $e');
      return false;
    }
  }

  Future<void> refreshUserData() async {
    if (_user == null) return;

    try {
      if (_isAdmin) {
        debugPrint('Skipping admin refresh.');
        return;
      }

      final parsedUserId = userId;
      if (parsedUserId == null) {
        debugPrint('Skipping user refresh: user id is not numeric.');
        return;
      }

      final updatedData = await _wooService.getCustomer(parsedUserId);

      if (updatedData != null) {
        _user = updatedData;
        await _persistUserAndFlags();
        debugPrint('User data refreshed');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error refreshing user data: $e');
    }
  }

  Future<void> handlePasswordChanged() async {
    await signOut(revokeServer: true);
  }

  Future<bool> login(String email, String password) async {
    return signIn(email, password);
  }

  Future<void> logout() async {
    await signOut();
  }
}
