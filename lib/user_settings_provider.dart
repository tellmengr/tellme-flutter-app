import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // ✅ Added for currency formatting

/// 🏠 Home Page Layout Options
enum HomePageStyle { grid, list, carousel, staggered, modern }

/// 🛍️ Product Detail Page Layout Options
/// NOTE: Renamed `related` -> `swipe` but kept the same index position (3)
/// so existing saved preferences (by index) continue to work.
enum ProductDetailStyle { classic, gallery, standard, swipe, modern }

/// 🌗 Theme + Page Style Settings Manager
class UserSettingsProvider with ChangeNotifier {
  HomePageStyle _homePageStyle = HomePageStyle.grid;
  ProductDetailStyle _productDetailStyle = ProductDetailStyle.standard;
  ThemeMode _themeMode = ThemeMode.system;

  bool _initialized = false;

  // --- Getters ---
  HomePageStyle get homePageStyle => _homePageStyle;
  ProductDetailStyle get productDetailStyle => _productDetailStyle;
  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _initialized;

  // =====================================================
  // 💰 Enhanced Global Currency Formatter (fixes ₦ issues)
  // =====================================================
  String formatCurrency(dynamic value, {bool showDecimals = true}) {
    double val = 0;
    if (value is String) {
      val = double.tryParse(value) ?? 0;
    } else if (value is num) {
      val = value.toDouble();
    }

    try {
      // Try Nigerian locale first
      final formatter = NumberFormat.currency(
        locale: 'en_NG',
        symbol: '₦',
        decimalDigits: showDecimals ? 2 : 0,
        customPattern: showDecimals ? '¤#,##0.00' : '¤#,##0',
      );
      return formatter.format(val);
    } catch (e) {
      // Fallback to manual formatting if locale fails
      return _formatCurrencyFallback(val, showDecimals: showDecimals);
    }
  }

  // =====================================================
  // 🔒 Fallback Currency Formatter (Always Works)
  // =====================================================
  String _formatCurrencyFallback(double value, {bool showDecimals = true}) {
    try {
      final formatter =
          NumberFormat(showDecimals ? "#,##0.00" : "#,##0", "en_US");
      final formattedNumber = formatter.format(value);
      return "₦$formattedNumber";
    } catch (e) {
      // Ultimate fallback - manual formatting
      return _manualCurrencyFormat(value, showDecimals: showDecimals);
    }
  }

  // =====================================================
  // 🛠️ Manual Currency Formatter (Ultimate Fallback)
  // =====================================================
  String _manualCurrencyFormat(double value, {bool showDecimals = true}) {
    String numberStr =
        showDecimals ? value.toStringAsFixed(2) : value.round().toString();

    // Add commas for thousands separator
    List<String> parts = numberStr.split('.');
    String wholePart = parts[0];
    String decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Insert commas from right to left
    String result = '';
    for (int i = 0; i < wholePart.length; i++) {
      if (i > 0 && (wholePart.length - i) % 3 == 0) {
        result += ',';
      }
      result += wholePart[i];
    }

    return "₦$result$decimalPart";
  }

  // =====================================================
  // 🎯 Convenience Methods for Different Use Cases
  // =====================================================

  /// Format price with decimals (e.g., ₦1,500.00)
  String formatPrice(dynamic value) =>
      formatCurrency(value, showDecimals: true);

  /// Format price without decimals (e.g., ₦1,500)
  String formatPriceShort(dynamic value) =>
      formatCurrency(value, showDecimals: false);

  // =====================================================
  // 🔹 Initialize all settings from SharedPreferences
  // =====================================================
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // 🏠 Load Home Page Style
      final homeIndex = prefs.getInt('homePageStyle') ?? 0;
      if (homeIndex >= 0 && homeIndex < HomePageStyle.values.length) {
        _homePageStyle = HomePageStyle.values[homeIndex];
      }

      // 🛍️ Load Product Detail Style (safe fallback)
      // We store by index, so renaming related->swipe does not break anything.
      final detailIndex = prefs.getInt('productDetailStyle') ?? 2;
      if (detailIndex >= 0 && detailIndex < ProductDetailStyle.values.length) {
        _productDetailStyle = ProductDetailStyle.values[detailIndex];
      } else {
        _productDetailStyle = ProductDetailStyle.standard;
      }

      // 🌙 Load Theme Mode
      final themeIndex = prefs.getInt('themeMode') ?? 0;
      if (themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
        _themeMode = ThemeMode.values[themeIndex];
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint("⚠️ Error loading user settings: $e");
      _initialized = true;
      notifyListeners();
    }
  }

  // =====================================================
  // 🏠 Save Home Page Style
  // =====================================================
  Future<void> setHomePageStyle(HomePageStyle style) async {
    if (_homePageStyle != style) {
      _homePageStyle = style;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('homePageStyle', style.index);
      notifyListeners();
    }
  }

  // =====================================================
  // 🛍️ Save Product Detail Page Style
  // =====================================================
  Future<void> setProductDetailStyle(ProductDetailStyle style) async {
    if (_productDetailStyle != style) {
      _productDetailStyle = style;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('productDetailStyle', style.index);
      notifyListeners();
    }
  }

  // =====================================================
  // 🌗 Save Theme Mode (Light, Dark, or System)
  // =====================================================
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('themeMode', mode.index);
      notifyListeners();
    }
  }

  // =====================================================
  // 🧹 Reset all settings (useful for debug or logout)
  // =====================================================
  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('homePageStyle');
    await prefs.remove('productDetailStyle');
    await prefs.remove('themeMode');

    _homePageStyle = HomePageStyle.grid;
    _productDetailStyle = ProductDetailStyle.standard;
    _themeMode = ThemeMode.system;

    notifyListeners();
  }
}
