import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'cart_provider.dart';
import 'celebration_theme_provider.dart'; // Add this import
import 'checkout_page.dart'; // ADD THIS
class ProductDetailStandard extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailStandard({super.key, required this.product});

  @override
  State<ProductDetailStandard> createState() => _ProductDetailStandardState();
}

class _ProductDetailStandardState extends State<ProductDetailStandard>
    with TickerProviderStateMixin {
  final _priceFmt = NumberFormat("#,##0", "en_US");

  // 👇 Peek carousel controller + page tracking
  late final PageController _imagesCtrl;
  double _page = 0.0; // fractional page for smooth transforms
  int _imgIndex = 0;

  int _quantity = 1;

  // 🎨 Glass / brand palette - Now with theme fallbacks
  static const Color kPrimaryBlue = Color(0xFF1565C0);
  static const Color kAccentBlue = Color(0xFF2196F3);
  static const Color kInk = Color(0xFF0D47A1);
  static const double kGlassBlur = 12.0;

  // ✅ Variations (saved to cart)
  Map<String, String> _selectedAttributes = {};

  // subtle image scale on swipe
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    // viewportFraction < 1.0 gives the "peek" effect
    _imagesCtrl = PageController(viewportFraction: 0.82)
      ..addListener(() {
        final p = _imagesCtrl.page ?? 0.0;
        if ((p - _page).abs() > 0.0001) {
          setState(() => _page = p);
        }
      });

    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 260),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 0.94, end: 1.0)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();

    _initializeAttributes();
  }

  // ---------- Data helpers ----------
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
    for (final a in _attributesList) {
      if (a is Map && a['variation'] == true) {
        final name = a['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        if ((_selectedAttributes[name] ?? '').isEmpty) return false;
      }
    }
    return true;
  }

  void _initializeAttributes() {
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
    _imagesCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    // Add theme provider
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final badgeColor = currentTheme?.badgeColor ?? Colors.redAccent;

    final String name = (p['name'] ?? 'Product').toString();
    final String descRaw = (p['description'] ?? '').toString();
    final String description =
        descRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim().isEmpty
            ? "No description available"
            : descRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    final double price = _asDouble(p['price']);
    final double regular = _asDouble(p['regular_price']);
    final bool onSale = regular > 0 && regular > price;

    final double rating =
        double.tryParse((p['average_rating'] ?? '0').toString()) ?? 0;

    final String stock =
        (p['stock_status'] ?? 'instock').toString().toLowerCase();
    final bool inStock = stock == 'instock';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: _glassAppBar(name, primaryColor),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_images.isNotEmpty) ...[
              _glassyPeekCarousel(_images, primaryColor, accentColor), // ✅ fixed bounded height
              const SizedBox(height: 10),
              _thumbStrip(_images, _imgIndex, primaryColor),
              const SizedBox(height: 16),
            ] else ...[
              _imagePlaceholder(),
              const SizedBox(height: 16),
            ],

            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.22,
                            color: primaryColor, // Use theme color
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StockPill(inStock: inStock),
                    ],
                  ),
                  if (rating > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(5, (i) {
                        final icon = i + 1 <= rating.floor()
                            ? Icons.star
                            : (i + 1 - rating <= 0.5
                                ? Icons.star_half
                                : Icons.star_border);
                        return Icon(icon, size: 18, color: Colors.amber[600]);
                      }),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          primaryColor.withOpacity(0.08), // Use theme color
                          accentColor.withOpacity(0.06), // Use theme color
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: primaryColor.withOpacity(0.18), width: 1), // Use theme color
                    ),
                    child: Row(
                      children: [
                        _NairaTight(
                          amount: _priceFmt.format(price),
                          size: 26,
                          bold: true,
                          color: onSale
                              ? const Color(0xFFD32F2F)
                              : primaryColor, // Use theme color
                        ),
                        const SizedBox(width: 10),
                        if (onSale)
                          _NairaTight(
                            amount: _priceFmt.format(regular),
                            size: 14,
                            bold: false,
                            color: Colors.grey.shade600,
                            strike: true,
                          ),
                        const Spacer(),
                        if (onSale) _saleBadge(primaryColor, accentColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (p['id'] != null ||
                      (p['sku']?.toString().isNotEmpty ?? false))
                    Text(
                      "ID: ${p['id'] ?? '-'}  •  SKU: ${p['sku']?.toString().isNotEmpty == true ? p['sku'] : '-'}",
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black54),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            _GlassCard(
              child: Row(
                children: [
                  const Text(
                    "Quantity",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _qtyBtn(Icons.remove, () {
                    if (_quantity > 1) setState(() => _quantity--);
                  }, primaryColor),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1), // Use theme color
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_quantity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primaryColor, // Use theme color
                      ),
                    ),
                  ),
                  _qtyBtn(Icons.add, () => setState(() => _quantity++), primaryColor),
                ],
              ),
            ),

            const SizedBox(height: 14),

            if (_hasVariations) _GlassCard(child: _buildProductVariations(primaryColor)),

            const SizedBox(height: 14),

            _GlassCard(
              pad: EdgeInsets.zero,
              child: _accordion(
                description,
                (widget.product['short_description'] ?? '').toString(),
                primaryColor,
                accentColor,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _frostedBottomBar(inStock, primaryColor, accentColor),
    );
  }

  // ---------- Glassy AppBar ----------
  AppBar _glassAppBar(String title, Color primaryColor) {
    return AppBar(
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700, color: primaryColor), // Use theme color
      ),
      centerTitle: true,
      backgroundColor: Colors.white.withOpacity(0.85),
      elevation: 0,
      iconTheme: IconThemeData(color: primaryColor), // Use theme color
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
          child: Container(color: Colors.transparent),
        ),
      ),
      actions: const [SizedBox(width: 4)],
    );
  }

  // ---------- Peek Carousel (FIXED HEIGHT) ----------
  Widget _glassyPeekCarousel(List<Map<String, dynamic>> images, Color primaryColor, Color accentColor) {
    return SizedBox( // ✅ bound height so Stack has finite constraints
      height: 300,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.9),
                      Colors.white.withOpacity(0.75)
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
                child: const SizedBox.shrink(),
              ),
            ),
            AnimatedBuilder(
              animation: _scaleAnim,
              builder: (_, child) =>
                  Transform.scale(scale: _scaleAnim.value, child: child),
              child: PageView.builder(
                controller: _imagesCtrl,
                itemCount: images.length,
                onPageChanged: (i) {
                  setState(() => _imgIndex = i);
                  _animCtrl
                    ..reset()
                    ..forward();
                },
                itemBuilder: (_, i) {
                  final src = (images[i]['src'] ??
                          images[i]['url'] ??
                          images[i]['image_url'] ??
                          '')
                      .toString();

                  final d = (_page - i).abs().clamp(0.0, 1.0);
                  final scale = 0.92 + (1 - d) * 0.08;
                  final lift = lerpDouble(14, 0, (1 - d)) ?? 0.0;

                  return Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform.scale(
                      scale: scale,
                      child: GestureDetector(
                        onTap: () {
                          if (src.isNotEmpty) _showZoom(src, primaryColor, accentColor);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: src.isEmpty
                                ? Container(
                                    color: Colors.grey.shade200,
                                    child: const Center(
                                        child: Icon(Icons.image, size: 60)),
                                  )
                                : Image.network(
                                    src,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Center(
                                            child: Icon(Icons.broken_image,
                                                size: 60)),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (i) {
                      final active = i == _imgIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: active ? 12 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: Colors.black
                              .withOpacity(active ? 0.7 : 0.35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showZoom(String imageUrl, Color primaryColor, Color accentColor) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: kGlassBlur, sigmaY: kGlassBlur),
                  child: Container(color: Colors.white.withOpacity(0.12)),
                ),
              ),
              Center(
                child: InteractiveViewer(
                  maxScale: 3.0,
                  minScale: 0.5,
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.white.withOpacity(0.92),
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.image_not_supported, size: 80),
    );
  }

  // ---------- Variations ----------
  Widget _buildProductVariations(Color primaryColor) {
    final accentColors = [
      const Color(0xFF2563EB),
      const Color(0xFF059669),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
      const Color(0xFFEA580C),
      const Color(0xFF0891B2),
    ];

    final varAttrs = _attributesList
        .where((a) => a is Map && a['variation'] == true)
        .cast<Map>();

    final keys =
        varAttrs.map((e) => e['name']?.toString() ?? '').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Product Options",
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: primaryColor), // Use theme color
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < keys.length; i++) ...[
          Text(
            keys[i],
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87),
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
          if (i != keys.length - 1) const SizedBox(height: 10),
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

  Widget _variationChip(
      String attributeName, String value, Color color, bool isSelected) {
    return InkWell(
      onTap: () =>
          setState(() => _selectedAttributes[attributeName] = value),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withOpacity(0.18) : Colors.grey.withOpacity(0.1),
          border: Border.all(
              color: isSelected ? color : Colors.grey.withOpacity(0.3),
              width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
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
  Widget _accordion(String description, String shortDescRaw, Color primaryColor, Color accentColor) {
    final shortDesc =
        shortDescRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return Theme(
      data:
          Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.86),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: accentColor.withOpacity(0.2), width: 1.5), // Use theme color
            ),
            child: ExpansionPanelList.radio(
              elevation: 0,
              animationDuration:
                  const Duration(milliseconds: 220),
              children: [
                _panel(0, "Description",
                    description.isEmpty ? "No description available" : description, primaryColor, accentColor),
                _panel(1, "Specification",
                    shortDesc.isEmpty ? "No specification provided" : shortDesc, primaryColor, accentColor),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withOpacity(0.14), // Use theme color
                      accentColor.withOpacity(0.1) // Use theme color
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
                  style: TextStyle(
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
          content,
          style: const TextStyle(
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

 // ---------- Bottom Bar ----------
   Widget _frostedBottomBar(bool inStock, Color primaryColor, Color accentColor) {
     final canPress = inStock && _canAddToCart;
     final cart = Provider.of<CartProvider>(context, listen: false);
     final p = widget.product;

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
                               productId: p['id'],
                               name: p['name']?.toString() ?? '',
                               price: _asDouble(p['price']),
                               image: _firstImage,
                               quantity: _quantity,
                               sku: p['sku']?.toString(),
                               attributes:
                                   Map<String, String>.from(_selectedAttributes),
                             );
                             ScaffoldMessenger.of(context).showSnackBar(
                               SnackBar(
                                 content: Text(
                                     "$_quantity × ${p['name'] ?? 'Product'} added to cart"),
                                 backgroundColor: primaryColor, // Use theme color
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
                                   content: Text(
                                       "Please select all required options."),
                                   backgroundColor: Colors.redAccent,
                                 ),
                               );
                             }
                           },
                     icon: const Icon(Icons.shopping_cart_outlined),
                     label: const Text("Add to Cart"),
                     style: OutlinedButton.styleFrom(
                       foregroundColor: primaryColor, // Use theme color
                       side: BorderSide(
                           color: primaryColor, width: 1.5), // Use theme color
                       padding: const EdgeInsets.symmetric(vertical: 14),
                       shape: RoundedRectangleBorder(
                           borderRadius: BorderRadius.circular(12)),
                     ),
                   ),
                 ),
                 const SizedBox(width: 12),
                 // Buy Now - UPDATED VERSION
                 Expanded(
                   child: Container(
                     decoration: BoxDecoration(
                       gradient: canPress
                           ? LinearGradient(
                               colors: [primaryColor, accentColor], // Use theme colors
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
                                 color: primaryColor.withOpacity(0.32), // Use theme color
                                 blurRadius: 10,
                                 offset: const Offset(0, 5),
                               ),
                             ]
                           : null,
                     ),
                     child: ElevatedButton.icon(
                       onPressed: canPress
                           ? () async {
                               // 1. Add to cart first
                               await cart.addToCartWithDetails(
                                 productId: p['id'],
                                 name: p['name']?.toString() ?? '',
                                 price: _asDouble(p['price']),
                                 image: _firstImage ?? '',
                                 quantity: _quantity,
                                 sku: p['sku']?.toString(),
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
                       icon: const Icon(Icons.flash_on),
                       label: const Text("Buy Now"),
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.transparent,
                         shadowColor: Colors.transparent,
                         foregroundColor: Colors.white,
                         disabledBackgroundColor: Colors.grey.shade400,
                         padding: const EdgeInsets.symmetric(vertical: 14),
                         shape: RoundedRectangleBorder(
                             borderRadius: BorderRadius.circular(12)),
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

  // ---------- Small helpers ----------
  Widget _thumbStrip(List<Map<String, dynamic>> images, int active, Color primaryColor) {
    if (images.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final src = (images[i]['src'] ??
                  images[i]['url'] ??
                  images[i]['image_url'] ??
                  '')
              .toString();
          final selected = i == active;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              _imagesCtrl.animateToPage(
                i,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            },
            child: Container(
              width: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? primaryColor : Colors.grey.shade300, // Use theme color
                  width: selected ? 2 : 1,
                ),
              ),
              child: src.isEmpty
                  ? const Icon(Icons.image, size: 24)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.network(
                        src,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Center(
                                child: Icon(Icons.broken_image, size: 20)),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _saleBadge(Color primaryColor, Color accentColor) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient:
            LinearGradient(colors: [primaryColor, accentColor]), // Use theme colors
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
              color: primaryColor.withOpacity(0.25), // Use theme color
              blurRadius: 10,
              offset: const Offset(0, 6))
        ],
      ),
      child: const Text(
        "SALE",
        style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onPressed, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08), // Use theme color
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: primaryColor.withOpacity(0.25), width: 1), // Use theme color
      ),
      child: IconButton(
        icon: Icon(icon, color: primaryColor, size: 20), // Use theme color
        splashRadius: 22,
        onPressed: onPressed,
      ),
    );
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '0') ?? 0.0;
  }
}

// ===== Glass card =====
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
                color: accentColor.withOpacity(0.18), // Use theme color
                width: 1.5),
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

// ===== Tight Naira renderer =====
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
      decoration:
          strike ? TextDecoration.lineThrough : TextDecoration.none,
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

class _StockPill extends StatelessWidget {
  final bool inStock;
  const _StockPill({required this.inStock});

  @override
  Widget build(BuildContext context) {
    final color =
        inStock ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        inStock ? "In Stock" : "Out of Stock",
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}