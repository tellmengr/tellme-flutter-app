import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:html_unescape/html_unescape.dart';
import 'user_settings_provider.dart';
import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'celebration_theme_provider.dart'; // Add this import
import 'checkout_page.dart'; // ADD THIS

class ProductDetailModern extends StatefulWidget {
  final dynamic product;

  const ProductDetailModern({
    Key? key,
    required this.product,
  }) : super(key: key);

  @override
  State<ProductDetailModern> createState() => _ProductDetailModernState();
}

class _ProductDetailModernState extends State<ProductDetailModern>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final HtmlUnescape _unescape = HtmlUnescape();
  int _currentImageIndex = 0;
  int _quantity = 1;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // 🔹 Track selected variation attributes
  Map<String, String> _selectedAttributes = {};

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ✅ Safe getters
  String get productName =>
      _unescape.convert(widget.product?['name'] ?? 'Product Name');
  String get productDescription =>
      widget.product?['description'] ?? 'No description available';
  String get productSpecifications =>
      widget.product?['short_description'] ?? 'No specification provided';
  String get productPolicies => "No store policies available";
  String get productInquiries => "No inquiries yet";
  String get productReviews => "No reviews yet";

  double get productPrice {
    final p = widget.product?['price'];
    if (p == null) return 0;
    if (p is num) return p.toDouble();
    return double.tryParse(p.toString()) ?? 0;
  }

  List<String> get productImages {
    final imgs = widget.product?['images'];
    if (imgs is List) {
      return imgs
          .map<String>((e) {
            if (e is Map<String, dynamic>) {
              return e['src']?.toString() ?? '';
            } else if (e is String) {
              return e;
            } else {
              return '';
            }
          })
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return ['assets/images/placeholder.png'];
  }

  String get productCategory =>
      _unescape.convert(
          (widget.product?['categories']?[0]?['name'] ?? 'General').toString());
  double get productRating =>
      double.tryParse(widget.product?['average_rating']?.toString() ?? '0') ??
      0.0;
  int get productReviewCount => widget.product?['rating_count'] ?? 0;

  // ✅ Check if all required attributes are selected
  bool get _canAddToCart {
    final attributes = widget.product?['attributes'] as List? ?? [];
    if (attributes.isEmpty) return true;
    for (var attr in attributes) {
      final name = attr['name']?.toString() ?? '';
      if ((_selectedAttributes[name] ?? '').isEmpty) return false;
    }
    return true;
  }

  // Helper methods for Buy Now
  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '0') ?? 0.0;
  }

  String? _getFirstImage() {
    final images = widget.product?['images'];
    if (images is List && images.isNotEmpty) {
      final firstImage = images.first;
      if (firstImage is Map) {
        return firstImage['src']?.toString() ??
               firstImage['url']?.toString() ??
               firstImage['image_url']?.toString();
      }
    }
    return widget.product?['image']?.toString() ??
           widget.product?['imageUrl']?.toString() ??
           widget.product?['image_url']?.toString();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<UserSettingsProvider>(context, listen: false);
    final themeProvider = context.watch<CelebrationThemeProvider?>();

    // Get theme colors exactly like in SignUpPage
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF004AAD);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF0096FF);
    final secondaryColor = currentTheme?.secondaryColor ?? const Color(0xFF004AAD);
    final gradientColors = currentTheme?.gradient.colors ?? [const Color(0xFF004AAD), const Color(0xFF0096FF)];
    final lightBlue = const Color(0xFFE3F2FD);
    final veryLightBlue = const Color(0xFFF5F8FF);

    return Scaffold(
      backgroundColor: veryLightBlue,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              lightBlue.withOpacity(0.3),
              veryLightBlue,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: CustomScrollView(
            slivers: [
              _buildAppBar(primaryColor, accentColor, veryLightBlue),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildImageCarousel(primaryColor, accentColor),
                    _buildInfoCard(settings, primaryColor, accentColor, lightBlue, veryLightBlue),
                    _buildVariations(primaryColor, accentColor),
                    const SizedBox(height: 20),
                    _buildQuantitySelector(primaryColor, accentColor),
                    const SizedBox(height: 20),
                    _buildAccordion(primaryColor, accentColor),
                    const SizedBox(height: 100), // space for floating bar
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // ✅ Floating bottom action bar with glass effect - THEME AWARE
      bottomNavigationBar: SafeArea(
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: accentColor.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: _buildActionButtons(primaryColor, accentColor),
            ),
          ),
        ),
      ),
    );
  }

  // 🔹 App Bar with Glass Effect - THEME AWARE
  Widget _buildAppBar(Color primaryColor, Color accentColor, Color veryLightBlue) {
    final wish = Provider.of<WishlistProvider>(context);
    final isWishlisted = wish.contains(widget.product);

    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.85),
                  veryLightBlue.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
      ),
      leading: _circleButton(
        Icons.arrow_back_ios_new_rounded,
        primaryColor: primaryColor,
        accentColor: accentColor,
        onTap: () => Navigator.pop(context),
      ),
      actions: [
        _circleButton(
          isWishlisted ? Icons.favorite : Icons.favorite_border,
          primaryColor: primaryColor,
          accentColor: accentColor,
          color: isWishlisted ? Colors.red : primaryColor,
          onTap: () => wish.toggle(widget.product),
        ),
      ],
    );
  }

  Widget _circleButton(IconData icon, {
    required Color primaryColor,
    required Color accentColor,
    Color color = Colors.black,
    required VoidCallback onTap
  }) {
    return Container(
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
                color: accentColor.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(icon, color: color, size: 22),
              onPressed: onTap,
            ),
          ),
        ),
      ),
    );
  }

  // 🖼 Image Carousel with Glass Effect - THEME AWARE
  Widget _buildImageCarousel(Color primaryColor, Color accentColor) {
    return SizedBox(
      height: 320,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() {
              _currentImageIndex = index;
            }),
            itemCount: productImages.length,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        productImages[index],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFE3F2FD).withOpacity(0.3),
                                  const Color(0xFFF5F8FF),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.image_outlined,
                              size: 80,
                              color: primaryColor.withOpacity(0.4),
                            ),
                          );
                        },
                      ),
                      // Glass overlay at bottom for better indicator visibility
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (productImages.length > 1)
            Positioned(
              bottom: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        productImages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentImageIndex == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: _currentImageIndex == index
                                ? LinearGradient(
                                    colors: [primaryColor, accentColor],
                                  )
                                : null,
                            color: _currentImageIndex == index
                                ? null
                                : Colors.grey.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 🧾 Product Info Card with Glass Effect - THEME AWARE
  Widget _buildInfoCard(UserSettingsProvider settings, Color primaryColor, Color accentColor, Color lightBlue, Color veryLightBlue) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: accentColor.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Tag with gradient - THEME AWARE
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withOpacity(0.15),
                        accentColor.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    productCategory,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  productName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),

                // ⭐ Rating
                Row(
                  children: [
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < productRating.round()
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: i < productRating.round()
                            ? Colors.amber[600]
                            : Colors.grey[300],
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      productReviewCount > 0
                          ? "${productRating.toStringAsFixed(1)} ($productReviewCount)"
                          : "No Reviews Yet",
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 💰 Price with gradient - THEME AWARE
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withOpacity(0.1),
                        accentColor.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    settings.formatPrice(productPrice),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 🔎 Product ID and SKU
                if (widget.product?['id'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "Product ID: ${widget.product['id']}",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                if ((widget.product?['sku'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      "SKU: ${widget.product['sku']}",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🔥 Variations with Glass Effect - THEME AWARE
  Widget _buildVariations(Color primaryColor, Color accentColor) {
    final attributes = widget.product?['attributes'] as List? ?? [];

    if (attributes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: attributes.map<Widget>((attr) {
          final name = attr['name']?.toString() ?? '';
          final options =
              (attr['options'] as List?)?.map((e) => e.toString()).toList() ??
                  [];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accentColor.withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _selectedAttributes[name],
                        items: options
                            .map((o) => DropdownMenuItem<String>(
                                value: o, child: Text(o)))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedAttributes[name] = val ?? '';
                          });
                        },
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: InputBorder.none,
                          hintText: 'Select $name',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                        ),
                        dropdownColor: Colors.white,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // 🔥 Accordion Section with Glass Effect - THEME AWARE
  Widget _buildAccordion(Color primaryColor, Color accentColor) {
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
                color: accentColor.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: ExpansionPanelList.radio(
              animationDuration: const Duration(milliseconds: 300),
              elevation: 0,
              expandedHeaderPadding: EdgeInsets.zero,
              children: [
                _buildPanel(0, "Description", productDescription, primaryColor, accentColor),
                _buildPanel(1, "Specification", productSpecifications, primaryColor, accentColor),
                _buildPanel(2, "Customer Reviews", productReviews, primaryColor, accentColor),
                _buildPanel(3, "Store Policies", productPolicies, primaryColor, accentColor),
                _buildPanel(4, "Inquiries", productInquiries, primaryColor, accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ExpansionPanelRadio _buildPanel(int value, String title, String content, Color primaryColor, Color accentColor) {
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
                      primaryColor.withOpacity(0.12),
                      accentColor.withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getPanelIcon(value),
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        );
      },
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          _unescape
              .convert(content.replaceAll(RegExp(r'<[^>]*>'), '').trim()),
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[800],
            height: 1.6,
          ),
        ),
      ),
    );
  }

  IconData _getPanelIcon(int value) {
    switch (value) {
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

  // 🔢 Quantity Selector with Glass Effect - THEME AWARE
  Widget _buildQuantitySelector(Color primaryColor, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accentColor.withOpacity(0.2),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Quantity",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withOpacity(0.12),
                        accentColor.withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: accentColor.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      _qtyButton(Icons.remove, primaryColor, () {
                        if (_quantity > 1) setState(() => _quantity--);
                      }),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          '$_quantity',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      _qtyButton(Icons.add, primaryColor, () {
                        setState(() => _quantity++);
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _qtyButton(IconData icon, Color primaryColor, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: primaryColor, size: 20),
        ),
      ),
    );
  }

  // 🛒 Beautiful Gradient Action Buttons - THEME AWARE
  Widget _buildActionButtons(Color primaryColor, Color accentColor) {
    return Row(
      children: [
        // Add to Cart Button - THEME AWARE
        Expanded(
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _canAddToCart
                    ? [primaryColor, accentColor]
                    : [Colors.grey.shade300, Colors.grey.shade400],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: _canAddToCart
                  ? [
                      BoxShadow(
                        color: accentColor.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: ElevatedButton(
              onPressed: _canAddToCart ? _onAddToCart : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.shopping_cart_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Add to Cart",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Buy Now Button - Outlined with gradient border - THEME AWARE
        Expanded(
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: _canAddToCart
                  ? LinearGradient(
                      colors: [primaryColor, accentColor],
                    )
                  : null,
              color: _canAddToCart ? null : Colors.grey.shade300,
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                onPressed: _canAddToCart
                    ? () async {
                        final cart = Provider.of<CartProvider>(context, listen: false);

                        // 1. Add to cart first
                        await cart.addToCartWithDetails(
                          productId: widget.product['id'],
                          name: widget.product['name']?.toString() ?? 'Product',
                          price: _asDouble(widget.product['price']),
                          image: _getFirstImage() ?? '',
                          quantity: _quantity,
                          sku: widget.product['sku']?.toString(),
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
                  foregroundColor: _canAddToCart ? primaryColor : Colors.grey.shade500,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.flash_on,
                      size: 20,
                      color: _canAddToCart ? accentColor : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      "Buy Now",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onAddToCart() {
    final cart = Provider.of<CartProvider>(context, listen: false);

    cart.addToCartWithDetails(
      productId: widget.product['id'],
      name: productName,
      price: productPrice,
      image: productImages.isNotEmpty ? productImages.first : '',
      quantity: _quantity,
      attributes: _selectedAttributes, // ✅ Save attributes
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text("$_quantity × $productName added to cart"),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}