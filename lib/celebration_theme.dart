import 'package:flutter/material.dart';

/// 🎨 Celebration Theme Model
class CelebrationTheme {
  final String id;
  final String name;
  final String description;
  final Color primaryColor;
  final Color accentColor;
  final Color secondaryColor;
  final LinearGradient gradient;
  final LinearGradient? drawerGradient; // ✅ NEW: Separate drawer gradient
  final String iconEmoji;
  final String greetingText;
  final String bannerText;
  final bool showSpecialBadge;
  final String badgeText;
  final Color badgeColor;
  final Color wishlistBadgeColor; // ✅ NEW: Wishlist badge color
  final Color cartBadgeColor; // ✅ NEW: Cart badge color

  CelebrationTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.primaryColor,
    required this.accentColor,
    required this.secondaryColor,
    required this.gradient,
    this.drawerGradient,
    required this.iconEmoji,
    required this.greetingText,
    required this.bannerText,
    this.showSpecialBadge = false,
    this.badgeText = '',
    this.badgeColor = Colors.red,
    this.wishlistBadgeColor = Colors.pink,
    this.cartBadgeColor = Colors.red,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  // Create from JSON
  static CelebrationTheme? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null) return null;
    return predefinedThemes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => defaultTheme,
    );
  }
}

// 🎨 PREDEFINED CELEBRATION THEMES

/// 🛍️ Default Theme (TellMe Blue - YOUR ORIGINAL DESIGN)
final CelebrationTheme defaultTheme = CelebrationTheme(
  id: 'default',
  name: 'Default (TellMe Blue)',
  description: 'Your original TellMe branding colors',
  primaryColor: const Color(0xFF004AAD), // ✅ Matches your kPrimaryBlue
  accentColor: const Color(0xFF0096FF), // ✅ Matches your kAccentBlue
  secondaryColor: const Color(0xFF1565C0), // ✅ Fallback color
  gradient: const LinearGradient(
    colors: [Color(0xFF004AAD), Color(0xFF0096FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  drawerGradient: const LinearGradient(
    colors: [Color(0xFF0074FF), Color(0xFF0056CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🛍️',
  greetingText: 'Welcome to TellMe',
  bannerText: 'Shop the best deals!',
  wishlistBadgeColor: Colors.pink, // ✅ Matches your original
  cartBadgeColor: Colors.red, // ✅ Matches your original
);

/// 🎄 Christmas Theme
final CelebrationTheme christmasTheme = CelebrationTheme(
  id: 'christmas',
  name: 'Christmas',
  description: 'Festive red and green for Christmas',
  primaryColor: const Color(0xFFC41E3A),
  accentColor: const Color(0xFF165B33),
  secondaryColor: const Color(0xFFFFD700),
  gradient: const LinearGradient(
    colors: [Color(0xFFC41E3A), Color(0xFF165B33)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🎄',
  greetingText: 'Merry Christmas!',
  bannerText: '🎅 Special Christmas Deals 🎁',
  showSpecialBadge: true,
  badgeText: 'XMAS SALE',
  badgeColor: const Color(0xFFFFD700),
  wishlistBadgeColor: const Color(0xFFFFD700),
  cartBadgeColor: const Color(0xFFC41E3A),
);

/// 🎆 New Year Theme
final CelebrationTheme newYearTheme = CelebrationTheme(
  id: 'newyear',
  name: 'New Year',
  description: 'Gold and silver celebration',
  primaryColor: const Color(0xFFFFD700),
  accentColor: const Color(0xFFC0C0C0),
  secondaryColor: const Color(0xFF000000),
  gradient: const LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFC0C0C0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🎆',
  greetingText: 'Happy New Year!',
  bannerText: '✨ New Year, New Deals! 🎊',
  showSpecialBadge: true,
  badgeText: 'NEW YEAR',
  badgeColor: const Color(0xFFFFD700),
  wishlistBadgeColor: const Color(0xFFC0C0C0),
  cartBadgeColor: const Color(0xFFFFD700),
);

/// 💚 Green Energy Week Theme
final CelebrationTheme greenEnergyTheme = CelebrationTheme(
  id: 'greenenergy',
  name: 'Green Energy Week',
  description: 'Eco-friendly green theme',
  primaryColor: const Color(0xFF2E7D32),
  accentColor: const Color(0xFF66BB6A),
  secondaryColor: const Color(0xFF4CAF50),
  gradient: const LinearGradient(
    colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🌱',
  greetingText: 'Go Green!',
  bannerText: '♻️ Sustainable Shopping Week 🌍',
  showSpecialBadge: true,
  badgeText: 'ECO DEALS',
  badgeColor: const Color(0xFF66BB6A),
  wishlistBadgeColor: const Color(0xFF66BB6A),
  cartBadgeColor: const Color(0xFF2E7D32),
);

/// ❤️ Valentine's Day Theme
final CelebrationTheme valentineTheme = CelebrationTheme(
  id: 'valentine',
  name: "Valentine's Day",
  description: 'Romantic pink and red',
  primaryColor: const Color(0xFFE91E63),
  accentColor: const Color(0xFFF06292),
  secondaryColor: const Color(0xFFFF4081),
  gradient: const LinearGradient(
    colors: [Color(0xFFE91E63), Color(0xFFF06292)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '❤️',
  greetingText: 'Love is in the air!',
  bannerText: '💕 Valentine\'s Special Gifts 💝',
  showSpecialBadge: true,
  badgeText: 'LOVE SALE',
  badgeColor: const Color(0xFFFF4081),
  wishlistBadgeColor: const Color(0xFFFF4081),
  cartBadgeColor: const Color(0xFFE91E63),
);

/// 🕌 Ramadan Theme
final CelebrationTheme ramadanTheme = CelebrationTheme(
  id: 'ramadan',
  name: 'Ramadan',
  description: 'Purple and gold for Ramadan',
  primaryColor: const Color(0xFF673AB7),
  accentColor: const Color(0xFFFFD700),
  secondaryColor: const Color(0xFF9C27B0),
  gradient: const LinearGradient(
    colors: [Color(0xFF673AB7), Color(0xFF512DA8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🕌',
  greetingText: 'Ramadan Kareem!',
  bannerText: '🌙 Blessed Ramadan Offers ⭐',
  showSpecialBadge: true,
  badgeText: 'RAMADAN',
  badgeColor: const Color(0xFFFFD700),
  wishlistBadgeColor: const Color(0xFFFFD700),
  cartBadgeColor: const Color(0xFF673AB7),
);

/// 🎃 Halloween Theme
final CelebrationTheme halloweenTheme = CelebrationTheme(
  id: 'halloween',
  name: 'Halloween',
  description: 'Spooky orange and black',
  primaryColor: const Color(0xFFFF6F00),
  accentColor: const Color(0xFF000000),
  secondaryColor: const Color(0xFFFF9800),
  gradient: const LinearGradient(
    colors: [Color(0xFFFF6F00), Color(0xFF000000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🎃',
  greetingText: 'Happy Halloween!',
  bannerText: '👻 Spooky Deals & Treats 🍬',
  showSpecialBadge: true,
  badgeText: 'SPOOKY SALE',
  badgeColor: const Color(0xFFFF9800),
  wishlistBadgeColor: const Color(0xFFFF9800),
  cartBadgeColor: const Color(0xFFFF6F00),
);

/// 🇳🇬 Nigeria Independence Day Theme
final CelebrationTheme independenceTheme = CelebrationTheme(
  id: 'independence',
  name: 'Independence Day',
  description: 'Nigerian green and white',
  primaryColor: const Color(0xFF008751),
  accentColor: const Color(0xFFFFFFFF),
  secondaryColor: const Color(0xFF4CAF50),
  gradient: const LinearGradient(
    colors: [Color(0xFF008751), Color(0xFF4CAF50)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🇳🇬',
  greetingText: 'Happy Independence Day!',
  bannerText: '🎊 Nigeria at 64! Celebrate with Great Deals 🇳🇬',
  showSpecialBadge: true,
  badgeText: 'NAIJA PRIDE',
  badgeColor: const Color(0xFF008751),
  wishlistBadgeColor: const Color(0xFF4CAF50),
  cartBadgeColor: const Color(0xFF008751),
);

/// 🎓 Back to School Theme
final CelebrationTheme backToSchoolTheme = CelebrationTheme(
  id: 'backtoschool',
  name: 'Back to School',
  description: 'Blue and yellow for education',
  primaryColor: const Color(0xFF1976D2),
  accentColor: const Color(0xFFFFC107),
  secondaryColor: const Color(0xFF2196F3),
  gradient: const LinearGradient(
    colors: [Color(0xFF1976D2), Color(0xFF2196F3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🎓',
  greetingText: 'Back to School!',
  bannerText: '📚 School Supplies & More 🎒',
  showSpecialBadge: true,
  badgeText: 'SCHOOL SALE',
  badgeColor: const Color(0xFFFFC107),
  wishlistBadgeColor: const Color(0xFFFFC107),
  cartBadgeColor: const Color(0xFF1976D2),
);

/// 🌸 Easter Theme
final CelebrationTheme easterTheme = CelebrationTheme(
  id: 'easter',
  name: 'Easter',
  description: 'Pastel colors for Easter',
  primaryColor: const Color(0xFF9C27B0),
  accentColor: const Color(0xFFFFEB3B),
  secondaryColor: const Color(0xFFE1BEE7),
  gradient: const LinearGradient(
    colors: [Color(0xFF9C27B0), Color(0xFFE1BEE7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  iconEmoji: '🐰',
  greetingText: 'Happy Easter!',
  bannerText: '🥚 Easter Egg Hunt Deals 🌸',
  showSpecialBadge: true,
  badgeText: 'EASTER SALE',
  badgeColor: const Color(0xFFFFEB3B),
  wishlistBadgeColor: const Color(0xFFFFEB3B),
  cartBadgeColor: const Color(0xFF9C27B0),
);

// 📚 List of all predefined themes
final List<CelebrationTheme> predefinedThemes = [
  defaultTheme,
  christmasTheme,
  newYearTheme,
  greenEnergyTheme,
  valentineTheme,
  ramadanTheme,
  halloweenTheme,
  independenceTheme,
  backToSchoolTheme,
  easterTheme,
];
