import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'user_provider.dart';
import 'woocommerce_service.dart';

// Softer, white-forward glass palette
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue  = Color(0xFF0096FF);

// Background tints (very subtle)
const kBGTopTint      = Color(0x0AF0F4F8); // ~4% white/blue haze
const kBGBottomTint   = Color(0x0AF8FBFF); // ~4% white/blue haze

// Card/glass
const kGlassFillLight = Color(0xCCFFFFFF); // 80% white (more white, less blue)
const kGlassBorder    = Color(0x1A96B3FF); // faint blue border
const kGlassShadow    = Color(0x1A004AAD); // faint blue shadow

// Input fields
const kFieldFill      = Color(0xF2FFFFFF); // 95% white
const kFieldBorder    = Color(0x1A000000); // very light neutral border
const kFieldBorderFOC = kPrimaryBlue;      // focused border

// Text colors for good contrast on white
const kTextPrimary    = Color(0xFF0F172A); // slate-900
const kTextSecondary  = Color(0xFF475569); // slate-600
const kTextHint       = Color(0xFF64748B); // slate-500

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({Key? key}) : super(key: key);

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  final _service = WooCommerceService();

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleChange() async {
    if (!_formKey.currentState!.validate()) return;

    final userProvider = context.read<UserProvider>();
    final user = userProvider.user;
    if (user == null || userProvider.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in as a customer.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // 1) Validate current password
      final email = user['email']?.toString() ?? '';
      final probe = await _service.signInCustomerSecure(email, _currentCtrl.text);
      if (probe == null) {
        throw Exception('Current password is incorrect.');
      }

      // 2) Update the password in Woo
      final customerId = user['id'] as int;
      final ok = await _service.updateCustomerPassword(customerId, _newCtrl.text);
      if (!ok) throw Exception('Password update failed. Please try again.');

      // 3) Local sign-out
      await userProvider.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed. Please sign in with your new password.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(); // back to Settings
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = kToolbarHeight + MediaQuery.of(context).padding.top + 12;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // White/clear app bar with blue icons/text
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Change Password', style: TextStyle(color: kTextPrimary)),
        iconTheme: const IconThemeData(color: kPrimaryBlue),
        foregroundColor: kPrimaryBlue,
      ),
      body: Stack(
        children: [
          const _SoftWhiteBackground(),
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, topPad, 16, 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: kGlassFillLight, // mostly white glass
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kGlassBorder, width: 1),
                    boxShadow: const [
                      BoxShadow(
                        color: kGlassShadow,
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const Text(
                          'Update your password',
                          style: TextStyle(
                            color: kTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _glassField(
                          context,
                          controller: _currentCtrl,
                          label: 'Current Password',
                          obscure: _obscure,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Enter current password' : null,
                        ),
                        const SizedBox(height: 12),
                        _glassField(
                          context,
                          controller: _newCtrl,
                          label: 'New Password',
                          obscure: _obscure,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter a new password';
                            if (v.length < 6) return 'Use at least 6 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _glassField(
                          context,
                          controller: _confirmCtrl,
                          label: 'Confirm New Password',
                          obscure: _obscure,
                          validator: (v) =>
                              (v != _newCtrl.text) ? 'Passwords do not match' : null,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: !_obscure,
                              onChanged: (val) => setState(() => _obscure = !(val ?? false)),
                              activeColor: kPrimaryBlue,
                              checkColor: Colors.white,
                            ),
                            const Text(
                              'Show passwords',
                              style: TextStyle(color: kTextSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _handleChange,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 3,
                              shadowColor: kPrimaryBlue.withOpacity(0.2),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Update Password'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: TextFormField(
          controller: controller,
          validator: validator,
          obscureText: obscure,
          style: const TextStyle(color: kTextPrimary),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: kTextHint),
            filled: true,
            fillColor: kFieldFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: kFieldBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: kFieldBorderFOC, width: 1.2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftWhiteBackground extends StatelessWidget {
  const _SoftWhiteBackground();

  @override
  Widget build(BuildContext context) {
    // Mostly white with *very* subtle blue tints and gentle blurred blobs
    return Stack(
      children: [
        // White-first gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.white, kBGTopTint, kBGBottomTint],
              stops: [0.0, 0.6, 0.85, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        // Super subtle blue blobs (reduced opacity vs earlier)
        Positioned(
          top: -70,
          left: -40,
          child: _blurCircle(200, kAccentBlue.withOpacity(0.08)),
        ),
        Positioned(
          bottom: -60,
          right: -30,
          child: _blurCircle(190, kPrimaryBlue.withOpacity(0.06)),
        ),
        Positioned(
          top: 140,
          right: -100,
          child: _blurCircle(140, kAccentBlue.withOpacity(0.06)),
        ),
        Positioned(
          bottom: -110,
          left: 120,
          child: _blurCircle(150, kPrimaryBlue.withOpacity(0.05)),
        ),

        // Whisper-thin glass veil to unify
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  Widget _blurCircle(double size, Color color) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: size,
          height: size,
          color: color,
        ),
      ),
    );
  }
}
