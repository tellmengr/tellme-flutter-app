import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:provider/provider.dart';
import 'dart:ui'; // for BackdropFilter
import 'woocommerce_service.dart';
import 'product_page.dart';
import 'celebration_theme_provider.dart';

// 🎨 Glass Theme Colors (fallback when no celebration theme)
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);
const kLightBlue = Color(0xFFE3F2FD);
const kVeryLightBlue = Color(0xFFF5F8FF);

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final WooCommerceService _service = WooCommerceService();
  final HtmlUnescape _unescape = HtmlUnescape(); // ✅ for decoding &amp; etc.
  List<dynamic> _categories = [];
  final Map<int, List<dynamic>> _subCache = {};
  final Map<int, String> _subStatus = {}; // "loading" | "done" | "error"
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories({bool refresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }

    try {
      final cats = await _service.getParentCategories();
      final filtered = cats.where((c) => (c['count'] ?? 0) > 0).toList();
      if (mounted) {
        setState(() {
          _categories = filtered;
          _loading = false;
        });
      }
    } catch (e) {
      print('❌ Failed to load categories: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSubcategories(int parentId, {bool retry = false}) async {
    if (_subCache.containsKey(parentId) && !retry) return;

    setState(() => _subStatus[parentId] = "loading");
    try {
      final subs = await _service.getSubCategories(parentId);
      final filtered = subs.where((c) => (c['count'] ?? 0) > 0).toList();

      if (mounted) {
        setState(() {
          _subCache[parentId] = filtered;
          _subStatus[parentId] = "done";
        });
      }
    } catch (e) {
      print('❌ Error loading subcategories for $parentId: $e');
      if (mounted) setState(() => _subStatus[parentId] = "error");
    }
  }

  Widget _buildShimmerCard() {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kLightBlue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accentColor.withOpacity(0.15),
                width: 1.5,
              ),
            ),
            child: ListTile(
              leading: Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              title: Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  width: 120,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTile(dynamic parent) {
    final parentId = parent['id'];
    final subState = _subStatus[parentId] ?? "idle";
    final subcats = _subCache[parentId];

    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kLightBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accentColor.withOpacity(0.15),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                onExpansionChanged: (expanded) {
                  if (expanded) _loadSubcategories(parentId);
                },
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withOpacity(0.1),
                        accentColor.withOpacity(0.08),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: (parent['image'] != null &&
                          parent['image']['src'] != null &&
                          parent['image']['src'].toString().isNotEmpty)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            parent['image']['src'],
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, _, __) => Icon(
                              Icons.broken_image,
                              color: primaryColor.withOpacity(0.5),
                            ),
                          ),
                        )
                      : Icon(Icons.category, color: accentColor),
                ),
                title: Text(
                  _unescape.convert(parent['name'] ?? "No name"), // ✅ Decoded
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                    fontSize: 15,
                  ),
                ),
                trailing: Icon(
                  Icons.expand_more_rounded,
                  color: primaryColor,
                ),
                children: [
                  if (subState == "loading")
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: accentColor,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  else if (subState == "error")
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            "Failed to load subcategories",
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text("Retry"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(
                                color: accentColor.withOpacity(0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () =>
                                _loadSubcategories(parentId, retry: true),
                          )
                        ],
                      ),
                    )
                  else if (subcats == null || subcats.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        "No subcategories available",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.9,
                        ),
                        itemCount: subcats.length,
                        itemBuilder: (context, i) {
                          final sub = subcats[i];
                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductPage(
                                    categoryId: sub['id'].toString(),
                                    title: _unescape.convert(
                                        sub['name'] ?? ""), // ✅ Decoded
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.8),
                                        secondaryColor.withOpacity(0.3),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: accentColor.withOpacity(0.2),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (sub['image'] != null &&
                                          sub['image']['src'] != null &&
                                          sub['image']['src']
                                              .toString()
                                              .isNotEmpty)
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Image.network(
                                            sub['image']['src'],
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                primaryColor.withOpacity(0.15),
                                                accentColor.withOpacity(0.1),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            Icons.widgets,
                                            size: 28,
                                            color: accentColor,
                                          ),
                                        ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _unescape.convert(
                                            sub['name'] ?? ""), // ✅ Decoded
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF2A2A2A),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kLightBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];

    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: const Text(
          "Categories",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: primaryColor,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              secondaryColor.withOpacity(0.3),
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: () => _loadCategories(refresh: true),
          color: accentColor,
          child: _loading
              ? ListView.builder(
                  itemCount: 6,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (_, __) => _buildShimmerCard(),
                )
              : _hasError
                  ? Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            margin: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: accentColor.withOpacity(0.2),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        primaryColor.withOpacity(0.1),
                                        accentColor.withOpacity(0.08),
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.wifi_off_rounded,
                                    size: 48,
                                    color: primaryColor.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "Failed to load categories",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [primaryColor, accentColor],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _loadCategories,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      "Retry",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _categories.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (_, i) => _buildCategoryTile(_categories[i]),
                    ),
        ),
      ),
    );
  }
}