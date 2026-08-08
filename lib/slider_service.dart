import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppSlide {
  static const String _siteBaseUrl = 'https://tellme.ng';

  final String title;
  final String subtitle;
  final String buttonText;
  final String buttonUrl; // deep link or web URL
  final String gradientStart; // hex like #1565C0
  final String gradientEnd; // hex like #00BFFF
  final String image; // full URL

  // NEW display flags
  final bool imageOnly; // render full-bleed image (no gradient/text/button)
  final bool hideTitle; // hide title text even in gradient layout
  final bool hideButton; // hide CTA button even in gradient layout

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

  static String _firstString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }

    return '';
  }

  static String _absoluteUrl(dynamic value) {
    final text = _s(value).trim();
    if (text.isEmpty) return '';
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) return text;
    if (text.startsWith('//')) return 'https:$text';
    if (text.startsWith('/')) return '$_siteBaseUrl$text';
    return '$_siteBaseUrl/$text';
  }

  static bool looksLikeSlide(Map<String, dynamic> source) {
    return _firstString(source, [
      'image',
      'imageSrc',
      'imageUrl',
      'desktopImage',
      'desktopImageUrl',
      'mobileImage',
      'mobileImageUrl',
      'src',
    ]).isNotEmpty;
  }

  factory AppSlide.fromJson(Map<String, dynamic> j) {
    final title = _firstString(j, ['title', 'heading', 'headline', 'name']);
    final subtitle = _firstString(j, [
      'subtitle',
      'subTitle',
      'description',
      'caption',
      'text',
    ]);
    final buttonText = _firstString(j, [
      'button_text',
      'buttonText',
      'cta',
      'ctaText',
      'cta_label',
      'label',
    ]);
    final buttonUrl = _absoluteUrl(
      _firstString(j, [
        'button_url',
        'buttonUrl',
        'ctaUrl',
        'cta_url',
        'link',
        'linkUrl',
        'href',
        'url',
      ]),
    );
    final image = _absoluteUrl(
      _firstString(j, [
        'image',
        'imageSrc',
        'imageUrl',
        'desktopImage',
        'desktopImageUrl',
        'mobileImage',
        'mobileImageUrl',
        'src',
        'url',
      ]),
    );

    final gradientStart =
        _firstString(j, ['gradient_start', 'gradientStart', 'fromColor']);
    final gradientEnd =
        _firstString(j, ['gradient_end', 'gradientEnd', 'toColor']);

    return AppSlide(
      title: title,
      subtitle: subtitle,
      buttonText: buttonText.isEmpty ? 'Learn More' : buttonText,
      buttonUrl: buttonUrl,
      gradientStart: gradientStart.isEmpty ? '#1565C0' : gradientStart,
      gradientEnd: gradientEnd.isEmpty ? '#00BFFF' : gradientEnd,
      image: image,
      imageOnly: _b(j['image_only'] ?? j['imageOnly']),
      hideTitle: _b(j['hide_title'] ?? j['hideTitle']),
      hideButton: _b(j['hide_button'] ?? j['hideButton']),
    );
  }

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
  static const _appearanceEndpoint = 'https://tellme.ng/api/v1/appearance';
  static const _legacyEndpoint = 'https://tellme.ng/wp-json/tellme/v1/sliders';
  static const _cacheKey = 'app_slides_cache_v3';
  static const _legacyCacheKey = 'app_slides_cache_v2';

  Future<List<AppSlide>> fetchSlides() async {
    final websiteSlides = await _fetchFromEndpoint(_appearanceEndpoint);
    if (websiteSlides.isNotEmpty) return websiteSlides;

    final legacySlides = await _fetchFromEndpoint(_legacyEndpoint);
    if (legacySlides.isNotEmpty) return legacySlides;

    return _cachedSlides();
  }

  Future<List<AppSlide>> _fetchFromEndpoint(String endpoint) async {
    try {
      final r = await http.get(
        Uri.parse(endpoint),
        headers: const {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 10));

      if (r.statusCode == 200) {
        final decoded = json.decode(r.body);
        final rawList = _extractSlides(decoded);

        final slides = rawList
            .whereType<Map>()
            .map<Map<String, dynamic>>((m) => m.cast<String, dynamic>())
            .map<AppSlide>(AppSlide.fromJson)
            .toList();

        if (slides.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, json.encode(rawList));
        }

        return slides;
      }
    } catch (_) {
      // Ignore and try the next source/cache.
    }

    return [];
  }

  List _extractSlides(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is! Map) return const [];

    final map = decoded.cast<String, dynamic>();

    if (AppSlide.looksLikeSlide(map)) return [map];

    for (final key in [
      'slides',
      'heroSlides',
      'banners',
      'items',
      'data',
    ]) {
      final value = map[key];
      if (value is List) return value;
    }

    for (final key in [
      'appearance',
      'storefrontAppearance',
      'home',
      'homepage',
      'hero',
      'heroPromo',
      'slider',
      'carousel',
    ]) {
      final value = map[key];
      final nested = _extractSlides(value);
      if (nested.isNotEmpty) return nested;
    }

    return const [];
  }

  Future<List<AppSlide>> _cachedSlides() async {
    final prefs = await SharedPreferences.getInstance();
    for (final cacheKey in [_cacheKey, _legacyCacheKey]) {
      final cached = prefs.getString(cacheKey);
      if (cached == null) continue;

      try {
        final List rawList = json.decode(cached) as List;
        final slides = rawList
            .whereType<Map>()
            .map<Map<String, dynamic>>((m) => m.cast<String, dynamic>())
            .map<AppSlide>(AppSlide.fromJson)
            .toList();
        if (slides.isNotEmpty) return slides;
      } catch (_) {
        await prefs.remove(cacheKey);
      }
    }

    return [];
  }
}
