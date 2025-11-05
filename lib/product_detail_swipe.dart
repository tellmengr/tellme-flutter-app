import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'cart_provider.dart';
import 'checkout_page.dart';
import 'celebration_theme_provider.dart'; // ADD THIS IMPORT

class ProductDetailSwipe extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailSwipe({super.key, required this.product});

  @override
  State<ProductDetailSwipe> createState() => _ProductDetailSwipeState();
}

class _ProductDetailSwipeState extends State<ProductDetailSwipe>
    with TickerProviderStateMixin {
  final _priceFmt = NumberFormat("#,##0", "en_US");

  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  int _quantity = 1;
  bool _isImageLoading = true;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  // 🎨 Glass / Brand palette (fallback colors)
  static const Color kPrimaryBlue = Color(0xFF1565C0);
  static const Color kAccentBlue = Color(0xFF2196F3);
  static const Color kInk = Color(0xFF0D47A1);
  static const double kGlassBlur = 12.0;

  // ✅ Variations
  Map<String, String> _selectedAttributes = {};

  // ---------- Getters / helpers ----------
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
    return (m['src'] ?? m['url'] ?? m['image_url'] ?? '').toString();
  }

  List<dynamic> get _attributesList =>
      (widget.product['attributes'] as List?) ?? const [];

  bool get _hasVariations =>
      _attributesList.any((a) => a is Map && a['variation'] == true);

  bool get _canAddToCart {
    if (!_hasVariations) return true;
    for (final a in _attributesList) {
      if (a is Map && a['variation'] == true) {
        final name = a['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        if ((_selectedAttributes[name] ?? '').isEmpty) return false;
      }
    }
    return true;
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '0') ?? 0.0;
  }

  // ---------- Lifecycle ----------
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();

    _initializeAttributes();
  }

  void _initializeAttributes() {
    // Preselect first option for each VARIATION attribute
    for (final item in _attributesList) {
      if (item is Map && item['variation'] == true) {
        final name = item['name']?.toString();
        final options =
            (item['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (name != null && name.isNotEmpty && options.isNotEmpty) {
          _selectedAttributes.putIfAbsent(name, () => options.first);
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ---------- Image nav ----------
  void _goToNextImage() {
    if (_currentImageIndex < _images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPreviousImage() {
    if (_currentImageIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _jumpToImage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    // 🎨 GET THEME COLORS FROM CELEBRATION THEME PROVIDER
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    // Use primary color for text since textColor property doesn't exist
    final inkColor = primaryColor; // Use primary color for text

    final List<Map<String, dynamic>> images = _images;
    final bool hasMultipleImages = images.length > 1;

    final double price = _asDouble(p['price']);
    final double regular = _asDouble(p['regular_price']);
    final bool onSale = regular > 0 && regular > price;

    final String stockStatus = (p['stock_status'] ?? '').toString();
    final bool inStock = stockStatus.toLowerCase() == 'instock';

    final double rating =
        double.tryParse((p['average_rating'] ?? '0').toString()) ?? 0;
    final int ratingCount = p['rating_count'] is int
        ? p['rating_count']
        : int.tryParse("${p['rating_count'] ?? 0}") ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: _glassAppBar(p['name']?.toString() ?? 'Product', primaryColor, accentColor, inkColor),
      body: Column(
        children: [
          // ✅ Swipe Image Gallery (glassy)
          Container(
            height: 350,
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
                      filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentImageIndex = index;
                              _isImageLoading = true;
                            });
                            _animationController
                              ..reset()
                              ..forward();
                          },
                          physics: const BouncingScrollPhysics(),
                          itemCount: images.isNotEmpty ? images.length : 1,
                          itemBuilder: (context, index) {
                            if (images.isNotEmpty) {
                              final String src = (images[index]['src'] ??
                                      images[index]['url'] ??
                                      images[index]['image_url'] ??
                                      '')
                                  .toString();
                              return GestureDetector(
                                onTap: () => _openLightbox(images, index),
                                child: Container(
                                  margin: const EdgeInsets.all(16),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      children: [
                                        if (_isImageLoading)
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Colors.grey[300]!,
                                                  Colors.grey[100]!,
                                                  Colors.grey[300]!,
                                                ],
                                              ),
                                            ),
                                            child: const Center(
                                              child: CircularProgressIndicator(),
                                            ),
                                          ),
                                        Image.network(
                                          src,
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                          height: double.infinity,
                                          loadingBuilder: (context, child, progress) {
                                            if (progress == null) {
                                              _isImageLoading = false;
                                              return child;
                                            }
                                            return Center(
                                              child: CircularProgressIndicator(
                                                value: progress.expectedTotalBytes != null
                                                    ? progress.cumulativeBytesLoaded /
                                                        progress.expectedTotalBytes!
                                                    : null,
                                              ),
                                            );
                                          },
                                          errorBuilder: (_, __, ___) => const Center(
                                            child: Icon(Icons.broken_image, color: Colors.grey, size: 80),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              return const Center(
                                child: Icon(Icons.image_not_supported, size: 120, color: Colors.grey),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),

                  // Arrows
                  if (hasMultipleImages) ...[
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _goToPreviousImage,
                          child: _arrowButton(Icons.chevron_left,
                              enabled: _currentImageIndex > 0),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _goToNextImage,
                          child: _arrowButton(Icons.chevron_right,
                              enabled: _currentImageIndex < images.length - 1),
                        ),
                      ),
                    ),
                  ],

                  // Dots
                  if (hasMultipleImages)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: images.asMap().entries.map((entry) {
                          final isActive = _currentImageIndex == entry.key;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            width: isActive ? 12 : 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.white.withOpacity(isActive ? 1 : 0.6),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // Sale badge
                  if (onSale)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _badge("SALE", primaryColor, accentColor),
                    ),
                ],
              ),
            ),
          ),

          // ✅ Product Info + Variants + Accordion
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GlassCard(
                    primaryColor: primaryColor,
                    accentColor: accentColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + stock row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                p['name']?.toString() ?? "No name",
                                style: GoogleFonts.montserrat(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                  color: inkColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _stockBadge(stockStatus),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // ⭐ Rating
                        if (ratingCount > 0 || rating > 0)
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

                        // Price row
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primaryColor.withOpacity(0.08),
                                accentColor.withOpacity(0.06),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryColor.withOpacity(0.18), width: 1),
                          ),
                          child: Row(
                            children: [
                              _NairaTight(
                                amount: _priceFmt.format(price),
                                bold: true,
                                size: 28,
                                color: onSale ? const Color(0xFFD32F2F) : primaryColor,
                              ),
                              const SizedBox(width: 10),
                              if (onSale)
                                _NairaTight(
                                  amount: _priceFmt.format(regular),
                                  bold: false,
                                  size: 16,
                                  color: Colors.grey,
                                  strike: true,
                                ),
                              const Spacer(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // 📦 Product ID & SKU
                        if (p['id'] != null ||
                            (p['sku']?.toString().isNotEmpty ?? false))
                          Text(
                            "ID: ${p['id'] ?? '-'}  •  SKU: ${p['sku']?.toString().isNotEmpty == true ? p['sku'] : '-'}",
                            style: GoogleFonts.roboto(fontSize: 12.5, color: Colors.black54),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Quantity
                  _GlassCard(
                    primaryColor: primaryColor,
                    accentColor: accentColor,
                    child: Row(
                      children: [
                        Text(
                          "Quantity",
                          style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        _qtyButton(Icons.remove, primaryColor, () {
                          if (_quantity > 1) setState(() => _quantity--);
                        }),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_quantity',
                            style: GoogleFonts.roboto(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        _qtyButton(Icons.add, primaryColor, () => setState(() => _quantity++)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Variations / Attributes (only show for variation attributes)
                  if (_hasVariations)
                    _GlassCard(
                      primaryColor: primaryColor,
                      accentColor: accentColor,
                      child: _buildProductVariations(primaryColor),
                    ),

                  const SizedBox(height: 14),

                  // Accordion
                  _GlassCard(
                    primaryColor: primaryColor,
                    accentColor: accentColor,
                    pad: EdgeInsets.zero,
                    child: _buildAccordionSection(primaryColor, accentColor),
                  ),

                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
      ),

      // ✅ Frosted Sticky Bottom Bar (now uses addToCartWithDetails + validation)
      bottomNavigationBar: _frostedBottomBar(p, inStock, primaryColor, accentColor),
    );
  }

  // ---------- Glass AppBar ----------
  PreferredSizeWidget _glassAppBar(String title, Color primaryColor, Color accentColor, Color inkColor) {
    return AppBar(
      title: Text(
        title,
        style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, color: inkColor),
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
      actions: const [SizedBox(width: 4)],
    );
  }

  // ---------- Variations UI ----------
  Widget _buildProductVariations(Color primaryColor) {
    final accentColors = [
      const Color(0xFF2563EB),
      const Color(0xFF059669),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
      const Color(0xFFEA580C),
      const Color(0xFF0891B2),
    ];

    // Show only variation attributes
    final varAttrs = _attributesList
        .where((a) => a is Map && a['variation'] == true)
        .cast<Map>();

    final keys = varAttrs.map((e) => e['name']?.toString() ?? '').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Product Options",
          style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w800, color: primaryColor),
        ),
        const SizedBox(height: 14),
        for (int i = 0; i < keys.length; i++) ...[
          Text(
            keys[i],
            style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _getAttributeOptions(keys[i])
                .map((option) => _variationChip(
                      keys[i],
                      option,
                      accentColors[i % accentColors.length],
                      option == _selectedAttributes[keys[i]],
                    ))
                .toList(),
          ),
          if (i != keys.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  List<String> _getAttributeOptions(String attributeName) {
    for (final item in _attributesList) {
      if (item is Map &&
          item['name'].toString() == attributeName &&
          item.containsKey('options')) {
        final options = (item['options'] as List?) ?? [];
        return options.map((e) => e.toString()).toList();
      }
    }
    return [];
  }

  Widget _variationChip(String attributeName, String value, Color color, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedAttributes[attributeName] = value),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.18) : Colors.grey.withOpacity(0.1),
          border: Border.all(color: isSelected ? color : Colors.grey.withOpacity(0.3), width: 1.5),
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
    final String description = (widget.product['description'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
    final String shortDesc = (widget.product['short_description'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();

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
              border: Border.all(color: accentColor.withOpacity(0.2), width: 1.5),
            ),
            child: ExpansionPanelList.radio(
              elevation: 0,
              animationDuration: const Duration(milliseconds: 220),
              children: [
                _panel(0, "Description", description.isEmpty ? "No description available" : description, primaryColor, accentColor),
                _panel(1, "Specification", shortDesc.isEmpty ? "No specification provided" : shortDesc, primaryColor, accentColor),
                _panel(2, "Customer Reviews", "No reviews yet", primaryColor, accentColor),
                _panel(3, "Store Policies", "No store policies available", primaryColor, accentColor),
                _panel(4, "Inquiries", "No inquiries yet", primaryColor, accentColor),
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
                    colors: [primaryColor.withOpacity(0.14), accentColor.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(_panelIcon(value), color: primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 16, color: primaryColor),
                ),
              ),
            ],
          ),
        );
      },
      body: Container(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Text(
          content,
          style: GoogleFonts.roboto(fontSize: 14, color: Colors.black87, height: 1.6),
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

  // ---------- Bottom Bar ----------
    Widget _frostedBottomBar(Map<String, dynamic> product, bool inStock, Color primaryColor, Color accentColor) {
      final canPress = inStock && _canAddToCart;
      final cart = Provider.of<CartProvider>(context, listen: false);

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
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canPress
                          ? () async {
                              await cart.addToCartWithDetails(
                                productId: product['id'],
                                name: product['name']?.toString() ?? '',
                                price: _asDouble(product['price']),
                                image: _firstImage,
                                quantity: _quantity,
                                sku: product['sku']?.toString(),
                                attributes: Map<String, String>.from(_selectedAttributes),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("$_quantity × ${product['name'] ?? 'Product'} added to cart"),
                                  backgroundColor: primaryColor,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          : () {
                              if (!inStock) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("This item is out of stock."),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Please select all required options."),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: Text("Add to Cart",
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: BorderSide(color: primaryColor, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Buy Now button - FIXED VERSION
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: canPress
                            ? LinearGradient(
                                colors: [primaryColor, accentColor],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              )
                            : const LinearGradient(
                                colors: [Colors.grey, Colors.grey],
                              ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: canPress
                            ? [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.32),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ]
                            : null,
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.flash_on),
                        label: Text("Buy Now",
                            style: GoogleFonts.montserrat(fontWeight: FontWeight.w700)),
                        onPressed: canPress
                            ? () async {
                                // 1. Add to cart first
                                await cart.addToCartWithDetails(
                                  productId: product['id'],
                                  name: product['name']?.toString() ?? 'Product',
                                  price: _asDouble(product['price']),
                                  image: _firstImage ?? '',
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

  // ---------- Small UI helpers ----------
  Widget _arrowButton(IconData icon, {bool enabled = true}) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _badge(String text, Color primaryColor, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryColor, accentColor]),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      child: Text(
        text,
        style: GoogleFonts.montserrat(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _stockBadge(String stockStatus) {
    final inStock = stockStatus.toLowerCase() == 'instock';
    final label = inStock ? "In stock" : (stockStatus.isEmpty ? "—" : stockStatus);
    final color = inStock ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _qtyButton(IconData icon, Color primaryColor, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.25), width: 1),
      ),
      child: IconButton(
        icon: Icon(icon, color: primaryColor, size: 20),
        splashRadius: 22,
        onPressed: onPressed,
      ),
    );
  }

  // 🔎 NEW: Fullscreen lightbox with pinch-to-zoom, pan & swipe
  void _openLightbox(List<Map<String, dynamic>> images, int initialIndex) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _Lightbox(
          images: images,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }
}

// ---------- Reusable glass card ----------
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? pad;
  final Color primaryColor;
  final Color accentColor;

  const _GlassCard({
    required this.child,
    this.pad,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
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
            border: Border.all(color: accentColor.withOpacity(0.18), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 22, offset: const Offset(0, 8)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Tight Naira renderer
class _NairaTight extends StatelessWidget {
  final String amount;
  final bool bold;
  final double size;
  final Color? color;
  final bool strike;

  const _NairaTight({
    required this.amount,
    this.bold = true,
    this.size = 16,
    this.color,
    this.strike = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: size,
      color: color ?? Colors.black,
      decoration: strike ? TextDecoration.lineThrough : TextDecoration.none,
      letterSpacing: -0.25,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '\u20A6', style: style),
          TextSpan(text: amount, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Fullscreen Lightbox
class _Lightbox extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;

  const _Lightbox({
    Key? key,
    required this.images,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late final PageController _controller;
  int _index = 0;

  // keep a controller per page so zoom state doesn't bleed between pages
  final Map<int, TransformationController> _controllers = {};
  Offset? _lastTapDownPos;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  TransformationController _getCtrlFor(int i) {
    return _controllers.putIfAbsent(i, () => TransformationController());
  }

  void _resetZoom(int i) {
    _getCtrlFor(i).value = Matrix4.identity();
  }

  void _toggleDoubleTapZoom(int i, Offset focalPoint) {
    final ctrl = _getCtrlFor(i);
    final current = ctrl.value;
    // If already zoomed, reset; otherwise zoom towards double-tap point
    final isZoomed = current.getMaxScaleOnAxis() > 1.01;
    if (isZoomed) {
      ctrl.value = Matrix4.identity();
      return;
    }
    // Zoom to ~2x centered around tap
    final zoom = 2.0;
    final matrix = Matrix4.identity()
      ..translate(-focalPoint.dx * (zoom - 1), -focalPoint.dy * (zoom - 1))
      ..scale(zoom, zoom);
    ctrl.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                // reset the new page's zoom so each page starts clean
                _resetZoom(i);
              },
              itemBuilder: (_, i) {
                final src = (images[i]['src'] ??
                        images[i]['url'] ??
                        images[i]['image_url'] ??
                        '')
                    .toString();
                final ctrl = _getCtrlFor(i);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: (d) => _lastTapDownPos = d.localPosition,
                  onDoubleTap: () {
                    if (_lastTapDownPos != null) {
                      _toggleDoubleTapZoom(i, _lastTapDownPos!);
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    // swipe down a bit to dismiss
                    if (details.delta.dy > 12) Navigator.of(context).maybePop();
                  },
                  child: Center(
                    child: InteractiveViewer(
                      transformationController: ctrl,
                      minScale: 1.0,
                      maxScale: 4.0,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: src.isEmpty
                          ? const Icon(Icons.broken_image,
                              color: Colors.white54, size: 120)
                          : Image.network(
                              src,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                color: Colors.white54,
                                size: 120,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),

            // Close button
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),

            // Counter
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "${_index + 1} / ${images.length}",
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}