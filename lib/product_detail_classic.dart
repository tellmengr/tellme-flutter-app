import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:html_unescape/html_unescape.dart';
import 'cart_provider.dart';
import 'celebration_theme_provider.dart'; // Add this import
import 'checkout_page.dart'; // ADD THIS

class ProductDetailClassic extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailClassic({super.key, required this.product});

  @override
  State<ProductDetailClassic> createState() => _ProductDetailClassicState();
}

class _ProductDetailClassicState extends State<ProductDetailClassic> {
  int _quantity = 1;
  int _currentImage = 0;
  Map<String, String> _selectedAttributes = {};
  final _unescape = HtmlUnescape();

  // 🎨 Glass / Brand palette - Now with theme fallbacks
  static const Color kPrimaryBlue = Color(0xFF1565C0);
  static const Color kAccentBlue  = Color(0xFF2196F3);
  static const Color kInk         = Color(0xFF0D47A1);
  static const double kGlassBlur  = 12.0;

  final NumberFormat _fmt = NumberFormat("#,##0", "en_US");

  // ====== 360° turntable state ======
  bool _showSpin = false;        // toggle between pager and 360 view
  List<String> _spinFrames = []; // image sequence for 360
  int _spinIndex = 0;            // current frame index

  // ✅ OPTION A: lower threshold so a few gallery images become a 360 set
  static const int _minFramesForSpin = 4; // was 12

  @override
  void initState() {
    super.initState();
    _initializeAttributes();

    // 1) Try explicit meta/field
    _spinFrames = _extractSpinFrames(widget.product);

    // 2) Fallback: infer from gallery (sorted by position/filename)
    if (_spinFrames.isEmpty) {
      _spinFrames = _inferSpinFromGallery(widget.product);
    }

    // Debug: see how many frames we got
    // (remove when satisfied)
    // ignore: avoid_print
    print('🔁 spin frames found: ${_spinFrames.length}');

    // 3) With Option A, start 360 if we have at least 4 frames
    if (_spinFrames.length >= _minFramesForSpin) {
      _showSpin = true;
    }
  }

  // ---------- Data helpers ----------
  void _initializeAttributes() {
    final attrs = widget.product['attributes'];
    if (attrs is List) {
      for (final item in attrs) {
        if (item is Map &&
            item.containsKey('name') &&
            item.containsKey('options')) {
          final List<String> options = (item['options'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ?? <String>[];
          if (options.isNotEmpty) {
            _selectedAttributes[item['name'].toString()] = options.first;
          }
        }
      }
    }
  }

  // ---------- 360: extract from explicit meta or field ----------
  List<String> _extractSpinFrames(Map<String, dynamic> p) {
    // direct field
    final direct = p['spin_frames'];
    if (direct is List && direct.isNotEmpty) {
      return direct.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    // meta_data search (case-insensitive key)
    final meta = p['meta_data'];
    if (meta is List) {
      for (final m in meta) {
        if (m is Map) {
          final key = m['key']?.toString().trim().toLowerCase();
          if (key == 'spin_frames') {
            final v = m['value'];
            if (v is List && v.isNotEmpty) {
              return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
            } else if (v is String && v.trim().isNotEmpty) {
              return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            }
          }
        }
      }
    }
    return <String>[];
  }

  // ---------- 360: infer from gallery order or filenames ----------
  List<String> _inferSpinFromGallery(Map<String, dynamic> p) {
    final imgsRaw = p['images'];
    if (imgsRaw is! List || imgsRaw.isEmpty) return <String>[];

    // Normalize: [{src, name, position}] list
    final List<Map<String, dynamic>> images = imgsRaw.map((e) {
      if (e is Map<String, dynamic>) return e;
      return {'src': e.toString(), 'name': null, 'position': null};
    }).where((e) => (e['src']?.toString().isNotEmpty ?? false)).toList();

    if (images.isEmpty) return <String>[];

    // A) Prefer Woo "position" if present & unique
    final positions = images.map((m) => m['position']).whereType<int>().toList();
    final hasUniquePositions = positions.isNotEmpty && positions.toSet().length == images.length;
    if (hasUniquePositions) {
      images.sort((a, b) {
        final pa = (a['position'] is int) ? a['position'] as int : 1 << 30;
        final pb = (b['position'] is int) ? b['position'] as int : 1 << 30;
        return pa.compareTo(pb);
      });
    } else {
      // B) Fallback to filename numeric suffix sort (img_0001.jpg …)
      images.sort(_sortByNumericSuffix);
    }

    // ✅ With Option A, we allow as low as 4 frames
    if (images.length < _minFramesForSpin) return <String>[];

    return images
        .map((m) => m['src']?.toString() ?? '')
        .where((u) => u.isNotEmpty)
        .toList();
  }

  int _sortByNumericSuffix(Map<String, dynamic> a, Map<String, dynamic> b) {
    String nameA = (a['name']?.toString() ?? a['src']?.toString() ?? '').toLowerCase();
    String nameB = (b['name']?.toString() ?? b['src']?.toString() ?? '').toLowerCase();

    final reg = RegExp(r'(\d+)(?=\.[a-z]{3,4}$)');
    int numA = int.tryParse(reg.firstMatch(nameA)?.group(1) ?? '') ?? 1 << 30;
    int numB = int.tryParse(reg.firstMatch(nameB)?.group(1) ?? '') ?? 1 << 30;

    if (numA != numB) return numA.compareTo(numB);
    return nameA.compareTo(nameB);
  }

  bool get _canAddToCart {
    final attrs = widget.product['attributes'];
    if (attrs is! List || attrs.isEmpty) return true;
    for (final a in attrs) {
      final name = a['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      if ((_selectedAttributes[name] ?? '').isEmpty) return false;
    }
    return true;
  }

  double get _priceValue {
    final p = widget.product['price'];
    if (p is num) return p.toDouble();
    return double.tryParse(p?.toString() ?? '0') ?? 0.0;
  }

  double get _regularValue {
    final p = widget.product['regular_price'];
    if (p is num) return p.toDouble();
    return double.tryParse(p?.toString() ?? '0') ?? 0.0;
  }

  String? get _firstImage {
    final imgs = widget.product['images'];
    if (imgs is List && imgs.isNotEmpty) {
      final first = imgs.first;
      if (first is Map && first['src'] != null) return first['src'].toString();
      if (first is String) return first;
    }
    return null;
  }

  // Woo data getters (unchanged)
  String get productDescription =>
      widget.product['description'] ?? 'No description available';
  String get productSpecifications =>
      widget.product['short_description'] ?? 'No specification provided';
  String get productPolicies => "No store policies available";
  String get productInquiries => "No inquiries yet";
  String get productReviews => "No reviews yet";

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final cart = Provider.of<CartProvider>(context, listen: false);

    // Add theme provider
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final badgeColor = currentTheme?.badgeColor ?? Colors.redAccent;

    final priceVal = _priceValue;
    final regVal   = _regularValue;
    final bool onSale = regVal > priceVal && regVal > 0;

    final List<Map<String, dynamic>> images = (product['images'] is List)
        ? (product['images'] as List)
            .map((e) => e is Map<String, dynamic> ? e : {'src': e.toString()})
            .toList()
        : [];

    final double rating =
        double.tryParse(product['average_rating']?.toString() ?? '0') ?? 0;
    final int ratingCount = product['rating_count'] ?? 0;
    final String stockStatus = (product['stock_status'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: _glassAppBar(product['name'] ?? "Product", primaryColor),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // 🖼 Image Carousel / 360 Turntable
                  if (images.isNotEmpty) _glassImageCarousel(images, onSale, primaryColor, accentColor, badgeColor)
                  else _imagePlaceholder(),

                  // 🏷 Product Info Card
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title & rating row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  product['name'] ?? "",
                                  style: GoogleFonts.montserrat(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    color: kInk,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _ratingPill(rating, ratingCount, primaryColor),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // ID & SKU
                          if (product['id'] != null ||
                              (product['sku']?.toString().isNotEmpty ?? false))
                            Text(
                              "ID: ${product['id'] ?? '-'}  •  SKU: ${product['sku']?.toString().isNotEmpty == true ? product['sku'] : '-'}",
                              style: GoogleFonts.roboto(
                                fontSize: 12.5,
                                color: Colors.grey[700],
                              ),
                            ),

                          const SizedBox(height: 14),

                          // Price row
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  primaryColor.withOpacity(0.08),
                                  accentColor.withOpacity(0.06),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: primaryColor.withOpacity(0.18),
                                  width: 1),
                            ),
                            child: Row(
                              children: [
                                _NairaTight(
                                  amount: _fmt.format(priceVal),
                                  bold: true,
                                  fontSize: 28,
                                  color: onSale
                                      ? const Color(0xFFD32F2F)
                                      : primaryColor, // Use theme color
                                ),
                                const SizedBox(width: 10),
                                if (onSale)
                                  _NairaTight(
                                    amount: _fmt.format(regVal),
                                    bold: false,
                                    fontSize: 16,
                                    color: Colors.grey,
                                    strike: true,
                                  ),
                                const Spacer(),
                                // Stock badge
                                _stockBadge(stockStatus),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 🔢 Quantity
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _GlassCard(
                      child: Row(
                        children: [
                          Text(
                            "Quantity",
                            style: GoogleFonts.montserrat(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          _quantityButton(Icons.remove, () {
                            if (_quantity > 1) setState(() => _quantity--);
                          }, primaryColor),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_quantity',
                              style: GoogleFonts.roboto(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: primaryColor, // Use theme color
                              ),
                            ),
                          ),
                          _quantityButton(Icons.add, () => setState(() => _quantity++), primaryColor),
                        ],
                      ),
                    ),
                  ),

                  // 🎨 Variations / Attributes
                  if ((_selectedAttributes.isNotEmpty) ||
                      ((widget.product['attributes'] as List?)?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _GlassCard(
                        child: _buildProductVariations(primaryColor),
                      ),
                    ),

                  // 📋 Accordion
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: _GlassCard(
                      pad: EdgeInsets.zero,
                      child: _buildAccordionSection(primaryColor, accentColor),
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _frostedBottomBar(cart, widget.product, primaryColor, accentColor),
    );
  }

  // ---------- UI PARTS (Glass) ----------
  PreferredSizeWidget _glassAppBar(String title, Color primaryColor) {
    return AppBar(
      title: Text(
        title,
        style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w700, color: kInk),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      centerTitle: true,
      backgroundColor: Colors.white.withOpacity(0.85),
      elevation: 0,
      iconTheme: IconThemeData(color: primaryColor),
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
          child: Container(color: Colors.transparent),
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.favorite_border), onPressed: () {}),
      ],
    );
  }

  // ======= pager + optional 360° turntable (Option A active) =======
  Widget _glassImageCarousel(List<Map<String, dynamic>> images, bool onSale, Color primaryColor, Color accentColor, Color badgeColor) {
    final hasSpin = _spinFrames.length >= _minFramesForSpin;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Frosted background
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.9),
                      Colors.white.withOpacity(0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: kGlassBlur, sigmaY: kGlassBlur),
                child: const SizedBox.expand(),
              ),
            ),

            // --- Main content: 360 view OR pager ---
            SizedBox(
              height: 330,
              child: _showSpin && hasSpin
                  ? _Turntable360(
                      frames: _spinFrames,
                      enableZoom: true,
                      onIndexChanged: (i) => _spinIndex = i,
                    )
                  : PageView.builder(
                      itemCount: images.length,
                      onPageChanged: (i) => setState(() => _currentImage = i),
                      itemBuilder: (_, index) {
                        final img = images[index]['src']?.toString();
                        return GestureDetector(
                          onTap: () => _showZoom(img),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.all(18),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                img ?? "",
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey[100],
                                  child: Icon(Icons.broken_image,
                                      size: 100, color: Colors.grey[400]),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Dots (only when pager is visible)
            if (images.length > 1 && !(_showSpin && hasSpin))
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        images.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: _currentImage == i ? 12 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(
                                _currentImage == i ? 1 : 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Sale badge (if any)
            if (onSale)
              Positioned(
                top: 12,
                left: 12,
                child: _badge("SALE", primaryColor, accentColor),
              ),

            // 360 toggle (only if frames exist)
            if (hasSpin)
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => setState(() => _showSpin = !_showSpin),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: primaryColor.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.threesixty,
                            size: 18,
                            color: _showSpin ? primaryColor : Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          _showSpin ? "Images" : "360 View",
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: _showSpin ? primaryColor : Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 280,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20), color: Colors.grey[100]),
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported,
          size: 120, color: Colors.grey[400]),
    );
  }

  Widget _ratingPill(double rating, int ratingCount, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: primaryColor.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              rating > 0
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              size: 18,
              color: rating > 0 ? Colors.amber[600] : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(
            rating > 0 ? "${rating.toStringAsFixed(1)}" : "—",
            style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: Colors.black87),
          ),
          if (ratingCount > 0)
            Text(
              " ($ratingCount)",
              style: GoogleFonts.roboto(
                  fontSize: 12, color: Colors.grey[700]),
            ),
        ],
      ),
    );
  }

  Widget _stockBadge(String stockStatus) {
    final inStock = stockStatus.toLowerCase() == 'instock';
    final label =
        inStock ? "In stock" : (stockStatus.isEmpty ? "—" : stockStatus);
    final color =
        inStock ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: GoogleFonts.montserrat(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _badge(String text, Color primaryColor, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryColor, accentColor]), // Use theme colors
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Text(text,
          style: GoogleFonts.montserrat(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }

  // ---------- Variations / Chips ----------
  Widget _buildProductVariations(Color primaryColor) {
    final accentColors = [
      const Color(0xFF2563EB),
      const Color(0xFF059669),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
      const Color(0xFFEA580C),
      const Color(0xFF0891B2),
    ];

    // Collect attribute names from product, not just selected map
    final List<String> attrNames = [];
    final attrs = widget.product['attributes'];
    if (attrs is List) {
      for (final a in attrs) {
        final name = a['name']?.toString();
        if (name != null && name.isNotEmpty) attrNames.add(name);
      }
    }
    // If none, fallback to whatever is already selected
    if (attrNames.isEmpty) attrNames.addAll(_selectedAttributes.keys);

    if (attrNames.isEmpty) {
      return Text("No variations",
          style: GoogleFonts.roboto(color: Colors.grey[700]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Product Options",
          style: GoogleFonts.montserrat(
              fontSize: 18, fontWeight: FontWeight.w800, color: primaryColor), // Use theme color
        ),
        const SizedBox(height: 14),
        for (int i = 0; i < attrNames.length; i++) ...[
          Text(
            attrNames[i],
            style: GoogleFonts.montserrat(
                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _getAttributeOptions(attrNames[i])
                .map((option) => _variationChip(
                      attrNames[i],
                      option,
                      accentColors[i % accentColors.length],
                      option == _selectedAttributes[attrNames[i]],
                    ))
                .toList(),
          ),
          if (i != attrNames.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  List<String> _getAttributeOptions(String attributeName) {
    if (widget.product['attributes'] is List) {
      for (var item in widget.product['attributes']) {
        if (item is Map &&
            item['name'].toString() == attributeName &&
            item.containsKey('options')) {
          final options = item['options'] as List;
          return options.map((e) => e.toString()).toList();
        }
      }
    }
    return [];
  }

  Widget _variationChip(
      String attributeName, String value, Color color, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedAttributes[attributeName] = value),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withOpacity(0.18) : Colors.grey.withOpacity(0.1),
          border:
              Border.all(color: isSelected ? color : Colors.grey.withOpacity(0.3), width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: GoogleFonts.roboto(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.grey[800],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 16, color: color),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- Accordion ----------
  Widget _buildAccordionSection(Color primaryColor, Color accentColor) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.86),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: accentColor.withOpacity(0.2), width: 1.5), // Use theme color
            ),
            child: ExpansionPanelList.radio(
              elevation: 0,
              animationDuration: const Duration(milliseconds: 220),
              children: [
                _panel(0, "Description", productDescription, primaryColor, accentColor),
                _panel(1, "Specification", productSpecifications, primaryColor, accentColor),
                _panel(2, "Customer Reviews", productReviews, primaryColor, accentColor),
                _panel(3, "Store Policies", productPolicies, primaryColor, accentColor),
                _panel(4, "Inquiries", productInquiries, primaryColor, accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ExpansionPanelRadio _panel(int value, String title, String content, Color primaryColor, Color accentColor) {
    return ExpansionPanelRadio(
      value: value,
      backgroundColor: Colors.transparent,
      headerBuilder: (context, isExpanded) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withOpacity(0.14),
                      accentColor.withOpacity(0.1) // Use theme colors
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(_panelIcon(value),
                    color: primaryColor, size: 20), // Use theme color
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: primaryColor), // Use theme color
                ),
              ),
            ],
          ),
        );
      },
      body: Container(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Text(
          _unescape.convert(
              content.replaceAll(RegExp(r'<[^>]*>'), '').trim()),
          style: GoogleFonts.roboto(
              fontSize: 14, color: Colors.black87, height: 1.6),
        ),
      ),
    );
  }

  IconData _panelIcon(int v) {
    switch (v) {
      case 0:
        return Icons.description_outlined;
      case 1:
        return Icons.inventory_2_outlined;
      case 2:
        return Icons.star_outline_rounded;
      case 3:
        return Icons.policy_outlined;
      case 4:
        return Icons.question_answer_outlined;
      default:
        return Icons.info_outline;
    }
  }

 // ---------- Bottom bar (frosted) ----------
   Widget _frostedBottomBar(CartProvider cart, Map<String, dynamic> product, Color primaryColor, Color accentColor) {
     return ClipRect(
       child: BackdropFilter(
         filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
         child: Container(
           padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
           decoration: BoxDecoration(
             color: Colors.white.withOpacity(0.9),
             boxShadow: [
               BoxShadow(
                   color: Colors.black.withOpacity(0.08),
                   blurRadius: 20,
                   offset: const Offset(0, -6)),
             ],
           ),
           child: SafeArea(
             top: false,
             child: Row(
               children: [
                 // ADD TO CART
                 Expanded(
                   child: OutlinedButton.icon(
                     icon: const Icon(Icons.shopping_cart_outlined),
                     label: Text("Add to Cart",
                         style: GoogleFonts.montserrat(
                             fontWeight: FontWeight.w700)),
                     onPressed: _canAddToCart
                         ? () async {
                             await cart.addToCartWithDetails(
                               productId: product['id'],
                               name: (product['name'] ?? 'Product').toString(),
                               price: _priceValue,
                               image: _firstImage ?? '',
                               quantity: _quantity,
                               sku: product['sku']?.toString(),
                               attributes: Map<String, String>.from(
                                   _selectedAttributes),
                             );
                             ScaffoldMessenger.of(context).showSnackBar(
                               SnackBar(
                                 content: Text(
                                   "$_quantity × ${product['name']} added to cart",
                                   style:
                                       GoogleFonts.roboto(color: Colors.white),
                                 ),
                                 backgroundColor: primaryColor, // Use theme color
                                 duration: const Duration(seconds: 1),
                                 behavior: SnackBarBehavior.floating,
                                 margin: const EdgeInsets.all(16),
                                 shape: RoundedRectangleBorder(
                                     borderRadius: BorderRadius.circular(12)),
                               ),
                             );
                           }
                         : () {
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(
                                 content:
                                     Text("Please select all options."),
                                 backgroundColor: Colors.redAccent,
                               ),
                             );
                           },
                     style: OutlinedButton.styleFrom(
                       foregroundColor: primaryColor, // Use theme color
                       side: BorderSide(color: primaryColor, width: 1.5), // Use theme color
                       padding: const EdgeInsets.symmetric(vertical: 14),
                       shape: RoundedRectangleBorder(
                           borderRadius: BorderRadius.circular(12)),
                     ),
                   ),
                 ),
                 const SizedBox(width: 12),
                 // Buy Now - CORRECTED VERSION
                 Expanded(
                   child: Container(
                     decoration: BoxDecoration(
                       gradient: _canAddToCart
                           ? LinearGradient(
                               colors: [accentColor, accentColor.withOpacity(0.8)],
                             )
                           : const LinearGradient(
                               colors: [Colors.grey, Colors.grey],
                             ),
                       borderRadius: const BorderRadius.all(Radius.circular(12)),
                       boxShadow: _canAddToCart
                           ? [
                               BoxShadow(
                                 color: accentColor.withOpacity(0.4),
                                 blurRadius: 12,
                                 offset: const Offset(0, 4),
                               ),
                             ]
                           : null,
                     ),
                     child: ElevatedButton.icon(
                       icon: const Icon(Icons.flash_on),
                       label: Text("Buy Now",
                           style: GoogleFonts.montserrat(fontWeight: FontWeight.w700)),
                       onPressed: _canAddToCart
                           ? () async {
                               // 1. Add to cart first
                               await cart.addToCartWithDetails(
                                 productId: product['id'],
                                 name: (product['name'] ?? 'Product').toString(), // FIXED: Use product parameter
                                 price: _priceValue,
                                 image: _firstImage ?? '', // FIXED: Provide default value
                                 quantity: _quantity,
                                 sku: product['sku']?.toString(),
                                 attributes: Map<String, String>.from(_selectedAttributes),
                               );

                               // 2. Get cart totals
                               double totalPrice = cart.getTotalPrice();
                               double shipping = 2500.0;
                               double total = totalPrice + shipping;

                               // 3. Navigate directly to checkout
                               Navigator.push(
                                 context,
                                 MaterialPageRoute(
                                   builder: (context) => CheckoutPage(
                                     cartItems: cart.cartItems,
                                     subtotal: totalPrice,
                                     shipping: shipping,
                                     total: total,
                                   ),
                                 ),
                               );
                             }
                           : null,
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.transparent,
                         shadowColor: Colors.transparent,
                         foregroundColor: Colors.white,
                         disabledBackgroundColor: Colors.grey.shade400,
                         padding: const EdgeInsets.symmetric(vertical: 14),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
   }
  // ---------- Helpers ----------
  Widget _quantityButton(IconData icon, VoidCallback onPressed, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08), // Use theme color
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.25), width: 1), // Use theme color
      ),
      child: IconButton(
        icon: Icon(icon, color: primaryColor, size: 20), // Use theme color
        splashRadius: 22,
        onPressed: onPressed,
      ),
    );
  }

  void _showZoom(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => Dialog(
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: kGlassBlur, sigmaY: kGlassBlur),
                  child:
                      Container(color: Colors.white.withOpacity(0.12)),
                ),
              ),
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[100],
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image,
                        size: 100, color: Colors.grey[400]),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.white.withOpacity(0.9),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Reusable glass card ----------
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? pad;
  const _GlassCard({required this.child, this.pad});

  @override
  Widget build(BuildContext context) {
    // Get theme colors
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF2196F3);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: pad ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.86),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: accentColor.withOpacity(0.18), width: 1.5), // Use theme color
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 22,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ₦ display widget
class _NairaTight extends StatelessWidget {
  final String amount;
  final bool bold;
  final double fontSize;
  final Color? color;
  final bool strike;

  const _NairaTight({
    required this.amount,
    this.bold = true,
    this.fontSize = 16,
    this.color,
    this.strike = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: fontSize,
      color: color ?? Colors.black,
      decoration: strike ? TextDecoration.lineThrough : TextDecoration.none,
    );

    return Text.rich(TextSpan(children: [
      TextSpan(text: '\u20A6', style: style),
      TextSpan(text: amount, style: style),
    ]));
  }
}

// ===== 360° turntable widget =====
class _Turntable360 extends StatefulWidget {
  final List<String> frames;
  final bool enableZoom;
  final ValueChanged<int>? onIndexChanged;

  const _Turntable360({
    Key? key,
    required this.frames,
    this.enableZoom = true,
    this.onIndexChanged,
  }) : super(key: key);

  @override
  State<_Turntable360> createState() => _Turntable360State();
}

class _Turntable360State extends State<_Turntable360> {
  int _index = 0;
  double _accumulatedDx = 0;
  bool _preloaded = false;

  // sensitivity: pixels per one frame change
  static const double _pxPerFrame = 14.0;

  @override
  void initState() {
    super.initState();
    _precacheAll();
  }

  Future<void> _precacheAll() async {
    for (final url in widget.frames) {
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {}
    }
    if (mounted) setState(() => _preloaded = true);
  }

  void _bump(int delta) {
    if (widget.frames.isEmpty) return;
    final len = widget.frames.length;
    _index = (_index + delta) % len;
    if (_index < 0) _index += len;
    widget.onIndexChanged?.call(_index);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.frames.isEmpty ? null : widget.frames[_index];

    Widget viewer = image == null
        ? const Center(child: Icon(Icons.image_not_supported_outlined))
        : Image.network(
            image,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
            ),
          );

    if (widget.enableZoom) {
      viewer = InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: viewer,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        _accumulatedDx += d.delta.dx;
        while (_accumulatedDx <= -_pxPerFrame) {
          _accumulatedDx += _pxPerFrame;
          _bump(1); // drag left -> next frame
        }
        while (_accumulatedDx >= _pxPerFrame) {
          _accumulatedDx -= _pxPerFrame;
          _bump(-1); // drag right -> previous frame
        }
      },
      onHorizontalDragEnd: (_) => _accumulatedDx = 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: viewer,
            ),
          ),
          if (!_preloaded)
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          // hint
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swipe, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Drag to rotate', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}