import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'product_detail_page.dart';
import 'celebration_theme_provider.dart'; // Add this import

class HomePageModern extends StatefulWidget {
  final List<dynamic> products;
  final bool isLoading;
  final String title;
  final bool showTitle;
  final int maxItems;
  final VoidCallback? onSeeAllPressed;

  const HomePageModern({
    super.key,
    required this.products,
    this.isLoading = false,
    this.title = "",
    this.showTitle = true,
    this.maxItems = 10,
    this.onSeeAllPressed,
  });

  @override
  State<HomePageModern> createState() => _HomePageModernState();
}

class _HomePageModernState extends State<HomePageModern>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late List<dynamic> _visible;

  @override
  void initState() {
    super.initState();
    _filterProducts();
  }

  @override
  void didUpdateWidget(covariant HomePageModern oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.products != oldWidget.products ||
        widget.maxItems != oldWidget.maxItems) {
      _filterProducts();
    }
  }

  void _filterProducts() {
    final filtered = widget.products.where((p) {
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

    setState(() => _visible = filtered.take(widget.maxItems).toList());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Add theme provider
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF1565C0);
    final badgeColor = currentTheme?.badgeColor ?? Colors.redAccent;

    if (widget.isLoading) {
      return _buildLoadingSkeleton(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // parent scrolls
      children: [
        if (widget.showTitle) _buildHeader(context, primaryColor),
        if (_visible.isEmpty)
          _buildEmpty(context)
        else
          // no inner scrolling – parent SingleChildScrollView handles it
          ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _visible.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) => _ModernShowcaseCard(
              product: _visible[i],
              themeProvider: themeProvider,
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Color primaryColor) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (widget.onSeeAllPressed != null &&
              widget.products.length > widget.maxItems)
            TextButton.icon(
              onPressed: widget.onSeeAllPressed,
              icon: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
              label: const Text('See All', style: TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(
                backgroundColor: primaryColor, // Use theme color
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.hourglass_empty, size: 64, color: Colors.blueGrey),
              SizedBox(height: 12),
              Text("Nothing to showcase yet",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text("Try a different category or come back later.",
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}

// ============== Showcase Card ==============

class _ModernShowcaseCard extends StatelessWidget {
  final dynamic product;
  final CelebrationThemeProvider? themeProvider;

  const _ModernShowcaseCard({
    required this.product,
    this.themeProvider,
  });

  // ---- Rating helpers -------------------------------------------------
  double _parseRating(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  List<Widget> _buildStars(double rating, {double size = 12}) {
    final int full = rating.floor().clamp(0, 5);
    final bool half = (rating - full) >= 0.5 && full < 5;
    final int empty = 5 - full - (half ? 1 : 0);

    final stars = <Widget>[];
    for (var i = 0; i < full; i++) {
      stars.add(Icon(Icons.star, size: size, color: Colors.amber[600]));
    }
    if (half) {
      stars.add(Icon(Icons.star_half, size: size, color: Colors.amber[600]));
    }
    for (var i = 0; i < empty; i++) {
      stars.add(Icon(Icons.star_border, size: size, color: Colors.amber[600]));
    }
    return stars;
  }
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wish = context.watch<WishlistProvider>();
    final cart = context.watch<CartProvider>();

    // Get theme colors
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF1565C0);
    final badgeColor = currentTheme?.badgeColor ?? Colors.redAccent;

    final images = product['images'] as List?;
    final String? imageUrl =
        (images != null && images.isNotEmpty) ? images[0]['src']?.toString() : null;

    final String name = product['name']?.toString() ?? '';
    final bool isVariable = product['type'] == 'variable';
    final bool isInStock = (product['stock_status'] ?? 'instock') == 'instock';

    final double priceVal =
        double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    final double regVal =
        double.tryParse(product['regular_price']?.toString() ?? '0') ?? 0;
    final bool onSale = regVal > priceVal && regVal > 0;
    final nf = NumberFormat('#,##0', 'en_NG');

    // discount badge
    final int? offPct =
        onSale ? (((regVal - priceVal) / regVal) * 100).round() : null;

    // rating value
    final double rating = _parseRating(product['average_rating']);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _navigateToDetail(context, product),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.colorScheme.surface,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 4),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image
            if (imageUrl != null)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image,
                      color: Colors.grey, size: 32),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              )
            else
              Container(
                color: Colors.grey.shade200,
                alignment: Alignment.center,
                child: const Icon(Icons.image,
                    size: 40, color: Colors.blueGrey),
              ),

            // Gradient overlay to improve contrast (bottom)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 110,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Top bar: discount + wishlist
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  if (offPct != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor, // Use theme badge color
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2))
                        ],
                      ),
                      child: Text('-$offPct%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  const Spacer(),
                  Material(
                    color: Colors.white.withOpacity(0.9),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => wish.toggle(product),
                      icon: Icon(
                        wish.contains(product)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: wish.contains(product)
                            ? Colors.red
                            : Colors.blueGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ---- Bottom "glass" bar with Name + Stars + Price + CTA ----
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                height: 64, // a touch taller to fit stars comfortably
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // Name + Stars + Price (stacked)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // ⭐ icons only (no counts / number)
                          Row(children: _buildStars(rating, size: 12)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              // price (unclippable)
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    children: [
                                      const Text(
                                        '\u20A6',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        nf.format(priceVal),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (onSale) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '\u20A6${nf.format(regVal)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    decoration: TextDecoration.lineThrough,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // CTA (thumb-friendly, high-contrast)
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 110, minHeight: 40),
                      child: ElevatedButton.icon(
                        onPressed: isInStock
                            ? () {
                                if (isVariable) {
                                  _navigateToDetail(context, product);
                                } else {
                                  cart.toggle(product);
                                }
                              }
                            : null,
                        icon: Icon(
                          isVariable
                              ? Icons.tune
                              : (cart.contains(product)
                                  ? Icons.check
                                  : Icons.shopping_cart),
                          size: 16,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isVariable
                                ? "Select Options"
                                : (cart.contains(product)
                                    ? "In Cart"
                                    : "Add to Cart"),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isVariable
                              ? Colors.orange
                              : (cart.contains(product)
                                  ? Colors.green
                                  : primaryColor), // Use theme color
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ----------------------------------------------------------------
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context, dynamic p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailPage(product: p)),
    );
  }
}