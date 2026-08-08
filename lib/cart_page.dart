import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'woocommerce_auth_service.dart';
import 'cart_provider.dart';
import 'checkout_page.dart';
import 'sign_in_page.dart';
import 'user_provider.dart';
import 'celebration_theme_provider.dart';
import 'loyalty_service.dart'; // ✅ NEW: loyalty API/model

// 🌈 Brand colors (fallback when no celebration theme)
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);

class CartPage extends StatefulWidget {
  final int? selectedIndex;
  final Function(int)? onBackToHome;

  const CartPage({
    super.key,
    this.selectedIndex,
    this.onBackToHome,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  double? _estimatedShipping;
  String? _estimatedShippingLabel;

  // ✅ Smart back handler (works for both bottom nav & drawer)
  void _handleBack(BuildContext context) {
    if (widget.onBackToHome != null) {
      widget.onBackToHome!(widget.selectedIndex ?? 0);
      Navigator.pop(context);
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  String _formatCartCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    ).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        final cartItems = List<Map<String, dynamic>>.from(cart.cartItems);

        return Scaffold(
          backgroundColor: Colors.grey[50],
          body: cartItems.isEmpty
              ? _buildEmptyCart(context, primaryColor, accentColor)
              : CustomScrollView(
                  slivers: [
                    _buildSliverAppBar(cart, context, primaryColor),
                    SliverList(
                      delegate: SliverChildListDelegate(
                        [
                          for (int index = 0; index < cartItems.length; index++)
                            KeyedSubtree(
                              key: ValueKey(
                                'cart-item-${cartItems[index]['cart_item_key'] ?? cartItems[index]['cart_item_id'] ?? cartItems[index]['id'] ?? cartItems[index]['product_id'] ?? index}',
                              ),
                              child: _buildCartItem(
                                cartItems[index],
                                cart,
                                index,
                                context,
                                themeProvider,
                              ),
                            ),
                          KeyedSubtree(
                            key: const ValueKey('delivery-estimate-card'),
                            child: _DeliveryEstimateCard(
                              cart: cart,
                              primaryColor: primaryColor,
                              accentColor: accentColor,
                              onReset: () {
                                setState(() {
                                  _estimatedShipping = null;
                                  _estimatedShippingLabel = null;
                                });
                              },
                              onEstimated: (amount, label) {
                                setState(() {
                                  _estimatedShipping = amount;
                                  _estimatedShippingLabel =
                                      _formatCartCurrency(amount);
                                });
                              },
                            ),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('order-summary-card'),
                            child: _buildOrderSummary(
                              cart,
                              context,
                              primaryColor,
                              accentColor,
                            ),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('checkout-button-card'),
                            child: _buildCheckoutButton(
                              cart,
                              context,
                              primaryColor,
                            ),
                          ),
                        ],
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
                            product['cart_item_id'] ?? product['id'].toString(),
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
          _buildVariationChip(
              attributeName, attributeValue, color, primaryColor),
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
  Widget _buildOrderSummary(CartProvider cart, BuildContext context,
      Color primaryColor, Color accentColor) {
    final formatCurrency =
        NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

    final double subtotal = cart.getTotalPrice();
    final double shipping = _estimatedShipping ?? 0.0;

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
            _summaryAmountRow(
              label: 'Subtotal',
              value: formatCurrency.format(subtotal),
            ),
            const SizedBox(height: 8),
            if (_estimatedShipping != null) ...[
              _shippingEstimateRow(formatCurrency, primaryColor),
              const SizedBox(height: 8),
            ],
            const Divider(height: 24),
            _summaryAmountRow(
              label: 'Cart total',
              value: formatCurrency.format(subtotal + shipping),
              valueColor: primaryColor,
              isTotal: true,
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
        final double shipping = _estimatedShipping ?? 0.0;
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
              _summaryAmountRow(
                label: 'Subtotal',
                value: formatCurrency.format(subtotal),
              ),
              const SizedBox(height: 8),
              if (_estimatedShipping != null) ...[
                _shippingEstimateRow(formatCurrency, primaryColor),
                const SizedBox(height: 8),
              ],

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
                    SizedBox(
                      width: 142,
                      child: Text(
                        '-${formatCurrency.format(discount)}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(height: 24),
              _summaryAmountRow(
                label: 'Cart total',
                value: formatCurrency.format(total),
                valueColor: primaryColor,
                isTotal: true,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shippingEstimateRow(
    NumberFormat formatCurrency,
    Color primaryColor,
  ) {
    return _summaryAmountRow(
      label: 'Shipping',
      value: _estimatedShippingLabel ??
          formatCurrency.format(_estimatedShipping ?? 0),
      valueColor: primaryColor,
    );
  }

  Widget _summaryAmountRow({
    required String label,
    required String value,
    Color? valueColor,
    bool isTotal = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w400,
              color: isTotal ? Colors.black : Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 142,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutButton(
      CartProvider cart, BuildContext context, Color primaryColor) {
    final canCheckout = _estimatedShipping != null;

    return Container(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed:
              canCheckout ? () => _proceedToCheckout(context, cart) : null,
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
              Text(canCheckout ? 'Secure Checkout' : 'Select delivery city',
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
                      color: Colors.grey[600], fontWeight: FontWeight.w500)),
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
    final double shipping = _estimatedShipping ?? 0.0;
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
    final themeProvider =
        Provider.of<CelebrationThemeProvider?>(context, listen: false);
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
                      color: Colors.grey[600], fontWeight: FontWeight.w500)),
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
            'shipping': _estimatedShipping ?? 0.0,
            'total': subtotal + (_estimatedShipping ?? 0.0),
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
                    shipping: _estimatedShipping ?? 0.0,
                    total: subtotal + (_estimatedShipping ?? 0.0),
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
                    shipping: _estimatedShipping ?? 0.0,
                    total: subtotal + (_estimatedShipping ?? 0.0),
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

class _DeliveryEstimateCard extends StatefulWidget {
  final CartProvider cart;
  final Color primaryColor;
  final Color accentColor;
  final VoidCallback onReset;
  final void Function(double amount, String label) onEstimated;

  const _DeliveryEstimateCard({
    required this.cart,
    required this.primaryColor,
    required this.accentColor,
    required this.onReset,
    required this.onEstimated,
  });

  @override
  State<_DeliveryEstimateCard> createState() => _DeliveryEstimateCardState();
}

class _DeliveryEstimateCardState extends State<_DeliveryEstimateCard> {
  final WooCommerceAuthService _authService = WooCommerceAuthService();
  final NumberFormat _formatCurrency = NumberFormat.currency(
    locale: 'en_NG',
    symbol: '₦',
    decimalDigits: 0,
  );

  List<Map<String, dynamic>> _states = [];
  List<Map<String, dynamic>> _cities = [];
  String? _selectedState;
  String? _selectedCity;
  bool _loadingStates = true;
  bool _loadingCities = false;
  bool _estimating = false;
  bool _reestimateScheduled = false;
  String? _errorText;
  String? _lastEstimateSignature;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  @override
  void didUpdateWidget(covariant _DeliveryEstimateCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_selectedCity == null ||
        _lastEstimateSignature == null ||
        _estimating) {
      return;
    }

    final currentSignature = _cartSignature();
    if (currentSignature == _lastEstimateSignature || _reestimateScheduled) {
      return;
    }

    _reestimateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reestimateScheduled = false;
      if (!mounted) return;
      widget.onReset();
      _estimateDelivery();
    });
  }

  Future<void> _loadStates() async {
    setState(() {
      _loadingStates = true;
      _errorText = null;
    });

    try {
      final states = await _authService.getTellmeStates();
      if (!mounted) return;
      setState(() {
        _states = _uniqueByCode(states);
        _loadingStates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStates = false;
        _errorText = 'Could not load states. Please try again.';
      });
    }
  }

  Future<void> _loadCities(String stateCode) async {
    setState(() {
      _loadingCities = true;
      _cities = [];
      _selectedCity = null;
      _errorText = null;
      _lastEstimateSignature = null;
    });
    widget.onReset();

    try {
      final cities = await _authService.getTellmeCities(stateCode);
      if (!mounted) return;
      setState(() {
        _cities = _uniqueByCode(cities);
        _loadingCities = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCities = false;
        _errorText = 'Could not load cities for this state.';
      });
    }
  }

  Future<void> _estimateDelivery() async {
    Map<String, dynamic>? city;
    for (final item in _cities) {
      if (item['code']?.toString() == _selectedCity) {
        city = item;
        break;
      }
    }

    if (_selectedState == null || city == null) {
      setState(() {
        _errorText = 'Select a state and city to estimate delivery.';
      });
      return;
    }

    setState(() {
      _estimating = true;
      _errorText = null;
    });

    try {
      final cityData = {
        ...city,
        'state': city['state'] ?? _selectedState,
      };
      final result = await widget.cart.calculateShippingForCity(cityData);
      if (!mounted) return;

      if (result['success'] == true) {
        final amount = (result['shipping_cost'] as num?)?.toDouble();
        final label = result['formatted_cost']?.toString().isNotEmpty == true
            ? result['formatted_cost'].toString()
            : _formatCurrency.format(amount ?? 0);
        _lastEstimateSignature = _cartSignature();
        widget.onEstimated(amount ?? 0, label);
        setState(() {
          _estimating = false;
        });
      } else {
        setState(() {
          _errorText =
              result['error']?.toString() ?? 'Could not estimate delivery.';
          _estimating = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Could not estimate delivery. Please try again.';
        _estimating = false;
      });
    }
  }

  String _cartSignature() {
    return '${widget.cart.totalQuantity}:${widget.cart.getTotalPrice().toStringAsFixed(2)}';
  }

  List<Map<String, dynamic>> _uniqueByCode(List<Map<String, dynamic>> items) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];

    for (final item in items) {
      final code = item['code']?.toString() ?? '';
      final name = item['name']?.toString() ?? '';
      final key = code.isNotEmpty ? code : name;
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      unique.add({
        ...item,
        'code': key,
      });
    }

    return unique;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.accentColor.withOpacity(0.18)),
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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.primaryColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_shipping_outlined,
                  color: widget.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimate your delivery fee',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose state and city before checkout.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingStates)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _selectedState,
              isExpanded: true,
              decoration: _inputDecoration('State'),
              items: _states.map((state) {
                return DropdownMenuItem<String>(
                  value: state['code']?.toString(),
                  child: Text(state['name']?.toString() ?? ''),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedState = value);
                _loadCities(value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCity,
              isExpanded: true,
              decoration: _inputDecoration(
                _loadingCities ? 'Loading cities...' : 'City',
              ),
              items: _cities.map((city) {
                return DropdownMenuItem<String>(
                  value: city['code']?.toString(),
                  child: Text(city['name']?.toString() ?? ''),
                );
              }).toList(),
              onChanged: _loadingCities
                  ? null
                  : (value) {
                      setState(() {
                        _selectedCity = value;
                        _errorText = null;
                      });
                      widget.onReset();
                      if (value != null) {
                        _estimateDelivery();
                      }
                    },
            ),
          ],
          if (_estimating) ...[
            const SizedBox(height: 12),
            _ResultPill(
              icon: Icons.hourglass_top_rounded,
              text: 'Calculating delivery fee...',
              color: widget.primaryColor,
            ),
          ] else if (_errorText != null) ...[
            const SizedBox(height: 12),
            _ResultPill(
              icon: Icons.info_outline,
              text: _errorText!,
              color: Colors.redAccent,
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.primaryColor, width: 1.4),
      ),
    );
  }
}

class _ResultPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _ResultPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
