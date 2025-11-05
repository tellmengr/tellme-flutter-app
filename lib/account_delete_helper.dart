// lib/account_delete_helper.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'user_provider.dart';
import 'bottom_nav_helper.dart';

class AccountDeletion {
  /// Unified delete flow. Returns true only when deletion succeeded.
  static Future<bool> confirmAndDelete(BuildContext context, String email) async {
    final passwordCtrl = TextEditingController();
    final confirmCtrl  = TextEditingController();
    final feedbackCtrl = TextEditingController();

    // 1) Confirm dialog
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFE53935)),
            ),
            const SizedBox(width: 10),
            const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This action is permanent and will anonymize past orders.\nType DELETE to confirm.',
              style: TextStyle(fontSize: 14.5, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'Type DELETE',
                prefixIcon: Icon(Icons.warning_amber_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Account Password',
                hintText: 'Enter your account password',
                prefixIcon: Icon(Icons.vpn_key_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedbackCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Feedback (optional)',
                prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;

    if (!proceed) return false;

    // 2) Validate
    if (confirmCtrl.text.trim().toUpperCase() != 'DELETE') {
      _snack(context, 'Please type DELETE to confirm.', const Color(0xFFE53935));
      return false;
    }
    if (passwordCtrl.text.trim().isEmpty) {
      _snack(context, 'Password is required.', const Color(0xFFE53935));
      return false;
    }

    // 3) Root loader (IMPORTANT: rootNavigator)
    final rootNav = Navigator.of(context, rootNavigator: true);
    bool loaderOpen = false;
    await Future<void>.microtask(() {
      showDialog(
        context: context,
        useRootNavigator: true,
        barrierColor: Colors.black45,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      loaderOpen = true;
    });

    try {
      final res = await _deleteAccountWithPassword(
        email: email.trim(),
        password: passwordCtrl.text.trim(),
        confirm: 'DELETE',
        feedback: feedbackCtrl.text.trim().isEmpty ? null : feedbackCtrl.text.trim(),
      );

      // 4) Always close loader on ROOT first
      if (loaderOpen && rootNav.canPop()) {
        rootNav.pop(); // close spinner
        loaderOpen = false;
      }

      if (res['success'] == true) {
        // Sign out (clears providers/tokens)
        await context.read<UserProvider>().signOut();
        if (!context.mounted) return true;

        // Close any leftover dialogs/sheets on ROOT
        while (rootNav.canPop()) {
          rootNav.pop();
        }

        // Jump home cleanly
        BottomNavHelper.navigateToTab(context, 0);

        // Show success AFTER the next frame so the new Scaffold is active
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _snack(context, 'Your account has been deleted.', const Color(0xFF43A047));
        });

        return true;
      } else {
        _snack(context, res['message']?.toString() ?? 'Delete failed.', const Color(0xFFE53935));
        return false;
      }
    } catch (e) {
      if (loaderOpen && rootNav.canPop()) {
        rootNav.pop();
        loaderOpen = false;
      }
      _snack(context, 'Delete error: $e', const Color(0xFFE53935));
      return false;
    }
  }

  // --- API call ---
  static Future<Map<String, dynamic>> _deleteAccountWithPassword({
    required String email,
    required String password,
    required String confirm,
    String? feedback,
  }) async {
    final uri = Uri.parse('https://tellme.ng/wp-json/tellme/v1/delete-account-password');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'confirm': confirm,
            if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
          }),
        )
        .timeout(const Duration(seconds: 25));

    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 && resp.statusCode < 300) return data;
      return {'success': false, 'message': data['message'] ?? 'Request failed (${resp.statusCode}).'};
    } catch (_) {
      return {'success': false, 'message': 'Unexpected response (${resp.statusCode}).'};
    }
  }

  static void _snack(BuildContext ctx, String msg, Color color) {
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: [
              Icon(
                color == const Color(0xFFE53935)
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(msg)),
            ],
          ),
        ),
      );
  }
}
