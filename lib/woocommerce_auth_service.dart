import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class WooCommerceAuthService {
  // ✅ WooCommerce site base
  static const String baseUrl = 'https://tellme.ng';

  // 🔐 WooCommerce API keys
  static const String consumerKey = 'ck_0d41e4b1b9151e611ced4220bed993ac87afb94d';
  static const String consumerSecret = 'cs_125a35108b788b64900b292f4ea4d678e461637e';

  // 💳 Paystack API keys (read securely at build time)
  static const String paystackSecretKey =
      String.fromEnvironment('PAYSTACK_SECRET_KEY'); // injected with --dart-define
  static const String paystackPublicKey =
      String.fromEnvironment('PAYSTACK_PUBLIC_KEY'); // injected with --dart-define


  // 🔥 Firebase instances for admin verification
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔑 Generate a strong random password for social signups
  String _generateRandomPassword([int length = 12]) {
    // Avoid ambiguous characters; include symbols for strength
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#\$%&*!?';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

/// 🔑 Request password reset (tries several endpoints; returns true on success)

Future<bool> requestPasswordReset(String email) async {
  try {
    final e = email.trim();
    if (e.isEmpty || !_isValidEmail(e)) {
      print('❌ requestPasswordReset: invalid email "$e"');
      return false;
    }

    // 1) TellMe custom endpoint
    final r1 = await http.post(
      Uri.parse('$baseUrl/wp-json/tellme/v1/password-reset'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': e}),
    );
    if (_pwResetOk(r1)) {
      print('✅ Password reset: tellme/v1/password-reset OK');
      return true;
    } else {
      print('ℹ️ tellme/v1/password-reset failed/unavailable: ${r1.statusCode} ${r1.body}');
    }

    // 2) Popular plugin: bdpwr
    final r2 = await http.post(
      Uri.parse('$baseUrl/wp-json/bdpwr/v1/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': e}),
    );
    if (_pwResetOk(r2)) {
      print('✅ Password reset: bdpwr/v1/reset-password OK');
      return true;
    } else {
      print('ℹ️ bdpwr/v1/reset-password failed/unavailable: ${r2.statusCode} ${r2.body}');
    }

    // 3) Another common pattern
    final r3 = await http.post(
      Uri.parse('$baseUrl/wp-json/wp/v2/users/lostpassword'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': e}),
    );
    if (_pwResetOk(r3)) {
      print('✅ Password reset: wp/v2/users/lostpassword OK');
      return true;
    } else {
      print('ℹ️ wp/v2/users/lostpassword failed/unavailable: ${r3.statusCode} ${r3.body}');
    }

    // 4) Fallback to classic form (WP usually replies 302 -> checkemail=confirm)
    final r4 = await http.post(
      Uri.parse('$baseUrl/wp-login.php?action=lostpassword'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'user_login=${Uri.encodeQueryComponent(e)}&redirect_to=',
    );
    if (_pwResetOk(r4)) {
      print('✅ Password reset via wp-login.php (lostpassword) OK');
      return true;
    }

    print('❌ All password reset attempts failed. Last status: ${r4.statusCode} ${r4.body}');
    return false;
  } catch (e) {
    print('❌ requestPasswordReset exception: $e');
    return false;
  }
}

// ---------- Helpers (keep inside the class) ----------

bool _isValidEmail(String e) {
  final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  return re.hasMatch(e);
}

/// Tolerant success detector.
/// Accepts:
///  - 2xx with typical success JSON/messages
///  - 302/303 redirect whose Location contains "checkemail=confirm" (WP classic)
///  - 2xx HTML with success phrases
bool _pwResetOk(http.Response r) {
  final code = r.statusCode;
  final bodyLower = r.body.toLowerCase();

  // ✅ Handle WP classic redirect success
  if (code >= 300 && code < 400) {
    final loc = (r.headers['location'] ?? r.headers['Location'] ?? '').toLowerCase();
    if (loc.contains('checkemail=confirm') || loc.contains('resetpass')) {
      return true;
    }
    // Some hosts rewrite but still indicate success in body
    if (_containsSuccessText(bodyLower)) return true;
  }

  // ✅ Normal JSON/HTML 2xx success
  if (code >= 200 && code < 300) {
    // Heuristic success text first (works for HTML pages)
    if (_containsSuccessText(bodyLower)) return true;

    // Then try JSON patterns
    try {
      final dynamic j = json.decode(r.body);
      if (j is Map) {
        if (j['success'] == true) return true;
        final status = (j['status'] ?? '').toString().toLowerCase();
        if (status == 'ok') return true;
        if (j['data'] is Map && ((j['data']['status'] == 200) || (j['data']['success'] == true))) {
          return true;
        }
        final codeStr = (j['code'] ?? '').toString().toLowerCase();
        if (codeStr.contains('password_reset_email_sent')) return true;
        final msg = (j['message'] ?? '').toString().toLowerCase();
        if (_containsSuccessText(msg)) return true;
      }
    } catch (_) {
      // non-JSON; we've already checked for success text
    }

    // If body doesn't contain hard error terms, accept 2xx as success
    if (!_containsHardError(bodyLower)) return true;
  }

  return false;
}

bool _containsSuccessText(String s) {
  const hints = <String>[
    'check your email',
    'password reset email',
    'reset link sent',
    'we have emailed',
    'please check your inbox',
    'if the email address exists',
    'mail has been sent',
    'e-mail has been sent',
    'email has been sent',
  ];
  return hints.any((h) => s.contains(h));
}

bool _containsHardError(String s) {
  const errs = <String>[
    'user not found',
    'invalid email',
    'invalid_username',
    'no such user',
    'could not',
    'error:',
    'failed',
  ];
  return errs.any((h) => s.contains(h));
}



  // ———————————————————————————————————————————————————————————————
  // 👑 ADMIN VERIFICATION METHODS
  // ———————————————————————————————————————————————————————————————

  /// Check if the current logged-in user is an admin
  Future<bool> checkUserIsAdmin() async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('❌ No Firebase user logged in');
        return false;
      }

      final isAdmin = await checkEmailIsAdmin(currentUser.email!);
      print('👑 Admin check for ${currentUser.email}: $isAdmin');
      return isAdmin;
    } catch (e) {
      print('❌ Error checking admin status: $e');
      return false;
    }
  }

  /// Check if a specific email is in the admin list
  Future<bool> checkEmailIsAdmin(String email) async {
    try {
      print('👑 Checking if $email is an admin...');
      final querySnapshot = await _firestore
          .collection('admins')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();

      final isAdmin = querySnapshot.docs.isNotEmpty;
      print('👑 Admin check result: $isAdmin');
      return isAdmin;
    } catch (e) {
      print('❌ Error checking admin status: $e');
      return false;
    }
  }

  /// 🔐 Authenticate WordPress Admin using WordPress REST API
  /// Returns admin user data if successful, null otherwise
  Future<Map<String, dynamic>?> authenticateWordPressAdmin(
    String email,
    String password,
  ) async {
    try {
      print('🔐 Authenticating WordPress admin: $email');

      final url = '$baseUrl/wp-json/wp/v2/users/me';
      final credentials = base64Encode(utf8.encode('$email:$password'));
      final authHeader = 'Basic $credentials';

      print('🔗 WordPress API URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json',
        },
      );

      print('📊 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        print('✅ WordPress API response: $userData');

        final roles = userData['roles'] as List<dynamic>?;
        print('👑 User roles: $roles');

        // Check if user has admin or shop_manager role
        if (roles != null &&
            (roles.contains('administrator') || roles.contains('shop_manager'))) {
          print('✅ Admin role confirmed!');

          return {
            'id': userData['id'],
            'email': userData['email'] ?? email,
            'first_name': userData['name']?.split(' ').first ?? 'Admin',
            'last_name': userData['name']?.split(' ').skip(1).join(' ') ?? '',
            'username': userData['slug'] ?? email.split('@')[0],
            'role': roles.first,
            'roles': roles,
            'is_wordpress_admin': true,
          };
        } else {
          print('❌ User does not have admin role');
          return null;
        }
      } else {
        print('❌ Authentication failed: ${response.statusCode}');
        print('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ WordPress admin authentication error: $e');
      return null;
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 🔑 Authentication + Signature Helpers
  // ———————————————————————————————————————————————————————————————
  String _generateSignature(String method, String url, Map<String, String> params) {
    var sortedParams = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    String paramString = sortedParams.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    String signatureBaseString =
        '$method&${Uri.encodeComponent(url)}&${Uri.encodeComponent(paramString)}';
    String signingKey = '${Uri.encodeComponent(consumerSecret)}&';

    var hmacSha1 = Hmac(sha1, utf8.encode(signingKey));
    var digest = hmacSha1.convert(utf8.encode(signatureBaseString));
    return base64.encode(digest.bytes);
  }

  Map<String, String> _getAuthParams() {
    var timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    var nonce = DateTime.now().millisecondsSinceEpoch.toString();
    return {
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_version': '1.0',
    };
  }

  // ———————————————————————————————————————————————————————————————
  // 👤 Customer Authentication + Creation  (FIXED)
  // ———————————————————————————————————————————————————————————————

  Future<Map<String, dynamic>?> createCustomer({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      print('🆕 Creating WooCommerce customer: $email');

      final url = '$baseUrl/wp-json/wc/v3/customers';
      final authParams = _getAuthParams();

      final customerData = {
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'billing': {
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
        },
        'shipping': {
          'first_name': firstName,
          'last_name': lastName,
        },
      };

      final signature = _generateSignature('POST', url, authParams);
      authParams['oauth_signature'] = signature;

      final authHeader = 'OAuth ' +
          authParams.entries
              .map((e) => '${e.key}="${Uri.encodeComponent(e.value)}"')
              .join(', ');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': authHeader},
        body: json.encode(customerData),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        print('✅ Customer created: ${data['id']}');
        return data;
      }

      // Gracefully handle duplicate-email case by fetching the existing account
      if (response.statusCode == 400 || response.statusCode == 409) {
        final bodyLower = response.body.toLowerCase();
        if (bodyLower.contains('email') && bodyLower.contains('exist')) {
          print('ℹ️ Email already exists. Returning existing customer…');
          return await getCustomerByEmail(email);
        }
      }

      print('❌ Failed to create customer: ${response.statusCode} - ${response.body}');
    } catch (e) {
      print('❌ Exception creating customer: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> validateCustomer(String email, String password) async {
    try {
      // NOTE: Validation here only checks existence by email (Woo REST can’t validate password directly)
      final url = '$baseUrl/wp-json/wc/v3/customers';
      final authParams = _getAuthParams()..addAll({'email': email});

      final signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      final query = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$query';

      final response = await http.get(Uri.parse(fullUrl));
      if (response.statusCode == 200) {
        final List<dynamic> users = json.decode(response.body);
        if (users.isNotEmpty) return users.first as Map<String, dynamic>;
      } else {
        print('❌ validateCustomer failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Exception validating customer: $e');
    }
    return null;
  }

  /// ✅ Ensure WooCommerce customer exists for social login (uses the fixes)
  Future<Map<String, dynamic>> ensureCustomer({
    required String email,
    String? firstName,
    String? lastName,
    String? avatarUrl,
  }) async {
    try {
      print('🔍 Checking if WooCommerce customer exists for $email');

      final existingCustomer = await getCustomerByEmail(email);
      if (existingCustomer != null) {
        print('✅ Existing customer found: ${existingCustomer['id']}');
        return existingCustomer;
      }

      print('🆕 No existing customer found — creating new one...');
      final created = await createCustomer(
        email: email,
        password: _generateRandomPassword(),
        firstName: firstName ?? '',
        lastName: lastName ?? '',
      );

      if (created != null) {
        print('✅ New customer created: ${created['id']}');
        return created;
      }
      throw Exception('Failed to create WooCommerce customer');
    } catch (e) {
      print('❌ ensureCustomer error: $e');
      rethrow;
    }
  }

  /// 🔍 Find WooCommerce customer by email  (OAuth signature FIXED)
  Future<Map<String, dynamic>?> getCustomerByEmail(String email) async {
    try {
      final url = '$baseUrl/wp-json/wc/v3/customers';

      // Include `email` in the **signed** params, then sign the base URL
      final authParams = _getAuthParams()..addAll({'email': email});

      final signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      final queryString = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final fullUrl = '$url?$queryString';
      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final List<dynamic> users = json.decode(response.body);
        if (users.isNotEmpty) return users.first as Map<String, dynamic>;
      } else {
        print('❌ getCustomerByEmail failed: ${response.statusCode} - ${response.body}');
      }
      return null;
    } catch (e) {
      print('❌ Error fetching customer by email: $e');
      return null;
    }
    }


  // ———————————————————————————————————————————————————————————————
  // 📦 PRODUCT DETAILS + SHIPPING CLASS FETCHING
  // ———————————————————————————————————————————————————————————————

  /// 📦 Get detailed product information including shipping class
  Future<Map<String, dynamic>?> getProductDetails(int productId) async {
    try {
      print('📦 Fetching product details for ID: $productId');
      final url = '$baseUrl/wp-json/wc/v3/products/$productId';
      var authParams = _getAuthParams();

      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String query = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$query';

      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final productData = json.decode(response.body);
        print('✅ Product details loaded: ${productData['name']}');

        // Extract shipping class information
        final shippingClass = productData['shipping_class'] ?? '';
        final shippingClassId = productData['shipping_class_id'] ?? 0;

        return {
          'id': productData['id'],
          'name': productData['name'],
          'price': productData['price'],
          'regular_price': productData['regular_price'],
          'sale_price': productData['sale_price'],
          'shipping_class': shippingClass,
          'shipping_class_id': shippingClassId,
          'weight': productData['weight'],
          'dimensions': productData['dimensions'],
          'categories': productData['categories'],
          'images': productData['images'],
          'stock_status': productData['stock_status'],
          'manage_stock': productData['manage_stock'],
          'stock_quantity': productData['stock_quantity'],
        };
      } else {
        print('❌ Failed to fetch product details: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Exception fetching product details: $e');
      return null;
    }
  }

  /// 📦 Get shipping class details by ID
  Future<Map<String, dynamic>?> getShippingClassDetails(int shippingClassId) async {
    try {
      print('📦 Fetching shipping class details for ID: $shippingClassId');
      final url = '$baseUrl/wp-json/wc/v3/products/shipping_classes/$shippingClassId';
      var authParams = _getAuthParams();

      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String query = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$query';

      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final classData = json.decode(response.body);
        print('✅ Shipping class loaded: ${classData['name']}');

        return {
          'id': classData['id'],
          'name': classData['name'],
          'slug': classData['slug'],
          'description': classData['description'],
          'count': classData['count'],
        };
      } else {
        print('❌ Failed to fetch shipping class: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Exception fetching shipping class: $e');
      return null;
    }
  }

  /// 📦 Get all shipping classes available
  Future<List<Map<String, dynamic>>> getAllShippingClasses() async {
    try {
      print('📦 Fetching all shipping classes...');
      final url = '$baseUrl/wp-json/wc/v3/products/shipping_classes';
      var authParams = _getAuthParams();

      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String query = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$query';

      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final List<dynamic> classesData = json.decode(response.body);
        print('✅ ${classesData.length} shipping classes loaded');

        return classesData.map((classData) => {
          'id': classData['id'],
          'name': classData['name'],
          'slug': classData['slug'],
          'description': classData['description'],
          'count': classData['count'],
        }).toList();
      } else {
        print('❌ Failed to fetch shipping classes: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Exception fetching shipping classes: $e');
      return [];
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 🔍 SEARCH FUNCTIONALITY - NEW SECTION
  // ———————————————————————————————————————————————————————————————

  /// 🔍 General product search (searches across name, description, SKU)
  Future<List<dynamic>> searchProducts(String query, {int perPage = 20}) async {
    try {
      print('🔍 Searching products with query: "$query"');
      final url = '$baseUrl/wp-json/wc/v3/products';
      var authParams = _getAuthParams();

      // Add search parameters
      authParams['search'] = query;
      authParams['per_page'] = perPage.toString();
      authParams['status'] = 'publish';

      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String queryString = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$queryString';

      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final List<dynamic> products = json.decode(response.body);
        print('✅ Found ${products.length} products for "$query"');
        return products;
      } else {
        print('❌ Search failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Exception searching products: $e');
      return [];
    }
  }

  /// 📝 Search products by name
  Future<List<dynamic>> searchProductsByName(String name, {int perPage = 20}) async {
    return await searchProducts(name, perPage: perPage);
  }

  /// 🏷️ Search products by SKU
  Future<List<dynamic>> searchProductsBySKU(String sku) async {
    try {
      print('🏷️ Searching products with SKU: "$sku"');
      final url = '$baseUrl/wp-json/wc/v3/products';
      var authParams = _getAuthParams();

      authParams['sku'] = sku;
      authParams['status'] = 'publish';

      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String queryString = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$queryString';

      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final List<dynamic> products = json.decode(response.body);
        print('✅ Found ${products.length} products with SKU "$sku"');
        return products;
      } else {
        print('❌ SKU search failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Exception searching by SKU: $e');
      return [];
    }
  }

  /// 🗂️ Search products by category
  Future<List<dynamic>> searchProductsByCategory(String categorySlug, {int perPage = 20}) async {
    try {
      print('🗂️ Searching products in category: "$categorySlug"');
      final url = '$baseUrl/wp-json/wc/v3/products';
      var authParams = _getAuthParams();

      authParams['category'] = categorySlug;
      authParams['per_page'] = perPage.toString();
      authParams['status'] = 'publish';

      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String queryString = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$queryString';

      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final List<dynamic> products = json.decode(response.body);
        print('✅ Found ${products.length} products in category "$categorySlug"');
        return products;
      } else {
        print('❌ Category search failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Exception searching by category: $e');
      return [];
    }
  }

  /// 🔢 Search product by ID
  Future<Map<String, dynamic>?> searchProductById(int productId) async {
    return await getProductDetails(productId);
  }

  /// 📚 Get all categories (for category search dropdown/filter)
  Future<List<dynamic>> getProductCategories({int perPage = 100}) async {
    try {
      print('📚 Fetching product categories...');
      final url = '$baseUrl/wp-json/wc/v3/products/categories';
      var authParams = _getAuthParams();

      authParams['per_page'] = perPage.toString();
      authParams['hide_empty'] = 'true';

      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String queryString = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final fullUrl = '$url?$queryString';

      final response = await http.get(Uri.parse(fullUrl));

      if (response.statusCode == 200) {
        final List<dynamic> categories = json.decode(response.body);
        print('✅ Found ${categories.length} categories');
        return categories;
      } else {
        print('❌ Failed to fetch categories: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Exception fetching categories: $e');
      return [];
    }
  }

  /// 🔍 Advanced search with multiple filters
  Future<List<dynamic>> advancedSearch({
    String? query,
    String? sku,
    String? category,
    int? productId,
    int perPage = 20,
  }) async {
    try {
      print('🔍 Advanced search with filters...');

      // If product ID is provided, search by ID directly
      if (productId != null) {
        final product = await searchProductById(productId);
        return product != null ? [product] : [];
      }

      // If SKU is provided, search by SKU
      if (sku != null && sku.isNotEmpty) {
        return await searchProductsBySKU(sku);
      }

      // If category is provided, search by category
      if (category != null && category.isNotEmpty) {
        return await searchProductsByCategory(category, perPage: perPage);
      }

      // Otherwise, general search
      if (query != null && query.isNotEmpty) {
        return await searchProducts(query, perPage: perPage);
      }

      // No filters provided, return empty
      return [];
    } catch (e) {
      print('❌ Exception in advanced search: $e');
      return [];
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 📍 LOCATION HANDLING — Countries, States, Cities
  // ———————————————————————————————————————————————————————————————

  /// 🏛️ Get Nigerian states from TellMe Shipping plugin
  Future<List<Map<String, dynamic>>> getTellmeStates() async {
    try {
      print('📍 Fetching Nigerian states from TellMe plugin...');
      final url = Uri.parse('$baseUrl/wp-json/tellme/v1/states');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ States API response: $data');

        if (data is Map) {
          // Transform from {'LA': 'LA', 'AB': 'AB'} to expected format
          List<Map<String, dynamic>> states = [];
          data.forEach((code, name) {
            states.add({
              'code': code.toString(),
              'name': _getStateName(code.toString()),
              'country': 'NG'
            });
          });

          print('✅ Transformed ${states.length} states');
          return states;
        }
      }

      print('❌ States API failed with status: ${response.statusCode}');
      throw Exception('Failed to load TellMe states: ${response.statusCode}');
    } catch (e) {
      print('❌ Exception in getTellmeStates: $e');
      throw Exception('Failed to load TellMe states: $e');
    }
  }

  /// 🏙️ Get cities for a specific state from TellMe Shipping plugin
  Future<List<Map<String, dynamic>>> getTellmeCities(String stateCode) async {
    try {
      print('🏙️ Fetching cities for state: $stateCode from TellMe plugin...');
      final url = Uri.parse('$baseUrl/wp-json/tellme/v1/cities/$stateCode');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Cities API response type: ${data.runtimeType}');

        List<Map<String, dynamic>> cities = [];

        if (data is Map) {
          // Parse the TellMe plugin data structure:
          // 'Abule Egba' => array('Agbado Ijaye Road' => 1, 'Ajasa Command Rd' => 1)
          // OR 'Agbara' => 1 (direct city)

          data.forEach((cityKey, cityValue) {
            String cityName = cityKey.toString();

            if (cityValue is num || (cityValue is String && _isShippingZoneId(cityValue))) {
              // Direct city assignment (e.g., 'Agbara' => 1)
              cities.add({
                'code': _generateCityCode(cityName),
                'name': cityName,
                'state': stateCode,
                'country': 'NG',
                'shipping_zone': cityValue.toString(),
              });
            } else if (cityValue is Map) {
              // City with areas (e.g., 'Abule Egba' => {'Agbado Ijaye Road' => 1, ...})
              cityValue.forEach((areaKey, areaValue) {
                if (_isShippingZoneId(areaValue)) {
                  String areaName = areaKey.toString();
                  String fullLocationName = '$cityName - $areaName';

                  cities.add({
                    'code': _generateCityCode(fullLocationName),
                    'name': fullLocationName,
                    'state': stateCode,
                    'country': 'NG',
                    'city': cityName,
                    'area': areaName,
                    'shipping_zone': areaValue.toString(),
                  });
                }
              });
            } else if (cityValue is List) {
              // Handle list of areas for a city
              for (var area in cityValue) {
                if (area is String) {
                  String fullLocationName = '$cityName - $area';
                  cities.add({
                    'code': _generateCityCode(fullLocationName),
                    'name': fullLocationName,
                    'state': stateCode,
                    'country': 'NG',
                    'city': cityName,
                    'area': area,
                  });
                }
              }
            }
          });
        } else if (data is List) {
          // Handle simple list structure (fallback)
          for (var city in data) {
            if (city is String) {
              cities.add({
                'code': _generateCityCode(city),
                'name': city,
                'state': stateCode,
                'country': 'NG',
              });
            }
          }
        }

        // Sort cities alphabetically by name
        cities.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

        print('✅ Transformed ${cities.length} cities/areas for state $stateCode');
        print('✅ Sample cities: ${cities.take(3).map((c) => c['name']).join(', ')}...');
        return cities;
      }

      print('❌ Cities API failed with status: ${response.statusCode}');
      print('❌ Cities API response: ${response.body}');
      throw Exception('Failed to load cities for $stateCode: ${response.statusCode}');
    } catch (e) {
      print('❌ Exception in getTellmeCities: $e');
      throw Exception('Failed to load cities for $stateCode: $e');
    }
  }

  /// 🔧 Helper: Check if a value is a shipping zone ID (numeric)
  bool _isShippingZoneId(dynamic value) {
    if (value is num) return true;
    if (value is String) {
      return int.tryParse(value) != null;
    }
    return false;
  }

  /// 🔧 Helper: Generate clean city code from name
  String _generateCityCode(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // Remove special chars except spaces
        .replaceAll(RegExp(r'\s+'), '_') // Replace spaces with underscore
        .replaceAll(RegExp(r'_+'), '_') // Replace multiple underscores with single
        .replaceAll(RegExp(r'^_|_$'), ''); // Remove leading/trailing underscores
  }

  /// 📍 Helper method to get full state name from code
  String _getStateName(String code) {
    const stateNames = {
      'AB': 'Abia', 'FC': 'Abuja', 'AD': 'Adamawa', 'AK': 'Akwa Ibom', 'AN': 'Anambra',
      'BA': 'Bauchi', 'BY': 'Bayelsa', 'BE': 'Benue', 'BO': 'Borno', 'CR': 'Cross River',
      'DE': 'Delta', 'EB': 'Ebonyi', 'ED': 'Edo', 'EK': 'Ekiti', 'EN': 'Enugu',
      'GO': 'Gombe', 'IM': 'Imo', 'JI': 'Jigawa', 'KD': 'Kaduna', 'KN': 'Kano',
      'KT': 'Katsina', 'KE': 'Kebbi', 'KO': 'Kogi', 'KW': 'Kwara', 'LA': 'Lagos',
      'NA': 'Nasarawa', 'NI': 'Niger', 'OG': 'Ogun', 'ON': 'Ondo', 'OS': 'Osun',
      'OY': 'Oyo', 'PL': 'Plateau', 'RI': 'Rivers', 'SO': 'Sokoto',
      'TA': 'Taraba', 'YO': 'Yobe', 'ZA': 'Zamfara',
    };
    return stateNames[code] ?? code;
  }

  Future<Map<String, dynamic>> getLocations() async {
    try {
      print('📡 Fetching TellMe states...');
      final states = await getTellmeStates();

      print('📡 Fetching Lagos cities...');
      final cities = await getTellmeCities('LA');

      return {
        'countries': [
          {'code': 'NG', 'name': 'Nigeria'}
        ],
        'states': states,
        'cities': cities,
      };
    } catch (e) {
      print('⚠️ Falling back to default Nigeria data: $e');
      return _getDefaultLocationData();
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 🚚 ENHANCED SHIPPING ZONES & COMPLEX COST CALCULATION
  // ———————————————————————————————————————————————————————————————

  /// 🚚 Get complex shipping zone data (ladders, base costs, shipping classes)
  Future<Map<String, dynamic>> getEnhancedShippingZones() async {
    try {
      print('🚚 Fetching enhanced shipping zones from TellMe plugin...');
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/tellme/v1/shipping-zones'),
        headers: {'Content-Type': 'application/json'},
      );

      print('🚚 Enhanced shipping zones response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Enhanced shipping data loaded successfully');
        print('✅ Data keys: ${data.keys.toList()}');

        return {
          'success': true,
          'data': data,
          'ladders': data['ladders'] ?? {},
          'base_costs': data['base_costs'] ?? {},
          'shipping_classes': data['shipping_classes'] ?? {},
          'zones': data['zones'] ?? {},
        };
      } else {
        print('❌ Enhanced shipping zones API failed: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        return {
          'success': false,
          'error': 'API returned status ${response.statusCode}',
          'fallback': true,
        };
      }
    } catch (e) {
      print('❌ Exception fetching enhanced shipping zones: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
        'fallback': true,
      };
    }
  }

  /// 💰 Calculate shipping cost using complex TellMe logic
  /// Requires cart items with shipping_class information
  Future<Map<String, dynamic>> calculateEnhancedShippingCost({
    required String zoneId,
    required List<Map<String, dynamic>> cartItems,
  }) async {
    try {
      print('💰 Calculating enhanced shipping cost for zone: $zoneId');
      print('💰 Cart items count: ${cartItems.length}');

      // Get the enhanced shipping data
      final shippingData = await getEnhancedShippingZones();

      if (!shippingData['success']) {
        return {
          'success': false,
          'error': 'Failed to load shipping data: ${shippingData['error']}',
          'fallback_cost': 1500.0,
        };
      }

      final ladders = shippingData['ladders'] as Map<String, dynamic>;
      final baseCosts = shippingData['base_costs'] as Map<String, dynamic>;
      final shippingClasses = shippingData['shipping_classes'] as Map<String, dynamic>;

      print('💰 Available ladders: ${ladders.keys.toList()}');
      print('💰 Available base costs: ${baseCosts.keys.toList()}');
      print('💰 Shipping class mappings: $shippingClasses');

      // Calculate per-item costs based on shipping class and quantity
      double totalItemCost = 0.0;
      List<Map<String, dynamic>> itemBreakdown = [];

      for (var item in cartItems) {
        final shippingClass = item['shipping_class'] ?? '';
        final quantity = (item['quantity'] ?? 1).toInt();
        final productName = item['name'] ?? 'Unknown Product';

        print('💰 Processing item: $productName (class: $shippingClass, qty: $quantity)');

        if (shippingClass.isNotEmpty && shippingClasses.containsKey(shippingClass)) {
          final ladderKey = shippingClasses[shippingClass];
          print('💰 Using ladder key: $ladderKey for class: $shippingClass');

          if (ladders.containsKey(ladderKey)) {
            final ladder = ladders[ladderKey] as Map<String, dynamic>;

            if (ladder.containsKey(zoneId)) {
              final perItemCost = (ladder[zoneId] ?? 0).toDouble();
              final itemTotalCost = perItemCost * quantity;
              totalItemCost += itemTotalCost;

              itemBreakdown.add({
                'product_name': productName,
                'shipping_class': shippingClass,
                'ladder_key': ladderKey,
                'quantity': quantity,
                'per_item_cost': perItemCost,
                'total_cost': itemTotalCost,
              });

              print('💰 Item cost: $quantity x ₦$perItemCost = ₦$itemTotalCost');
            } else {
              print('⚠️ Zone $zoneId not found in ladder $ladderKey');
            }
          } else {
            print('⚠️ Ladder $ladderKey not found in ladders data');
          }
        } else {
          print('⚠️ No shipping class or invalid class for item: $productName');
          // For items without shipping class, you might want to use a default cost
          // or assign them to a default shipping class
        }
      }

      // Add base zone cost (charged once per order)
      final baseCost = (baseCosts[zoneId] ?? 0).toDouble();
      final totalShippingCost = totalItemCost + baseCost;

      print('💰 Calculation summary:');
      print('💰 Total item cost: ₦$totalItemCost');
      print('💰 Base zone cost: ₦$baseCost');
      print('💰 Total shipping cost: ₦$totalShippingCost');

      return {
        'success': true,
        'zone_id': zoneId,
        'total_cost': totalShippingCost,
        'item_cost': totalItemCost,
        'base_cost': baseCost,
        'formatted_cost': '₦${totalShippingCost.toStringAsFixed(2)}',
        'item_breakdown': itemBreakdown,
        'calculation_method': 'enhanced_tellme_logic',
      };

    } catch (e) {
      print('❌ Error calculating enhanced shipping cost: $e');
      return {
        'success': false,
        'error': 'Calculation error: $e',
        'fallback_cost': 1500.0,
      };
    }
  }

  /// 🔄 Enhanced calculate shipping for selected city (with complex logic)
  Future<Map<String, dynamic>> calculateEnhancedShippingForCity({
    required Map<String, dynamic> cityData,
    required List<Map<String, dynamic>> cartItems,
  }) async {
    try {
      print('🔄 Calculating enhanced shipping for: ${cityData['name']}');

      final String? zoneId = cityData['shipping_zone'];
      if (zoneId == null || zoneId.isEmpty) {
        return {
          'success': false,
          'error': 'No shipping zone found for this city',
          'shipping_method': 'No Method Available',
          'shipping_cost': 0.0,
          'formatted_cost': '₦0.00',
        };
      }

      // Use the enhanced calculation
      final costResult = await calculateEnhancedShippingCost(
        zoneId: zoneId,
        cartItems: cartItems,
      );

      if (costResult['success'] == true) {
        final totalCost = costResult['total_cost'] ?? 0.0;
        final formattedCost = costResult['formatted_cost'] ?? '₦0.00';

        return {
          'success': true,
          'shipping_method': 'TellMe Enhanced Delivery',
          'shipping_cost': totalCost,
          'formatted_cost': formattedCost,
          'shipping_description': 'Enhanced delivery to ${cityData['name']}',
          'zone_id': zoneId,
          'method_id': 'tellme_enhanced_$zoneId',
          'item_cost': costResult['item_cost'],
          'base_cost': costResult['base_cost'],
          'item_breakdown': costResult['item_breakdown'],
          'calculation_details': costResult,
        };
      } else {
        // Fallback to simple calculation
        final fallbackCost = costResult['fallback_cost'] ?? 1500.0;
        return {
          'success': true,
          'shipping_method': 'Standard Delivery',
          'shipping_cost': fallbackCost,
          'formatted_cost': '₦${fallbackCost.toStringAsFixed(2)}',
          'shipping_description': 'Standard delivery to ${cityData['name']}',
          'zone_id': zoneId,
          'method_id': 'tellme_fallback',
          'fallback_reason': costResult['error'],
        };
      }
    } catch (e) {
      print('❌ Error calculating enhanced shipping: $e');
      return {
        'success': false,
        'error': 'Enhanced calculation error: $e',
        'shipping_method': 'Unknown Method',
        'shipping_cost': 0.0,
        'formatted_cost': '₦0.00',
      };
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 🚚 LEGACY SHIPPING METHODS (Simple zone-based)
  // ———————————————————————————————————————————————————————————————

  Future<Map<String, dynamic>> getShippingZones() async {
    try {
      print('🚚 Fetching WooCommerce shipping zones...');
      final url = '$baseUrl/wp-json/wc/v3/shipping/zones';
      var authParams = _getAuthParams();
      var signature = _generateSignature('GET', url, authParams);
      authParams['oauth_signature'] = signature;

      String query = authParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final response = await http.get(Uri.parse('$url?$query'));

      if (response.statusCode == 200) {
        final zones = json.decode(response.body);
        print('✅ Zones loaded: ${zones.length}');
        return {'shipping_options': zones};
      }
      throw Exception('Shipping zone load failed');
    } catch (e) {
      print('❌ Shipping zone error: $e');
      return _getDefaultShippingData();
    }
  }

  /// 💰 Get shipping cost for a specific zone ID (legacy method)
  Future<Map<String, dynamic>> getShippingCostForZone(String zoneId) async {
    try {
      print('💰 Fetching shipping cost for zone: $zoneId');
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/tellme/v1/shipping-zones'),
        headers: {'Content-Type': 'application/json'},
      );

      print('💰 Shipping zones response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // The data should be like: {'1': 1500, '2': 2000, '3': 2500}
        if (data is Map && data.containsKey(zoneId)) {
          final cost = data[zoneId];
          return {
            'success': true,
            'zone_id': zoneId,
            'cost': cost.toDouble(),
            'formatted_cost': '₦${cost.toStringAsFixed(2)}',
          };
        } else {
          return {
            'success': false,
            'error': 'Zone $zoneId not found in shipping costs',
            'fallback_cost': 1500.0, // Default fallback cost
          };
        }
      } else {
        return {
          'success': false,
          'error': 'Failed to fetch shipping zones',
          'fallback_cost': 1500.0,
        };
      }
    } catch (e) {
      print('❌ Error getting shipping cost for zone $zoneId: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
        'fallback_cost': 1500.0,
      };
    }
  }

  /// 📦 Get shipping methods/costs for a selected city (legacy method)
  Future<Map<String, dynamic>> getShippingMethodsForCity(Map<String, dynamic> cityData) async {
    try {
      print('📦 Getting shipping methods for city: ${cityData['name']}');

      final String? zoneId = cityData['shipping_zone'];
      if (zoneId == null || zoneId.isEmpty) {
        return {
          'success': false,
          'error': 'No shipping zone found for this city',
          'shipping_options': [],
        };
      }

      // Get the cost for this zone
      final costResult = await getShippingCostForZone(zoneId);

      if (costResult['success'] == true) {
        final cost = costResult['cost'] ?? 1500.0;
        final formattedCost = costResult['formatted_cost'] ?? '₦${cost.toStringAsFixed(2)}';

        return {
          'success': true,
          'city_name': cityData['name'],
          'zone_id': zoneId,
          'shipping_options': [
            {
              'id': 'tellme_$zoneId',
              'title': 'TellMe Delivery',
              'cost': cost,
              'formatted_cost': formattedCost,
              'description': 'Delivery to ${cityData['name']}',
              'zone': zoneId,
            }
          ],
        };
      } else {
        // Fallback with default cost
        final fallbackCost = costResult['fallback_cost'] ?? 1500.0;
        return {
          'success': true,
          'city_name': cityData['name'],
          'zone_id': zoneId,
          'shipping_options': [
            {
              'id': 'tellme_default',
              'title': 'Standard Delivery',
              'cost': fallbackCost,
              'formatted_cost': '₦${fallbackCost.toStringAsFixed(2)}',
              'description': 'Standard delivery to ${cityData['name']}',
              'zone': zoneId,
            }
          ],
          'note': 'Using fallback cost due to: ${costResult['error']}',
        };
      }
    } catch (e) {
      print('❌ Error getting shipping methods for city: $e');
      return {
        'success': false,
        'error': 'Failed to get shipping methods: $e',
        'shipping_options': [],
      };
    }
  }

  /// 🔄 Calculate shipping for selected city (legacy method)
  Future<Map<String, dynamic>> calculateShippingForCity(Map<String, dynamic> cityData) async {
    try {
      print('🔄 Calculating shipping for: ${cityData['name']}');

      final shippingResult = await getShippingMethodsForCity(cityData);

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
      print('❌ Error calculating shipping: $e');
      return {
        'success': false,
        'error': 'Calculation error: $e',
        'shipping_method': 'Unknown Method',
        'shipping_cost': 0.0,
        'formatted_cost': '₦0.00',
      };
    }
  }

  /// 🏷️ Format shipping method display text
  String formatShippingMethod(Map<String, dynamic> shippingData) {
    if (shippingData['success'] == true) {
      final method = shippingData['shipping_method'] ?? 'Unknown Method';
      final cost = shippingData['formatted_cost'] ?? '₦0.00';
      return '$method - $cost';
    }
    return 'Unknown Method - ₦0.00';
  }

  /// 💲 Get shipping cost as double for calculations
  double getShippingCostAmount(Map<String, dynamic> shippingData) {
    if (shippingData['success'] == true) {
      return (shippingData['shipping_cost'] ?? 0.0).toDouble();
    }
    return 0.0;
  }

  // ———————————————————————————————————————————————————————————————
  // 💰 TERAWALLET INTEGRATION - FIXED ENDPOINTS
  // ———————————————————————————————————————————————————————————————

  /// 💳 Get wallet balance for a specific user
  Future<Map<String, dynamic>> getWalletBalance(int userId) async {
    try {
      print('💰 Fetching wallet balance for user: $userId');
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/wallet/v1/balance?user_id=$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print('💰 Wallet balance response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          return {
            'success': true,
            'balance': data['balance'],
            'user_id': data['user_id'],
            'timestamp': data['timestamp'],
          };
        } else {
          return {
            'success': false,
            'error': 'Failed to retrieve wallet balance',
            'details': data,
          };
        }
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['message'] ?? 'Failed to get wallet balance',
          'code': errorData['code'] ?? 'unknown_error',
        };
      }
    } catch (e) {
      print('❌ Error getting wallet balance: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 📊 Get wallet transactions for a specific user
  Future<Map<String, dynamic>> getWalletTransactions(int userId, {int limit = 10}) async {
    try {
      print('📊 Fetching wallet transactions for user: $userId');
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/wallet/v1/transactions?user_id=$userId&limit=$limit'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print('📊 Wallet transactions response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          return {
            'success': true,
            'transactions': data['transactions'],
            'count': data['count'],
            'user_id': data['user_id'],
            'timestamp': data['timestamp'],
          };
        } else {
          return {
            'success': false,
            'error': 'Failed to retrieve wallet transactions',
            'details': data,
          };
        }
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['message'] ?? 'Failed to get wallet transactions',
          'code': errorData['code'] ?? 'unknown_error',
        };
      }
    } catch (e) {
      print('❌ Error getting wallet transactions: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// ➕ Add funds to wallet (FIXED - no kobo conversion needed)
  Future<Map<String, dynamic>> addWalletFunds(int userId, double amount, {String? description}) async {
    try {
      print('➕ Adding ₦$amount to wallet for user: $userId');
      final response = await http.post(
        Uri.parse('$baseUrl/wp-json/wallet/v1/add-funds'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_id': userId,
          'amount': amount, // ✅ No kobo conversion needed - PHP handles this internally
          'description': description ?? 'Funds added via mobile app',
        }),
      );

      print('➕ Add wallet funds response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          return {
            'success': true,
            'message': data['message'],
            'transaction_id': data['transaction_id'],
            'amount_added': data['amount_added'],
            'new_balance': data['new_balance'],
            'timestamp': data['timestamp'],
          };
        } else {
          return {
            'success': false,
            'error': 'Failed to add funds to wallet',
            'details': data,
          };
        }
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['message'] ?? 'Failed to add funds to wallet',
          'code': errorData['code'] ?? 'unknown_error',
        };
      }
    } catch (e) {
      print('❌ Error adding wallet funds: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 💸 Debit funds from wallet using the correct /wallet/v1/debit endpoint
  Future<Map<String, dynamic>> debitWalletFunds(
    int userId,
    double amount, {
    String? orderId,
    String? description,
  }) async {
    try {
      print('💸 Debiting ₦$amount from wallet for user: $userId');

      // ✅ USE THE CORRECT DEBIT ENDPOINT (from PHP code)
      final response = await http.post(
        Uri.parse('$baseUrl/wp-json/wallet/v1/debit'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_id': userId,
          'amount': amount, // ✅ POSITIVE amount (plugin handles conversion internally)
          'description': description ?? 'Payment for Order #$orderId',
          if (orderId != null) 'order_id': int.parse(orderId),
        }),
      );

      print('💸 Wallet debit response: ${response.statusCode}');
      print('💸 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ Wallet debited successfully via /wallet/v1/debit endpoint');
        return {
          'success': true,
          'data': data,
          'endpoint_used': 'debit',
        };
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          errorData['message'] ?? 'Wallet debit failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Wallet debit error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 💵 Format wallet balance for display in UI - FIXED VERSION
  String formatWalletBalance(Map<String, dynamic> balanceData) {
    if (balanceData['success'] == true && balanceData['balance'] != null) {
      final balance = balanceData['balance'];

      // Always use the raw amount and format it properly in Flutter
      // ✅ FIXED: Convert to double to handle both int and double from API
      final amount = (balance['raw'] ?? 0.0).toDouble();
      final symbol = balance['currency_symbol'] ?? '₦';

      // Format the amount with thousands separators
      final formattedAmount = formatCurrency(amount);

      // If the symbol is an HTML entity, convert it to proper symbol
      String cleanSymbol = symbol;
      if (symbol.contains('&#8358;')) {
        cleanSymbol = '₦'; // Nigerian Naira
      } else if (symbol.contains('&')) {
        // Strip any other HTML entities and use fallback
        cleanSymbol = '₦';
      }

      return '$cleanSymbol$formattedAmount';
    }
    return '₦0.00';
  }

  /// 🔢 Helper method to format currency with thousands separators - MADE PUBLIC
  String formatCurrency(double amount) {
    // Format with 2 decimal places and thousands separators
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '₦${formatter.format(amount)}';
  }

  /// 🔢 Get wallet balance as a double value for calculations
  double getWalletBalanceAmount(Map<String, dynamic> balanceData) {
    if (balanceData['success'] == true && balanceData['balance'] != null) {
      final balance = balanceData['balance'];
      return (balance['raw'] ?? 0.0).toDouble();
    }
    return 0.0;
  }

  /// ✅ Check if user has sufficient wallet balance for a purchase
  bool hasSufficientWalletBalance(Map<String, dynamic> balanceData, double requiredAmount) {
    final currentBalance = getWalletBalanceAmount(balanceData);
    return currentBalance >= requiredAmount;
  }

/// 💳 Credit wallet (add funds) - for wallet top-up functionality - FIXED VERSION
Future<Map<String, dynamic>> creditWallet(
  int userId,
  double amount, [
  String description = 'Wallet Top-Up',
]) async {
  try {
    print('💳 Crediting ₦$amount to wallet for user: $userId');

    // ✅ FIXED: Use the correct endpoint that matches your PHP code
    final response = await http.post(
      Uri.parse('$baseUrl/wp-json/wallet/v1/add-funds'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'user_id': userId,
        'amount': amount,
        'description': description,
      }),
    );

    print('💳 Credit wallet response: ${response.statusCode} - ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['success'] == true) {
        print('✅ Wallet credited successfully!');
        return {
          'success': true,
          'message': data['message'],
          'transaction_id': data['transaction_id'],
          'amount_credited': data['amount_added'],
          'new_balance': data['new_balance'],
          'timestamp': data['timestamp'],
        };
      } else {
        print('❌ Wallet credit failed in API response');
        return {
          'success': false,
          'error': data['message'] ?? 'Failed to credit wallet',
          'details': data,
        };
      }
    } else {
      print('❌ HTTP error in wallet credit: ${response.statusCode}');
      final errorData = json.decode(response.body);
      return {
        'success': false,
        'error': errorData['message'] ?? 'Failed to credit wallet - HTTP ${response.statusCode}',
        'code': errorData['code'] ?? 'http_error',
        'status_code': response.statusCode,
      };
    }
  } catch (e) {
    print('❌ Error crediting wallet: $e');
    return {
      'success': false,
      'error': 'Network error: $e',
    };
  }
}

  // 💳 ENHANCED: Paystack payment initialization with DNS fallback
  Future<Map<String, dynamic>> initializePaystackTransaction({
    required String email,
    required double amount,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('💳 Initializing Paystack transaction with enhanced error handling...');
      print('💳 Email: $email, Amount: $amount, Reference: $reference');

      final response = await http.post(
        Uri.parse('https://api.paystack.co/transaction/initialize'),
        headers: {
          'Authorization': 'Bearer $paystackSecretKey',
          'Content-Type': 'application/json',
          'User-Agent': 'TellMe-Flutter-App/1.0',
        },
        body: json.encode({
          'email': email,
          'amount': (amount * 100).toInt(), // Convert to kobo
          'reference': reference,
          'metadata': metadata ?? {},
        }),
      ).timeout(Duration(seconds: 30));

      final result = json.decode(response.body);
      print('💳 Paystack initialization response: ${response.statusCode}');

      if (result['status'] == true) {
        print('✅ Paystack transaction initialized successfully');
        return result;
      } else {
        print('❌ Paystack initialization failed: ${result['message']}');
        return {
          'status': false,
          'message': result['message'] ?? 'Payment initialization failed',
          'errors': result['errors'] ?? [],
        };
      }
    } catch (e) {
      print('❌ Paystack initialization error: $e');

      // Enhanced error classification
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('OS Error')) {
        return {
          'status': false,
          'message': 'Network error: Cannot connect to payment server. Please check your internet connection.',
          'error_type': 'network_error',
          'original_error': e.toString(),
        };
      } else if (e.toString().contains('TimeoutException')) {
        return {
          'status': false,
          'message': 'Connection timeout. Please try again.',
          'error_type': 'timeout',
          'original_error': e.toString(),
        };
      } else {
        return {
          'status': false,
          'message': 'Payment initialization failed: $e',
          'error_type': 'unknown',
          'original_error': e.toString(),
        };
      }
    }
  }

  /// ✅ Enhanced Paystack transaction verification
  Future<Map<String, dynamic>> verifyPaystackTransaction(String reference) async {
    try {
      print('🔍 Verifying Paystack transaction: $reference');

      final response = await http.get(
        Uri.parse('https://api.paystack.co/transaction/verify/$reference'),
        headers: {
          'Authorization': 'Bearer $paystackSecretKey',
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 30));

      final result = json.decode(response.body);
      print('🔍 Verification response: ${response.statusCode}');
      print('🔍 Transaction status: ${result['data']['status']}');

      return result;
    } catch (e) {
      print('❌ Payment verification error: $e');
      return {
        'status': false,
        'message': 'Payment verification failed: $e',
        'data': {'status': 'failed'},
      };
    }
  }

  /// 👤 Helper method to get current user's wallet balance
  /// You'll need to store the current user ID somewhere in your app state
  Future<Map<String, dynamic>> getCurrentUserWalletBalance() async {
    // Replace this with your actual current user ID logic
    // You might get this from SharedPreferences, a state management solution, etc.
    final currentUserId = getCurrentUserId(); // Implement this method

    if (currentUserId != null) {
      return await getWalletBalance(currentUserId);
    } else {
      return {
        'success': false,
        'error': 'No current user found',
      };
    }
  }

  /// 🔧 Placeholder for getCurrentUserId - implement based on your app's user management
  int? getCurrentUserId() {
    // TODO: Implement this method to return the current user's ID
    // This might come from:
    // - SharedPreferences: SharedPreferences.getInstance().then((prefs) => prefs.getInt('user_id'))
    // - A state management solution (Provider, Riverpod, Bloc, etc.)
    // - A global variable or singleton

    // For testing, you can hardcode a user ID:
    return 1; // Replace with actual user management logic
  }


  // ———————————————————————————————————————————————————————————————
  // 🛒 ORDER CREATION (All Payment Methods)
  // ———————————————————————————————————————————————————————————————
  Future<Map<String, dynamic>?> createOrder({
    required int customerId,
    required List<Map<String, dynamic>> lineItems,
    required Map<String, String> billing,
    required Map<String, String> shipping,
    String? paymentReference,
    String? paymentMethod,
    String? paymentMethodTitle,
    String status = 'pending',
    Map<String, dynamic>? shippingLines,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('🛒 Creating order for customer: $customerId with payment method: $paymentMethod');
      final url = '$baseUrl/wp-json/wc/v3/orders';
      var authParams = _getAuthParams();

      // ✅ Normalize and handle Bank Transfer (bacs)
      if (status == 'pending_payment' || status == 'awaiting_bank_transfer') {
        status = 'pending';
      }
      if (paymentMethod == 'bacs') {
        print('🏦 Detected Bank Transfer (bacs) → Setting status to on-hold');
        status = 'on-hold';
      }

      var orderData = {
        'customer_id': customerId,
        'line_items': lineItems,
        'billing': billing,
        'shipping': shipping,
        'status': status,
      };

      // Add payment method info
      if (paymentMethod != null) orderData['payment_method'] = paymentMethod;
      if (paymentMethodTitle != null) orderData['payment_method_title'] = paymentMethodTitle;

      // For wallet payments, mark as paid instantly
      if (paymentMethod == 'woo-wallet') {
        orderData['set_paid'] = true;
        orderData['status'] = 'processing';
      }

      // For Paystack, include transaction reference
      if (paymentMethod == 'paystack' && paymentReference != null) {
        orderData['set_paid'] = true;
        orderData['transaction_id'] = paymentReference;
        orderData['meta_data'] = <Map<String, String>>[
          {'key': 'paystack_reference', 'value': paymentReference},
        ];
      }

      // ✅ Add Bank Transfer metadata
      if (paymentMethod == 'bacs') {
        orderData['meta_data'] = <Map<String, String>>[
          {'key': 'awaiting_bank_transfer', 'value': 'true'},
          {'key': 'payment_note', 'value': 'Customer selected Bank Transfer and will pay manually'},
          {'key': 'payment_initiated_at', 'value': DateTime.now().toIso8601String()},
        ];
      }

      // ✅ Add shipping info (ensure all are String values)
      if (shippingLines != null) {
        orderData['shipping_lines'] = <Map<String, String>>[
          {
            'method_id': shippingLines['method_id'].toString(),
            'method_title': shippingLines['title'].toString(),
            'total': shippingLines['cost'].toString(),
          }
        ];
      }

      // ✅ Add custom metadata (convert all entries to strings)
      if (metadata != null) {
        final metadataList = metadata.entries
            .map((e) => {'key': e.key.toString(), 'value': e.value.toString()})
            .toList();

        if (orderData['meta_data'] != null) {
          final existingMetadata = orderData['meta_data'] as List<Map<String, String>>;
          existingMetadata.addAll(metadataList);
        } else {
          orderData['meta_data'] = metadataList;
        }
      }

      print('🛒 Final Order Data: ${json.encode(orderData)}');

      var signature = _generateSignature('POST', url, authParams);
      authParams['oauth_signature'] = signature;

      String authHeader = 'OAuth ' +
          authParams.entries.map((e) => '${e.key}="${Uri.encodeComponent(e.value)}"').join(', ');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': authHeader},
        body: json.encode(orderData),
      );

      print('🛒 Order creation response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 201) {
        final orderResponse = json.decode(response.body);
        print('✅ Order created successfully: ${orderResponse['id']}');
        return orderResponse;
      } else {
        print('❌ Failed to create order: ${response.statusCode} - ${response.body}');
        return {
          'error': true,
          'message': 'Failed to create order',
          'status_code': response.statusCode,
          'response_body': response.body,
        };
      }
    } catch (e) {
      print('❌ Exception creating order: $e');
      return {'error': true, 'message': 'Exception creating order: $e'};
    }
  }

  /// 💰 Process wallet payment and create order (FIXED VERSION)
  Future<Map<String, dynamic>> processWalletPayment({
    required int userId,
    required double totalAmount,
    required List<Map<String, dynamic>> lineItems,
    required Map<String, String> billing,
    required Map<String, String> shipping,
    Map<String, dynamic>? shippingLines,
    String? customerNote,
  }) async {
    try {
      print('💰 Starting wallet payment process for user: $userId');
      print('💰 Total amount: ₦$totalAmount');

      // 1️⃣ Check wallet balance
      final balanceData = await getWalletBalance(userId);
      if (balanceData['error'] != null) {
        throw Exception('Failed to get wallet balance: ${balanceData['error']}');
      }

      // ✅ FIXED: Use the helper method instead of double.tryParse
      final double currentBalance = getWalletBalanceAmount(balanceData);

      print('💰 Current wallet balance: ₦$currentBalance');

      // 2️⃣ Verify sufficient balance
      if (currentBalance < totalAmount) {
        throw Exception(
          'Insufficient wallet balance. Available: ₦$currentBalance, Required: ₦$totalAmount',
        );
      }

      // 3️⃣ Create WooCommerce order
      print('📦 Creating WooCommerce order...');
      final orderResult = await createOrder(
        customerId: userId,
        lineItems: lineItems,
        billing: billing,
        shipping: shipping,
        paymentMethod: 'woo-wallet',
        paymentMethodTitle: 'TeraWallet',
        status: 'processing',
        metadata: {
          'wallet_payment': 'true',
          'payment_source': 'flutter_app',
        },
      );

      if (orderResult == null || orderResult['error'] == true) {
        throw Exception(
          'Order creation failed: ${orderResult?['message'] ?? 'Unknown error'}',
        );
      }

      final orderId = orderResult['id']?.toString() ?? 'unknown';
      print('✅ Order created successfully: #$orderId');

      // 4️⃣ ⚡ NOW DEBIT THE WALLET (This is the critical missing step!)
      print('💸 Debiting wallet for order #$orderId...');
      final debitResult = await debitWalletFunds(
        userId,
        totalAmount,
        orderId: orderId,
        description: 'Payment for Order #$orderId',
      );

      if (debitResult['success'] != true) {
        // ⚠️ Order was created but wallet debit failed
        print('⚠️ WARNING: Order created but wallet debit failed!');
        throw Exception(
          'Wallet debit failed: ${debitResult['error'] ?? 'Unknown error'}',
        );
      }

      print('✅ Wallet debited successfully');

      // 5️⃣ Return complete success
      return {
        'success': true,
        'order_id': orderId,
        'order_data': orderResult,
        'wallet_debited': true,
        'amount_debited': totalAmount,
      };
    } catch (e) {
      print('❌ Wallet payment error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }


  // ———————————————————————————————————————————————————————————————
  // // 👉 OPTIONAL: customer login via the same custom endpoint used above
  // ———————————————————————————————————————————————————————————————

  Future<Map<String, dynamic>?> loginCustomer(String email, String password) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/wp-json/tellme/v1/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email.trim(), 'password': password}),
      );

      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is Map && decoded['success'] == true) {
          // ✅ Cast safely to Map<String, dynamic>
          return Map<String, dynamic>.from(decoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }


  Future<bool> revokeAllSessions() async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/wp-json/tellme/v1/logout-all'),
        headers: {'Content-Type': 'application/json'},
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ———————————————————————————————————————————————————————————————
  // 🔧 HELPER METHODS & DEFAULT DATA
  // ———————————————————————————————————————————————————————————————
  Map<String, dynamic> _getDefaultLocationData() {
    return {
      'countries': [
        {'code': 'NG', 'name': 'Nigeria'}
      ],
      'states': [
        {'code': 'LA', 'name': 'Lagos', 'country': 'NG'},
        {'code': 'AB', 'name': 'Abuja (FCT)', 'country': 'NG'},
        {'code': 'KN', 'name': 'Kano', 'country': 'NG'},
        {'code': 'RV', 'name': 'Rivers', 'country': 'NG'},
        {'code': 'OG', 'name': 'Ogun', 'country': 'NG'},
      ],
      'cities': [
        {'code': 'ikeja', 'name': 'Ikeja', 'state': 'LA', 'country': 'NG'},
        {'code': 'surulere', 'name': 'Surulere', 'state': 'LA', 'country': 'NG'},
        {'code': 'victoria_island', 'name': 'Victoria Island', 'state': 'LA', 'country': 'NG'},
      ],
    };
  }

  Map<String, dynamic> _getDefaultShippingData() {
    return {
      'shipping_options': [
        {'id': '1', 'title': 'Standard Delivery', 'cost': '1500', 'zone': 'Nigeria'},
        {'id': '2', 'title': 'Express Delivery', 'cost': '2500', 'zone': 'Nigeria'},
      ],
    };
  }

  // ———————————————————————————————————————————————————————————————
  // 🗑️ ACCOUNT DELETION (uses tellme/v1/delete-account)
  // ———————————————————————————————————————————————————————————————

  /// Delete the current WP account using a WordPress **Application Password**.
  /// - [email]       The user’s WP login/email
  /// - [appPassword] The 24-char WP App Password generated in their WP Profile
  /// - [feedback]    Optional text (stored as user meta)
  ///
  /// Returns: { success: bool, message: String?, status?: int, body?: String }
  Future<Map<String, dynamic>> deleteAccountWithAppPassword({
    required String email,
    required String appPassword,
    String? feedback,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/wp-json/tellme/v1/delete-account');

      // WP displays Application Passwords with spaces → strip them
      final user = email.trim();
      final pass = appPassword.trim().replaceAll(RegExp(r'\s+'), '');

      // Basic auth with Application Password
      final basic = base64Encode(utf8.encode('$user:$pass'));
      final headers = <String, String>{
        'Authorization': 'Basic $basic',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final body = json.encode({
        'confirm': 'DELETE',
        if (feedback != null && feedback.trim().isNotEmpty)
          'feedback': feedback.trim(),
      });

      final resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 25));
      final status = resp.statusCode;

      // Try JSON decode; fall back to raw text
      Map<String, dynamic> parsed;
      try {
        parsed = Map<String, dynamic>.from(json.decode(resp.body));
      } catch (_) {
        parsed = {
          'success': status >= 200 && status < 300,
          'message': resp.body,
        };
      }

      if (status >= 200 && status < 300) {
        return {
          'success': true,
          'message': parsed['message'] ?? 'Account deleted',
          'status': status,
        };
      }

      // Friendlier messages for common auth errors
      String msg = parsed['message']?.toString() ?? 'Delete failed (HTTP $status)';
      if (status == 401 || status == 403) {
        msg =
            'Authentication failed. Check the email and Application Password (remove spaces) or enable Application Passwords in WordPress.';
      }

      return {
        'success': false,
        'message': msg,
        'status': status,
        'body': resp.body,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }


/// 🗑️ Delete account using EMAIL + PASSWORD
/// POST https://tellme.ng/wp-json/tellme/v1/delete-account-password
/// Body: { email, password, confirm: "DELETE", feedback? }
Future<Map<String, dynamic>> deleteAccountWithPassword({
  required String email,
  required String password,
  String? feedback,
}) async {
  final uri = Uri.parse('$baseUrl/wp-json/tellme/v1/delete-account-password');

  final payload = <String, dynamic>{
    'email': email.trim(),
    'password': password,
    'confirm': 'DELETE',
    if (feedback != null && feedback.trim().isNotEmpty) 'feedback': feedback.trim(),
  };

  try {
    final res = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(payload),
    );

    // Normalize response
    final statusOk = res.statusCode >= 200 && res.statusCode < 300;
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(res.body));
    } catch (_) {
      body = {'message': res.body};
    }

    if (statusOk || (body['success'] == true)) {
      return {
        'success': true,
        'message': body['message'] ?? 'Account deleted successfully.',
        'status': res.statusCode,
      };
    }

    return {
      'success': false,
      'message': body['message']?.toString() ?? 'Delete failed (HTTP ${res.statusCode}).',
      'status': res.statusCode,
    };
  } catch (e) {
    return {'success': false, 'message': 'Network error: $e'};
  }
}


  /// Alternate path: delete using an existing **WP cookie** session.
  /// Pass the full Cookie header string if you ever carry WP cookies.
  Future<Map<String, dynamic>> deleteAccountWithCookie({
    required String cookieHeader,
    String? feedback,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/wp-json/tellme/v1/delete-account');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Cookie': cookieHeader,
      };

      final body = json.encode({
        'confirm': 'DELETE',
        if (feedback != null && feedback.trim().isNotEmpty)
          'feedback': feedback.trim(),
      });

      final resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 25));
      final status = resp.statusCode;

      Map<String, dynamic> parsed;
      try {
        parsed = Map<String, dynamic>.from(json.decode(resp.body));
      } catch (_) {
        parsed = {
          'success': status >= 200 && status < 300,
          'message': resp.body,
        };
      }

      if (status >= 200 && status < 300) {
        return {
          'success': true,
          'message': parsed['message'] ?? 'Account deleted',
          'status': status,
        };
      }

      String msg = parsed['message']?.toString() ?? 'Delete failed (HTTP $status)';
      if (status == 401 || status == 403) {
        msg =
            'Not authenticated. Make sure the WordPress session (Cookie header) is valid.';
      }

      return {
        'success': false,
        'message': msg,
        'status': status,
        'body': resp.body,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// 📧 Send generic HTTP requests with OAuth signing
  Future<Map<String, dynamic>?> sendRequest(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    try {
      print('📡 Sending $method request to: $endpoint');

      final url = '$baseUrl/wp-json/$endpoint';
      final authParams = _getAuthParams();

      // Add data to params for GET requests
      if (method == 'GET' && data != null) {
        authParams.addAll(data.map((key, value) => MapEntry(key.toString(), value.toString())));
      }

      final signature = _generateSignature(method.toUpperCase(), url, authParams);
      authParams['oauth_signature'] = signature;

      final authHeader = 'OAuth ' +
          authParams.entries
              .map((e) => '${e.key}="${Uri.encodeComponent(e.value)}"')
              .join(', ');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': authHeader,
      };

      http.Response response;

      switch (method.toUpperCase()) {
        case 'POST':
          response = await http.post(
            Uri.parse(url),
            headers: headers,
            body: data != null ? json.encode(data) : null,
          );
          break;
        case 'PUT':
          response = await http.put(
            Uri.parse(url),
            headers: headers,
            body: data != null ? json.encode(data) : null,
          );
          break;
        case 'DELETE':
          response = await http.delete(
            Uri.parse(url),
            headers: headers,
          );
          break;
        default: // GET
          final queryString = authParams.entries
              .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
              .join('&');
          final fullUrl = '$url?$queryString';
          response = await http.get(Uri.parse(fullUrl));
      }

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return json.decode(response.body);
      } else {
        print('❌ Request failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Exception in sendRequest: $e');
      return null;
    }
  }

}