import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:html_unescape/html_unescape.dart';
import 'dart:ui'; // for BackdropFilter
import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'woocommerce_service.dart';
import 'app_header.dart';
import 'product_detail_page.dart';
import 'celebration_theme_provider.dart';

// 🎨 Glass Theme Colors (fallback colors only - will use celebration theme colors)
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);
const kLightBlue = Color(0xFFE3F2FD);
const kVeryLightBlue = Color(0xFFF5F8FF);
const kRed = Color(0xFFE53935);
const kGreen = Color(0xFF43A047);

enum SortType { newest, priceLow, priceHigh, rating, popularity }

class ProductPage extends StatefulWidget {
  final String title;
  final String? categoryId;

  const ProductPage({
    Key? key,
    required this.title,
    this.categoryId,
  }) : super(key: key);

  @override
  _ProductPageState createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final WooCommerceService _service = WooCommerceService();
  static final Map<String, List<dynamic>> _cache = {};

  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  bool _isLoading = true;
  int _currentPage = 1;
  bool _hasMorePages = true;
  final ScrollController _scrollController = ScrollController();
  SortType _sort = SortType.newest;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoading &&
        _hasMorePages) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadProducts() async {
    final cacheKey = widget.categoryId ?? 'all';

    if (_cache.containsKey(cacheKey) && _cache[cacheKey]!.isNotEmpty) {
      setState(() {
        _products = _cache[cacheKey]!;
        _filterAndSort();
        _isLoading = false;
      });
    }

    try {
      setState(() => _isLoading = true);

      List<dynamic> items = [];
      for (int attempt = 0; attempt < 2; attempt++) {
        items = widget.categoryId == null
            ? await _service.getProducts(page: _currentPage)
            : await _service.getProductsByCategory(
                int.parse(widget.categoryId!),
                page: _currentPage,
              );

        if (items.isNotEmpty) break;
        await Future.delayed(const Duration(seconds: 2));
      }

      if (mounted) {
        final cartProvider = Provider.of<CartProvider>(context, listen: false);

        setState(() {
          _products = items.cast<Map<String, dynamic>>();
          _isLoading = false;
          _hasMorePages = items.length >= 10;
        });

        _cache[cacheKey] = _products;
        await cartProvider.cacheProducts(_products.cast<Map<String, dynamic>>());
        _filterAndSort();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final themeProvider = context.read<CelebrationThemeProvider?>();
        final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Connection issue — tap to retry'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _loadProducts,
              textColor: Colors.white,
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: errorColor,
          ),
        );
      }
    }
  }

  Future<void> _loadMoreProducts() async {
    try {
      setState(() => _isLoading = true);
      _currentPage++;

      final items = widget.categoryId == null
          ? await _service.getProducts(page: _currentPage)
          : await _service.getProductsByCategory(
              int.parse(widget.categoryId!), page: _currentPage);

      if (mounted && items.isNotEmpty) {
        final cartProvider = Provider.of<CartProvider>(context, listen: false);

        setState(() {
          _products.addAll(items.cast<Map<String, dynamic>>());
          _hasMorePages = items.length >= 10;
          _isLoading = false;
        });

        _cache[widget.categoryId ?? 'all'] = _products;
        await cartProvider.cacheProducts(items.cast<Map<String, dynamic>>());
        _filterAndSort();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshProducts() async {
    _currentPage = 1;
    _cache.remove(widget.categoryId ?? 'all');
    await _loadProducts();
  }

  void _filterAndSort() {
    final filtered = _products.where((p) {
      if (p == null) return false;
      final price = double.tryParse(p['price']?.toString() ?? '') ?? 0;
      final name = p['name']?.toString().trim() ?? '';
      final stock = p['stock_status']?.toString().toLowerCase() ?? '';
      final images = p['images'];
      if (price <= 0) return false;
      if (stock == 'outofstock') return false;
      if (images == null || (images is List && images.isEmpty)) return false;
      if (name.isEmpty) return false;
      return true;
    }).toList();

    switch (_sort) {
      case SortType.priceLow:
        filtered.sort((a, b) => _num(a['price']).compareTo(_num(b['price'])));
        break;
      case SortType.priceHigh:
        filtered.sort((a, b) => _num(b['price']).compareTo(_num(a['price'])));
        break;
      case SortType.rating:
        filtered.sort((a, b) =>
            _num(b['average_rating']).compareTo(_num(a['average_rating'])));
        break;
      case SortType.popularity:
        filtered.sort((a, b) =>
            _num(b['total_sales']).compareTo(_num(a['total_sales'])));
        break;
      case SortType.newest:
      default:
        filtered.sort((a, b) {
          try {
            final da = DateTime.parse(a['date_created']);
            final db = DateTime.parse(b['date_created']);
            return db.compareTo(da);
          } catch (_) {
            return 0;
          }
        });
    }

    setState(() => _filteredProducts = filtered);
  }

  num _num(dynamic v) => num.tryParse(v?.toString() ?? '0') ?? 0;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final decodedTitle = HtmlUnescape().convert(widget.title);

    // 🎨 CELEBRATION THEME INTEGRATION - Listen for theme changes
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;

    // Use celebration theme colors or fallback to brand colors
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kPrimaryBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];
    final badgeColor = currentTheme?.badgeColor ?? kRed;

    return Scaffold(
      appBar: AppHeader(
        title: decodedTitle,
        showBackButton: true,
        titleStyle: const TextStyle(
          fontFamily: 'Book Antiqua',
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accentColor.withOpacity(0.3), // 🎨 Use celebration theme accent color
              primaryColor.withOpacity(0.1), // 🎨 Use celebration theme primary color
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterRow(primaryColor, accentColor), // 🎨 Pass theme colors
            Expanded(
              child: _isLoading && _products.isEmpty
                  ? _buildShimmerLoading(primaryColor, accentColor) // 🎨 Pass theme colors
                  : _filteredProducts.isEmpty
                      ? _buildEmpty(primaryColor, accentColor) // 🎨 Pass theme colors
                      : RefreshIndicator(
                          onRefresh: _refreshProducts,
                          color: accentColor, // 🎨 Use celebration theme accent color
                          child: GridView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            physics: const BouncingScrollPhysics(),
                            itemCount:
                                _filteredProducts.length + (_isLoading ? 2 : 0),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:
                                  MediaQuery.of(context).size.width > 600
                                      ? 3
                                      : 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.55,
                            ),
                            itemBuilder: (context, index) {
                              if (index >= _filteredProducts.length) {
                                return Center(
                                  child: CircularProgressIndicator(
                                    color: accentColor, // 🎨 Use celebration theme accent color
                                    strokeWidth: 2.5,
                                  ),
                                );
                              }
                              return ProductCard(
                                product: _filteredProducts[index],
                                index: index,
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

  Widget _buildFilterRow(Color primaryColor, Color accentColor) => Container( // 🎨 Add theme colors
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accentColor.withOpacity(0.15), // 🎨 Use celebration theme accent color
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.08), // 🎨 Use celebration theme primary color
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    _filterChip('Newest', SortType.newest, Icons.new_releases, primaryColor, accentColor), // 🎨 Pass theme colors
                    _filterChip(
                        'Low Price', SortType.priceLow, Icons.trending_down, primaryColor, accentColor), // 🎨 Pass theme colors
                    _filterChip(
                        'High Price', SortType.priceHigh, Icons.trending_up, primaryColor, accentColor), // 🎨 Pass theme colors
                    _filterChip('Top Rated', SortType.rating, Icons.star, primaryColor, accentColor), // 🎨 Pass theme colors
                    _filterChip('Popular', SortType.popularity,
                        Icons.local_fire_department, primaryColor, accentColor), // 🎨 Pass theme colors
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _filterChip(String label, SortType type, IconData icon, Color primaryColor, Color accentColor) { // 🎨 Add theme colors
    final selected = _sort == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      colors: [primaryColor, accentColor], // 🎨 Use celebration theme gradient
                    )
                  : null,
              color: selected ? null : Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? accentColor.withOpacity(0.5) // 🎨 Use celebration theme accent color
                    : Colors.grey.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accentColor.withOpacity(0.3), // 🎨 Use celebration theme accent color
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() => _sort = type);
                  _filterAndSort();
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: selected ? Colors.white : Colors.blueGrey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.blueGrey,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading(Color primaryColor, Color accentColor) => Center( // 🎨 Add theme colors
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
                  color: accentColor.withOpacity(0.2), // 🎨 Use celebration theme accent color
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.1), // 🎨 Use celebration theme primary color
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3,
                    color: accentColor, // 🎨 Use celebration theme accent color
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Loading products...",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildEmpty(Color primaryColor, Color accentColor) => Center( // 🎨 Add theme colors
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
                  color: accentColor.withOpacity(0.2), // 🎨 Use celebration theme accent color
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.1), // 🎨 Use celebration theme primary color
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
                          primaryColor.withOpacity(0.1), // 🎨 Use celebration theme primary color
                          accentColor.withOpacity(0.08), // 🎨 Use celebration theme accent color
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      size: 64,
                      color: primaryColor.withOpacity(0.7), // 🎨 Use celebration theme primary color
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No Products Found",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Try adjusting your filters.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------
// PRODUCT CARD WITH GLASS EFFECT
// ------------------------------------------------------------
class ProductCard extends StatefulWidget {
  final dynamic product;
  final int index;
  const ProductCard({super.key, required this.product, required this.index});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final wish = Provider.of<WishlistProvider>(context);
    final p = widget.product;
    final unescape = HtmlUnescape();

    // 🎨 CELEBRATION THEME INTEGRATION for ProductCard
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final badgeColor = currentTheme?.badgeColor ?? kRed;

    final name = unescape.convert(p['name'] ?? 'Unknown Product');
    final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
    final reg = double.tryParse(p['regular_price']?.toString() ?? '0') ?? 0;
    final sale = reg > price && reg > 0;
    final int? offPct = sale ? (((reg - price) / reg) * 100).round() : null;

    final img = (p['images'] is List && p['images'].isNotEmpty)
        ? p['images'][0]['src']
        : null;
    final f = NumberFormat("#,##0", "en_US");

    return FadeTransition(
      opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailPage(product: widget.product),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accentColor.withOpacity(0.2), // 🎨 Use celebration theme accent color
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.12), // 🎨 Use celebration theme primary color
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🖼️ Product image + discount badge
                    Expanded(
                      flex: 3,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20)),
                            child: img != null
                                ? Image.network(
                                    img,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: accentColor.withOpacity(0.3), // 🎨 Use celebration theme accent color
                                        child: Icon(
                                          Icons.image,
                                          size: 40,
                                          color: primaryColor.withOpacity(0.5), // 🎨 Use celebration theme primary color
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: accentColor.withOpacity(0.3), // 🎨 Use celebration theme accent color
                                    child: Icon(
                                      Icons.image,
                                      size: 40,
                                      color: primaryColor.withOpacity(0.5), // 🎨 Use celebration theme primary color
                                    ),
                                  ),
                          ),
                          if (offPct != null)
                            Positioned(
                              top: 10,
                              left: 10,
                              child: _DiscountBadge(text: "-$offPct%", primaryColor: primaryColor), // 🎨 Pass theme color
                            ),
                        ],
                      ),
                    ),

                    // 🧾 Product info
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            if (p['average_rating'] != null &&
                                p['average_rating'] != '0')
                              Row(
                                children: List.generate(5, (index) {
                                  final rating = double.tryParse(
                                          p['average_rating'].toString()) ??
                                      0;
                                  return Icon(
                                    index < rating.floor()
                                        ? Icons.star
                                        : index < rating
                                            ? Icons.star_half
                                            : Icons.star_border,
                                    color: Colors.amber[600],
                                    size: 14,
                                  );
                                }),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _NairaTight(
                                  amount: f.format(price),
                                  bold: true,
                                  color: sale
                                      ? badgeColor // 🎨 Use celebration theme badge color for sale price
                                      : primaryColor, // 🎨 Use celebration theme primary color
                                ),
                                if (sale) ...[
                                  const SizedBox(width: 8),
                                  _NairaTight(
                                    amount: f.format(reg),
                                    bold: false,
                                    fontSize: 11,
                                    color: Colors.grey,
                                    strike: true,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        wish.contains(p)
                                            ? badgeColor.withOpacity(0.15) // 🎨 Use celebration theme badge color
                                            : accentColor.withOpacity(0.3), // 🎨 Use celebration theme accent color
                                        wish.contains(p)
                                            ? badgeColor.withOpacity(0.1) // 🎨 Use celebration theme badge color
                                            : accentColor.withOpacity(0.2), // 🎨 Use celebration theme accent color
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: IconButton(
                                    onPressed: () => wish.toggle(p),
                                    icon: Icon(
                                      wish.contains(p)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: wish.contains(p)
                                          ? badgeColor // 🎨 Use celebration theme badge color
                                          : primaryColor, // 🎨 Use celebration theme primary color
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [primaryColor, accentColor], // 🎨 Use celebration theme gradient
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accentColor.withOpacity(0.3), // 🎨 Use celebration theme accent color
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        cart.addToCartFast(p);
                                        final themeProvider = context.read<CelebrationThemeProvider?>();
                                        final successColor = themeProvider?.currentTheme.accentColor ?? kGreen;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text('$name added to cart!'),
                                            duration:
                                                const Duration(seconds: 1),
                                            backgroundColor: successColor, // 🎨 Use celebration theme accent color for success
                                            behavior: SnackBarBehavior.floating,
                                            margin: const EdgeInsets.all(16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.shopping_cart, size: 15),
                                          SizedBox(width: 4),
                                          Text(
                                            "Add",
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ₦ Compact price display
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
      letterSpacing: -0.25,
      decoration: strike ? TextDecoration.lineThrough : TextDecoration.none,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '\u20A6', style: style), // ₦ symbol
          TextSpan(text: amount, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ------------------------------------------------------------
// Discount badge widget with glass effect
// ------------------------------------------------------------
class _DiscountBadge extends StatelessWidget {
  final String text;
  final Color primaryColor; // 🎨 Theme color

  const _DiscountBadge({required this.text, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.redAccent, Colors.red],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withOpacity(0.5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}