import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'product_detail_page.dart';
import 'celebration_theme_provider.dart'; // Add this import

class HomePageStaggered extends StatefulWidget {
  final List<dynamic> products;
  final bool isLoading;
  final String title;
  final bool showTitle;

  /// When 0 (default), starts with `pageSize`
  final int maxItems;

  final VoidCallback? onSeeAllPressed;

  // 🔁 Infinite-scroll hooks (same idea as AdvancedProductGridView)
  final ScrollController? parentScrollController;
  final int pageSize;
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final bool canLoadMore;

  const HomePageStaggered({
    super.key,
    required this.products,
    this.isLoading = false,
    this.title = "",
    this.showTitle = true,
    this.maxItems = 0,
    this.onSeeAllPressed,
    this.parentScrollController,
    this.pageSize = 20,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.canLoadMore = false,
  });

  @override
  State<HomePageStaggered> createState() => _HomePageStaggeredState();
}

class _HomePageStaggeredState extends State<HomePageStaggered>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Same pattern as grid:
  List<dynamic> _all = [];
  int _limit = 0;
  int _lastInputLen = 0;
  int _lastTotal = 0;
  bool _askedForMore = false;

  @override
  void initState() {
    super.initState();
    _lastInputLen = widget.products.length;
    _recomputeAndResetLimit();
    widget.parentScrollController?.addListener(_maybeLoadMoreFromParent);
  }

  @override
  void didUpdateWidget(covariant HomePageStaggered oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Re-attach if controller changed
    if (oldWidget.parentScrollController != widget.parentScrollController) {
      oldWidget.parentScrollController?.removeListener(_maybeLoadMoreFromParent);
      widget.parentScrollController?.addListener(_maybeLoadMoreFromParent);
    }

    final inputLenChanged = widget.products.length != _lastInputLen;
    final instanceChanged = !identical(widget.products, oldWidget.products);

    if (instanceChanged || inputLenChanged) {
      _lastInputLen = widget.products.length;
      _recomputeAndPreserveProgress(oldTotal: _all.length);
    }

    if (oldWidget.isLoadingMore && !widget.isLoadingMore) {
      _askedForMore = false;
    }
  }

  @override
  void dispose() {
    widget.parentScrollController?.removeListener(_maybeLoadMoreFromParent);
    super.dispose();
  }

  // ---------- Filtering & limiting ----------

  void _recomputeAndResetLimit() {
    _all = _filter(widget.products);
    _lastTotal = _all.length;
    _limit = _initialLimit();
    setState(() {});
  }

  void _recomputeAndPreserveProgress({required int oldTotal}) {
    final oldLimit = _limit;
    _all = _filter(widget.products);
    final newTotal = _all.length;

    int nextLimit = oldLimit.clamp(0, newTotal);

    // If total increased (new server page arrived), reveal one extra page locally
    if (newTotal > oldTotal) {
      nextLimit = (nextLimit + widget.pageSize).clamp(0, newTotal);
    }
    if (nextLimit == 0) nextLimit = _initialLimit();

    _limit = nextLimit;
    _lastTotal = newTotal;
    setState(() {});
  }

  int _initialLimit() {
    final start = (widget.maxItems <= 0) ? widget.pageSize : widget.maxItems;
    return start.clamp(0, _all.length);
  }

  List<dynamic> _filter(List<dynamic> source) {
    final filtered = source.where((p) {
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

    // newest-ish
    try {
      filtered.sort((a, b) {
        final da = DateTime.tryParse(a['date_created']?.toString() ?? '');
        final db = DateTime.tryParse(b['date_created']?.toString() ?? '');
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
    } catch (_) {}
    return filtered;
  }

  // ---------- Infinite reveal & load-more ----------

  void _maybeLoadMoreFromParent() {
    final c = widget.parentScrollController;
    if (c == null) return;

    if (c.position.pixels >= c.position.maxScrollExtent - 120) {
      // 1) Reveal more locally
      if (_limit < _all.length) {
        setState(() {
          _limit = (_limit + widget.pageSize).clamp(0, _all.length);
        });
        return;
      }
      // 2) Ask parent for next page
      if (widget.canLoadMore && !widget.isLoadingMore && !_askedForMore) {
        _askedForMore = true;
        widget.onLoadMore?.call();
      }
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Add theme provider
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF1565C0);
    final badgeColor = currentTheme?.badgeColor ?? Colors.redAccent;

    if (widget.isLoading && _all.isEmpty) {
      return _buildLoadingSkeleton(context);
    }

    final visible = (_limit <= _all.length) ? _all.take(_limit).toList() : _all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // parent scrolls
      children: [
        if (widget.showTitle) _buildHeader(context, primaryColor),

        if (visible.isEmpty)
          _buildEmpty(context)
        else
          // DO NOT scroll this: parent handles scroll
          MasonryGridView.count(
            key: ValueKey('staggered_${visible.length}'),
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: visible.length,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (_, i) => _StaggeredCard(
              product: visible[i],
              index: i,
              themeProvider: themeProvider,
            ),
          ),

        // Local "show more" reveal if we still have hidden items
        if (_limit < _all.length)
          _ShowMoreButton(
            onTap: () {
              setState(() {
                _limit = (_limit + widget.pageSize).clamp(0, _all.length);
              });
            },
            primaryColor: primaryColor,
          )
        else if (widget.isLoadingMore)
          _FooterLoader(primaryColor: primaryColor)
        else if (widget.canLoadMore && widget.onLoadMore != null)
          _ShowMoreButton(
            label: "Load more products",
            onTap: () {
              if (!_askedForMore) {
                _askedForMore = true;
                widget.onLoadMore?.call();
              }
            },
            primaryColor: primaryColor,
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
              widget.products.length >
                  (widget.maxItems == 0 ? widget.pageSize : widget.maxItems))
            TextButton.icon(
              onPressed: widget.onSeeAllPressed,
              icon: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
              label: const Text('See All', style: TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(
                backgroundColor: primaryColor, // Use theme color
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) => MasonryGridView.count(
        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, i) => Container(
          height: 180.0 + (i % 3) * 40.0,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );

  Widget _buildEmpty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.hourglass_empty, size: 64, color: Colors.blueGrey),
              SizedBox(height: 12),
              Text("No items to show", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text("Try a different category or come back later.",
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}

// ============== Staggered Card (grid-style info layout) ==============

class _StaggeredCard extends StatelessWidget {
  final dynamic product;
  final int index;
  final CelebrationThemeProvider? themeProvider;

  const _StaggeredCard({
    required this.product,
    required this.index,
    this.themeProvider,
  });

  double _parseRating(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  List<Widget> _buildStars(double rating, {double size = 14}) {
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
    final bool inCart = cart.contains(product);

    final double priceVal =
        double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    final double regVal =
        double.tryParse(product['regular_price']?.toString() ?? '0') ?? 0;
    final bool onSale = regVal > priceVal && regVal > 0;
    final nf = NumberFormat('#,##0', 'en_NG');

    final double cardImageHeight = 150.0 + (index % 3) * 30.0; // staggered look
    final int? offPct =
        onSale ? (((regVal - priceVal) / regVal) * 100).round() : null;

    final double rating = _parseRating(product['average_rating']);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _navigateToDetail(context, product),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---------- Image with wishlist & discount ----------
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    height: cardImageHeight,
                    width: double.infinity,
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey, size: 28),
                            ),
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            },
                          )
                        : Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image,
                                size: 32, color: Colors.blueGrey),
                          ),
                  ),
                ),
                // discount
                if (offPct != null)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor, // Use theme badge color
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                        ],
                      ),
                      child: Text(
                        '-$offPct%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                // wishlist
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: Colors.white.withOpacity(0.9),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => wish.toggle(product),
                      icon: Icon(
                        wish.contains(product) ? Icons.favorite : Icons.favorite_border,
                        color: wish.contains(product) ? Colors.red : Colors.blueGrey,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ---------- Info & CTA (grid-style) ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // name
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ⭐ icons only
                  Row(children: _buildStars(rating, size: 14)),
                  const SizedBox(height: 8),

                  // Price on its own row (bigger)
                  Row(
                    children: [
                      const Text(
                        '\u20A6',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.25,
                        ),
                      ),
                      Text(
                        nf.format(priceVal),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.25,
                          color: onSale ? Colors.redAccent : primaryColor, // Use theme color
                        ),
                      ),
                      if (onSale) ...[
                        const SizedBox(width: 8),
                        Text(
                          '\u20A6${nf.format(regVal)}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Full-width pill button (same as grid)
                  _CartPillButton(
                    isVariable: isVariable,
                    inCart: inCart,
                    onPressed: !isInStock
                        ? null
                        : () {
                            if (isVariable) {
                              _navigateToDetail(context, product);
                            } else {
                              cart.toggle(product);
                            }
                          },
                    themeProvider: themeProvider,
                  ),
                ],
              ),
            ),
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

// ------- Shared mini widgets -------

class _ShowMoreButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String label;
  final Color primaryColor;

  const _ShowMoreButton({
    Key? key,
    required this.onTap,
    this.label = "Show more",
    required this.primaryColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18.0),
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(Icons.expand_more, color: primaryColor),
          label: Text(label, style: TextStyle(color: primaryColor)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
      ),
    );
  }
}

class _FooterLoader extends StatelessWidget {
  final Color primaryColor;

  const _FooterLoader({required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 18),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
        ),
      ),
    );
  }
}

/// 🔵/🟣/🟢 Reusable pill button to mirror grid style
/// - Add to Cart  => blue
/// - Select (variable) => deep pink
/// - In Cart => green
class _CartPillButton extends StatelessWidget {
  final bool isVariable;
  final bool inCart;
  final VoidCallback? onPressed;
  final CelebrationThemeProvider? themeProvider;

  const _CartPillButton({
    Key? key,
    required this.isVariable,
    required this.inCart,
    required this.onPressed,
    this.themeProvider,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Get theme colors
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);

    // Updated brand colors with theme integration
    final Color blue = primaryColor; // Add to Cart - use theme primary color
    const Color deepPink = Color(0xFFC2185B); // Select - deep pink
    const Color green = Colors.green;        // In Cart - green

    final bool showGreen = inCart && !isVariable;
    final Color bg = showGreen ? green : (isVariable ? deepPink : blue);
    final IconData icon =
        showGreen ? Icons.check : (isVariable ? Icons.tune : Icons.shopping_cart);
    final String label =
        showGreen ? 'In Cart' : (isVariable ? 'Select Type' : 'Add to Cart');

    return SizedBox(
      width: double.infinity,
      height: 42, // Slightly taller for better appearance
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 2,
          backgroundColor: bg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Round square
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // White icon container with round square border
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6), // Round square
              ),
              child: Icon(icon, size: 16, color: bg),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}