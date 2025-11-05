import 'dart:ui'; // for ImageFilter (glassy blur)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';                 // ✅ for kDebugMode
import 'package:firebase_core/firebase_core.dart';        // ✅ show projectId (no extra init here)

import 'user_settings_provider.dart';
import 'celebration_theme.dart';
import 'celebration_theme_provider.dart';
import 'user_provider.dart';

// ✅ Your existing pages
import 'profile_page.dart';
import 'change_password_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  // ✅ Easter egg counter for admin toggle (tap AppBar title 5×)
  static int _tapCount = 0;

  @override
  Widget build(BuildContext context) {
    final settings      = Provider.of<UserSettingsProvider>(context);
    final themeProvider = Provider.of<CelebrationThemeProvider>(context);
    final userProvider  = Provider.of<UserProvider>(context);
    final isAdmin       = userProvider.isAdmin;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get theme colors exactly like in SignUpPage
    final currentTheme = themeProvider.currentTheme;
    final primaryColor = currentTheme.primaryColor;
    final accentColor = currentTheme.accentColor;
    final gradientColors = currentTheme.gradient.colors;
    final lightBlue = const Color(0xFFE3F2FD);
    final veryLightBlue = const Color(0xFFF5F8FF);
    final kVeryFaintBlue = Color(0x08F0F8FF); // Very faint blue with high transparency
    final kSoftBlueBG = Color(0x05E6F3FF); // Super light blue background tint
    final kGlassBlue = Color(0x30E6F3FF); // Semi-transparent blue for glass effect
    final kGlassBorder = Color(0x20B8D4FF); // Very faint blue border for glass sections

    // Debug info
    if (kDebugMode) {
      debugPrint('🎯 SettingsPage - isAdmin: $isAdmin');
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // ✅ Enhanced admin toggle with better feedback
        title: GestureDetector(
          onTap: () async {
            // Remove this line if you want it to work in release too:
            if (!kDebugMode) return;

            _tapCount++;
            debugPrint('🎯 Settings title tapped: $_tapCount/5 times');

            if (_tapCount >= 5) {
              _tapCount = 0;
              final userProvider = context.read<UserProvider>();
              final newVal = !userProvider.isAdmin;

              debugPrint('👑 Setting admin flag to: $newVal');

              await userProvider.setAdminFlag(newVal);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(newVal
                        ? '👑 Admin mode enabled – Celebration Themes unlocked'
                        : 'Admin mode disabled'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            } else {
              // Show tap feedback
              if (context.mounted) {
                ScaffoldMessenger.of(context).removeCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Tap ${5 - _tapCount} more times for admin mode'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(milliseconds: 800),
                  ),
                );
              }
            }
          },
          child: const Text("Settings"),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : primaryColor,
      ),
      body: Stack(
        children: [
          // 🌤️ Enhanced glassy background with very faint blue - THEME AWARE
          _SoftBackground(primaryColor: primaryColor, accentColor: accentColor),

          // Subtle top glass scrim for readability under status bar - THEME AWARE
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: kToolbarHeight + MediaQuery.of(context).padding.top,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kVeryFaintBlue.withOpacity(0.85),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 24),
            children: [
              _glassSection(
                context,
                label: "Account",
                primaryColor: primaryColor,
                accentColor: accentColor,
                children: [
                  _GlassTile(
                    leading: const Icon(Icons.person),
                    title: "Profile Information",
                    subtitle: "Manage your name, email & phone",
                    primaryColor: primaryColor,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ProfilePage()), // ⬅️ no const
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _GlassTile(
                    leading: const Icon(Icons.lock),
                    title: "Change Password",
                    primaryColor: primaryColor,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ChangePasswordPage()), // ⬅️ no const
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              _glassSection(
                context,
                label: "Preferences",
                primaryColor: primaryColor,
                accentColor: accentColor,
                children: [
                  _GlassExpansion(
                    leading: const Icon(Icons.color_lens),
                    title: "Theme",
                    subtitle: settings.themeMode
                        .toString()
                        .split('.')
                        .last
                        .toUpperCase(),
                    primaryColor: primaryColor,
                    children: [
                      RadioListTile<ThemeMode>(
                        title: const Text("System Default"),
                        value: ThemeMode.system,
                        groupValue: settings.themeMode,
                        onChanged: (val) => settings.setThemeMode(val!),
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text("Light"),
                        value: ThemeMode.light,
                        groupValue: settings.themeMode,
                        onChanged: (val) => settings.setThemeMode(val!),
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text("Dark"),
                        value: ThemeMode.dark,
                        groupValue: settings.themeMode,
                        onChanged: (val) => settings.setThemeMode(val!),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  _GlassTile(
                    leading: const Icon(Icons.language),
                    title: "Language",
                    subtitle: "English",
                    primaryColor: primaryColor,
                    onTap: () {},
                  ),
                  // ❌ Currency removed (as requested)
                ],
              ),

              const SizedBox(height: 16),

              _glassSection(
                context,
                label: "Page Styles",
                primaryColor: primaryColor,
                accentColor: accentColor,
                children: [
                  _GlassExpansion(
                    leading: const Icon(Icons.style),
                    title: "Page Style Settings",
                    subtitle: "Customize how pages look",
                    primaryColor: primaryColor,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          "Product Detail Style",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...ProductDetailStyle.values.map((style) {
                        return RadioListTile<ProductDetailStyle>(
                          title: Text(style.toString().split('.').last.toUpperCase()),
                          value: style,
                          groupValue: settings.productDetailStyle,
                          onChanged: (val) => settings.setProductDetailStyle(val!),
                        );
                      }).toList(),

                      const Divider(),

                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          "Home Page Style",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...HomePageStyle.values.map((style) {
                        return RadioListTile<HomePageStyle>(
                          title: Text(style.toString().split('.').last.toUpperCase()),
                          value: style,
                          groupValue: settings.homePageStyle,
                          onChanged: (val) => settings.setHomePageStyle(val!),
                        );
                      }).toList(),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

             // 🎯 Celebration Themes section - ADMIN ONLY (in all modes)
             if (isAdmin)
               _glassSection(
                 context,
                 label: "Celebration Themes",
                 badge: "ADMIN",
                 primaryColor: primaryColor,
                 accentColor: accentColor,
                 children: _buildCelebrationThemesSection(context, themeProvider, primaryColor, accentColor),
               ),

               const SizedBox(height: 16),

               _glassSection(
                 context,
                 label: "App Controls",
                 primaryColor: primaryColor,
                 accentColor: accentColor,
                 children: [
                   SwitchListTile.adaptive(
                     secondary: const Icon(Icons.notifications),
                     title: const Text("Push Notifications"),
                     value: true,
                     onChanged: (val) {},
                   ),
                   const Divider(height: 1),
                   _GlassTile(
                     leading: const Icon(Icons.storage),
                     title: "Clear Cache",
                     subtitle: "Free up storage space",
                     primaryColor: primaryColor,
                     onTap: () {},
                   ),
                   const Divider(height: 1),
                   ListTile(
                     leading: Icon(Icons.info_outline, color: accentColor),
                     title: const Text("App Version"),
                     subtitle: const Text("1.0.0"),
                   ),
                 ],
               ),
             ],
           ),
         ],
       ),
     );
   }

  // ===== Celebration Themes (updated with theme colors) =====
  List<Widget> _buildCelebrationThemesSection(
      BuildContext context, CelebrationThemeProvider themeProvider, Color primaryColor, Color accentColor) {
    final String projectId = _safeProjectId();

    return [
      ListTile(
        leading: Text(
          themeProvider.currentTheme.iconEmoji,
          style: const TextStyle(fontSize: 32),
        ),
        title: Text(
          "Current Theme: ${themeProvider.currentTheme.name}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(themeProvider.currentTheme.description),
      ),
      if (projectId.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _cloudPill(
            icon: Icons.cloud_done,
            text: "",
            primaryColor: primaryColor,
            accentColor: accentColor,
          ),
        ),
      _GlassExpansion(
        leading: const Icon(Icons.palette),
        title: "Select Celebration Theme",
        subtitle: "Active: ${themeProvider.currentTheme.name}",
        primaryColor: primaryColor,
        children: [
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: predefinedThemes.length,
              itemBuilder: (context, index) {
                final theme = predefinedThemes[index];
                final isActive = theme.id == themeProvider.currentTheme.id;

                return GestureDetector(
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: AlertDialog(
                            backgroundColor: Colors.white.withOpacity(0.1),
                            elevation: 0,
                            contentPadding: const EdgeInsets.all(24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(theme.iconEmoji, style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('Set Global Theme?')),
                              ],
                            ),
                            content: Text(
                              'This will change the theme to "${theme.name}" for ALL users in real-time. Continue?',
                              style: const TextStyle(fontSize: 16),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0x30E6F3FF).withOpacity(0.8),
                                  foregroundColor: primaryColor,
                                  side: BorderSide(
                                    color: const Color(0x20B8D4FF).withOpacity(0.8),
                                    width: 1,
                                  ),
                                ),
                                child: const Text('Set for Everyone'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                    if (confirmed == true) {
                      try {
                        await themeProvider.setGlobalTheme(theme.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('🌍 ${theme.iconEmoji} "${theme.name}" set globally!'),
                              backgroundColor: const Color(0x30E6F3FF),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('⚠️ Failed to set global theme: $e'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.primaryColor.withOpacity(0.8),
                              theme.accentColor.withOpacity(0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.primaryColor.withOpacity(0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(theme.iconEmoji, style: const TextStyle(fontSize: 32)),
                                  const Spacer(),
                                  const SizedBox(height: 4),
                                  Text(
                                    theme.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    theme.description,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 11,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isActive)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.check, color: primaryColor, size: 16),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
      ListTile(
        leading: Icon(Icons.schedule, color: accentColor),
        title: const Text("Schedule Theme"),
        subtitle: const Text("Auto-apply themes for holidays"),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Theme scheduling coming soon!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    ];
  }

  // ===== Enhanced glass section with better transparency - THEME AWARE =====
  Widget _glassSection(
    BuildContext context, {
    required String label,
    required List<Widget> children,
    String? badge,
    required Color primaryColor,
    required Color accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? Colors.white : primaryColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isDark ? Colors.white.withOpacity(0.08) : const Color(0x30E6F3FF).withOpacity(0.4),
                isDark ? Colors.white.withOpacity(0.03) : const Color(0x08F0F8FF).withOpacity(0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.15) : const Color(0x20B8D4FF),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: headerColor,
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: badge == "DEBUG"
                                  ? Colors.blue.withOpacity(0.2)
                                  : Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: badge == "DEBUG"
                                    ? Colors.blue.withOpacity(0.4)
                                    : Colors.orange.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badge == "DEBUG" ? Colors.blue : Colors.orange,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.black.withOpacity(0.06)),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  // --- Helpers ---
  String _safeProjectId() {
    try {
      if (Firebase.apps.isEmpty) return '';
      return Firebase.app().options.projectId ?? '';
    } catch (_) {
      return '';
    }
  }

  Widget _cloudPill({required IconData icon, required String text, required Color primaryColor, required Color accentColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x30E6F3FF).withOpacity(0.7),
            border: Border.all(color: const Color(0x20B8D4FF), width: 1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: primaryColor),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftBackground extends StatelessWidget {
  final Color primaryColor;
  final Color accentColor;

  const _SoftBackground({required this.primaryColor, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    // Enhanced glassy background with very faint blue tones + additional glass blobs - THEME AWARE
    return Stack(
      children: [
        // Base gradient with very faint blue
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x08F0F8FF), Color(0x05E6F3FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        // Enhanced faint blurred circles for depth - THEME AWARE
        Positioned(
          top: -40,
          left: -20,
          child: _blurCircle(160, accentColor.withOpacity(0.10)),
        ),
        Positioned(
          bottom: -30,
          right: -10,
          child: _blurCircle(140, primaryColor.withOpacity(0.08)),
        ),
        // Additional glass blobs for enhanced depth - THEME AWARE
        Positioned(
          top: -100,
          left: -50,
          child: _blurCircle(120, const Color(0x30E6F3FF).withOpacity(0.15)),
        ),
        Positioned(
          top: 120,
          right: -60,
          child: _blurCircle(100, accentColor.withOpacity(0.12)),
        ),
        Positioned(
          bottom: -80,
          left: 60,
          child: _blurCircle(110, primaryColor.withOpacity(0.10)),
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

class _GlassTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color primaryColor;

  const _GlassTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: IconTheme(
              data: IconThemeData(color: isDark ? Colors.white : primaryColor),
              child: leading,
            ),
            title: Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A), // slate-900-ish
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: subtitle != null
                ? Text(
                    subtitle!,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF475569), // slate-600
                    ),
                  )
                : null,
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF64748B), // slate-500
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _GlassExpansion extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Color primaryColor;

  const _GlassExpansion({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.children,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final titleStyle = TextStyle(
      color: isDark ? Colors.white : const Color(0xFF0F172A),
      fontWeight: FontWeight.w600,
    );
    final subtitleStyle = TextStyle(
      color: isDark ? Colors.white70 : const Color(0xFF475569),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isDark ? 0.05 : 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.black.withOpacity(0.06),
              splashColor: Colors.black.withOpacity(0.04),
              highlightColor: Colors.black.withOpacity(0.02),
              listTileTheme: ListTileThemeData(
                iconColor: isDark ? Colors.white : primaryColor,
              ),
            ),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: IconTheme(
                data: IconThemeData(color: isDark ? Colors.white : primaryColor),
                child: leading,
              ),
              title: Text(title, style: titleStyle),
              subtitle: subtitle != null ? Text(subtitle!, style: subtitleStyle) : null,
              collapsedIconColor: isDark ? Colors.white : primaryColor,
              iconColor: isDark ? Colors.white : primaryColor,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}