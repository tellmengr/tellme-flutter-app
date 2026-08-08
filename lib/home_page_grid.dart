import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'product_detail_page.dart';
import 'celebration_theme_provider.dart';

enum SortType { newest, priceLow, priceHigh, rating, popularity }

class AdvancedProductGridView extends StatefulWidget {
  final List<dynamic> products;
  final String title;
  final bool showTitle;
  final bool showFilters;
  final bool isLoading;
  final int maxItems;
  final VoidCallback? onSeeAllPressed;
  final ScrollController? parentScrollController;
  final int pageSize;
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final bool canLoadMore;

  const AdvancedProductGridView({
    super.key,
    required this.products,
    this.title = "",
    this.showTitle = true,
    this.showFilters = false,
    this.isLoading = false,
    this.maxItems = 0,
    this.onSeeAllPressed,
    this.parentScrollController,
    this.pageSize = 12,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.canLoadMore = false,
  });

  @override
  State<AdvancedProductGridView> createState() =>
      _AdvancedProductGridViewState();
}

class _AdvancedProductGridViewState extends State<AdvancedProductGridView>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  SortType _sort = SortType.newest;
  List<dynamic> _all = [];
  int _limit = 0;
  int _lastInputLen = 0;
  bool _askedForMore = false;

  @override
  void initState() {
    super.initState();
    _lastInputLen = widget.products.length;
    _recomputeAndResetLimit();
    widget.parentScrollController?.addListener(_maybeLoadMoreFromParent);
  }

  @override
  void didUpdateWidget(covariant AdvancedProductGridView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.parentScrollController != widget.parentScrollController) {
      oldWidget.parentScrollController
          ?.removeListener(_maybeLoadMoreFromParent);
      widget.parentScrollController?.addListener(_maybeLoadMoreFromParent);
    }

    final inputLenChanged = widget.products.length != _lastInputLen;
    final instanceChanged = !identical(widget.products, oldWidget.products);

    if (instanceChanged || inputLenChanged) {
      final oldTotal = _all.length;
      _lastInputLen = widget.products.length;
      _recomputeAndPreserveProgress(oldTotal: oldTotal);
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

  void _recomputeAndResetLimit() {
    _all = _filterAndSort(widget.products);
    _limit = _initialLimit();
    setState(() {});
  }

  void _recomputeAndPreserveProgress({required int oldTotal}) {
    final oldLimit = _limit;
    _all = _filterAndSort(widget.products);
    final newTotal = _all.length;

    int nextLimit = oldLimit.clamp(0, newTotal);
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
    final filtered = source.where((p) {
      if (p == null) return false;

      final name = p['name']?.toString().trim() ?? '';
      final stock = p['stock_status']?.toString().toLowerCase() ?? '';

      if (name.isEmpty) return false;
      if (stock == 'outofstock') return false;

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
        filtered.sort(
            (a, b) => _num(b['total_sales']).compareTo(_num(a['total_sales'])));
        break;
      case SortType.newest:
      default:
        filtered.sort((a, b) {
          final da = DateTime.tryParse(a['date_created']?.toString() ?? '');
          final db = DateTime.tryParse(b['date_created']?.toString() ?? '');
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
    }

    return filtered;
  }

  num _num(dynamic v) => num.tryParse(v?.toString() ?? '0') ?? 0;

  void _maybeLoadMoreFromParent() {
    final c = widget.parentScrollController;
    if (c == null) return;

    if (c.position.pixels >= c.position.maxScrollExtent - 120) {
      if (_limit < _all.length) {
        setState(() {
          _limit = (_limit + widget.pageSize).clamp(0, _all.length);
        });
        return;
      }

      if (widget.canLoadMore && !widget.isLoadingMore && !_askedForMore) {
        _askedForMore = true;
        widget.onLoadMore?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF1565C0);

    if (widget.isLoading && _all.isEmpty) {
      return _buildLoading(context, primaryColor);
    }

    final theme = Theme.of(context);
    final visible = (_limit <= _all.length) ? _all.take(_limit).toList() : _all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (widget.onSeeAllPressed != null)
                  TextButton.icon(
                    onPressed: widget.onSeeAllPressed,
                    icon: const Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'See All',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.showFilters)
          _buildFilterRow(theme, primaryColor, accentColor),
        if (visible.isEmpty)
          _buildEmpty(context)
        else
          GridView.builder(
            key: ValueKey('${_sort}_${visible.length}'),
            padding: const EdgeInsets.all(12),
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            cacheExtent: 800,
            itemCount: visible.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.55,
            ),
            itemBuilder: (_, i) => ProductCard(
              product: visible[i],
              index: i,
              themeProvider: themeProvider,
            ),
          ),
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

  Widget _buildFilterRow(
    ThemeData theme,
    Color primaryColor,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip(
                'Newest', SortType.newest, Icons.new_releases, primaryColor),
            _filterChip('Low Price', SortType.priceLow, Icons.trending_down,
                primaryColor),
            _filterChip('High Price', SortType.priceHigh, Icons.trending_up,
                primaryColor),
            _filterChip('Top Rated', SortType.rating, Icons.star, primaryColor),
            _filterChip('Popular', SortType.popularity,
                Icons.local_fire_department, primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    String label,
    SortType type,
    IconData icon,
    Color primaryColor,
  ) {
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

  Widget _buildLoading(BuildContext context, Color primaryColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primaryColor),
          const SizedBox(height: 12),
          const Text(
            "Loading products...",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.blueGrey),
            SizedBox(height: 12),
            Text(
              "No Products Found",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            Text(
              "Try adjusting your filters.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatefulWidget {
  final dynamic product;
  final int index;
  final CelebrationThemeProvider? themeProvider;

  const ProductCard({
    super.key,
    required this.product,
    required this.index,
    this.themeProvider,
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
      duration: Duration(milliseconds: 400 + widget.index * 50),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _readImageUrl(dynamic value) {
    final text = value?.toString().trim() ?? "";
    return text.isEmpty ? null : text;
  }

  String? _productImageUrl(dynamic product) {
    if (product is! Map) return null;

    final images = product["images"];
    if (images is List) {
      for (final item in images) {
        if (item is String) {
          final url = _readImageUrl(item);
          if (url != null) return url;
        }

        if (item is Map) {
          final url = _readImageUrl(
            item["src"] ??
                item["url"] ??
                item["image"] ??
                item["imageUrl"] ??
                item["thumbnail"] ??
                item["thumbnailUrl"],
          );

          if (url != null) return url;
        }
      }
    }

    return _readImageUrl(
      product["imageUrl"] ??
          product["image_url"] ??
          product["image"] ??
          product["thumbnailUrl"] ??
          product["thumbnail_url"] ??
          product["thumbnail"] ??
          product["featuredImage"] ??
          product["featured_image"],
    );
  }

  double _ratingValue(dynamic product) {
    if (product is! Map) return 0;

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

  int _ratingCount(dynamic product) {
    if (product is! Map) return 0;

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

  Widget _ratingRow(double rating, int ratingCount) {
    final hasRating = rating > 0;

    return Row(
      children: [
        ...List.generate(5, (index) {
          final icon = index + 1 <= rating.floor()
              ? Icons.star_rounded
              : (hasRating && index + 1 - rating <= 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_border_rounded);
          return Icon(
            icon,
            color: hasRating ? Colors.amber[600] : Colors.grey.shade400,
            size: 14,
          );
        }),
        if (ratingCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '$ratingCount',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final wish = Provider.of<WishlistProvider>(context);
    final p = widget.product;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final cardBg = isDark ? theme.colorScheme.surface : Colors.white;
    final softShadowColor =
        isDark ? Colors.black.withOpacity(0.5) : Colors.black12;

    final currentTheme = widget.themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final badgeColor = currentTheme?.badgeColor ?? Colors.redAccent;

    final isVariable = p['type'] == 'variable';
    final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
    final reg = double.tryParse(p['regular_price']?.toString() ?? '0') ?? 0;
    final sale = reg > price && reg > 0;
    final int? offPct = sale ? (((reg - price) / reg) * 100).round() : null;
    final rating = _ratingValue(p);
    final ratingCount = _ratingCount(p);

    final img = _productImageUrl(p);
    final f = NumberFormat("#,##0", "en_US");

    return FadeTransition(
      opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductDetailPage(product: p),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: softShadowColor,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
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
                            top: Radius.circular(18),
                          ),
                          child: img != null
                              ? Image.network(
                                  img,
                                  key: ValueKey(img),
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.grey.shade200,
                                      alignment: Alignment.center,
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: primaryColor,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey.shade100,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.broken_image,
                                      size: 36,
                                      color: Colors.grey,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.image, size: 40),
                                  ),
                                ),
                        ),
                        if (offPct != null)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: _DiscountBadge(
                              text: "-$offPct%",
                              badgeColor: badgeColor,
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
                            p['name']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: textColor,
                            ),
                          ),
                          const Spacer(),
                          _ratingRow(rating, ratingCount),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _NairaTight(
                                amount: f.format(price),
                                bold: true,
                                color: sale ? Colors.redAccent : primaryColor,
                              ),
                              if (sale) ...[
                                const SizedBox(width: 8),
                                _NairaTight(
                                  amount: f.format(reg),
                                  bold: false,
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  strike: true,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () => wish.toggle(p),
                                icon: Icon(
                                  wish.contains(p)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: wish.contains(p)
                                      ? Colors.red
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Expanded(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 38,
                                    minWidth: 100,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (isVariable) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ProductDetailPage(product: p),
                                          ),
                                        );
                                      } else {
                                        cart.addToCartFast(p);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${p['name']} added to cart.',
                                            ),
                                            duration:
                                                const Duration(seconds: 1),
                                            backgroundColor: Colors.green,
                                            behavior: SnackBarBehavior.floating,
                                            margin: const EdgeInsets.all(16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isVariable
                                          ? Colors.orange
                                          : primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            isVariable
                                                ? Icons.tune
                                                : Icons.shopping_cart,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            "Add to Cart",
                                            style: TextStyle(fontSize: 13),
                                          ),
                                        ],
                                      ),
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
    );
  }
}

class _ShowMoreButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final Color primaryColor;

  const _ShowMoreButton({
    super.key,
    required this.onTap,
    this.label = "Show more",
    required this.primaryColor,
  });

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
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: primaryColor,
          ),
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
    final theme = Theme.of(context);

    final style = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: fontSize,
      color: color ?? theme.colorScheme.onSurface,
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
  final Color badgeColor;

  const _DiscountBadge({
    required this.text,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
