import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'wishlist_provider.dart';
import 'cart_provider.dart';
import 'product_detail_page.dart';
import 'app_header.dart';
import 'celebration_theme_provider.dart'; // Add this import

class WishlistPage extends StatelessWidget {
  final int? selectedIndex;
  final Function(int)? onBackToHome;

  const WishlistPage({
    super.key,
    this.selectedIndex,
    this.onBackToHome,
  });

  // ✅ Smart unified back handler
  void _handleBack(BuildContext context) {
    if (onBackToHome != null) {
      onBackToHome!(selectedIndex ?? 0);
      Navigator.pop(context);
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<CelebrationThemeProvider?>();

    // Get theme colors exactly like in SignUpPage
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? const Color(0xFF004AAD);
    final accentColor = currentTheme?.accentColor ?? const Color(0xFF0096FF);
    final gradientColors = currentTheme?.gradient.colors ?? [const Color(0xFF004AAD), const Color(0xFF0096FF)];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppHeader(
        title: "My Wishlist",
        showBackButton: true,
        showMenu: false,
        useGradient: true,
        showTitle: true,
        showWishlist: false,
        showCart: true,
      ),
      body: Consumer<WishlistProvider>(
        builder: (context, wishlist, child) {
          if (wishlist.count == 0) {
            return _buildEmptyState(context, primaryColor);
          }

          return Column(
            children: [
              // 📊 Wishlist summary header - THEME AWARE
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Your Favorites",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${wishlist.count} ${wishlist.count == 1 ? 'item' : 'items'}",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => _showClearConfirmation(context),
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                      tooltip: "Clear All",
                    ),
                  ],
                ),
              ),

              // 💕 Wishlist items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: wishlist.count,
                  itemBuilder: (context, index) {
                    final item = wishlist.items[index];
                    return _buildWishlistCard(context, item, wishlist, primaryColor, accentColor);
                  },
                ),
              ),

              // 🛒 Bottom action button - THEME AWARE
              _buildBottomActions(context, wishlist, primaryColor, accentColor),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // 💳 WISHLIST CARD - THEME AWARE
  // ------------------------------------------------------------------
  Widget _buildWishlistCard(BuildContext context, dynamic item, WishlistProvider wishlist, Color primaryColor, Color accentColor) {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final id = item['id'] ?? item['product_id'] ?? 0;
    final name = item['name'] ?? 'Unknown Product';
    final price = _parsePrice(item['price']);
    final imageUrl = _getImageUrl(item);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailPage(product: item),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 🖼️ Product Image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),

              const SizedBox(width: 12),

              // 📝 Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "₦${price.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontSize: 18,
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 🎯 Action Buttons - THEME AWARE
              Column(
                children: [
                  IconButton(
                    onPressed: () {
                      cart.addToCartFast(item);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("$name added to cart"),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 2),
                          action: SnackBarAction(
                            label: "VIEW",
                            textColor: Colors.white,
                            onPressed: () {
                              Navigator.pushNamed(context, '/cart');
                            },
                          ),
                        ),
                      );
                    },
                    icon: Icon(Icons.shopping_cart_outlined, color: primaryColor),
                    tooltip: "Add to Cart",
                  ),
                  IconButton(
                    onPressed: () {
                      wishlist.remove(item);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("$name removed from wishlist"),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: "Remove",
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🎨 EMPTY STATE - THEME AWARE
  // ------------------------------------------------------------------
  Widget _buildEmptyState(BuildContext context, Color primaryColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 120, color: Colors.grey[300]),
          const SizedBox(height: 24),
          Text(
            "Your wishlist is empty",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Start adding items you love!",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _handleBack(context), // ✅ unified
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text("Continue Shopping"),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🔽 BOTTOM ACTIONS - THEME AWARE
  // ------------------------------------------------------------------
  Widget _buildBottomActions(BuildContext context, WishlistProvider wishlist, Color primaryColor, Color accentColor) {
    final cart = Provider.of<CartProvider>(context, listen: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addAllToCart(context, wishlist, cart),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text("Add All to Cart"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/cart'),
                icon: const Icon(Icons.shopping_cart),
                label: const Text("View Cart"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🛠️ HELPER METHODS
  // ------------------------------------------------------------------
  Widget _buildPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey[200],
      child: Icon(Icons.image, color: Colors.grey[400], size: 40),
    );
  }

  String? _getImageUrl(dynamic item) {
    if (item['images'] != null && (item['images'] as List).isNotEmpty) {
      return item['images'][0]['src'];
    }
    return item['image'] ?? item['thumbnail'];
  }

  double _parsePrice(dynamic price) {
    if (price == null) return 0.0;
    if (price is num) return price.toDouble();
    if (price is String) {
      return double.tryParse(price.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    }
    return 0.0;
  }

  void _addAllToCart(BuildContext context, WishlistProvider wishlist, CartProvider cart) {
    for (var item in wishlist.items) {
      cart.addToCartFast(item);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${wishlist.count} items added to cart"),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: "VIEW CART",
          textColor: Colors.white,
          onPressed: () => Navigator.pushNamed(context, '/cart'),
        ),
      ),
    );
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear Wishlist?"),
        content:
            const Text("Are you sure you want to remove all items from your wishlist?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Provider.of<WishlistProvider>(context, listen: false).clear();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Wishlist cleared"),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: const Text("Clear All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}