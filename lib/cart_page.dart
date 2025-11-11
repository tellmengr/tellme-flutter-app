import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'cart_provider.dart';
import 'checkout_page.dart';
import 'sign_in_page.dart';
import 'user_provider.dart';
import 'celebration_theme_provider.dart';
import 'loyalty_service.dart'; // ✅ NEW: loyalty API/model

// 🌈 Brand colors (fallback when no celebration theme)
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);

class CartPage extends StatelessWidget {
  final int? selectedIndex;
  final Function(int)? onBackToHome;

  const CartPage({
    super.key,
    this.selectedIndex,
    this.onBackToHome,
  });

  // ✅ Smart back handler (works for both bottom nav & drawer)
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
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        return Scaffold(
          backgroundColor: Colors.grey[50],
          body: cart.cartItems.isEmpty
              ? _buildEmptyCart(context, primaryColor, accentColor)
              : CustomScrollView(
                  slivers: [
                    _buildSliverAppBar(cart, context, primaryColor),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index < cart.cartItems.length) {
                            return _buildCartItem(
                              cart.cartItems[index],
                              cart,
                              index,
                              context,
                              themeProvider,
                            );
                          } else if (index == cart.cartItems.length) {
                            return _buildOrderSummary(
                              cart,
                              context,
                              primaryColor,
                              accentColor,
                            );
                          } else {
                            return _buildCheckoutButton(
                              cart,
                              context,
                              primaryColor,
                            );
                          }
                        },
                        childCount: cart.cartItems.length + 2,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSliverAppBar(
      CartProvider cart, BuildContext context, Color primaryColor) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
        onPressed: () => _handleBack(context), // ✅ unified
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.black),
          onPressed: () {},
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: Colors.white,
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shopping Cart',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${cart.cartItems.length} Items',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCart(
      BuildContext context, Color primaryColor, Color accentColor) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => _handleBack(context), // ✅ unified
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Your cart is empty',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add some items to get started',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _handleBack(context), // ✅ unified
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Continue Shopping',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(
    Map<String, dynamic> product,
    CartProvider cart,
    int index,
    BuildContext context,
    CelebrationThemeProvider? themeProvider,
  ) {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );

    final name = product['name'] ?? "Unknown Product";
    final price = product['price']?.toString() ?? "0";
    final quantity = product['quantity'] ?? 1;

    String? image;
    if (product['images'] != null &&
        product['images'] is List &&
        product['images'].isNotEmpty) {
      final firstImage = product['images'][0];
      if (firstImage is Map) {
        image = firstImage['src']?.toString() ??
            firstImage['url']?.toString() ??
            firstImage['image_url']?.toString();
      }
    }
    image ??= product['image']?.toString() ??
        product['imageUrl']?.toString() ??
        product['image_url']?.toString() ??
        product['featured_image']?.toString() ??
        product['thumbnail']?.toString();

    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 80,
              height: 80,
              color: Colors.grey[200],
              child: image != null && image.isNotEmpty
                  ? Image.network(
                      image,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image, color: Colors.grey),
                    )
                  : const Icon(Icons.image_outlined,
                      color: Colors.grey, size: 32),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _buildProductVariations(product, primaryColor, accentColor),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatCurrency.format(double.tryParse(price) ?? 0),
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: quantity > 1
                              ? () => cart.updateQuantity(
                                    product['cart_item_id'] ??
                                        product['id'].toString(),
                                    quantity - 1,
                                  )
                              : null,
                        ),
                        Text(
                          '$quantity',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => cart.updateQuantity(
                            product['cart_item_id'] ??
                                product['id'].toString(),
                            quantity + 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      final cartItemId =
                          product['cart_item_id'] ?? product['id'].toString();
                      _showRemoveDialog(context, cart, cartItemId, name);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductVariations(
      Map<String, dynamic> product, Color primaryColor, Color accentColor) {
    Map<String, String> attributes = {};

    // Handle both List and Map formats
    if (product['attributes'] is List) {
      for (var item in product['attributes']) {
        if (item is Map &&
            item.containsKey('name') &&
            item.containsKey('option')) {
          attributes[item['name'].toString()] = item['option'].toString();
        }
      }
    } else if (product['attributes'] is Map) {
      attributes = Map<String, String>.from(product['attributes']);
    }

    List<Widget> variationChips = [];

    // Add SKU if available
    final sku = product['sku']?.toString();
    if (sku != null && sku.isNotEmpty) {
      variationChips.add(_buildVariationChip(
          'SKU', sku, const Color(0xFF64748B), primaryColor));
    }

    // ✅ Use theme colors for variation chips instead of hardcoded colors
    List<Color> accentColors = [
      primaryColor, // Primary theme color
      accentColor, // Accent theme color
      primaryColor.withOpacity(0.7),
      accentColor.withOpacity(0.7),
      primaryColor.withOpacity(0.5),
      accentColor.withOpacity(0.5),
      const Color(0xFF2563EB), // Blue
      const Color(0xFF059669), // Green
    ];

    int colorIndex = 0;
    for (var entry in attributes.entries) {
      final attributeName = entry.key;
      final attributeValue = entry.value;

      if (attributeValue.isNotEmpty) {
        final color = accentColors[colorIndex % accentColors.length];
        variationChips.add(
          _buildVariationChip(attributeName, attributeValue, color, primaryColor),
        );
        colorIndex++;
      }
    }

    if (variationChips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: variationChips),
    );
  }

  Widget _buildVariationChip(
      String label, String value, Color accentColor, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accentColor,
        ),
      ),
    );
  }

  /// ✅ UPDATED: Order summary now fetches and shows loyalty discount
  Widget _buildOrderSummary(
      CartProvider cart, BuildContext context, Color primaryColor, Color accentColor) {
    final formatCurrency =
        NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

    final double subtotal = cart.getTotalPrice();
    const double shipping = 2500.0;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final bool isLoggedIn = userProvider.isLoggedIn;

    // 🧠 Get the WordPress user ID (same approach you used before)
    final int userId = isLoggedIn ? (userProvider.userId ?? 0) : 0;

    // If not logged in, show normal summary (no loyalty).
    if (!isLoggedIn || userId == 0) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order Summary',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal',
                    style: GoogleFonts.inter(
                        fontSize: 16, color: Colors.grey[600])),
                Text(formatCurrency.format(subtotal),
                    style:
                        GoogleFonts.inter(fontSize: 16, color: Colors.black)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Shipping',
                    style: GoogleFonts.inter(
                        fontSize: 16, color: Colors.grey[600])),
                Text(formatCurrency.format(shipping),
                    style:
                        GoogleFonts.inter(fontSize: 16, color: Colors.black)),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total',
                    style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
                Text(formatCurrency.format(subtotal + shipping),
                    style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor)),
              ],
            ),
          ],
        ),
      );
    }

    // If logged in, fetch loyalty discount from the API.
    return FutureBuilder<LoyaltyDiscount>(
      future: LoyaltyService.fetchLoyaltyDiscount(
        userId: userId,
        cartTotal: subtotal,
      ),
      builder: (context, snapshot) {
        final loyalty = snapshot.data ?? LoyaltyDiscount.empty();
        final double discount =
            (loyalty.eligible && loyalty.discount > 0) ? loyalty.discount : 0.0;
        final double total = subtotal + shipping - discount;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order Summary',
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal',
                      style: GoogleFonts.inter(
                          fontSize: 16, color: Colors.grey[600])),
                  Text(formatCurrency.format(subtotal),
                      style: GoogleFonts.inter(
                          fontSize: 16, color: Colors.black)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Shipping',
                      style: GoogleFonts.inter(
                          fontSize: 16, color: Colors.grey[600])),
                  Text(formatCurrency.format(shipping),
                      style: GoogleFonts.inter(
                          fontSize: 16, color: Colors.black)),
                ],
              ),

              // 🔻 Loyalty discount row (only if applicable)
              if (snapshot.connectionState == ConnectionState.waiting)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Checking loyalty...',
                          style: GoogleFonts.inter(
                              fontSize: 14, color: Colors.grey[500])),
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ),
                )
              else if (discount > 0) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (loyalty.imageUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Image.network(
                          loyalty.imageUrl,
                          height: 32,
                          fit: BoxFit.contain,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        loyalty.label.isNotEmpty
                            ? loyalty.label
                            : 'Loyalty Discount',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                    Text(
                      '-${formatCurrency.format(discount)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total',
                      style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                  Text(formatCurrency.format(total),
                      style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryColor)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckoutButton(
      CartProvider cart, BuildContext context, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () => _proceedToCheckout(context, cart),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 20),
              const SizedBox(width: 8),
              Text('Secure Checkout',
                  style: GoogleFonts.inter(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  void _showRemoveDialog(BuildContext context, CartProvider cart,
      String cartItemId, String productName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Remove Item',
              style:
                  GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Text(
              'Are you sure you want to remove "$productName" from your cart?',
              style: GoogleFonts.inter(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.inter(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500)),
            ),
            TextButton(
              onPressed: () {
                cart.removeFromCart(cartItemId);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('$productName removed from cart'),
                  backgroundColor: Colors.red[400],
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ));
              },
              child: Text('Remove',
                  style: GoogleFonts.inter(
                      color: Colors.red[600], fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  // 🔥 NEW: checkout logic that fetches loyalty and passes it into CheckoutPage
  Future<void> _proceedToCheckout(
      BuildContext context, CartProvider cart) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final bool isLoggedIn = userProvider.isLoggedIn;

    final double subtotal = cart.getTotalPrice();
    const double shipping = 2500.0;
    final double total = subtotal + shipping;

    LoyaltyDiscount? loyalty;

    if (isLoggedIn) {
      final int userId = userProvider.userId ?? 0;
      if (userId != 0) {
        try {
          loyalty = await LoyaltyService.fetchLoyaltyDiscount(
            userId: userId,
            cartTotal: subtotal,
          );
        } catch (e) {
          print('Loyalty fetch error (cart → checkout): $e');
          loyalty = LoyaltyDiscount.empty();
        }
      }
    }

    if (isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutPage(
            cartItems: cart.cartItems,
            subtotal: subtotal,
            shipping: shipping,
            total: total,
            loyalty: loyalty, // 👈 pass loyalty into checkout
          ),
        ),
      );
    } else {
      _showSignInDialog(context, cart, subtotal);
    }
  }

  void _showSignInDialog(
      BuildContext context, CartProvider cart, double subtotal) {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: primaryColor),
              const SizedBox(width: 8),
              Text('Sign In Required',
                  style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text('Please sign in to your account to proceed.',
              style: GoogleFonts.inter(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.inter(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToSignIn(context, cart, subtotal);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Sign In',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  // 🔐 After sign-in, also fetch loyalty before pushing CheckoutPage
  void _navigateToSignIn(
      BuildContext context, CartProvider cart, double subtotal) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignInPage(
          pendingCheckoutData: {
            'cartItems': cart.cartItems,
            'subtotal': subtotal,
            'shipping': 2500.0,
            'total': subtotal + 2500.0,
          },
          onSignedIn: () {
            final userProvider =
                Provider.of<UserProvider>(context, listen: false);
            final int userId = userProvider.userId ?? 0;

            // fetch loyalty asynchronously, then navigate
            LoyaltyService.fetchLoyaltyDiscount(
              userId: userId,
              cartTotal: subtotal,
            ).then((loyalty) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => CheckoutPage(
                    cartItems: cart.cartItems,
                    subtotal: subtotal,
                    shipping: 2500.0,
                    total: subtotal + 2500.0,
                    loyalty: loyalty,
                  ),
                ),
              );
            }).catchError((e) {
              print('Loyalty fetch error (after sign-in): $e');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => CheckoutPage(
                    cartItems: cart.cartItems,
                    subtotal: subtotal,
                    shipping: 2500.0,
                    total: subtotal + 2500.0,
                    loyalty: LoyaltyDiscount.empty(),
                  ),
                ),
              );
            });
          },
        ),
      ),
    );
  }
}
