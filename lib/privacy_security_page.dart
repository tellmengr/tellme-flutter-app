import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';
import 'woocommerce_service.dart';
import 'account_delete_helper.dart'; // ✅ reuse the same deletion flow

// 🎨 Brand Colors
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);
const kRed = Color(0xFFE53935);
const kGreen = Color(0xFF43A047);

class PrivacySecurityPage extends StatefulWidget {
  const PrivacySecurityPage({Key? key}) : super(key: key);

  @override
  State<PrivacySecurityPage> createState() => _PrivacySecurityPageState();
}

class _PrivacySecurityPageState extends State<PrivacySecurityPage> {
  bool _deleting = false; // 🔒 optional spinner guard for double-taps

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Privacy & Security',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Account Security'),
          const SizedBox(height: 12),
          _buildMenuCard([
            _buildMenuItem(
              icon: Icons.lock_outline,
              title: 'Change Password',
              subtitle: 'Update your password',
              onTap: () => _showChangePasswordDialog(),
            ),
            const Divider(height: 1),
            _buildMenuItem(
              icon: Icons.phone_android_outlined,
              title: 'Two-Factor Authentication',
              subtitle: 'Add extra security',
              onTap: () => _showComingSoon('Two-Factor Authentication'),
            ),
            const Divider(height: 1),
            _buildMenuItem(
              icon: Icons.devices_outlined,
              title: 'Active Sessions',
              subtitle: 'Manage logged-in devices',
              onTap: () => _showComingSoon('Active Sessions'),
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionHeader('Privacy'),
          const SizedBox(height: 12),
          _buildMenuCard([
            _buildMenuItem(
              icon: Icons.visibility_outlined,
              title: 'Profile Visibility',
              subtitle: 'Control who can see your profile',
              onTap: () => _showComingSoon('Profile Visibility'),
            ),
            const Divider(height: 1),
            _buildMenuItem(
              icon: Icons.history_outlined,
              title: 'Activity History',
              subtitle: 'View and manage your activity',
              onTap: () => _showComingSoon('Activity History'),
            ),
            const Divider(height: 1),
            _buildMenuItem(
              icon: Icons.share_outlined,
              title: 'Data Sharing',
              subtitle: 'Manage data sharing preferences',
              onTap: () => _showComingSoon('Data Sharing'),
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionHeader('Data Management'),
          const SizedBox(height: 12),
          _buildMenuCard([
            _buildMenuItem(
              icon: Icons.download_outlined,
              title: 'Download Your Data',
              subtitle: 'Get a copy of your information',
              onTap: () => _showComingSoon('Download Your Data'),
            ),
            const Divider(height: 1),
            _buildMenuItem(
              icon: Icons.delete_outline,
              title: 'Delete Account',
              subtitle: 'Permanently delete your account',
              onTap: _deleting ? null : _showDeleteAccountDialog, // ✅ same flow as Profile
              textColor: kRed,
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color? textColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: (textColor ?? kPrimaryBlue).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: textColor ?? kPrimaryBlue, size: 24),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor ?? Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      ),
      trailing: _deleting && title == 'Delete Account'
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: kRed),
            )
          : Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  // -------------------------------------------
  // Change Password (unchanged, still Woo API)
  // -------------------------------------------
  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Change Password',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter current password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter new password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value != newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState?.validate() ?? false) {
                        setDialogState(() => isLoading = true);

                        try {
                          final userProvider = Provider.of<UserProvider>(context, listen: false);
                          final userId = userProvider.user?['id'];

                          if (userId == null) throw Exception('User not logged in');

                          final wooService = WooCommerceService();
                          final success = await wooService.updateCustomerPassword(
                            userId,
                            newPasswordController.text,
                          );

                          if (!success) {
                            throw Exception('Failed to update password');
                          }

                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password updated successfully!'),
                                backgroundColor: kGreen,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: kRed,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setDialogState(() => isLoading = false);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------
  // Delete Account — now reuses the shared helper flow (DRY)
  // --------------------------------------------------------
  Future<void> _showDeleteAccountDialog() async {
    setState(() => _deleting = true);
    try {
      final user = context.read<UserProvider>().user;
      final email = (user?['email'] ?? '').toString();
      await AccountDeletion.confirmAndDelete(context, email);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Coming Soon!'),
        backgroundColor: kAccentBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
