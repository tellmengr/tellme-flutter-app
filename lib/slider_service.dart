import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppSlide {
  final String title;
  final String subtitle;
  final String buttonText;
  final String buttonUrl;     // deep link or web URL
  final String gradientStart; // hex like #1565C0
  final String gradientEnd;   // hex like #00BFFF
  final String image;         // full URL

  // NEW display flags
  final bool imageOnly;       // render full-bleed image (no gradient/text/button)
  final bool hideTitle;       // hide title text even in gradient layout
  final bool hideButton;      // hide CTA button even in gradient layout

  AppSlide({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.buttonUrl,
    required this.gradientStart,
    required this.gradientEnd,
    required this.image,
    this.imageOnly = false,
    this.hideTitle = false,
    this.hideButton = false,
  });

  static String _s(dynamic v, [String fallback = '']) =>
      (v == null) ? fallback : v.toString();

  static bool _b(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }
    return false;
  }

  factory AppSlide.fromJson(Map<String, dynamic> j) => AppSlide(
        title: _s(j['title']),
        subtitle: _s(j['subtitle']),
        buttonText: _s(j['button_text'], 'Learn More'),
        buttonUrl: _s(j['button_url']),
        gradientStart: _s(j['gradient_start'], '#1565C0').isEmpty
            ? '#1565C0'
            : _s(j['gradient_start']),
        gradientEnd: _s(j['gradient_end'], '#00BFFF').isEmpty
            ? '#00BFFF'
            : _s(j['gradient_end']),
        image: _s(j['image']),
        imageOnly: _b(j['image_only']),
        hideTitle: _b(j['hide_title']),
        hideButton: _b(j['hide_button']),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'button_text': buttonText,
        'button_url': buttonUrl,
        'gradient_start': gradientStart,
        'gradient_end': gradientEnd,
        'image': image,
        'image_only': imageOnly,
        'hide_title': hideTitle,
        'hide_button': hideButton,
      };
}

class SliderService {
  // Update this to your domain if different:
  static const _endpoint = 'https://tellme.ng/wp-json/tellme/v1/sliders';
  static const _cacheKey = 'app_slides_cache_v2'; // bumped for new fields

  Future<List<AppSlide>> fetchSlides() async {
    try {
      final r = await http.get(
        Uri.parse(_endpoint),
        headers: const {
          'Accept': 'application/json',
          // help avoid stale responses while editing in WP
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 10));

      if (r.statusCode == 200) {
        final decoded = json.decode(r.body);
        final List rawList =
            (decoded is Map && decoded['slides'] is List) ? decoded['slides'] : const [];

        final slides = rawList
            .whereType<Map>()
            .map<Map<String, dynamic>>((m) => m.cast<String, dynamic>())
            .map<AppSlide>(AppSlide.fromJson)
            .toList();

        // cache the raw list
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, json.encode(rawList));

        return slides;
      }
    } catch (_) {
      // ignore (we'll use cache)
    }

    // Fallback to cache
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      final List rawList = json.decode(cached) as List;
      return rawList
          .whereType<Map>()
          .map<Map<String, dynamic>>((m) => m.cast<String, dynamic>())
          .map<AppSlide>(AppSlide.fromJson)
          .toList();
    }

    return [];
  }
}
