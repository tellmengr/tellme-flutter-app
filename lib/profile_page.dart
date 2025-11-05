// ============================================================
// 🌟 HYBRID PROFILE PAGE - SIGN-IN DESIGN ELEMENTS INTEGRATED
// Now wired to CelebrationThemeProvider (global admin theme)
// ============================================================

import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import 'glass_widgets.dart';
import 'user_provider.dart';
import 'bottom_nav_helper.dart';
import 'woocommerce_auth_service.dart';
import 'celebration_theme_provider.dart'; // 👈 NEW: use global celebration theme

// (These are referenced via named routes; imports not strictly required,
// but safe to keep if you directly navigate with MaterialPageRoute elsewhere)
import 'sign_in_page.dart';
import 'sign_up_page.dart';
import 'my_orders_page.dart';
import 'edit_profile_page.dart';
import 'addresses_page.dart';
import 'notifications_settings_page.dart';
import 'privacy_security_page.dart';
import 'help_center_page.dart';
import 'about_page.dart';
import 'wishlist_page.dart';
import 'checkout_page.dart';
import 'account_delete_helper.dart';

// 🎨 Keep neutrals & semantic colors (not replaced by celebration theme)
const kBackgroundBlue = Color(0xFFF5F8FF);
const kWhite = Color(0xFFFFFFFF);
const kTextDark = Color(0xFF1A1A1A);
const kTextMedium = Color(0xFF4A5568);
const kTextLight = Color(0xFF718096);
const kGrey100 = Color(0xFFF5F5F5);
const kGrey200 = Color(0xFFEEEEEE);
const kGrey300 = Color(0xFFE0E0E0);
const kWalletGreen = Color(0xFF10B981);
const kRed = Color(0xFFE53935);
const kGreen = Color(0xFF43A047);
const kYellow = Color(0xFFFFB300);

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  // 🔑 Safe SnackBar via Scaffold key
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Enhanced animations inspired by sign-in page
  late final AnimationController _ac =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..forward();
  late final Animation<double> _fadeAnimation =
      CurvedAnimation(parent: _ac, curve: Curves.easeInOut);

  // Wallet state
  bool _isLoadingWallet = false;
  Map<String, dynamic>? _walletBalance;
  String? _walletError;

  // Payment state
  bool _isProcessingPayment = false;

  // 🔒 Deletion progress (for button state)
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = context.read<UserProvider>();
      if (userProvider.isLoggedIn) {
        _loadWalletBalance();
      }
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    if (!userProvider.isLoggedIn) {
      return _buildSignInPrompt(context);
    }
    return _buildLoggedInView(context, userProvider);
  }

  // ------------------------------------------------------------------
  // 🔐 SIGN-IN PROMPT - Sign-In Page Style (now themed)
  // ------------------------------------------------------------------
  Widget _buildSignInPrompt(BuildContext context) {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: t.primaryColor,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 🎨 Use global celebration gradient
          Container(
            decoration: BoxDecoration(
              gradient: t.gradient,
            ),
          ),

          // 💠 Soft glow shapes
          const Positioned(
            top: -60,
            right: -40,
            child: _GlowCircle(diameter: 220, opacity: 0.10),
          ),
          const Positioned(
            bottom: 80,
            left: -60,
            child: _GlowCircle(diameter: 180, opacity: 0.08),
          ),

          // 👤 Profile-specific header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildProfileHeader(),
                  const SizedBox(height: 32),
                  _buildSignInCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: const [
        SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(color: Colors.white),
        ),
        SizedBox(height: 16),
        Text(
          "TELLME",
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 6,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
          ),
        ),
        SizedBox(height: 12),
        Text(
          "My Profile",
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 8),
        Text(
          "Sign in to access your profile",
          style: TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildSignInCard() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: const _ProfileGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 8),
            _WelcomeTitle(), // 👈 themed title
            SizedBox(height: 8),
            Text(
              'Sign in to access your orders, wishlist, and manage your account',
              style: TextStyle(
                fontSize: 15,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            SizedBox(height: 32),
            _PrimaryCTA(
              label: "SIGN IN",
              onPressed: null, // uses default route
            ),
            SizedBox(height: 16),
            _SecondaryCTA(
              label: "CREATE ACCOUNT",
              onPressed: null, // uses default route
            ),
            SizedBox(height: 24),
            _AvatarPlaceholder(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 👤 LOGGED IN VIEW - Hybrid Design (now themed)
  // ------------------------------------------------------------------
  Widget _buildLoggedInView(BuildContext context, UserProvider userProvider) {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;
    final user = userProvider.user;
    final firstName = user?['first_name'] ?? 'User';
    final lastName = user?['last_name'] ?? '';
    final email = user?['email'] ?? 'user@example.com';
    final isAdmin = userProvider.isAdmin;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kBackgroundBlue,
      body: CustomScrollView(
        slivers: [
          // 🎨 Enhanced App Bar with global celebration gradient
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Container(
              margin: const EdgeInsets.only(left: 20, top: 8),
              decoration: BoxDecoration(
                color: kWhite.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: t.primaryColor.withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios_new, color: t.primaryColor, size: 18),
                onPressed: () => BottomNavHelper.goBack(context),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(gradient: t.gradient),
                child: SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: 20, bottom: 32, left: 20, right: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildUserAvatar(), // themed inside
                        const SizedBox(height: 20),
                        _buildUserInfo(firstName, lastName, email),
                        if (isAdmin) _buildAdminBadge(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 📋 Content with Glass cards
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 20),

                // 💰 WALLET SECTION
                _buildSectionHeader('💰 Wallet'),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: _ProfileGlassCard(child: _buildWalletContent()),
                ),

                const SizedBox(height: 32),

                // Account Section
                _buildSectionHeader('Account'),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: _ProfileGlassCard(child: _buildAccountMenu()),
                ),

                const SizedBox(height: 32),

                // Settings Section
                _buildSectionHeader('Settings'),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: _ProfileGlassCard(child: _buildSettingsMenu()),
                ),

                const SizedBox(height: 32),

                // Support Section
                _buildSectionHeader('Support'),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: _ProfileGlassCard(child: _buildSupportMenu()),
                ),

                const SizedBox(height: 40),

                // Sign Out Button
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: _SignOutCTA(
                    onPressed: () => _showSignOutDialog(userProvider),
                  ),
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 👤 USER PROFILE COMPONENTS
  // ------------------------------------------------------------------
  Widget _buildUserAvatar() {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;

    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kWhite,
        border: Border.all(color: kWhite, width: 4),
        boxShadow: [
          BoxShadow(
            color: t.primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(Icons.person_rounded, size: 50, color: t.primaryColor),
    );
  }

  Widget _buildUserInfo(String firstName, String lastName, String email) {
    return Column(
      children: [
        const Text(
          // Name text remains white on gradient
          '',
          style: TextStyle(fontSize: 0),
        ),
        Text(
          '$firstName $lastName',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: kWhite,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          email,
          style: TextStyle(
            fontSize: 14,
            color: kWhite.withOpacity(0.9),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAdminBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: kYellow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kYellow.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'ADMIN',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kWhite,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 💰 WALLET CONTENT - Glass Card
  // ------------------------------------------------------------------
  Widget _buildWalletContent() {
    return Column(
      children: [
        // Balance header
        Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: kWalletGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.account_balance_wallet, color: kWalletGreen, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wallet Balance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextDark),
                  ),
                  const SizedBox(height: 8),
                  if (_isLoadingWallet)
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(kWalletGreen),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Loading...',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextMedium),
                        ),
                      ],
                    )
                  else if (_walletError != null)
                    Text(
                      _walletError!,
                      style: const TextStyle(fontSize: 14, color: kRed, fontWeight: FontWeight.w500),
                    )
                  else if (_walletBalance != null)
                    Row(
                      children: [
                        Text(
                          '₦${_formatWalletBalance()}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kWalletGreen),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () async {
                            await _loadWalletBalance();
                            _showSnackSafe('Wallet balance refreshed!', kGreen);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: kWalletGreen.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.refresh, size: 16, color: kWalletGreen),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Actions
        Row(
          children: [
            Expanded(
              child: _WalletButton(
                label: _isProcessingPayment ? 'Processing...' : 'Add Funds',
                onPressed: _isProcessingPayment ? null : _showAddFundsDialog,
                isPrimary: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _WalletButton(
                label: 'History',
                onPressed: _isProcessingPayment
                    ? null
                    : () => BottomNavHelper.navigateToRoute(context, '/wallet-history'),
                isPrimary: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 📋 MENU SECTIONS
  // ------------------------------------------------------------------
  Widget _buildAccountMenu() {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;

    return Column(
      children: [
        _buildMenuItem(
          icon: Icons.shopping_bag_rounded,
          title: 'My Orders',
          subtitle: 'View order history',
          onTap: () => BottomNavHelper.navigateToRoute(context, '/myorders'),
          color: t.primaryColor,
        ),
        _buildDivider(),
        _buildMenuItem(
          icon: Icons.favorite_rounded,
          title: 'Wishlist',
          subtitle: 'Your saved items',
          onTap: () => BottomNavHelper.navigateToTab(context, 3),
          color: t.primaryColor,
        ),
        _buildDivider(),
        _buildMenuItem(
          icon: Icons.location_on_rounded,
          title: 'Addresses',
          subtitle: 'Manage delivery addresses',
          onTap: () => BottomNavHelper.navigateToRoute(context, '/addresses'),
          color: t.primaryColor,
        ),
      ],
    );
  }

  Widget _buildSettingsMenu() {
    final user = context.read<UserProvider>().user;
    final email = user?['email'] ?? '';
    final t = context.watch<CelebrationThemeProvider>().currentTheme;

    return Column(
      children: [
        _buildMenuItem(
          icon: Icons.person_rounded,
          title: 'Edit Profile',
          subtitle: 'Update your information',
          onTap: () => BottomNavHelper.navigateToRoute(context, '/editprofile'),
          color: t.primaryColor,
        ),
        _buildDivider(),
        _buildMenuItem(
          icon: Icons.notifications_rounded,
          title: 'Notifications',
          subtitle: 'Manage notifications',
          onTap: () => BottomNavHelper.navigateToRoute(context, '/notifications'),
          color: t.primaryColor,
        ),
        _buildDivider(),
        _buildMenuItem(
          icon: Icons.security_rounded,
          title: 'Privacy & Security',
          subtitle: 'Manage your privacy',
          onTap: () => BottomNavHelper.navigateToRoute(context, '/privacy'),
          color: t.primaryColor,
        ),
        _buildDivider(),
        // 🔥 Delete Account (uses shared helper)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: kRed.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_forever_rounded, color: kRed, size: 24),
          ),
          title: const Text(
            'Delete Account',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kRed),
          ),
          subtitle: const Text(
            'Permanently remove your account',
            style: TextStyle(fontSize: 13, color: kTextMedium, fontWeight: FontWeight.w400),
          ),
          trailing: _isDeleting
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(kRed),
                  ),
                )
              : const Icon(Icons.chevron_right_rounded, color: kGrey300, size: 20),
          onTap: _isDeleting
              ? null
              : () async {
                  _setStateIfMounted(() => _isDeleting = true);
                  try {
                    await AccountDeletion.confirmAndDelete(context, email);
                  } finally {
                    _setStateIfMounted(() => _isDeleting = false);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildSupportMenu() {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;

    return Column(
      children: [
        _buildMenuItem(
          icon: Icons.help_rounded,
          title: 'Help Center',
          subtitle: 'Get help and support',
          onTap: () => BottomNavHelper.navigateToRoute(context, '/help'),
          color: t.primaryColor,
        ),
        _buildDivider(),
        _buildMenuItem(
          icon: Icons.info_rounded,
          title: 'About',
          subtitle: 'App information',
          onTap: () => BottomNavHelper.navigateToRoute(context, '/about'),
          color: t.primaryColor,
        ),
      ],
    );
  }

  Widget _buildDivider() => const Divider(height: 1, color: kGrey200, thickness: 1);

  // ------------------------------------------------------------------
  // 🧩 SHARED COMPONENTS
  // ------------------------------------------------------------------
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: kTextLight,
            letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color, // 👈 pass themed color
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: kTextDark)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 13, color: kTextMedium, fontWeight: FontWeight.w400)),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: kGrey300, size: 20),
      onTap: onTap,
    );
  }

  void _showSignOutDialog(UserProvider userProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: kWhite,
        title: const Text('Sign Out',
            style:
                TextStyle(fontWeight: FontWeight.w800, color: kTextDark, fontSize: 20)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: kTextMedium, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style:
                    TextStyle(color: kTextMedium, fontWeight: FontWeight.w600)),
          ),
          Container(
            decoration:
                BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(12)),
            child: TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await userProvider.signOut();
                if (!mounted) return;
                _showSnackSafe('Signed out successfully', kGreen);
              },
              child: const Text('Sign Out',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- SAFE HELPERS ----------
  void _setStateIfMounted(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _showSnackSafe(String message, Color backgroundColor) {
    final ctx = _scaffoldKey.currentContext;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: [
              Icon(
                backgroundColor == kRed
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  // ------------------------------------------------------------------
  // 💰 WALLET METHODS
  // ------------------------------------------------------------------
  Future<void> _loadWalletBalance() async {
    try {
      _setStateIfMounted(() {
        _isLoadingWallet = true;
        _walletError = null;
      });

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) {
        _setStateIfMounted(() {
          _walletError = 'User not logged in';
          _walletBalance = null;
          _isLoadingWallet = false;
        });
        return;
      }

      final authService = WooCommerceAuthService();
      final userId = int.tryParse(user['id'].toString());

      if (userId == null || userId <= 0) {
        _setStateIfMounted(() {
          _walletError = 'Invalid user ID';
          _walletBalance = null;
          _isLoadingWallet = false;
        });
        return;
      }

      final walletResult = await authService.getWalletBalance(userId);

      _setStateIfMounted(() {
        if (walletResult != null && walletResult['success'] == true) {
          _walletBalance = walletResult;
          _walletError = null;
        } else {
          _walletError =
              'TeraWallet plugin may not be installed or activated. Please contact support.';
          _walletBalance = null;
        }
        _isLoadingWallet = false;
      });
    } catch (e) {
      _setStateIfMounted(() {
        _walletError =
            'TeraWallet plugin may not be installed or activated. Please contact support.';
        _walletBalance = null;
        _isLoadingWallet = false;
      });
    }
  }

  String _formatWalletBalance() {
    if (_walletBalance == null) return '0';
    final authService = WooCommerceAuthService();
    final balance = authService.getWalletBalanceAmount(_walletBalance!);
    return NumberFormat('#,###').format(balance);
    // Note: currency symbol added in UI above
  }

  void _showAddFundsDialog() {
    final TextEditingController amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: kWhite,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kWalletGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.account_balance_wallet, color: kWalletGreen),
            ),
            const SizedBox(width: 12),
            const Text('Add Funds',
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: kTextDark)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the amount you want to add to your wallet:',
                style: TextStyle(color: kTextMedium, fontSize: 15)),
            const SizedBox(height: 20),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'Amount (₦)',
                prefixIcon: const Icon(Icons.money, color: kWalletGreen),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kGrey200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: context.read<CelebrationThemeProvider>().currentTheme.primaryColor, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style:
                    TextStyle(color: kTextMedium, fontWeight: FontWeight.w600)),
          ),
          Container(
            decoration: BoxDecoration(
                color: kWalletGreen, borderRadius: BorderRadius.circular(12)),
            child: TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _processAddFunds(
                    double.tryParse(amountController.text) ?? 0);
              },
              child: const Text('Add Funds',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _processAddFunds(double amount) async {
    if (amount <= 0) {
      _showSnackSafe('Please enter a valid amount', kRed);
      return;
    }
    if (amount < 100) {
      _showSnackSafe('Minimum amount is ₦100', kRed);
      return;
    }
    if (amount > 500000) {
      _showSnackSafe('Maximum amount is ₦500,000', kRed);
      return;
    }

    try {
      _setStateIfMounted(() => _isProcessingPayment = true);

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      if (user == null) throw Exception('User not logged in');

      // ✅ FIXED: Use direct navigation instead of named route
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutPage(
            cartItems: [
              {
                'id': 'wallet_topup',
                'name': 'Wallet Top-up',
                'price': amount.toString(),
                'quantity': 1,
                'images': [
                  {
                    'src': 'https://via.placeholder.com/100x100/10B981/FFFFFF?text=Wallet'
                  }
                ],
                'cart_item_id': 'wallet_topup_${DateTime.now().millisecondsSinceEpoch}',
              }
            ],
            subtotal: amount,
            shipping: 0.0,
            total: amount,
            isWalletTopUp: true, // 👈 This will now work correctly!
            walletTopUpAmount: amount,
          ),
        ),
      );
    } catch (e) {
      _setStateIfMounted(() => _isProcessingPayment = false);
      _showSnackSafe('Error: $e', kRed);
    } finally {
      _setStateIfMounted(() => _isProcessingPayment = false);
    }
  } // <-- ✅ END OF _processAddFunds method
  } // <-- ✅ END OF _ProfilePageState class

// ==================================================================
// TOP-LEVEL HELPER WIDGETS (now consume CelebrationThemeProvider)
// ==================================================================

class _ProfileGlassCard extends StatelessWidget {
  final Widget child;
  const _ProfileGlassCard({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            color: kWhite.withOpacity(0.85),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kWhite.withOpacity(0.7), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _WelcomeTitle extends StatelessWidget {
  const _WelcomeTitle({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;
    return Text(
      'Welcome to Your Profile',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: t.primaryColor,
      ),
      textAlign: TextAlign.left,
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kWhite, t.accentColor.withOpacity(0.1)],
        ),
        border: Border.all(color: kWhite.withOpacity(0.9), width: 3),
        boxShadow: [
          BoxShadow(
              color: t.primaryColor.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Icon(Icons.person_rounded, size: 50, color: t.primaryColor),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double diameter;
  final double opacity;
  const _GlowCircle(
      {Key? key, required this.diameter, this.opacity = 0.1})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
        boxShadow: [
          BoxShadow(
              blurRadius: 60,
              spreadRadius: 10,
              color: Colors.white.withOpacity(opacity * 0.8)),
        ],
      ),
    );
  }
}

class _PrimaryCTA extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _PrimaryCTA({Key? key, required this.label, required this.onPressed})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;
    final go = onPressed ?? () => BottomNavHelper.navigateToRoute(context, '/signin');
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: go,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: t.gradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryCTA extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _SecondaryCTA({Key? key, required this.label, required this.onPressed})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<CelebrationThemeProvider>().currentTheme;
    final go = onPressed ?? () => BottomNavHelper.navigateToRoute(context, '/signup');
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: go,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: t.primaryColor, width: 1.8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: t.primaryColor,
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _WalletButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  const _WalletButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.isPrimary = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: kWalletGreen,
          ),
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      );
    } else {
      return SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kWalletGreen, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text(
            'History',
            style: TextStyle(
                color: kWalletGreen, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      );
    }
  }
}

class _SignOutCTA extends StatelessWidget {
  final VoidCallback? onPressed;
  const _SignOutCTA({Key? key, required this.onPressed}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kRed,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 20),
            SizedBox(width: 10),
            Text(
              'SIGN OUT',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}