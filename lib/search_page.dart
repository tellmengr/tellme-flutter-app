import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'woocommerce_auth_service.dart';
import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'product_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'celebration_theme_provider.dart';

// 🌈 Brand colors (fallback when no celebration theme)
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);

class SearchPage extends StatefulWidget {
  /// Optional: if opened from bottom nav, pass the index you want to go back to (usually 0 for Home)
  final int? selectedIndex;

  /// Optional: callback from BottomNavShell to switch tabs when there's no route to pop
  final Function(int)? onBackToHome;

  /// Optional initial search text
  final String? initialQuery;

  /// Optional initial search type: 'all' | 'name' | 'sku' | 'id' | 'category'
  /// Use 'id' when opening from a push that contains productId.
  final String? initialSearchType;

  const SearchPage({
    super.key,
    this.initialQuery,
    this.initialSearchType,
    this.selectedIndex,
    this.onBackToHome,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final WooCommerceAuthService _wooService = WooCommerceAuthService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String _searchType = 'all'; // all, name, sku, id, category

  // ✅ New: auto-open product detail when searching by ID and a single hit returns
  bool _autoOpenOnSingleHit = true;

  @override
  void initState() {
    super.initState();

    // Use provided type for the first search (e.g., 'id' from push)
    if (widget.initialSearchType != null && widget.initialSearchType!.isNotEmpty) {
      _searchType = widget.initialSearchType!;
    }

    // Kick off initial search if provided
    if ((widget.initialQuery ?? '').isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      _performSearch(widget.initialQuery!);
    }

    // So the clear (×) button updates as you type
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ✅ Smart back handler: pop if possible, else switch to a tab (e.g., Home)
  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else if (widget.onBackToHome != null) {
      widget.onBackToHome!(widget.selectedIndex ?? 0);
    }
  }

  // 🔍 Perform search based on selected type
  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      List<dynamic> results = [];
      switch (_searchType) {
        case 'name':
          results = await _wooService.searchProductsByName(q);
          break;
        case 'sku':
          results = await _wooService.searchProductsBySKU(q);
          break;
        case 'id':
          final productId = int.tryParse(q);
          if (productId != null) {
            final product = await _wooService.searchProductById(productId);
            if (product != null) results = [product];
          }
          break;
        case 'category':
          results = await _wooService.searchProductsByCategory(q);
          break;
        case 'all':
        default:
          results = await _wooService.searchProducts(q);
          break;
      }

      if (!mounted) return;

      // ✅ Auto-open when searching by ID and exactly one result is found
      if (_autoOpenOnSingleHit && _searchType == 'id' && results.length == 1) {
        final product = results.first;
        _autoOpenOnSingleHit = false; // prevent re-trigger on back
        _isSearching = false;
        _searchResults = results;
        setState(() {}); // update UI before navigating
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductDetailPage(product: product)),
        );
        return;
      }

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    // We always show a back arrow; if there's nothing to pop, our handler will switch tab.
    return Scaffold(
      backgroundColor: Colors.grey[50],
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: _handleBack,
          tooltip: 'Back',
        ),
        title: const Text(
          "Search Products",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // 🔍 Search bar section (blue header area)
          Container(
            width: double.infinity,
            color: primaryColor,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _buildSearchBar(themeProvider),
          ),

          // 🎯 Search type filters
          _buildSearchFilters(),

          // 📊 Results section
          Expanded(child: _buildSearchResults(themeProvider)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🔍 SEARCH BAR
  // ------------------------------------------------------------------
  Widget _buildSearchBar(CelebrationThemeProvider? themeProvider) {
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(30),
      shadowColor: Colors.black26,
      child: TextField(
        controller: _searchController,
        autofocus: false, // avoids initial overscroll/keyboard push
        textInputAction: TextInputAction.search,
        onSubmitted: _performSearch,
        decoration: InputDecoration(
          hintText: "Search by name, SKU, ID, or category...",
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: primaryColor),
          suffixIcon: (_searchController.text.isNotEmpty)
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                      _hasSearched = false;
                      _autoOpenOnSingleHit = true; // reset when clearing
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.white),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(color: accentColor, width: 1.2),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🎯 SEARCH FILTERS
  // ------------------------------------------------------------------
  Widget _buildSearchFilters() {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              "Search by: ",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            _chip('All', 'all', Icons.search, primaryColor, accentColor),
            _chip('Name', 'name', Icons.title, primaryColor, accentColor),
            _chip('SKU', 'sku', Icons.qr_code, primaryColor, accentColor),
            _chip('Product ID', 'id', Icons.numbers, primaryColor, accentColor),
            _chip('Category', 'category', Icons.category, primaryColor, accentColor),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, IconData icon, Color primaryColor, Color accentColor) {
    final isSelected = _searchType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : primaryColor),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _searchType = value);
          if (_searchController.text.isNotEmpty) {
            _performSearch(_searchController.text);
          }
        },
        selectedColor: primaryColor,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : primaryColor,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  // ------------------------------------------------------------------
  // 📊 SEARCH RESULTS
  // ------------------------------------------------------------------
  Widget _buildSearchResults(CelebrationThemeProvider? themeProvider) {
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 12),
            Text("Searching products...", style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return _emptyState(
        icon: Icons.search,
        title: "Start searching",
        message: "Enter a product name, SKU, ID, or category to find products",
      );
    }

    if (_searchResults.isEmpty) {
      return _emptyState(
        icon: Icons.search_off,
        title: "No results found",
        message: "Try a different search term or filter",
      );
    }

    // Add a little bottom padding so it doesn't clash with the bottom nav bar.
    final bottomPadding = 16.0 + MediaQuery.of(context).padding.bottom;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (_, i) => _productCard(_searchResults[i], themeProvider),
    );
  }

  // ------------------------------------------------------------------
  // 💳 PRODUCT CARD
  // ------------------------------------------------------------------
  Widget _productCard(dynamic product, CelebrationThemeProvider? themeProvider) {
    final name = product['name'] ?? 'Unknown Product';
    final price = _parsePrice(product['price']);
    final imageUrl = _getImageUrl(product);
    final sku = product['sku'] ?? '';

    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProductDetailPage(product: product)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🖼️ Image
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _placeholder(),
                            errorWidget: (_, __, ___) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                  Positioned(top: 8, right: 8, child: _wishlistButton(product)),
                ],
              ),
            ),

            // 📝 Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sku.isNotEmpty)
                    Text('SKU: $sku',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(
                    "₦${price.toStringAsFixed(0)}",
                    style: TextStyle(
                      fontSize: 16,
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final cart = context.read<CartProvider>();
                        cart.addToCartFast(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("$name added to cart"),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.shopping_cart, size: 16),
                      label: const Text('Add', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 💕 WISHLIST BUTTON
  // ------------------------------------------------------------------
  Widget _wishlistButton(dynamic product) {
    return Consumer<WishlistProvider>(
      builder: (context, wishlist, _) {
        final isInWishlist = wishlist.contains(product);
        return CircleAvatar(
          backgroundColor: Colors.white,
          radius: 18,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              isInWishlist ? Icons.favorite : Icons.favorite_border,
              color: isInWishlist ? Colors.red : Colors.grey,
              size: 20,
            ),
            onPressed: () {
              if (isInWishlist) {
                wishlist.remove(product);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Removed from wishlist"),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 1),
                  ),
                );
              } else {
                wishlist.add(product);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Added to wishlist"),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // 🎨 EMPTY STATE
  // ------------------------------------------------------------------
  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 100, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🛠️ HELPERS
  // ------------------------------------------------------------------
  Widget _placeholder() => Container(
        color: Colors.grey[200],
        child: Icon(Icons.image, color: Colors.grey[400], size: 40),
      );

  String? _getImageUrl(dynamic product) {
    if (product['images'] != null && (product['images'] as List).isNotEmpty) {
      return product['images'][0]['src'];
    }
    return product['image'] ?? product['thumbnail'];
  }

  double _parsePrice(dynamic price) {
    if (price == null) return 0.0;
    if (price is num) return price.toDouble();
    if (price is String) {
      return double.tryParse(price.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    }
    return 0.0;
  }
}