import 'package:flutter/material.dart';
// import 'package:package_info_plus/package_info_plus.dart'; // Add this dependency to pubspec.yaml to enable version info

// 🎨 Brand Colors
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);

class AboutPage extends StatefulWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '1.0.0';
  String _buildNumber = '1';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    // Uncomment below when package_info_plus is added to pubspec.yaml
    // try {
    //   final packageInfo = await PackageInfo.fromPlatform();
    //   setState(() {
    //     _version = packageInfo.version;
    //     _buildNumber = packageInfo.buildNumber;
    //   });
    // } catch (e) {
    //   // If package_info_plus is not available, use default values
    //   setState(() {
    //     _version = '1.0.0';
    //     _buildNumber = '1';
    //   });
    // }

    // Using default values for now
    setState(() {
      _version = '1.0.0';
      _buildNumber = '1';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'About',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // App Logo Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryBlue, kAccentBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      size: 60,
                      color: kPrimaryBlue,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Your Shop',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version $_version (Build $_buildNumber)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),

            // Info Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    title: 'About Us',
                    description:
                        'We are committed to providing you with the best shopping experience. Our mission is to deliver quality products at great prices with exceptional customer service.',
                    icon: Icons.info_outline,
                  ),
                  const SizedBox(height: 16),

                  _buildMenuCard([
                    _buildMenuItem(
                      icon: Icons.description_outlined,
                      title: 'Terms of Service',
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    _buildMenuItem(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    _buildMenuItem(
                      icon: Icons.gavel_outlined,
                      title: 'Licenses',
                      onTap: () => showLicensePage(context: context),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // Social Links
                  _buildSocialLinks(),
                  const SizedBox(height: 32),

                  // Copyright
                  Text(
                    '© 2025 Your Shop. All rights reserved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: kPrimaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: kPrimaryBlue, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
        ],
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
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: kPrimaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: kPrimaryBlue, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  Widget _buildSocialLinks() {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        children: [
          const Text(
            'Follow Us',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSocialButton(
                icon: Icons.facebook,
                onTap: () {},
              ),
              const SizedBox(width: 16),
              _buildSocialButton(
                icon: Icons.camera_alt,
                onTap: () {},
              ),
              const SizedBox(width: 16),
              _buildSocialButton(
                icon: Icons.message,
                onTap: () {},
              ),
              const SizedBox(width: 16),
              _buildSocialButton(
                icon: Icons.language,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: kPrimaryBlue.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: Icon(icon, color: kPrimaryBlue, size: 28),
        ),
      ),
    );
  }
}
