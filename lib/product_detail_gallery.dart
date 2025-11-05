import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:html_unescape/html_unescape.dart';
import 'cart_provider.dart';
import 'celebration_theme_provider.dart'; // Add this import
import 'checkout_page.dart'; // ADD THIS

class ProductDetailGallery extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailGallery({super.key, required this.product});

  @override
  State<ProductDetailGallery> createState() => _ProductDetailGalleryState();
}

class _ProductDetailGalleryState extends State<ProductDetailGallery> {
  final HtmlUnescape _unescape = HtmlUnescape();
  int _currentImage = 0;
  int _quantity = 1;

  // ✅ Peek carousel controller state
  late final PageController _pageCtrl;
  double _page = 0.0;

  // Selected variation attributes (e.g., {"Color":"Red","Size":"M"})
  Map<String, String> _selectedAttributes = {};

  // 🎨 Glass Theme Colors - Now with theme fallbacks
  static const kPrimaryBlue = Color(0xFF004AAD);
  static const kAccentBlue = Color(0xFF0096FF);
  static const kLightBlue = Color(0xFFE3F2FD);
  static const kVeryLightBlue = Color(0xFFF5F8FF);

  final NumberFormat _fmt = NumberFormat("#,##0", "en_US");

  @override
  void initState() {
    super.initState();
    _initializeAttributes();

    // Peek carousel controller — neighbors "peek" in view
    _pageCtrl = PageController(viewportFraction: 0.82);
    _pageCtrl.addListener(() {
      final p = _pageCtrl.page ?? 0.0;
      if ((p - _page).abs() > 0.0001) {
        setState(() => _page = p);
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  // ----------------- Safe getters -----------------
  String get productDescription =>
      widget.product['description']?.toString().replaceAll(RegExp(r'<[^>]*>'), '').trim() ??
      'No description available';
  String get productSpecifications =>
      widget.product['short_description']?.toString().replaceAll(RegExp(r'<[^>]*>'), '').trim() ??
      'No specification provided';
  String get productPolicies =>
      "Store policies coming soon. Please contact us for any questions about returns, warranties, or shipping.";
  String get productInquiries =>
      "Have questions about this product? Contact our support team for detailed information and assistance.";
  String get productReviews =>
      "Customer reviews will be available soon. Check back later for authentic customer feedback and ratings.";

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

  List<Map<String, dynamic>> get _images {
    final imgs = widget.product['images'];
    if (imgs is List) {
      return imgs
          .map((e) => e is Map<String, dynamic> ? e : {'src': e.toString()})
          .toList();
    }
    return const [];
  }

  String get _firstImage {
    if (_images.isEmpty) return '';
    final m = _images.first;
    return m['src']?.toString() ??
        m['url']?.toString() ??
        m['image_url']?.toString() ??
        '';
  }

  List<dynamic> get _attributesList =>
      (widget.product['attributes'] as List?) ?? const [];

  bool get _hasVariations =>
      _attributesList.any((a) => a is Map && a['variation'] == true);

  bool get _canAddToCart {
    if (!_hasVariations) return true;
    for (final attr in _attributesList) {
      if (attr is Map && attr['variation'] == true) {
        final name = attr['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        if ((_selectedAttributes[name] ?? '').isEmpty) return false;
      }
    }
    return true;
  }

  void _initializeAttributes() {
    // Preselect the first option for each variation attribute for a smooth UX
    if (_attributesList.isEmpty) return;
    for (final attr in _attributesList) {
      if (attr is Map && (attr['variation'] == true)) {
        final name = attr['name']?.toString();
        final options =
            (attr['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (name != null && name.isNotEmpty && options.isNotEmpty) {
          _selectedAttributes.putIfAbsent(name, () => options.first);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final cart = Provider.of<CartProvider>(context, listen: false);

    // Add theme provider
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final badgeColor = currentTheme?.badgeColor ?? const Color(0xFFFF5722);

    final priceVal = _priceValue;
    final regVal = _regularValue;
    final bool onSale = regVal > priceVal && regVal > 0;
    final double rating =
        double.tryParse(product['average_rating']?.toString() ?? '0') ?? 0;
    final int ratingCount = product['rating_count'] ?? 0;

    final String productName = product['name'] ?? 'Product Name';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kLightBlue.withOpacity(0.3),
              kVeryLightBlue,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // 📱 App Bar
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 60,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: Container(
                    margin: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.85),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accentColor.withOpacity(0.2), // Use theme color
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withOpacity(0.1), // Use theme color
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: Icon(Icons.arrow_back_ios_new_rounded,
                                color: primaryColor, size: 20), // Use theme color
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 📸 IMAGE PEEK CAROUSEL (UPDATED)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 310,
                    child: _images.isEmpty
                        ? _emptyImageCard(primaryColor)
                        : Stack(
                            children: [
                              PageView.builder(
                                controller: _pageCtrl,
                                onPageChanged: (index) =>
                                    setState(() => _currentImage = index),
                                itemCount: _images.length,
                                itemBuilder: (context, index) {
                                  final src = _images[index]['src']?.toString() ??
                                      _images[index]['url']?.toString() ??
                                      _images[index]['image_url']?.toString() ??
                                      'https://via.placeholder.com/300x300?text=No+Image';

                                  // Distance of this page from the center
                                  final delta = (index - _page).abs();

                                  // Scale from 0.92 (far) → 1.0 (center)
                                  final scale = 1.0 - (0.08 * delta).clamp(0.0, 0.08);

                                  // Lift the center slightly
                                  final lift = lerpDouble(16, 0, (1 - delta).clamp(0.0, 1.0))!;

                                  return Transform.translate(
                                    offset: Offset(0, lift),
                                    child: Transform.scale(
                                      scale: scale,
                                      child: GestureDetector(
                                        onTap: () => _showZoom(src),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 10),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(24),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.08),
                                                blurRadius: 18,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(24),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                Image.network(
                                                  src,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, _, __) {
                                                    return Container(
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          colors: [
                                                            kLightBlue.withOpacity(0.3),
                                                            kVeryLightBlue,
                                                          ],
                                                        ),
                                                      ),
                                                      child: Icon(
                                                        Icons.image_outlined,
                                                        size: 80,
                                                        color: primaryColor.withOpacity(0.4), // Use theme color
                                                      ),
                                                    );
                                                  },
                                                ),
                                                // Glass fade at bottom for dots/legibility
                                                Positioned(
                                                  bottom: 0,
                                                  left: 0,
                                                  right: 0,
                                                  child: Container(
                                                    height: 56,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: Alignment.bottomCenter,
                                                        end: Alignment.topCenter,
                                                        colors: [
                                                          Colors.black.withOpacity(0.20),
                                                          Colors.transparent,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // Dots indicator (glassy pill)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 12,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.28),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.25),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(
                                        _images.length,
                                        (i) => AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 220),
                                          width: _currentImage == i ? 12 : 7,
                                          height: 7,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                                _currentImage == i ? 1 : 0.6),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                // 📋 Product Details
                SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.9),
                          const Color(0xFFF8FAFF).withOpacity(0.9),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🏷️ Title
                          Text(
                            productName,
                            style: GoogleFonts.montserrat(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: primaryColor, // Use theme color
                            ),
                          ),
                          const SizedBox(height: 8),

                          // ⭐ Rating
                          Row(
                            children: [
                              ...List.generate(
                                5,
                                (i) => Icon(
                                  i < rating.round()
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  color: i < rating.round()
                                      ? Colors.amber[600]
                                      : Colors.grey[300],
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ratingCount > 0
                                    ? "${rating.toStringAsFixed(1)} ($ratingCount)"
                                    : "No Reviews Yet",
                                style: GoogleFonts.roboto(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 💰 Price
                          Row(
                            children: [
                              if (onSale) ...[
                                _NairaText(
                                  _fmt.format(regVal),
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                  strike: true,
                                ),
                                const SizedBox(width: 8),
                              ],
                              _NairaText(
                                _fmt.format(priceVal),
                                fontSize: onSale ? 20 : 24,
                                color: primaryColor, // Use theme color
                                bold: true,
                              ),
                              if (onSale) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        badgeColor, // Use theme badge color
                                        badgeColor.withOpacity(0.8), // Use theme badge color
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "${(((regVal - priceVal) / (regVal == 0 ? 1 : regVal)) * 100).round()}% OFF",
                                    style: GoogleFonts.roboto(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 🎯 Variation Selection Chips
                          if (_hasVariations) ...[
                            Text(
                              "Select Options",
                              style: GoogleFonts.montserrat(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryColor, // Use theme color
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._attributesList
                                .where((attr) =>
                                    attr is Map && attr['variation'] == true)
                                .map<Widget>((attr) {
                              final name = attr['name']?.toString() ?? '';
                              final options = (attr['options'] as List?)
                                      ?.map((e) => e.toString())
                                      .toList() ??
                                  [];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.montserrat(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: primaryColor, // Use theme color
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: options.map<Widget>((option) {
                                        final isSelected =
                                            _selectedAttributes[name] == option;
                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedAttributes[name] =
                                                  option;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 8),
                                            decoration: BoxDecoration(
                                              gradient: isSelected
                                                  ? LinearGradient(colors: [
                                                      primaryColor, // Use theme color
                                                      accentColor // Use theme color
                                                    ])
                                                  : null,
                                              color: isSelected
                                                  ? null
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(25),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Colors.transparent
                                                    : primaryColor.withOpacity(0.5), // Use theme color
                                                width: 1.5,
                                              ),
                                              boxShadow: isSelected
                                                  ? [
                                                      BoxShadow(
                                                        color: primaryColor.withOpacity(0.3), // Use theme color
                                                        blurRadius: 8,
                                                        offset:
                                                            const Offset(0, 2),
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: Text(
                                              option,
                                              style: GoogleFonts.montserrat(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: isSelected
                                                    ? Colors.white
                                                    : primaryColor, // Use theme color
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 20),
                          ],

                          // 🔢 Quantity Selector with Glass Effect
                          Text(
                            "Quantity",
                            style: GoogleFonts.montserrat(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryColor, // Use theme color
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFF1F5FB).withOpacity(0.9),
                                      Colors.white.withOpacity(0.9),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                      color: primaryColor.withOpacity(0.3), // Use theme color
                                      width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        if (_quantity > 1) {
                                          setState(() => _quantity--);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(30),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              const Color(0xFFE3F2FD)
                                                  .withOpacity(0.9),
                                              const Color(0xFFF5F8FF)
                                                  .withOpacity(0.9),
                                            ],
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(6),
                                        child: Icon(Icons.remove_rounded,
                                            color: primaryColor), // Use theme color
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      width: 36,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$_quantity',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: primaryColor, // Use theme color
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    InkWell(
                                      onTap: () => setState(() => _quantity++),
                                      borderRadius: BorderRadius.circular(30),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              primaryColor, // Use theme color
                                              accentColor // Use theme color
                                            ],
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(6),
                                        child: const Icon(Icons.add_rounded,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // 📦 Product ID & SKU
                          if (product['id'] != null ||
                              (product['sku']?.toString().isNotEmpty ?? false))
                            Text(
                              "ID: ${product['id'] ?? '-'}  •  SKU: ${product['sku']?.toString().isNotEmpty == true ? product['sku'] : '-'}",
                              style: GoogleFonts.roboto(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          const SizedBox(height: 20),

                          // 🔥 Accordion Section with Glass Effect
                          _buildAccordionSection(primaryColor, accentColor),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // 🛒 Glass Floating Buttons
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accentColor.withOpacity(0.15), // Use theme color
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.12), // Use theme color
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Add to Cart
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: _canAddToCart
                                  ? LinearGradient(
                                      colors: [primaryColor, accentColor], // Use theme colors
                                    )
                                  : const LinearGradient(
                                      colors: [Colors.grey, Colors.grey],
                                    ),
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(12)),
                              boxShadow: _canAddToCart
                                  ? [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(0.4), // Use theme color
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.shopping_cart_outlined),
                              label: const Text("Add to Cart"),
                              onPressed: _canAddToCart
                                  ? () async {
                                      await Provider.of<CartProvider>(context,
                                              listen: false)
                                          .addToCartWithDetails(
                                        productId: product['id'],
                                        name: productName,
                                        price: _priceValue,
                                        image: _firstImage,
                                        quantity: _quantity,
                                        sku: product['sku']?.toString(),
                                        attributes:
                                            Map<String, String>.from(_selectedAttributes),
                                      );

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(Icons.check_circle,
                                                  color: Colors.white),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                    "$_quantity × $productName added to cart"),
                                              ),
                                            ],
                                          ),
                                          backgroundColor: Colors.green,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          margin: const EdgeInsets.all(16),
                                        ),
                                      );
                                    }
                                  : () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Please select all required options."),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

              // Buy Now - SIMPLE VERSION
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
                    label: const Text("Buy Now"),
                    onPressed: _canAddToCart
                        ? () async {
                            // 1. Add to cart first
                            await cart.addToCartWithDetails(
                              productId: product['id'],
                              name: productName,
                              price: _priceValue,
                              image: _firstImage,
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Placeholder card when there are no images
  Widget _emptyImageCard(Color primaryColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kLightBlue.withOpacity(0.3), kVeryLightBlue],
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.image_outlined,
            size: 80,
            color: primaryColor.withOpacity(0.4), // Use theme color
          ),
        ),
      ),
    );
  }

  // Lightbox zoom
  void _showZoom(String imageUrl) {
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
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.white.withOpacity(0.12)),
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

  // 🔥 Accordion Section with Glass Effect
  Widget _buildAccordionSection(Color primaryColor, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accentColor.withOpacity(0.2), // Use theme color
                width: 1.5,
              ),
            ),
            child: ExpansionPanelList.radio(
              animationDuration: const Duration(milliseconds: 300),
              elevation: 0,
              expandedHeaderPadding: EdgeInsets.zero,
              children: [
                _buildPanel(0, "Description", productDescription, Icons.description_outlined, primaryColor, accentColor),
                _buildPanel(1, "Specification", productSpecifications, Icons.inventory_2_outlined, primaryColor, accentColor),
                _buildPanel(2, "Customer Reviews", productReviews, Icons.star_outline_rounded, primaryColor, accentColor),
                _buildPanel(3, "Store Policies", productPolicies, Icons.policy_outlined, primaryColor, accentColor),
                _buildPanel(4, "Inquiries", productInquiries, Icons.question_answer_outlined, primaryColor, accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ExpansionPanelRadio _buildPanel(int value, String title, String content, IconData iconData, Color primaryColor, Color accentColor) {
    return ExpansionPanelRadio(
      value: value,
      backgroundColor: Colors.transparent,
      headerBuilder: (context, isExpanded) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withOpacity(0.12), // Use theme color
                      accentColor.withOpacity(0.08), // Use theme color
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconData,
                  color: primaryColor, // Use theme color
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        );
      },
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          _unescape.convert(content),
          style: GoogleFonts.roboto(
            fontSize: 14,
            color: Colors.grey[800],
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

// ₦ Formatter
class _NairaText extends StatelessWidget {
  final String text;
  final bool bold;
  final double fontSize;
  final Color? color;
  final bool strike;

  const _NairaText(
    this.text, {
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
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '\u20A6', style: style),
        TextSpan(text: text, style: style),
      ]),
    );
  }
}