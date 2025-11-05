// home_page_carousel.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'product_detail_page.dart';
import 'celebration_theme_provider.dart'; // Add this import

class ProductSnapCarousel extends StatefulWidget {
  final List<dynamic> products;
  final bool isLoading;
  final double height;
  final Duration autoPlayInterval;
  final double topGap;

  // ⬇️ New: server-paging hooks (optional)
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final bool canLoadMore;

  const ProductSnapCarousel({
    super.key,
    required this.products,
    this.isLoading = false,
    this.height = 330,
    this.autoPlayInterval = Duration.zero,
    this.topGap = 20,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.canLoadMore = false,
  });

  @override
  State<ProductSnapCarousel> createState() => _ProductSnapCarouselState();
}

class _ProductSnapCarouselState extends State<ProductSnapCarousel> {
  late final PageController _controller;
  int _current = 1; // first REAL item (after left ghost)
  Timer? _timer;
  bool _askedForMore = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      viewportFraction: 0.42,
      initialPage: 1,
      keepPage: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.hasClients) {
        _controller.jumpToPage(1);
        setState(() => _current = 1);
      }
    });

    if (widget.autoPlayInterval.inMilliseconds > 0) {
      _timer = Timer.periodic(widget.autoPlayInterval, (_) {
        if (!mounted || !_controller.hasClients || widget.products.isEmpty) return;
        final total = _displayList().length;
        final next = (_current + 1) % total;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant ProductSnapCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoadingMore && !widget.isLoadingMore) {
      _askedForMore = false; // allow another fetch
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------

  List<dynamic> _filtered() {
    return widget.products.where((p) {
      if (p == null) return false;
      final price = double.tryParse(p['price']?.toString() ?? '') ?? 0;
      final name = (p['name']?.toString() ?? '').trim();
      final images = p['images'];
      final stock = (p['stock_status']?.toString() ?? '').toLowerCase();
      return price > 0 &&
          name.isNotEmpty &&
          stock != 'outofstock' &&
          images != null &&
          (images is List && images.isNotEmpty);
    }).toList();
  }

  /// Ghost pages + optional trailing loader page.
  List<dynamic?> _displayList() {
    final items = _filtered();
    final list = <dynamic?>[null, ...items, null];
    if (widget.canLoadMore) list.add('__loader__');
    return list;
  }

  void _maybeAskForMore(int pageIndex) {
    // if user reached the last **real** page (before loader), ask parent to load
    final items = _filtered();
    final lastRealIndex = 1 + items.length - 1; // ghosts at 0 and items.length+1
    if (pageIndex >= lastRealIndex && widget.canLoadMore && !_askedForMore) {
      _askedForMore = true;
      widget.onLoadMore?.call();
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    // Add theme provider
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF1565C0);

    if (widget.isLoading) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    final filtered = _filtered();
    if (filtered.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Text("No products available.")),
      );
    }

    final display = _displayList();

    // IMPORTANT: Size internal children from actual constraints to avoid overflow.
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double dotsArea = 18; // height for dots/loader row
          final double totalH = constraints.maxHeight;
          final double topGap = widget.topGap.clamp(0, totalH);
          final double pageH = (totalH - topGap - dotsArea).clamp(180.0, totalH);

          return Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              SizedBox(height: topGap),

              // PageView fits exactly in the remaining height budget
              SizedBox(
                height: pageH,
                child: PageView.builder(
                  controller: _controller,
                  padEnds: false,
                  physics: const BouncingScrollPhysics(),
                  itemCount: display.length,
                  onPageChanged: (i) {
                    setState(() => _current = i);
                    _maybeAskForMore(i);
                  },
                  itemBuilder: (context, index) {
                    final data = display[index];
                    Widget content;
                    if (data == null) {
                      content = const SizedBox.shrink(); // ghost
                    } else if (data == '__loader__') {
                      content = _TailLoaderCard(primaryColor: primaryColor);
                    } else {
                      content = _ProductCard(
                        product: data,
                        themeProvider: themeProvider,
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _AnimatedCarouselCard(
                        pageController: _controller,
                        index: index,
                        child: content,
                      ),
                    );
                  },
                ),
              ),

              // Dots/loader row — fixed small height to avoid overflow
              SizedBox(
                height: dotsArea,
                child: Center(
                  child: widget.isLoadingMore
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor)
                        )
                      : _Dots(
                          count: filtered.length,
                          active: ((_current - 1).clamp(0, filtered.length - 1)),
                          primaryColor: primaryColor,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedCarouselCard extends StatelessWidget {
  final PageController pageController;
  final int index;
  final Widget child;

  const _AnimatedCarouselCard({
    required this.pageController,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) {
        double t = 0;
        if (pageController.position.haveDimensions) {
          final double curr = (pageController.page ?? pageController.initialPage.toDouble());
          t = (curr - index.toDouble()).abs().clamp(0.0, 1.0);
        }
        final scale = 1 - (0.10 * t);   // 0.90 – 1.00
        final opacity = 1 - (0.35 * t); // 0.65 – 1.00

        return Align(
          alignment: Alignment.center,
          child: ClipRect(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      },
    );
  }
}

class _TailLoaderCard extends StatelessWidget {
  final Color primaryColor;

  const _TailLoaderCard({required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 220,
        height: 300,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))],
        ),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor)
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final dynamic product;
  final CelebrationThemeProvider? themeProvider;

  const _ProductCard({
    required this.product,
    this.themeProvider,
  });

  static const double _cardWidth = 220;
  static const double _cardHeight = 300;
  static const double _nameBlockHeight = 40;
  static const double _starsHeight = 18;
  static const double _buttonHeight = 42;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final wish = context.watch<WishlistProvider>();
    final f = NumberFormat("#,##0", "en_US");

    // Get theme colors
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF1565C0);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF1565C0);

    final bool isVariable = product['type'] == 'variable';
    final double price = double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    final double reg = double.tryParse(product['regular_price']?.toString() ?? '') ?? 0;
    final bool sale = reg > 0 && reg > price;

    final images = product['images'] as List?;
    final String? imageUrl =
        (images != null && images.isNotEmpty) ? (images[0]['src']?.toString()) : null;

    final double rating = double.tryParse(product['average_rating']?.toString() ?? '0') ?? 0;
    final bool inCart = cart.contains(product);
    final String mainLabel = isVariable ? "Select Options" : (inCart ? "In Cart" : "Add to Cart");

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductDetailPage(product: product)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: _cardWidth,
            height: _cardHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image + sticky wishlist heart
                Stack(
                  children: [
                    imageUrl != null
                        ? Image.network(
                            imageUrl,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            height: 140,
                            width: double.infinity,
                            color: Colors.grey[200],
                            child: const Icon(Icons.image, size: 48, color: Colors.grey),
                          ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => wish.toggle(product),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              wish.contains(product) ? Icons.favorite : Icons.favorite_border,
                              size: 18,
                              color: wish.contains(product) ? Colors.red : Colors.blueGrey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        SizedBox(
                          height: _nameBlockHeight,
                          child: Text(
                            (product['name']?.toString() ?? '').trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),

                        // ⭐
                        SizedBox(
                          height: _starsHeight,
                          child: Row(
                            children: List.generate(5, (i) {
                              final icon = i + 1 <= rating.floor()
                                  ? Icons.star
                                  : (i + 1 - rating <= 0.5 ? Icons.star_half : Icons.star_border);
                              final color = rating > 0 ? Colors.amber[600] : Colors.grey[400];
                              return Icon(icon, size: 14, color: color);
                            }),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Price
                        Row(
                          children: [
                            _NairaTight(
                              amount: f.format(price),
                              bold: true,
                              color: primaryColor,
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

                        const Spacer(),

                        // Button
                        SizedBox(
                          width: double.infinity,
                          height: _buttonHeight,
                          child: ElevatedButton(
                            onPressed: () {
                              if (isVariable) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProductDetailPage(product: product),
                                  ),
                                );
                              } else {
                                cart.toggle(product);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isVariable
                                ? Colors.orange
                                : (inCart ? Colors.green : primaryColor),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                mainLabel,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
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

class _Dots extends StatelessWidget {
  final int count;
  final int active;
  final Color primaryColor;

  const _Dots({
    required this.count,
    required this.active,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: isActive ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive ? primaryColor : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );
  }
}