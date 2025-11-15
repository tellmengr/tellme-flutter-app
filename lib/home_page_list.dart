import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'product_detail_page.dart';
import 'celebration_theme_provider.dart'; // Add this import

enum SortType { newest, priceLow, priceHigh, rating, popularity }

class AdvancedProductListView extends StatefulWidget {
  final List<dynamic> products;
  final String title;
  final bool showTitle;

  /// When 0, we start with `pageSize` (recommended).
  final int maxItems;

  final VoidCallback? onSeeAllPressed;
  final bool showFilters;
  final bool isLoading;

  // 🔁 Infinite scroll hooks (optional)
  final ScrollController? parentScrollController;
  final int pageSize;
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final bool canLoadMore;

  const AdvancedProductListView({
    super.key,
    required this.products,
    this.title = "",
    this.showTitle = true,
    this.maxItems = 0, // 👈 align with grid default
    this.onSeeAllPressed,
    this.showFilters = false,
    this.isLoading = false,
    this.parentScrollController,
    this.pageSize = 12,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.canLoadMore = false,
  });

  @override
  State<AdvancedProductListView> createState() =>
      _AdvancedProductListViewState();
}

class _AdvancedProductListViewState extends State<AdvancedProductListView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  SortType _sort = SortType.newest;

  // Full filtered list and current reveal size
  List<dynamic> _all = [];
  int _limit = 0;

  // Detect in-place mutations (append to same List)
  int _lastInputLen = 0;

  // Debounce parent load-more
  bool _askedForMore = false;

  @override
  void initState() {
    super.initState();
    _lastInputLen = widget.products.length;
    _recomputeAndResetLimit();
    widget.parentScrollController?.addListener(_maybeLoadMoreFromParent);
  }

  @override
  void didUpdateWidget(covariant AdvancedProductListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Re-wire scroll listener if controller instance changed
    if (oldWidget.parentScrollController != widget.parentScrollController) {
      oldWidget.parentScrollController?.removeListener(_maybeLoadMoreFromParent);
      widget.parentScrollController?.addListener(_maybeLoadMoreFromParent);
    }

    final instanceChanged = !identical(widget.products, oldWidget.products);
    final lengthChanged = widget.products.length != _lastInputLen;

    if (instanceChanged || lengthChanged || widget.maxItems != oldWidget.maxItems) {
      _lastInputLen = widget.products.length;
      _recomputeAndPreserveProgress(oldTotal: _all.length);
    }

    if (oldWidget.isLoadingMore && !widget.isLoadingMore) {
      _askedForMore = false; // reset debounce when parent finished loading
    }
  }

  @override
  void dispose() {
    widget.parentScrollController?.removeListener(_maybeLoadMoreFromParent);
    super.dispose();
  }

  // ---------- Filtering, sorting, limiting ----------

  void _recomputeAndResetLimit() {
    _all = _filterAndSort(widget.products);
    _limit = _initialLimit();
    setState(() {});
  }

  void _recomputeAndPreserveProgress({required int oldTotal}) {
    final oldLimit = _limit;
    _all = _filterAndSort(widget.products);
    final newTotal = _all.length;

    // Keep at least what we already revealed
    int nextLimit = oldLimit.clamp(0, newTotal);

    // If new items arrived (e.g., page 2), auto-reveal one more "page"
    if (newTotal > oldTotal) {
      nextLimit = (nextLimit + widget.pageSize).clamp(0, newTotal);
    }

    if (nextLimit == 0) nextLimit = _initialLimit();
    _limit = nextLimit;
    setState(() {});
  }

  int _initialLimit() {
    final start = (widget.maxItems <= 0) ? widget.pageSize : widget.maxItems;
    return start.clamp(0, _all.length);
  }

  List<dynamic> _filterAndSort(List<dynamic> source) {
    // 🚫 Hide items without price, OOS, no image, or empty name
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

    return filtered;
  }

  num _num(dynamic v) => num.tryParse(v?.toString() ?? '0') ?? 0;

  // ---------- Infinite reveal & load-more ----------

  void _maybeLoadMoreFromParent() {
    final c = widget.parentScrollController;
    if (c == null) return;

    if (c.position.pixels >= c.position.maxScrollExtent - 120) {
      // 1) Reveal more from current list
      if (_limit < _all.length) {
        setState(() {
          _limit = (_limit + widget.pageSize).clamp(0, _all.length);
        });
        return;
      }

      // 2) Ask parent to fetch next page
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

  if (widget.isLoading && _all.isEmpty) {
    return _buildLoadingList(primaryColor);
  }

  final visible =
      (_limit <= _all.length) ? _all.take(_limit).toList() : _all;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.showTitle)
        _buildSectionHeader(context, primaryColor),
      if (widget.showFilters)
        _buildFilterRow(context, primaryColor),

      if (visible.isEmpty)
        _buildEmptyState(context)
      else
        ListView.separated(
          key: ValueKey('list_${_sort}_${visible.length}'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: visible.length,
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => AdvancedProductListCard(
            product: visible[i],
            index: i,
            themeProvider: themeProvider,
          ),
        ),

      // Footer controls
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

Widget _buildSectionHeader(BuildContext context, Color primaryColor) {
  final theme = Theme.of(context);
  final showSeeAll =
      widget.onSeeAllPressed != null && widget.products.length > _limit;

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              // 👇 removed the "$count products" line
            ],
          ),
        ),
        if (showSeeAll)
          TextButton.icon(
            onPressed: widget.onSeeAllPressed,
            icon: const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.white),
            label: const Text(
              "See All",
              style: TextStyle(color: Colors.white),
            ),
            style: TextButton.styleFrom(
              backgroundColor: primaryColor,
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


  Widget _buildFilterRow(BuildContext context, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('Newest', SortType.newest, Icons.new_releases, primaryColor),
            _filterChip('Low Price', SortType.priceLow, Icons.trending_down, primaryColor),
            _filterChip('High Price', SortType.priceHigh, Icons.trending_up, primaryColor),
            _filterChip('Top Rated', SortType.rating, Icons.star, primaryColor),
            _filterChip('Popular', SortType.popularity, Icons.local_fire_department, primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, SortType type, IconData icon, Color primaryColor) {
    final selected = _sort == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        avatar: Icon(
          icon,
          size: 16,
          color: selected ? Colors.white : Colors.blueGrey,
        ),
        selected: selected,
        onSelected: (_) {
          setState(() => _sort = type);
          _recomputeAndResetLimit();
        },
        selectedColor: primaryColor,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.blueGrey,
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: Colors.grey.shade100,
        elevation: selected ? 2 : 0,
      ),
    );
  }

  Widget _buildLoadingList(Color primaryColor) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.shopping_bag_outlined,
                  size: 64, color: Colors.blueGrey),
              SizedBox(height: 12),
              Text("No Products Found",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text("Try adjusting your filters.",
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------------
// PRODUCT LIST CARD
// ------------------------------------------------------------------
class AdvancedProductListCard extends StatefulWidget {
  final dynamic product;
  final int index;
  final CelebrationThemeProvider? themeProvider;

  const AdvancedProductListCard({
    super.key,
    required this.product,
    required this.index,
    this.themeProvider,
  });

  @override
  State<AdvancedProductListCard> createState() =>
      _AdvancedProductListCardState();
}

class _AdvancedProductListCardState extends State<AdvancedProductListCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
    if (half) stars.add(Icon(Icons.star_half, size: size, color: Colors.amber[600]));
    for (var i = 0; i < empty; i++) {
      stars.add(Icon(Icons.star_border, size: size, color: Colors.amber[600]));
    }
    return stars;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.product;

    // Get theme colors
    final currentTheme = widget.themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF1565C0);

    final images = p['images'] as List?;
    final String? imageUrl =
        (images != null && images.isNotEmpty) ? images[0]['src']?.toString() : null;

    final double rating = _parseRating(p['average_rating']);
    final bool isInStock = (p['stock_status'] ?? 'instock') == 'instock';
    final bool isVariable = p['type'] == 'variable';

    final cart = Provider.of<CartProvider>(context);
    final wish = Provider.of<WishlistProvider>(context);

    final double priceVal = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
    final double regVal   = double.tryParse(p['regular_price']?.toString() ?? '0') ?? 0;
    final bool onSale = regVal > priceVal && regVal > 0;
    final nf = NumberFormat('#,##0', 'en_NG');

    return Hero(
      tag: 'product_list_${p['id']}_${widget.index}',
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTapDown: (_) => _controller.forward(),
              onTapUp:   (_) => _controller.reverse(),
              onTapCancel: () => _controller.reverse(),
              onTap: () => _navigateToDetail(context),
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    _buildImage(imageUrl, primaryColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // NAME
                            Text(
                              p['name']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // ⭐ RATING
                            Row(children: _buildStars(rating, size: 14)),
                            const SizedBox(height: 6),

                            // 💰 Price + Wishlist + Button
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final double maxWidth = constraints.maxWidth;
                                // Improved button sizing - larger but responsive
                                final double targetButtonWidth =
                                    maxWidth < 360 ? 120 : 140; // Increased from 110/130
                                final double buttonHeight = 40; // Increased height

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // PRICE - Made more compact
                                    Flexible(
                                      flex: 2,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(right: 2),
                                              child: Text.rich(
                                                TextSpan(
                                                  children: [
                                                    const TextSpan(
                                                      text: '\u20A6',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                        fontFamily: 'Roboto',
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: nf.format(priceVal),
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w700,
                                                        fontFamily: 'Roboto',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                maxLines: 1,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                                textWidthBasis: TextWidthBasis.longestLine,
                                              ),
                                            ),
                                            if (onSale) ...[
                                              const SizedBox(width: 6), // Reduced spacing
                                              Text.rich(
                                                TextSpan(
                                                  children: [
                                                    const TextSpan(
                                                      text: '\u20A6',
                                                      style: TextStyle(
                                                        fontSize: 11, // Slightly smaller
                                                        fontWeight: FontWeight.w400,
                                                        color: Colors.grey,
                                                        decoration: TextDecoration.lineThrough,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: nf.format(regVal),
                                                      style: const TextStyle(
                                                        fontSize: 11, // Slightly smaller
                                                        fontWeight: FontWeight.w400,
                                                        color: Colors.grey,
                                                        decoration: TextDecoration.lineThrough,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                maxLines: 1,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 4), // Reduced spacing

                                    // Wishlist button - made more compact
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(4), // Reduced padding
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      onPressed: () => wish.toggle(p),
                                      icon: Icon(
                                        wish.contains(p)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: wish.contains(p)
                                            ? Colors.red
                                            : Colors.blueGrey,
                                        size: 18, // Slightly smaller
                                      ),
                                    ),

                                    const SizedBox(width: 4), // Reduced spacing

                                    // ADD TO CART BUTTON - Improved sizing
                                    Flexible(
                                      flex: 3, // Give button more space priority
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: buttonHeight,
                                          maxHeight: buttonHeight,
                                          minWidth: targetButtonWidth,
                                          maxWidth: targetButtonWidth,
                                        ),
                                        child: ElevatedButton(
                                          onPressed: isInStock
                                              ? () {
                                                  if (isVariable) {
                                                    _navigateToDetail(context);
                                                  } else {
                                                    final cart = Provider.of<CartProvider>(context, listen: false);
                                                    cart.toggle(p);
                                                  }
                                                }
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isVariable
                                                ? Colors.orange
                                                : (cart.contains(p)
                                                    ? Colors.green
                                                    : primaryColor), // Use theme color
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 10), // Better padding
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isVariable
                                                      ? Icons.tune
                                                      : (cart.contains(p)
                                                          ? Icons.check
                                                          : Icons.shopping_cart),
                                                  size: 16, // Slightly larger icon
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  isVariable
                                                      ? "Select Options"
                                                      : (cart.contains(p)
                                                          ? "In Cart"
                                                          : "Add to Cart"),
                                                  style: const TextStyle(
                                                    fontSize: 13, // Slightly larger text
                                                    fontWeight: FontWeight.w600,
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
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String? url, Color primaryColor) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
      ),
      child: SizedBox(
        width: 120,
        height: double.infinity,
        child: url != null
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFEFF3F8),
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const ColoredBox(
                    color: Color(0xFFEFF3F8),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
              )
            : const ColoredBox(
                color: Color(0xFFEFF3F8),
                child: Icon(Icons.image, color: Colors.grey),
              ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(product: widget.product),
      ),
    );
  }
}

class _ShowMoreButton extends StatelessWidget {
  final VoidCallback onTap;
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