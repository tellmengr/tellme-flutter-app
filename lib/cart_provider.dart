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
  final Map<dynamic, Map<String, dynamic>> _productCache = {};
  final Map<int, Map<String, dynamic>> _shippingClassCache = {};

  String _cartText(dynamic value) => value?.toString().trim() ?? '';

  Map<String, String> _cartStringMap(dynamic value) {
    if (value is! Map) return <String, String>{};
    return value.map(
      (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
    );
  }

  Map<String, String> _cartSelectedAttributes(Map<String, dynamic> product) {
    final selected = <String, String>{};

    void addAll(dynamic value) {
      final map = _cartStringMap(value);
      for (final entry in map.entries) {
        final key = entry.key.trim();
        final item = entry.value.trim();
        if (key.isNotEmpty && item.isNotEmpty) selected[key] = item;
      }
    }

    addAll(product['attributes']);
    addAll(product['selectedOptions']);
    addAll(product['options']);

    final color = _cartText(product['color']);
    if (color.isNotEmpty) selected.putIfAbsent('Color', () => color);

    final size = _cartText(product['size']);
    if (size.isNotEmpty) {
      selected.putIfAbsent('Size', () => size);
      selected.putIfAbsent('Shoe Size', () => size);
    }

    return selected;
  }

  String _resolveVariantIdForCart(
    dynamic productId,
    Map<String, String>? attributes, [
    Map<String, dynamic>? source,
  ]) {
    String normalizeOptionKey(String value) => value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final cached = productId != null ? _productCache[productId] : null;
    final product = <String, dynamic>{
      if (cached != null) ...cached,
      if (source != null) ...source,
    };

    for (final key in const [
      'variantId',
      'variant_id',
      'backendVariantId',
      'backend_variant_id',
    ]) {
      final value = _cartText(product[key]);
      if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(value)) return value;
    }

    final selected = <String, String>{};
    selected.addAll(_cartStringMap(attributes));
    selected.addAll(_cartSelectedAttributes(product));

    final normalizedSelected = <String, String>{};
    selected.forEach((key, value) {
      final cleanedValue = value.trim().toLowerCase();
      if (cleanedValue.isNotEmpty) {
        normalizedSelected[normalizeOptionKey(key)] = cleanedValue;
      }
    });

    final variants = product['variants'];
    if (variants is List && variants.isNotEmpty) {
      if (normalizedSelected.isEmpty && variants.length == 1) {
        final first = variants.first;
        if (first is Map) {
          final value = _cartText(first['id'] ??
              first['variantId'] ??
              first['variant_id'] ??
              first['backendVariantId']);
          if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(value)) return value;
        }
      }

      for (final raw in variants) {
        if (raw is! Map) continue;
        final options = <String, String>{};
        options.addAll(_cartStringMap(raw['attributes']));
        options.addAll(_cartStringMap(raw['options']));

        final normalizedVariant = <String, String>{};
        options.forEach((key, value) {
          final cleanedValue = value.trim().toLowerCase();
          if (cleanedValue.isNotEmpty) {
            normalizedVariant[normalizeOptionKey(key)] = cleanedValue;
          }
        });

        if (normalizedSelected.isNotEmpty && normalizedVariant.isNotEmpty) {
          final matches = normalizedSelected.entries.every((entry) {
            final actual = normalizedVariant[entry.key] ?? '';
            return actual == entry.value;
          });
          if (matches) {
            final value = _cartText(raw['id'] ??
                raw['variantId'] ??
                raw['variant_id'] ??
                raw['backendVariantId']);
            if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(value)) return value;
          }
        }
      }
    }

    return '';
  }

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
  void _cacheProductDetailsInBackground(dynamic productId) async {
    try {
      // Only fetch if not already cached
      if (_productCache[productId] != null &&
          _productCache[productId]!['shipping_class'] == null) {
        final cachedProduct = _productCache[productId] ?? <String, dynamic>{};
        final detailId = cachedProduct['sku'] ??
            cachedProduct['variant_sku'] ??
            cachedProduct['backendId'] ??
            cachedProduct['backend_id'] ??
            productId;
        final productDetails =
            await _wooCommerceService.getProductDetails(detailId);

        if (productDetails != null) {
          final selected = _cartSelectedAttributes(_productCache[productId]!);
          final resolvedVariantId = _resolveVariantIdForCart(
            productId,
            selected,
            productDetails,
          );

          // Update cache with detailed info and backend variant context.
          _productCache[productId]!.addAll({
            'id': productDetails['id'] ?? _productCache[productId]!['id'],
            'backendId': productDetails['backendId'] ??
                productDetails['backend_id'] ??
                productDetails['id'] ??
                _productCache[productId]!['backendId'],
            'backend_id': productDetails['backend_id'] ??
                productDetails['backendId'] ??
                productDetails['id'] ??
                _productCache[productId]!['backend_id'],
            'variants': productDetails['variants'] ??
                _productCache[productId]!['variants'],
            'variant_id': resolvedVariantId,
            'variantId': resolvedVariantId,
            'backendVariantId': resolvedVariantId,
            'shipping_class': productDetails['shipping_class'] ?? '',
            'shipping_class_id': productDetails['shipping_class_id'] ?? 0,
            'weight': productDetails['weight'] ?? '',
            'dimensions': productDetails['dimensions'] ?? {},
            'stock_status': productDetails['stock_status'] ?? 'instock',
            'sku':
                productDetails['sku'] ?? _productCache[productId]!['sku'] ?? '',
          });

          // Cache shipping class details if available
          final shippingClassId = productDetails['shipping_class_id'];
          if (shippingClassId != null &&
              shippingClassId > 0 &&
              !_shippingClassCache.containsKey(shippingClassId)) {
            final classDetails = await _wooCommerceService
                .getShippingClassDetails(shippingClassId);
            if (classDetails != null) {
              _shippingClassCache[shippingClassId] = classDetails;
              _productCache[productId]!['shipping_class_name'] =
                  classDetails['name'];
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
          'backendId':
              cachedProduct['backendId'] ?? cachedProduct['backend_id'] ?? '',
          'variant_id': _resolveVariantIdForCart(
            productId,
            _cartSelectedAttributes(enhancedProduct),
            cachedProduct,
          ),
          'variantId': _resolveVariantIdForCart(
            productId,
            _cartSelectedAttributes(enhancedProduct),
            cachedProduct,
          ),
          'backendVariantId': _resolveVariantIdForCart(
            productId,
            _cartSelectedAttributes(enhancedProduct),
            cachedProduct,
          ),
          'variants':
              cachedProduct['variants'] ?? enhancedProduct['variants'] ?? [],
          'selectedOptions': enhancedProduct['selectedOptions'] ??
              enhancedProduct['attributes'] ??
              {},
          'shipping_class': cachedProduct['shipping_class'] ?? '',
          'shipping_class_id': cachedProduct['shipping_class_id'] ?? 0,
          'shipping_class_name': cachedProduct['shipping_class_name'] ?? '',
          'weight': cachedProduct['weight'] ?? '',
          'dimensions': cachedProduct['dimensions'] ?? {},
          'stock_status': cachedProduct['stock_status'] ?? 'instock',
          'sku': cachedProduct['sku'] ??
              enhancedProduct['sku'] ??
              '', // ✅ NEW: Ensure SKU is preserved
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
      enhancedProduct['cart_item_id'] =
          _generateCartItemId(productId, product['color'], product['size']);

      // Add to cart
      _cartItems.add(enhancedProduct);

      await _saveCartToStorage();
      notifyListeners();

      print(
          '✅ Added to cart INSTANTLY with shipping class: ${enhancedProduct['shipping_class'] ?? 'none'}');
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
        final detailId = product['sku'] ??
            product['variant_sku'] ??
            product['backendId'] ??
            product['backend_id'] ??
            productId;
        final productDetails =
            await _wooCommerceService.getProductDetails(detailId);

        if (productDetails != null) {
          // Add shipping class information
          enhancedProduct['shipping_class'] =
              productDetails['shipping_class'] ?? '';
          enhancedProduct['shipping_class_id'] =
              productDetails['shipping_class_id'] ?? 0;
          enhancedProduct['backendId'] = productDetails['backendId'] ??
              productDetails['backend_id'] ??
              enhancedProduct['backendId'] ??
              '';
          final selected = _cartSelectedAttributes(enhancedProduct);
          final resolvedVariantId = _resolveVariantIdForCart(
            productId,
            selected,
            {
              ...productDetails,
              'selectedOptions': selected,
              'attributes': selected,
            },
          );
          enhancedProduct['variants'] =
              productDetails['variants'] ?? enhancedProduct['variants'];
          enhancedProduct['variant_id'] = resolvedVariantId.isNotEmpty
              ? resolvedVariantId
              : productDetails['variant_id'] ??
                  productDetails['variantId'] ??
                  enhancedProduct['variant_id'] ??
                  '';
          enhancedProduct['variantId'] = resolvedVariantId.isNotEmpty
              ? resolvedVariantId
              : productDetails['variantId'] ??
                  productDetails['variant_id'] ??
                  enhancedProduct['variantId'] ??
                  '';
          enhancedProduct['backendVariantId'] = enhancedProduct['variant_id'] ??
              enhancedProduct['variantId'] ??
              '';
          enhancedProduct['weight'] = productDetails['weight'] ?? '';
          enhancedProduct['dimensions'] = productDetails['dimensions'] ?? {};
          enhancedProduct['stock_status'] =
              productDetails['stock_status'] ?? 'instock';
          enhancedProduct['sku'] = productDetails['sku'] ??
              enhancedProduct['sku'] ??
              ''; // ✅ NEW: Add SKU

          // Get shipping class name if available
          final shippingClass = productDetails['shipping_class'] ?? '';
          if (shippingClass.isNotEmpty) {
            final shippingClassId = productDetails['shipping_class_id'];
            if (shippingClassId != null && shippingClassId > 0) {
              final classDetails = await _wooCommerceService
                  .getShippingClassDetails(shippingClassId);
              if (classDetails != null) {
                enhancedProduct['shipping_class_name'] =
                    classDetails['name'] ?? shippingClass;
              }
            }
          }

          print(
              '✅ Product shipping class: ${enhancedProduct['shipping_class']}');
        } else {
          print('⚠️ Could not fetch product details for ID: $productId');
          // Continue with basic product info
        }
      }

      // Add metadata
      enhancedProduct['added_at'] = DateTime.now().toIso8601String();
      enhancedProduct['cart_item_id'] =
          _generateCartItemId(productId, product['color'], product['size']);

      // Add to cart (preserving your original logic)
      _cartItems.add(enhancedProduct);

      await _saveCartToStorage();
      notifyListeners(); // ✅ CRITICAL: This triggers UI updates including the badge!

      print(
          '✅ Added to cart with shipping class: ${enhancedProduct['shipping_class'] ?? 'none'}');
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
    required dynamic productId,
    required String name,
    required double price,
    required String image,
    int quantity = 1,
    String? color,
    String? size,
    String? sku,
    String? variantId,
    Map<String, String>? attributes,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      String attributeKey = '';
      if (attributes != null && attributes.isNotEmpty) {
        final sortedKeys = attributes.keys.toList()..sort();
        attributeKey =
            sortedKeys.map((key) => '$key:${attributes[key]}').join('|');
      }

      final resolvedVariantId = variantId ??
          _resolveVariantIdForCart(
            productId,
            attributes,
            {
              'sku': sku ?? '',
              'color': color,
              'size': size,
              'attributes': attributes ?? <String, String>{},
              'selectedOptions': attributes ?? <String, String>{},
            },
          );

      final product = {
        'id': productId,
        'sku': sku ?? '',
        'variant_id': resolvedVariantId,
        'variantId': resolvedVariantId,
        'backendVariantId': resolvedVariantId,
        'name': name,
        'price': price,
        'image': image,
        'color': color,
        'size': size,
        'attributes': attributes ?? <String, String>{},
        'selectedOptions': attributes ?? <String, String>{},
        'attribute_key': attributeKey,
      };

      for (int i = 0; i < quantity; i++) {
        await addToCartFast(product);
      }

      print('Added $quantity x $name with attributes: $attributes');
    } catch (e) {
      _setError('Failed to add item with attributes: $e');
      print('Error adding item with attributes: $e');
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
      String itemKey =
          _cartItems[i]['id']?.toString() ?? _cartItems[i]['name'] ?? '';
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
          item['id']?.toString() == cartItemId);

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
          final String productKey =
              product['id']?.toString() ?? product['name'] ?? '';
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
      String uniqueKey =
          attributeKey.isNotEmpty ? '${baseKey}_$attributeKey' : baseKey;

      if (uniqueProducts.containsKey(uniqueKey)) {
        uniqueProducts[uniqueKey]!['quantity'] =
            (uniqueProducts[uniqueKey]!['quantity'] ?? 0) + 1;
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
    if (sku.isNotEmpty) return 'SKU: $sku';
    if (id.isEmpty) return '';
    if (id.length > 12) return 'Item: ${id.substring(0, 8).toUpperCase()}';
    return 'Product ID: $id';
  }

  /// 🔍 Check if two items have the same attributes
  bool hasSameAttributes(
      Map<String, dynamic> item1, Map<String, dynamic> item2) {
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

      final uniqueProducts = getUniqueProductsWithQuantity();

      for (var product in uniqueProducts) {
        final productId = product['id'];
        if (productId == null) continue;

        final detailId = product['sku'] ??
            product['variant_sku'] ??
            product['backendId'] ??
            product['backend_id'] ??
            productId;
        final productDetails =
            await _wooCommerceService.getProductDetails(detailId);

        if (productDetails == null) continue;

        final productKey = product['id']?.toString() ?? product['name'] ?? '';

        for (int i = 0; i < _cartItems.length; i++) {
          final itemKey =
              _cartItems[i]['id']?.toString() ?? _cartItems[i]['name'] ?? '';
          if (itemKey != productKey) continue;

          final selected = _cartSelectedAttributes(_cartItems[i]);
          final resolvedVariantId = _resolveVariantIdForCart(
            productId,
            selected,
            {
              ...productDetails,
              'selectedOptions': selected,
              'attributes': selected,
            },
          );

          _cartItems[i].addAll({
            'backendId': productDetails['backendId'] ??
                productDetails['backend_id'] ??
                productDetails['id'] ??
                _cartItems[i]['backendId'],
            'backend_id': productDetails['backend_id'] ??
                productDetails['backendId'] ??
                productDetails['id'] ??
                _cartItems[i]['backend_id'],
            'variants': productDetails['variants'] ?? _cartItems[i]['variants'],
            if (resolvedVariantId.isNotEmpty) 'variant_id': resolvedVariantId,
            if (resolvedVariantId.isNotEmpty) 'variantId': resolvedVariantId,
            if (resolvedVariantId.isNotEmpty)
              'backendVariantId': resolvedVariantId,
            'shipping_class': productDetails['shipping_class'] ?? '',
            'shipping_class_id': productDetails['shipping_class_id'] ?? 0,
            'weight': productDetails['weight'] ?? '',
            'dimensions': productDetails['dimensions'] ?? {},
            'sku': productDetails['sku'] ?? _cartItems[i]['sku'] ?? '',
          });
        }
      }

      await _saveCartToStorage();
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh shipping class data: $e');
      print('Error refreshing shipping class data: $e');
    } finally {
      _setLoading(false);
    }
  }

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
  Future<Map<String, dynamic>> calculateShippingForCity(
      Map<String, dynamic> cityData) async {
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
      var result = await _wooCommerceService.calculateEnhancedShippingForCity(
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
  Future<Map<String, dynamic>> calculateSimpleShippingForCity(
      Map<String, dynamic> cityData) async {
    try {
      print('🔄 Calculating simple shipping for: ${cityData['name']}');

      final shippingResult =
          await _wooCommerceService.getShippingMethodsForCity(cityData);

      if (shippingResult['success'] == true &&
          shippingResult['shipping_options'].isNotEmpty) {
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
          print(
              '⚠️ ${missingShippingClass.length} items missing shipping class, will refresh when needed');
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
