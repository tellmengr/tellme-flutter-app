import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'celebration_theme_provider.dart';

// 🎨 Brand Colors
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);
const kGreen = Color(0xFF43A047);
const kRed = Color(0xFFE53935);

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({Key? key}) : super(key: key);

  @override
  State<NotificationsSettingsPage> createState() => _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  bool _orderUpdates = true;
  bool _promotions = true;
  bool _newArrivals = false;
  bool _priceDrops = true;
  bool _newsletter = false;
  bool _pushNotifications = true;
  bool _emailNotifications = true;
  bool _smsNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _orderUpdates = prefs.getBool('notif_order_updates') ?? true;
      _promotions = prefs.getBool('notif_promotions') ?? true;
      _newArrivals = prefs.getBool('notif_new_arrivals') ?? false;
      _priceDrops = prefs.getBool('notif_price_drops') ?? true;
      _newsletter = prefs.getBool('notif_newsletter') ?? false;
      _pushNotifications = prefs.getBool('notif_push') ?? true;
      _emailNotifications = prefs.getBool('notif_email') ?? true;
      _smsNotifications = prefs.getBool('notif_sms') ?? false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    // 🎨 CELEBRATION THEME INTEGRATION - Listen for theme changes
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;

    // Use celebration theme colors or fallback to brand colors
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kPrimaryBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];
    final badgeColor = currentTheme?.badgeColor ?? kRed;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Notification Types', themeProvider),
          const SizedBox(height: 12),
          _buildSettingsCard(themeProvider, [
            _buildSwitchTile(
              title: 'Order Updates',
              subtitle: 'Get notified about order status',
              icon: Icons.shopping_bag_outlined,
              value: _orderUpdates,
              onChanged: (value) {
                setState(() => _orderUpdates = value);
                _saveSetting('notif_order_updates', value);
              },
              themeProvider: themeProvider,
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: 'Promotions & Offers',
              subtitle: 'Special deals and discounts',
              icon: Icons.local_offer_outlined,
              value: _promotions,
              onChanged: (value) {
                setState(() => _promotions = value);
                _saveSetting('notif_promotions', value);
              },
              themeProvider: themeProvider,
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: 'New Arrivals',
              subtitle: 'Latest products and collections',
              icon: Icons.new_releases_outlined,
              value: _newArrivals,
              onChanged: (value) {
                setState(() => _newArrivals = value);
                _saveSetting('notif_new_arrivals', value);
              },
              themeProvider: themeProvider,
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: 'Price Drops',
              subtitle: 'Wishlist items on sale',
              icon: Icons.trending_down_rounded,
              value: _priceDrops,
              onChanged: (value) {
                setState(() => _priceDrops = value);
                _saveSetting('notif_price_drops', value);
              },
              themeProvider: themeProvider,
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: 'Newsletter',
              subtitle: 'Weekly updates and tips',
              icon: Icons.mail_outline,
              value: _newsletter,
              onChanged: (value) {
                setState(() => _newsletter = value);
                _saveSetting('notif_newsletter', value);
              },
              themeProvider: themeProvider,
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionHeader('Delivery Methods', themeProvider),
          const SizedBox(height: 12),
          _buildSettingsCard(themeProvider, [
            _buildSwitchTile(
              title: 'Push Notifications',
              subtitle: 'Receive notifications on this device',
              icon: Icons.notifications_outlined,
              value: _pushNotifications,
              onChanged: (value) {
                setState(() => _pushNotifications = value);
                _saveSetting('notif_push', value);
              },
              themeProvider: themeProvider,
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: 'Email Notifications',
              subtitle: 'Receive updates via email',
              icon: Icons.email_outlined,
              value: _emailNotifications,
              onChanged: (value) {
                setState(() => _emailNotifications = value);
                _saveSetting('notif_email', value);
              },
              themeProvider: themeProvider,
            ),
            const Divider(height: 1),
            _buildSwitchTile(
              title: 'SMS Notifications',
              subtitle: 'Receive text messages',
              icon: Icons.sms_outlined,
              value: _smsNotifications,
              onChanged: (value) {
                setState(() => _smsNotifications = value);
                _saveSetting('notif_sms', value);
              },
              themeProvider: themeProvider,
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, CelebrationThemeProvider? themeProvider) {
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

  Widget _buildSettingsCard(CelebrationThemeProvider? themeProvider, List<Widget> children) {
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.08), // 🎨 Use theme-aware shadow color
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    required CelebrationThemeProvider? themeProvider,
  }) {
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      secondary: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: primaryColor, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: primaryColor,
    );
  }
}