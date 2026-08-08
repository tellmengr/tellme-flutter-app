import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_header.dart';
import 'cart_provider.dart';
import 'celebration_theme_provider.dart';
import 'product_detail_page.dart';
import 'wishlist_provider.dart';
import 'woocommerce_service.dart';

const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);
const kRed = Color(0xFFE53935);
const kGreen = Color(0xFF43A047);

enum SortType { newest, priceLow, priceHigh, rating, popularity }

class ProductPage extends StatefulWidget {
  final String title;
  final String? categoryId;

  const ProductPage({
    super.key,
    required this.title,
    this.categoryId,
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final WooCommerceService _service = WooCommerceService();
  final ScrollController _scrollController = ScrollController();

  static final Map<String, List<Map<String, dynamic>>> _cache = {};

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMorePages = true;
  int _currentPage = 1;
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
    if (!_scrollController.hasClients || _isLoading || _isLoadingMore) return;

    final position = _scrollController.position;
    final nearBottom = position.pixels >= position.maxScrollExtent - 240;

    if (nearBottom && _hasMorePages) {
      _loadMoreProducts();
    }
  }

  String get _cacheKey => widget.categoryId?.trim().isNotEmpty == true
      ? widget.categoryId!.trim()
      : 'all';

  List<Map<String, dynamic>> _normalizeProducts(List<dynamic> items) {
    return items
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<List<dynamic>> _fetchProductsPage(int page) {
    final categoryId = widget.categoryId?.trim();

    if (categoryId == null || categoryId.isEmpty) {
      return _service.getProducts(page: page);
    }

    return _service.getProductsByCategory(categoryId, page: page);
  }

  Future<void> _loadProducts() async {
    final cached = _cache[_cacheKey];

    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _products = List<Map<String, dynamic>>.from(cached);
        _isLoading = false;
      });
      _filterAndSort();
      return;
    }

    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _hasMorePages = true;
    });

    try {
      List<dynamic> items = [];

      for (int attempt = 0; attempt < 2; attempt++) {
        items = await _fetchProductsPage(_currentPage);
        if (items.isNotEmpty) break;
        await Future.delayed(const Duration(seconds: 2));
      }

      if (!mounted) return;

      final products = _normalizeProducts(items);
      final cartProvider = Provider.of<CartProvider>(context, listen: false);

      setState(() {
        _products = products;
        _isLoading = false;
        _hasMorePages = products.length >= 10;
      });

      _cache[_cacheKey] = products;
      await cartProvider.cacheProducts(products);
      _filterAndSort();
    } catch (_) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      final themeProvider = context.read<CelebrationThemeProvider?>();
      final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Connection issue - tap to retry'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _refreshProducts,
            textColor: Colors.white,
          ),
          duration: const Duration(seconds: 5),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMorePages) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final items = await _fetchProductsPage(nextPage);
      final products = _normalizeProducts(items);

      if (!mounted) return;

      setState(() {
        _currentPage = nextPage;
        _products.addAll(products);
        _hasMorePages = products.length >= 10;
        _isLoadingMore = false;
      });

      _cache[_cacheKey] = List<Map<String, dynamic>>.from(_products);

      if (products.isNotEmpty) {
        final cartProvider = Provider.of<CartProvider>(context, listen: false);
        await cartProvider.cacheProducts(products);
      }

      _filterAndSort();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refreshProducts() async {
    _cache.remove(_cacheKey);

    setState(() {
      _currentPage = 1;
      _products = [];
      _filteredProducts = [];
      _hasMorePages = true;
    });

    await _loadProducts();
  }

  void _filterAndSort() {
    final filtered = _products.where((p) {
      final price = double.tryParse(p['price']?.toString() ?? '') ?? 0;
      final name = p['name']?.toString().trim() ?? '';
      final stock = p['stock_status']?.toString().toLowerCase() ?? '';

      if (price <= 0) return false;
      if (stock == 'outofstock' || stock == 'out_of_stock') return false;
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
        filtered.sort(
          (a, b) =>
              _num(b['average_rating']).compareTo(_num(a['average_rating'])),
        );
        break;
      case SortType.popularity:
        filtered.sort(
          (a, b) => _num(b['total_sales']).compareTo(_num(a['total_sales'])),
        );
        break;
      case SortType.newest:
        filtered.sort((a, b) {
          final da = _dateValue(a['date_created']);
          final db = _dateValue(b['date_created']);
          return db.compareTo(da);
        });
        break;
    }

    if (!mounted) return;
    setState(() => _filteredProducts = filtered);
  }

  num _num(dynamic value) {
    return num.tryParse(value?.toString() ?? '0') ?? 0;
  }

  DateTime _dateValue(dynamic value) {
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final decodedTitle = HtmlUnescape().convert(widget.title);
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;

    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

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
              accentColor.withOpacity(0.3),
              primaryColor.withOpacity(0.1),
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterRow(primaryColor, accentColor),
            Expanded(
              child: _isLoading && _products.isEmpty
                  ? _buildShimmerLoading(primaryColor, accentColor)
                  : _filteredProducts.isEmpty
                      ? _buildEmpty(primaryColor, accentColor)
                      : RefreshIndicator(
                          onRefresh: _refreshProducts,
                          color: accentColor,
                          child: GridView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            itemCount: _filteredProducts.length +
                                (_isLoadingMore ? 2 : 0),
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
                                    color: accentColor,
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

  Widget _buildFilterRow(Color primaryColor, Color accentColor) {
    return Container(
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  _filterChip(
                    'Newest',
                    SortType.newest,
                    Icons.new_releases,
                    primaryColor,
                    accentColor,
                  ),
                  _filterChip(
                    'Low Price',
                    SortType.priceLow,
                    Icons.trending_down,
                    primaryColor,
                    accentColor,
                  ),
                  _filterChip(
                    'High Price',
                    SortType.priceHigh,
                    Icons.trending_up,
                    primaryColor,
                    accentColor,
                  ),
                  _filterChip(
                    'Top Rated',
                    SortType.rating,
                    Icons.star,
                    primaryColor,
                    accentColor,
                  ),
                  _filterChip(
                    'Popular',
                    SortType.popularity,
                    Icons.local_fire_department,
                    primaryColor,
                    accentColor,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(
    String label,
    SortType type,
    IconData icon,
    Color primaryColor,
    Color accentColor,
  ) {
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
                  ? LinearGradient(colors: [primaryColor, accentColor])
                  : null,
              color: selected ? null : Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? accentColor.withOpacity(0.5)
                    : Colors.grey.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accentColor.withOpacity(0.3),
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

  Widget _buildShimmerLoading(Color primaryColor, Color accentColor) {
    return Center(
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
                CircularProgressIndicator(
                  strokeWidth: 3,
                  color: accentColor,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Loading products...',
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
  }

  Widget _buildEmpty(Color primaryColor, Color accentColor) {
    return Center(
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
                    Icons.shopping_bag_outlined,
                    size: 64,
                    color: primaryColor.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Products Found',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Try adjusting your filters.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final int index;

  const ProductCard({
    super.key,
    required this.product,
    required this.index,
  });

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

  String? _readImageUrl(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _productImageUrl(Map<String, dynamic> product) {
    final images = product['images'];

    if (images is List) {
      for (final item in images) {
        if (item is String) {
          final url = _readImageUrl(item);
          if (url != null) return url;
        }

        if (item is Map) {
          final url = _readImageUrl(
            item['src'] ??
                item['url'] ??
                item['image'] ??
                item['imageUrl'] ??
                item['thumbnail'] ??
                item['thumbnailUrl'],
          );

          if (url != null) return url;
        }
      }
    }

    return _readImageUrl(
      product['imageUrl'] ??
          product['image_url'] ??
          product['image'] ??
          product['thumbnailUrl'] ??
          product['thumbnail_url'] ??
          product['thumbnail'] ??
          product['featuredImage'] ??
          product['featured_image'],
    );
  }

  double _ratingValue(Map<String, dynamic> product) {
    for (final key in const [
      'average_rating',
      'averageRating',
      'rating_average',
      'ratingAverage',
      'review_average',
      'reviewAverage',
      'rating',
    ]) {
      final parsed = double.tryParse(product[key]?.toString() ?? '');
      if (parsed != null && parsed > 0) return parsed.clamp(0, 5).toDouble();
    }

    final reviews = product['reviews'];
    if (reviews is Map) {
      for (final key in const ['average', 'rating', 'averageRating']) {
        final parsed = double.tryParse(reviews[key]?.toString() ?? '');
        if (parsed != null && parsed > 0) return parsed.clamp(0, 5).toDouble();
      }
    }

    return 0;
  }

  int _ratingCount(Map<String, dynamic> product) {
    for (final key in const [
      'rating_count',
      'ratingCount',
      'review_count',
      'reviewCount',
      'reviews_count',
      'reviewsCount',
    ]) {
      final parsed = int.tryParse(product[key]?.toString() ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }

    final reviews = product['reviews'];
    if (reviews is Map) {
      for (final key in const ['count', 'total', 'reviewCount']) {
        final parsed = int.tryParse(reviews[key]?.toString() ?? '');
        if (parsed != null && parsed > 0) return parsed;
      }
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final wish = Provider.of<WishlistProvider>(context);
    final p = widget.product;
    final unescape = HtmlUnescape();

    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final badgeColor = currentTheme?.badgeColor ?? kRed;

    final name = unescape.convert(p['name']?.toString() ?? 'Unknown Product');
    final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
    final reg = double.tryParse(p['regular_price']?.toString() ?? '0') ?? 0;
    final sale = reg > price && reg > 0;
    final int? offPct = sale ? (((reg - price) / reg) * 100).round() : null;
    final rating = _ratingValue(p);
    final ratingCount = _ratingCount(p);
    final stock = p['stock_status']?.toString().toLowerCase() ?? '';
    final inStock = stock.isEmpty || stock == 'instock' || stock == 'in_stock';
    final img = _productImageUrl(p);
    final f = NumberFormat('#,##0', 'en_US');

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
                    color: accentColor.withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            child: img != null
                                ? Image.network(
                                    img,
                                    key: ValueKey(img),
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;

                                      return Container(
                                        color: accentColor.withOpacity(0.2),
                                        alignment: Alignment.center,
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: primaryColor,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return _ImageFallback(
                                        primaryColor: primaryColor,
                                        accentColor: accentColor,
                                      );
                                    },
                                  )
                                : _ImageFallback(
                                    primaryColor: primaryColor,
                                    accentColor: accentColor,
                                  ),
                          ),
                          if (offPct != null)
                            Positioned(
                              top: 10,
                              left: 10,
                              child: _DiscountBadge(
                                text: '-$offPct%',
                                primaryColor: primaryColor,
                              ),
                            ),
                        ],
                      ),
                    ),
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
                            Row(
                              children: [
                                Expanded(
                                  child: _RatingStars(
                                    value: rating,
                                    count: ratingCount,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _StockMiniPill(inStock: inStock),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _NairaTight(
                                  amount: f.format(price),
                                  bold: true,
                                  color: sale ? badgeColor : primaryColor,
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
                                            ? badgeColor.withOpacity(0.15)
                                            : accentColor.withOpacity(0.3),
                                        wish.contains(p)
                                            ? badgeColor.withOpacity(0.1)
                                            : accentColor.withOpacity(0.2),
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
                                          ? badgeColor
                                          : primaryColor,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [primaryColor, accentColor],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accentColor.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        cart.addToCartFast(p);

                                        final successColor = context
                                                .read<
                                                    CelebrationThemeProvider?>()
                                                ?.currentTheme
                                                .accentColor ??
                                            kGreen;

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text('$name added to cart!'),
                                            duration:
                                                const Duration(seconds: 1),
                                            backgroundColor: successColor,
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
                                            'Add',
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

class _ImageFallback extends StatelessWidget {
  final Color primaryColor;
  final Color accentColor;

  const _ImageFallback({
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: accentColor.withOpacity(0.3),
      alignment: Alignment.center,
      child: Icon(
        Icons.image,
        size: 40,
        color: primaryColor.withOpacity(0.5),
      ),
    );
  }
}

class _RatingStars extends StatelessWidget {
  final dynamic value;
  final int count;

  const _RatingStars({
    required this.value,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    final rating = double.tryParse(value?.toString() ?? '0') ?? 0;
    final hasRating = rating > 0;

    return Row(
      children: [
        ...List.generate(5, (index) {
          return Icon(
            index < rating.floor()
                ? Icons.star_rounded
                : (hasRating && index < rating
                    ? Icons.star_half_rounded
                    : Icons.star_border_rounded),
            color: hasRating ? Colors.amber[600] : Colors.grey.shade400,
            size: 14,
          );
        }),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            hasRating
                ? (count > 0
                    ? '(${count.toString()})'
                    : rating.toStringAsFixed(1))
                : 'New',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: hasRating ? Colors.grey.shade700 : Colors.grey.shade500,
            ),
          ),
        ),
      ],
    );
  }
}

class _StockMiniPill extends StatelessWidget {
  final bool inStock;

  const _StockMiniPill({required this.inStock});

  @override
  Widget build(BuildContext context) {
    final color = inStock ? kGreen : kRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        inStock ? 'In stock' : 'Out',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

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
          TextSpan(text: '\u20A6', style: style),
          TextSpan(text: amount, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final String text;
  final Color primaryColor;

  const _DiscountBadge({
    required this.text,
    required this.primaryColor,
  });

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
