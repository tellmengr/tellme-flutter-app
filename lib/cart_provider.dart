import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'woocommerce_auth_service.dart';

class CartProvider with ChangeNotifier {
  final WooCommerceAuthService _wooCommerceService = WooCommerceAuthService();

  List<Map<String, dynamic>> _cartItems = [];
  bool _isLoading = false;
  String? _error;

  // ✅ NEW: Product cache to eliminate API calls
  final Map<int, Map<String, dynamic>> _productCache = {};
  final Map<int, Map<String, dynamic>> _shippingClassCache = {};

  // ———————————————————————————————————————————————————————————————
  // 🔧 EXISTING GETTERS (PRESERVED FROM YOUR ORIGINAL CODE)
  // ———————————————————————————————————————————————————————————————
  List<Map<String, dynamic>> get cartItems => getUniqueProductsWithQuantity();

  int get itemCount => getUniqueProductsWithQuantity().length;

  // ✅ CRITICAL: Get total quantity of all items (THIS FIXES THE BADGE!)
  int get totalQuantity {
    return getUniqueProductsWithQuantity()
        .fold(0, (sum, item) => sum + (item['quantity'] as int));
  }

  // New getters for enhanced functionality
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get subtotal => getTotalPrice();

  // ———————————————————————————————————————————————————————————————
  // 🚀 NEW: PRODUCT CACHING SYSTEM
  // ———————————————————————————————————————————————————————————————

  /// 🚀 Cache products when loading from home/category pages
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    print('🚀 Caching ${products.length} products for fast cart operations...');

    for (var product in products) {
      final productId = product['id'];
      if (productId != null) {
        // Store basic product info
        _productCache[productId] = Map<String, dynamic>.from(product);

        // Pre-fetch and cache detailed information in background
        _cacheProductDetailsInBackground(productId);
      }
    }

    print('✅ Product cache updated with ${_productCache.length} products');
  }

  /// 🔄 Background caching of detailed product info (non-blocking)
  void _cacheProductDetailsInBackground(int productId) async {
    try {
      // Only fetch if not already cached
      if (_productCache[productId] != null &&
          _productCache[productId]!['shipping_class'] == null) {

        final productDetails = await _wooCommerceService.getProductDetails(productId);

        if (productDetails != null) {
          // Update cache with detailed info
          _productCache[productId]!.addAll({
            'shipping_class': productDetails['shipping_class'] ?? '',
            'shipping_class_id': productDetails['shipping_class_id'] ?? 0,
            'weight': productDetails['weight'] ?? '',
            'dimensions': productDetails['dimensions'] ?? {},
            'stock_status': productDetails['stock_status'] ?? 'instock',
            'sku': productDetails['sku'] ?? '',   // ✅ NEW: Cache SKU
          });

          // Cache shipping class details if available
          final shippingClassId = productDetails['shipping_class_id'];
          if (shippingClassId != null && shippingClassId > 0 &&
              !_shippingClassCache.containsKey(shippingClassId)) {

            final classDetails = await _wooCommerceService.getShippingClassDetails(shippingClassId);
            if (classDetails != null) {
              _shippingClassCache[shippingClassId] = classDetails;
              _productCache[productId]!['shipping_class_name'] = classDetails['name'];
            }
          }

          print('🔄 Background cached details for product $productId');
        }
      }
    } catch (e) {
      print('⚠️ Background caching failed for product $productId: $e');
      // Fail silently, don't affect user experience
    }
  }

  /// 🚀 INSTANT: Add to cart using cached data (NO API CALLS!)
  Future<void> addToCartFast(Map<String, dynamic> product) async {
    try {
      _setLoading(true);
      _clearError();

      final productId = product['id'];
      final productName = product['name'] ?? 'Unknown Product';

      print('🛒 Adding product to cart (FAST): $productName (ID: $productId)');

      // Create enhanced product data
      Map<String, dynamic> enhancedProduct = Map<String, dynamic>.from(product);

      // ✅ USE CACHED DATA (NO API CALLS!)
      if (productId != null && _productCache.containsKey(productId)) {
        final cachedProduct = _productCache[productId]!;

        // Add cached shipping class information
        enhancedProduct.addAll({
          'shipping_class': cachedProduct['shipping_class'] ?? '',
          'shipping_class_id': cachedProduct['shipping_class_id'] ?? 0,
          'shipping_class_name': cachedProduct['shipping_class_name'] ?? '',
          'weight': cachedProduct['weight'] ?? '',
          'dimensions': cachedProduct['dimensions'] ?? {},
          'stock_status': cachedProduct['stock_status'] ?? 'instock',
          'sku': cachedProduct['sku'] ?? '',  // ✅ NEW: Ensure SKU is preserved
        });

        print('✅ Used cached data - NO API calls needed!');
        print('✅ Product shipping class: ${enhancedProduct['shipping_class']}');
      } else {
        print('⚠️ Product not in cache, will use basic info');
        // Fall back to slow method if not cached
        await addToCart(product);
        return;
      }

      // Add metadata
      enhancedProduct['added_at'] = DateTime.now().toIso8601String();
      enhancedProduct['cart_item_id'] = _generateCartItemId(productId, product['color'], product['size']);

      // Add to cart
      _cartItems.add(enhancedProduct);

      await _saveCartToStorage();
      notifyListeners();

      print('✅ Added to cart INSTANTLY with shipping class: ${enhancedProduct['shipping_class'] ?? 'none'}');

    } catch (e) {
      _setError('Failed to add item to cart: $e');
      print('❌ Error adding to cart: $e');

      // Fallback: Add basic product without enhanced data
      _cartItems.add(product);
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 🛒 EXISTING CART OPERATIONS (PRESERVED FROM YOUR ORIGINAL CODE)
  // ———————————————————————————————————————————————————————————————

  // Get quantity of a specific product (PRESERVED)
  int getProductQuantity(Map<String, dynamic> product) {
    String productKey = product['id']?.toString() ?? product['name'] ?? '';
    return _cartItems.where((item) {
      String itemKey = item['id']?.toString() ?? item['name'] ?? '';
      return itemKey == productKey;
    }).length;
  }

  // Calculate total price (PRESERVED)
  double getTotalPrice() {
    double total = 0.0;
    for (var item in getUniqueProductsWithQuantity()) {
      double price = 0.0;
      if (item['price'] != null) {
        if (item['price'] is String) {
          price = double.tryParse(item['price']) ?? 0.0;
        } else if (item['price'] is num) {
          price = item['price'].toDouble();
        }
      }
      int quantity = item['quantity'] ?? 1;
      total += price * quantity;
    }
    return total;
  }

  /// ➕ SLOW VERSION: Add item to cart with API calls (PRESERVED FOR FALLBACK)
  Future<void> addToCart(Map<String, dynamic> product) async {
    try {
      _setLoading(true);
      _clearError();

      // Extract product info
      final productId = product['id'];
      final productName = product['name'] ?? 'Unknown Product';

      print('🛒 Adding product to cart: $productName (ID: $productId)');

      // Create enhanced product data
      Map<String, dynamic> enhancedProduct = Map<String, dynamic>.from(product);

      // 📦 Fetch detailed product information including shipping class if we have an ID
      if (productId != null) {
        final productDetails = await _wooCommerceService.getProductDetails(productId);

        if (productDetails != null) {
          // Add shipping class information
          enhancedProduct['shipping_class'] = productDetails['shipping_class'] ?? '';
          enhancedProduct['shipping_class_id'] = productDetails['shipping_class_id'] ?? 0;
          enhancedProduct['weight'] = productDetails['weight'] ?? '';
          enhancedProduct['dimensions'] = productDetails['dimensions'] ?? {};
          enhancedProduct['stock_status'] = productDetails['stock_status'] ?? 'instock';
          enhancedProduct['sku'] = productDetails['sku'] ?? '';  // ✅ NEW: Add SKU

          // Get shipping class name if available
          final shippingClass = productDetails['shipping_class'] ?? '';
          if (shippingClass.isNotEmpty) {
            final shippingClassId = productDetails['shipping_class_id'];
            if (shippingClassId != null && shippingClassId > 0) {
              final classDetails = await _wooCommerceService.getShippingClassDetails(shippingClassId);
              if (classDetails != null) {
                enhancedProduct['shipping_class_name'] = classDetails['name'] ?? shippingClass;
              }
            }
          }

          print('✅ Product shipping class: ${enhancedProduct['shipping_class']}');
        } else {
          print('⚠️ Could not fetch product details for ID: $productId');
          // Continue with basic product info
        }
      }

      // Add metadata
      enhancedProduct['added_at'] = DateTime.now().toIso8601String();
      enhancedProduct['cart_item_id'] = _generateCartItemId(productId, product['color'], product['size']);

      // Add to cart (preserving your original logic)
      _cartItems.add(enhancedProduct);

      await _saveCartToStorage();
      notifyListeners(); // ✅ CRITICAL: This triggers UI updates including the badge!

      print('✅ Added to cart with shipping class: ${enhancedProduct['shipping_class'] ?? 'none'}');

    } catch (e) {
      _setError('Failed to add item to cart: $e');
      print('❌ Error adding to cart: $e');

      // Fallback: Add basic product without enhanced data
      _cartItems.add(product);
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// ➕ ENHANCED: Add item with explicit parameters (✅ NOW WITH ATTRIBUTES SUPPORT)
  Future<void> addToCartWithDetails({
    required int productId,
    required String name,
    required double price,
    required String image,
    int quantity = 1,
    String? color,
    String? size,
    String? sku,                          // ✅ NEW: Added SKU parameter
    Map<String, String>? attributes,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      // Create unique product identifier including attributes
      String attributeKey = '';
      if (attributes != null && attributes.isNotEmpty) {
        // Sort attributes for consistent key generation
        final sortedKeys = attributes.keys.toList()..sort();
        attributeKey = sortedKeys.map((key) => '$key:${attributes[key]}').join('|');
      }

      final product = {
        'id': productId,
        'sku': sku ?? '',                  // ✅ NEW: Save SKU
        'name': name,
        'price': price,
        'image': image,
        'color': color,
        'size': size,
        'attributes': attributes ?? {}, // ✅ Include attributes
        'attribute_key': attributeKey, // For unique identification
      };

      // Add the specified quantity
      for (int i = 0; i < quantity; i++) {
        await addToCartFast(product);
      }

      print('✅ Added $quantity × $name with attributes: $attributes');

    } catch (e) {
      _setError('Failed to add item with attributes: $e');
      print('❌ Error adding item with attributes: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Add one more quantity of a product (PRESERVED)
  void increaseQuantity(Map<String, dynamic> product) {
    _cartItems.add(product);
    _saveCartToStorage();
    notifyListeners();
  }

  // Remove one instance of a product (PRESERVED)
  void removeOne(Map<String, dynamic> product) {
    String productKey = product['id']?.toString() ?? product['name'] ?? '';

    for (int i = 0; i < _cartItems.length; i++) {
      String itemKey = _cartItems[i]['id']?.toString() ?? _cartItems[i]['name'] ?? '';
      if (itemKey == productKey) {
        _cartItems.removeAt(i);
        break;
      }
    }
    _saveCartToStorage();
    notifyListeners();
  }

  // Remove all instances of a product (PRESERVED)
  void removeProduct(Map<String, dynamic> product) {
    String productKey = product['id']?.toString() ?? product['name'] ?? '';
    _cartItems.removeWhere((item) {
      String itemKey = item['id']?.toString() ?? item['name'] ?? '';
      return itemKey == productKey;
    });
    _saveCartToStorage();
    notifyListeners();
  }

  /// 🗑️ Remove product by cart item ID
  Future<void> removeFromCart(String cartItemId) async {
    try {
      _cartItems.removeWhere((item) => item['cart_item_id'] == cartItemId);
      await _saveCartToStorage();
      notifyListeners();
      print('🗑️ Removed item from cart: $cartItemId');
    } catch (e) {
      _setError('Failed to remove item from cart: $e');
    }
  }

  /// 🔄 Update product quantity in cart
  Future<void> updateQuantity(String cartItemId, int newQuantity) async {
    try {
      if (newQuantity <= 0) {
        await removeFromCart(cartItemId);
        return;
      }

      // Find the product in unique products
      final uniqueProducts = getUniqueProductsWithQuantity();
      final productIndex = uniqueProducts.indexWhere((item) =>
        item['cart_item_id'] == cartItemId ||
        item['id']?.toString() == cartItemId
      );

      if (productIndex >= 0) {
        final product = uniqueProducts[productIndex];
        final currentQuantity = product['quantity'] ?? 1;
        final difference = newQuantity - currentQuantity;

        if (difference > 0) {
          // Add more items
          for (int i = 0; i < difference; i++) {
            _cartItems.add(Map<String, dynamic>.from(product));
          }
        } else if (difference < 0) {
          // Remove items
          final String productKey = product['id']?.toString() ?? product['name'] ?? '';
          int toRemove = difference.abs().toInt();

          _cartItems.removeWhere((item) {
            if (toRemove <= 0) return false;
            String itemKey = item['id']?.toString() ?? item['name'] ?? '';
            if (itemKey == productKey) {
              toRemove--;
              return true;
            }
            return false;
          });
        }

        await _saveCartToStorage();
        notifyListeners();
        print('🔄 Updated quantity for cart item: $cartItemId');
      }
    } catch (e) {
      _setError('Failed to update quantity: $e');
    }
  }

  // Clear entire cart (PRESERVED + ENHANCED)
  void clearCart() {
    _cartItems.clear();
    _saveCartToStorage();
    notifyListeners();
    print('🧹 Cart cleared');
  }

  // Check if product is in cart (PRESERVED)
  bool isInCart(Map<String, dynamic> product) {
    String productKey = product['id']?.toString() ?? product['name'] ?? '';
    return _cartItems.any((item) {
      String itemKey = item['id']?.toString() ?? item['name'] ?? '';
      return itemKey == productKey;
    });
  }

  // Check if product is in cart (alternative method name) (PRESERVED)
  bool contains(dynamic product) {
    // Handle both Map<String, dynamic> and String ID
    if (product is String) {
      return _cartItems.any((item) {
        String itemKey = item['id']?.toString() ?? item['name'] ?? '';
        return itemKey == product;
      });
    } else if (product is Map<String, dynamic>) {
      return isInCart(product);
    }
    return false;
  }

  // Toggle product in cart (add if not present, remove if present) (PRESERVED)
  void toggle(Map<String, dynamic> product) {
    if (isInCart(product)) {
      removeOne(product);
    } else {
      addToCartFast(product); // ✅ Use fast version
    }
  }

  // ✅ CRITICAL: Get unique products with their quantities (ENHANCED TO HANDLE ATTRIBUTES)
  List<Map<String, dynamic>> getUniqueProductsWithQuantity() {
    Map<String, Map<String, dynamic>> uniqueProducts = {};

    for (var item in _cartItems) {
      // Create unique key including attributes
      String baseKey = item['id']?.toString() ?? item['name'] ?? '';
      String attributeKey = item['attribute_key'] ?? '';
      String uniqueKey = attributeKey.isNotEmpty ? '${baseKey}_$attributeKey' : baseKey;

      if (uniqueProducts.containsKey(uniqueKey)) {
        uniqueProducts[uniqueKey]!['quantity'] = (uniqueProducts[uniqueKey]!['quantity'] ?? 0) + 1;
      } else {
        uniqueProducts[uniqueKey] = Map<String, dynamic>.from(item);
        uniqueProducts[uniqueKey]!['quantity'] = 1;
      }
    }

    return uniqueProducts.values.toList();
  }

  /// 📝 Get formatted attribute string for display
  String getFormattedAttributes(Map<String, dynamic> cartItem) {
    final attributes = cartItem['attributes'] as Map<String, String>? ?? {};

    if (attributes.isEmpty) return '';

    return attributes.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
  }

  /// 🆔 NEW: Helper to get Product ID + SKU for display
  String getProductIdSku(Map<String, dynamic> cartItem) {
    final id = cartItem['id']?.toString() ?? '';
    final sku = cartItem['sku']?.toString() ?? '';
    if (id.isEmpty && sku.isEmpty) return '';
    return 'Product ID: $id | SKU: $sku';
  }

  /// 🔍 Check if two items have the same attributes
  bool hasSameAttributes(Map<String, dynamic> item1, Map<String, dynamic> item2) {
    final attrs1 = item1['attributes'] as Map<String, String>? ?? {};
    final attrs2 = item2['attributes'] as Map<String, String>? ?? {};

    if (attrs1.length != attrs2.length) return false;

    for (String key in attrs1.keys) {
      if (attrs1[key] != attrs2[key]) return false;
    }

    return true;
  }

  // ———————————————————————————————————————————————————————————————
  // 🚚 SHIPPING CLASS VALIDATION & UTILITIES
  // ———————————————————————————————————————————————————————————————

  /// ✅ Check if all cart items have shipping class information
  bool get allItemsHaveShippingClass {
    if (_cartItems.isEmpty) return true;

    final uniqueProducts = getUniqueProductsWithQuantity();
    return uniqueProducts.every((item) {
      final shippingClass = item['shipping_class'] ?? '';
      return shippingClass.isNotEmpty;
    });
  }

  /// 📊 Get summary of shipping classes in cart
  Map<String, int> getShippingClassSummary() {
    final summary = <String, int>{};
    final uniqueProducts = getUniqueProductsWithQuantity();

    for (var item in uniqueProducts) {
      final shippingClass = item['shipping_class'] ?? 'no_class';
      final quantity = (item['quantity'] ?? 1) as int;
      summary[shippingClass] = (summary[shippingClass] ?? 0) + quantity;
    }

    return summary;
  }

  /// 🔄 Refresh shipping class data for all cart items
  Future<void> refreshShippingClassData() async {
    try {
      _setLoading(true);
      _clearError();

      print('🔄 Refreshing shipping class data for cart items...');

      final uniqueProducts = getUniqueProductsWithQuantity();

      for (var product in uniqueProducts) {
        final productId = product['id'];

        if (productId != null) {
          final productDetails = await _wooCommerceService.getProductDetails(productId);

          if (productDetails != null) {
            // Update all instances of this product in _cartItems
            final String productKey = product['id']?.toString() ?? product['name'] ?? '';

            for (int i = 0; i < _cartItems.length; i++) {
              String itemKey = _cartItems[i]['id']?.toString() ?? _cartItems[i]['name'] ?? '';
              if (itemKey == productKey) {
                _cartItems[i]['shipping_class'] = productDetails['shipping_class'] ?? '';
                _cartItems[i]['shipping_class_id'] = productDetails['shipping_class_id'] ?? 0;
                _cartItems[i]['weight'] = productDetails['weight'] ?? '';
                _cartItems[i]['dimensions'] = productDetails['dimensions'] ?? {};
                _cartItems[i]['sku'] = productDetails['sku'] ?? '';  // ✅ NEW: Update SKU

                // Update shipping class name if available
                final shippingClass = productDetails['shipping_class'] ?? '';
                if (shippingClass.isNotEmpty) {
                  final shippingClassId = productDetails['shipping_class_id'];
                  if (shippingClassId != null && shippingClassId > 0) {
                    final classDetails = await _wooCommerceService.getShippingClassDetails(shippingClassId);
                    if (classDetails != null) {
                      _cartItems[i]['shipping_class_name'] = classDetails['name'] ?? shippingClass;
                    }
                  }
                }
              }
            }
          }
        }
      }

      await _saveCartToStorage();
      notifyListeners();

      print('✅ Shipping class data refreshed for all items');

    } catch (e) {
      _setError('Failed to refresh shipping class data: $e');
      print('❌ Error refreshing shipping class data: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// ⚠️ Get cart items missing shipping class information
  List<Map<String, dynamic>> getItemsMissingShippingClass() {
    final uniqueProducts = getUniqueProductsWithQuantity();
    return uniqueProducts.where((item) {
      final shippingClass = item['shipping_class'] ?? '';
      return shippingClass.isEmpty;
    }).toList();
  }

  // ———————————————————————————————————————————————————————————————
  // 🚚 ENHANCED SHIPPING CALCULATION INTEGRATION
  // ———————————————————————————————————————————————————————————————

  /// 💰 Calculate enhanced shipping cost for selected city
  Future<Map<String, dynamic>> calculateShippingForCity(Map<String, dynamic> cityData) async {
    try {
      _setLoading(true);
      _clearError();

      print('💰 Calculating enhanced shipping for city: ${cityData['name']}');

      final uniqueProducts = getUniqueProductsWithQuantity();
      print('💰 Cart items: ${uniqueProducts.length}');

      // Ensure all items have shipping class data
      if (!allItemsHaveShippingClass) {
        print('⚠️ Some items missing shipping class, refreshing...');
        await refreshShippingClassData();
      }

      // Use the enhanced shipping calculation with unique products
      final result = await _wooCommerceService.calculateEnhancedShippingForCity(
        cityData: cityData,
        cartItems: uniqueProducts,
      );

      print('✅ Shipping calculation result: ${result['success']}');
      if (result['success'] == true) {
        print('💰 Total shipping cost: ${result['formatted_cost']}');
      }

      return result;

    } catch (e) {
      _setError('Failed to calculate shipping: $e');
      print('❌ Error calculating shipping: $e');
      return {
        'success': false,
        'error': 'Calculation error: $e',
        'shipping_cost': 0.0,
        'formatted_cost': '₦0.00',
      };
    } finally {
      _setLoading(false);
    }
  }

  /// 🔄 Calculate shipping using legacy method (fallback)
  Future<Map<String, dynamic>> calculateSimpleShippingForCity(Map<String, dynamic> cityData) async {
    try {
      print('🔄 Calculating simple shipping for: ${cityData['name']}');

      final shippingResult = await _wooCommerceService.getShippingMethodsForCity(cityData);

      if (shippingResult['success'] == true && shippingResult['shipping_options'].isNotEmpty) {
        final shippingOption = shippingResult['shipping_options'][0];

        return {
          'success': true,
          'shipping_method': shippingOption['title'],
          'shipping_cost': shippingOption['cost'],
          'formatted_cost': shippingOption['formatted_cost'],
          'shipping_description': shippingOption['description'],
          'zone_id': shippingOption['zone'],
          'method_id': shippingOption['id'],
        };
      } else {
        return {
          'success': false,
          'error': shippingResult['error'] ?? 'No shipping options available',
          'shipping_method': 'Unknown Method',
          'shipping_cost': 0.0,
          'formatted_cost': '₦0.00',
        };
      }
    } catch (e) {
      print('❌ Error calculating simple shipping: $e');
      return {
        'success': false,
        'error': 'Calculation error: $e',
        'shipping_method': 'Unknown Method',
        'shipping_cost': 0.0,
        'formatted_cost': '₦0.00',
      };
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 💾 STORAGE & PERSISTENCE
  // ———————————————————————————————————————————————————————————————

  /// 💾 Save cart to local storage
  Future<void> _saveCartToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartJson = json.encode(_cartItems);
      await prefs.setString('cart_items', cartJson);
      print('💾 Cart saved to storage');
    } catch (e) {
      print('❌ Error saving cart to storage: $e');
    }
  }

  /// 📥 Load cart from local storage
  Future<void> loadCartFromStorage() async {
    try {
      _setLoading(true);
      final prefs = await SharedPreferences.getInstance();
      final cartJson = prefs.getString('cart_items');

      if (cartJson != null) {
        final List<dynamic> decodedCart = json.decode(cartJson);
        _cartItems = decodedCart.cast<Map<String, dynamic>>();

        print('📥 Loaded ${_cartItems.length} items from storage');

        // Check if any items are missing shipping class data
        final missingShippingClass = getItemsMissingShippingClass();
        if (missingShippingClass.isNotEmpty) {
          print('⚠️ ${missingShippingClass.length} items missing shipping class, will refresh when needed');
        }

        notifyListeners();
      }
    } catch (e) {
      _setError('Failed to load cart from storage: $e');
      print('❌ Error loading cart from storage: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 🔧 HELPER METHODS
  // ———————————————————————————————————————————————————————————————

  /// 🆔 Generate unique cart item ID
  String _generateCartItemId(dynamic productId, String? color, String? size) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final colorSuffix = color != null ? '_$color' : '';
    final sizeSuffix = size != null ? '_$size' : '';
    return 'cart_${productId}${colorSuffix}${sizeSuffix}_$timestamp';
  }

  /// ⏳ Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// ❌ Set error message
  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  /// ✅ Clear error message
  void _clearError() {
    _error = null;
    notifyListeners();
  }

  // ———————————————————————————————————————————————————————————————
  // 📊 CART ANALYTICS & UTILITIES
  // ———————————————————————————————————————————————————————————————

  /// 📊 Get cart summary with shipping class breakdown
  Map<String, dynamic> getCartSummary() {
    final shippingClassSummary = getShippingClassSummary();
    final uniqueProducts = getUniqueProductsWithQuantity();

    final totalWeight = uniqueProducts.fold(0.0, (sum, item) {
      final weight = double.tryParse(item['weight']?.toString() ?? '0') ?? 0.0;
      final quantity = item['quantity'] ?? 1;
      return sum + (weight * quantity);
    });

    return {
      'total_items': uniqueProducts.length,
      'total_quantity': totalQuantity,
      'subtotal': subtotal,
      'formatted_subtotal': '₦${subtotal.toStringAsFixed(2)}',
      'total_weight': totalWeight,
      'shipping_classes': shippingClassSummary,
      'has_all_shipping_classes': allItemsHaveShippingClass,
      'missing_shipping_class_count': getItemsMissingShippingClass().length,
    };
  }

  /// 🧹 Clean up resources
  @override
  void dispose() {
    super.dispose();
  }
}