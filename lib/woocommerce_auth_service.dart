import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

import 'tellme_account_api.dart';

class WooCommerceAuthService {
  // ✅ WooCommerce site base
  static const String baseUrl = 'https://tellme.ng';
  static const String apiBaseUrl = '$baseUrl/api/v1';

  // 🔐 WooCommerce API keys
  static const String consumerKey =
      'ck_0d41e4b1b9151e611ced4220bed993ac87afb94d';
  static const String consumerSecret =
      'cs_125a35108b788b64900b292f4ea4d678e461637e';

  // 💳 Paystack API keys (read securely at build time)
  static const String paystackSecretKey = String.fromEnvironment(
      'PAYSTACK_SECRET_KEY'); // injected with --dart-define
  static const String paystackPublicKey = String.fromEnvironment(
      'PAYSTACK_PUBLIC_KEY'); // injected with --dart-define

  // 🔥 Firebase instances for admin verification
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TellmeAccountApi _accountApi = TellmeAccountApi();

  Uri _apiUri(String path, [Map<String, String>? queryParameters]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$apiBaseUrl/$cleanPath')
        .replace(queryParameters: queryParameters);
  }

  Map<String, String> get _jsonHeaders => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  String _cleanString(dynamic value) => value?.toString().trim() ?? '';

  String _firstText(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _cleanString(data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _isHex32(String? value) {
    if (value == null) return false;
    return RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(value.trim());
  }

  String _slugify(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  double _toNairaAmount(dynamic value) {
    if (value == null) return 0.0;
    final raw = value is num
        ? value.toDouble()
        : double.tryParse(value.toString().replaceAll(RegExp(r'[^\d.]'), '')) ??
            0.0;
    return raw >= 10000 ? raw / 100 : raw;
  }

  String _formatNaira(double amount) => 'NGN ${amount.toStringAsFixed(2)}';

  String? _extractVariantId(Map<dynamic, dynamic> item) {
    String normalizeOptionKey(String value) => value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final direct = _firstText(item, [
      'variantId',
      'variant_id',
      'backendVariantId',
      'backend_variant_id',
    ]);
    if (_isHex32(direct)) return direct;

    final selectedOptions = <String, String>{};
    selectedOptions.addAll(_stringOptions(item['attributes']));
    selectedOptions.addAll(_stringOptions(item['selectedOptions']));
    selectedOptions.addAll(_stringOptions(item['options']));

    final color = _cleanString(item['color']);
    if (color.isNotEmpty) selectedOptions.putIfAbsent('Color', () => color);

    final size = _cleanString(item['size']);
    if (size.isNotEmpty) {
      selectedOptions.putIfAbsent('Size', () => size);
      selectedOptions.putIfAbsent('Shoe Size', () => size);
    }

    final normalizedSelected = <String, String>{};
    selectedOptions.forEach((key, value) {
      final cleanedValue = value.trim().toLowerCase();
      if (cleanedValue.isNotEmpty) {
        normalizedSelected[normalizeOptionKey(key)] = cleanedValue;
      }
    });

    final variants = item['variants'];
    if (variants is List && variants.isNotEmpty) {
      if (normalizedSelected.isEmpty && variants.length == 1) {
        final only = variants.first;
        if (only is Map) {
          final value = _firstText(only, [
            'id',
            'variantId',
            'variant_id',
            'backendVariantId',
            'backend_variant_id',
          ]);
          if (_isHex32(value)) return value;
        }
      }

      for (final raw in variants) {
        if (raw is! Map) continue;
        final options = <String, String>{};
        options.addAll(_stringOptions(raw['attributes']));
        options.addAll(_stringOptions(raw['options']));

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
            final value = _firstText(raw, [
              'id',
              'variantId',
              'variant_id',
              'backendVariantId',
              'backend_variant_id',
            ]);
            if (_isHex32(value)) return value;
          }
        }
      }
    }

    return null;
  }

  Map<String, String> _stringOptions(dynamic options) {
    if (options is! Map) return {};
    return options.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  String _baseTellMeSku(String value) {
    final match =
        RegExp(r'(TELLME\d+)', caseSensitive: false).firstMatch(value.trim());
    return match?.group(1)?.toUpperCase() ?? '';
  }

  Set<String> _lookupCandidates(String value) {
    final raw = value.trim();
    final baseSku = _baseTellMeSku(raw);
    return {
      if (raw.isNotEmpty) raw.toUpperCase(),
      if (baseSku.isNotEmpty) baseSku,
    };
  }

  String _lookupText(dynamic value) =>
      value?.toString().trim().toUpperCase() ?? '';

  Map<String, dynamic>? _findVariantByLookup(
    List<dynamic> variants,
    Set<String> candidates,
  ) {
    if (candidates.isEmpty) return null;

    for (final raw in variants) {
      if (raw is! Map) continue;
      final variant = raw.cast<String, dynamic>();
      for (final key in const ['sku', 'variantSku', 'variant_sku']) {
        if (candidates.contains(_lookupText(variant[key]))) return variant;
      }
    }

    for (final raw in variants) {
      if (raw is! Map) continue;
      final variant = raw.cast<String, dynamic>();
      final sku = _lookupText(
          variant['sku'] ?? variant['variantSku'] ?? variant['variant_sku']);
      final baseSku = _baseTellMeSku(sku);
      if (baseSku.isNotEmpty && candidates.contains(baseSku)) return variant;
    }

    return null;
  }

  Map<String, dynamic>? _normalizeCatalogProduct(
    Map<String, dynamic> product, {
    Map<String, dynamic>? preferredVariant,
  }) {
    final variants =
        product['variants'] is List ? product['variants'] as List : <dynamic>[];
    final firstVariant = preferredVariant ??
        (variants.whereType<Map>().isNotEmpty
            ? variants.whereType<Map>().first.cast<String, dynamic>()
            : <String, dynamic>{});
    final price = firstVariant['price'] is Map
        ? (firstVariant['price'] as Map)['amount']
        : product['price'];
    final rawId = product['legacyId'] ?? product['id'];
    final numericId =
        rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

    return {
      'id': numericId ?? rawId,
      'product_id': numericId ?? rawId,
      'backendId': product['id'],
      'variant_id': firstVariant['id'],
      'variantId': firstVariant['id'],
      'name': product['name'] ?? '',
      'price': _toNairaAmount(price).toStringAsFixed(2),
      'regular_price': _toNairaAmount(price).toStringAsFixed(2),
      'sale_price': '',
      'shipping_class': '',
      'shipping_class_id': 0,
      'weight': '',
      'dimensions': {},
      'categories': [
        {
          'name': product['category'],
          'slug': product['categorySlug'],
        }
      ],
      'images': [
        {'src': product['imageUrl'] ?? product['visual'] ?? ''}
      ],
      'stock_status': firstVariant['stockStatus'] ?? 'instock',
      'manage_stock': false,
      'stock_quantity': null,
      'sku': firstVariant['sku'] ?? product['sku'] ?? '',
      'variants': variants,
      'average_rating': product['average_rating'] ??
          product['averageRating'] ??
          product['rating_average'] ??
          product['ratingAverage'] ??
          product['review_average'] ??
          product['reviewAverage'] ??
          (product['reviews'] is Map
              ? (product['reviews'] as Map)['average']
              : null) ??
          product['rating'] ??
          '0',
      'rating_count': product['rating_count'] ??
          product['ratingCount'] ??
          product['review_count'] ??
          product['reviewCount'] ??
          product['reviews_count'] ??
          product['reviewsCount'] ??
          (product['reviews'] is Map
              ? (product['reviews'] as Map)['count']
              : null) ??
          0,
    };
  }

  // 🔑 Generate a strong random password for social signups
  String _generateRandomPassword([int length = 12]) {
    // Avoid ambiguous characters; include symbols for strength
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#\$%&*!?';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
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
        print(
            'ℹ️ tellme/v1/password-reset failed/unavailable: ${r1.statusCode} ${r1.body}');
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
        print(
            'ℹ️ bdpwr/v1/reset-password failed/unavailable: ${r2.statusCode} ${r2.body}');
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
        print(
            'ℹ️ wp/v2/users/lostpassword failed/unavailable: ${r3.statusCode} ${r3.body}');
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

      print(
          '❌ All password reset attempts failed. Last status: ${r4.statusCode} ${r4.body}');
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
      final loc =
          (r.headers['location'] ?? r.headers['Location'] ?? '').toLowerCase();
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
          if (j['data'] is Map &&
              ((j['data']['status'] == 200) ||
                  (j['data']['success'] == true))) {
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
            (roles.contains('administrator') ||
                roles.contains('shop_manager'))) {
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
  String _generateSignature(
      String method, String url, Map<String, String> params) {
    var sortedParams = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    String paramString = sortedParams.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
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
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authHeader
        },
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

      print(
          '❌ Failed to create customer: ${response.statusCode} - ${response.body}');
    } catch (e) {
      print('❌ Exception creating customer: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> validateCustomer(
      String email, String password) async {
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
        print(
            '❌ validateCustomer failed: ${response.statusCode} - ${response.body}');
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
        print(
            '❌ getCustomerByEmail failed: ${response.statusCode} - ${response.body}');
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
  Future<Map<String, dynamic>?> getProductDetails(dynamic productId) async {
    try {
      final requestedProductId = productId?.toString().trim() ?? '';
      if (requestedProductId.isEmpty) return null;

      final candidates = _lookupCandidates(requestedProductId);
      final baseSku = _baseTellMeSku(requestedProductId);
      final query = baseSku.isNotEmpty ? baseSku : requestedProductId;

      print(
          'Fetching product details from TellMe catalog for ID/SKU: $requestedProductId');
      final response = await http.get(
        _apiUri('products', {'q': query, 'per_page': '20'}),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final products = decoded is Map && decoded['data'] is List
            ? decoded['data'] as List
            : <dynamic>[];

        for (final product in products.whereType<Map>()) {
          final productMap = product.cast<String, dynamic>();
          final variants = productMap['variants'] is List
              ? productMap['variants'] as List
              : <dynamic>[];
          final matchedVariant = _findVariantByLookup(variants, candidates);

          final legacyId = _lookupText(productMap['legacyId']);
          final id = _lookupText(productMap['id']);
          final sku = _lookupText(productMap['sku']);
          final baseProductSku = _baseTellMeSku(sku);
          final productMatches = candidates.contains(legacyId) ||
              candidates.contains(id) ||
              candidates.contains(sku) ||
              (baseProductSku.isNotEmpty &&
                  candidates.contains(baseProductSku));

          if (productMatches ||
              matchedVariant != null ||
              products.length == 1) {
            final normalized = _normalizeCatalogProduct(
              productMap,
              preferredVariant: matchedVariant,
            );
            if (normalized != null) {
              print('Product details loaded: ${normalized['name']}');
              return normalized;
            }
          }
        }

        print('Product $productId was not returned by the TellMe catalog.');
        return null;
      }

      print('Failed to fetch product details: ${response.statusCode}');
      return null;
    } catch (e) {
      print('Exception fetching product details: $e');
      return null;
    }
  }

  /// 📦 Get shipping class details by ID
  Future<Map<String, dynamic>?> getShippingClassDetails(
      int shippingClassId) async {
    try {
      print('📦 Fetching shipping class details for ID: $shippingClassId');
      final url =
          '$baseUrl/wp-json/wc/v3/products/shipping_classes/$shippingClassId';
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

        return classesData
            .map((classData) => {
                  'id': classData['id'],
                  'name': classData['name'],
                  'slug': classData['slug'],
                  'description': classData['description'],
                  'count': classData['count'],
                })
            .toList();
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
  Future<List<dynamic>> searchProductsByName(String name,
      {int perPage = 20}) async {
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
  Future<List<dynamic>> searchProductsByCategory(String categorySlug,
      {int perPage = 20}) async {
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
        print(
            '✅ Found ${products.length} products in category "$categorySlug"');
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
      print('Fetching Nigerian states from TellMe delivery API...');
      final response = await http.get(
        _apiUri('delivery/places'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawStates = data is Map && data['states'] is List
            ? data['states'] as List
            : data is List
                ? data
                : <dynamic>[];

        final states = rawStates
            .map<Map<String, dynamic>>((state) {
              if (state is Map) {
                final code = _firstText(state, [
                  'code',
                  'stateCode',
                  'id',
                  'slug',
                  'abbreviation',
                ]);
                final name = _firstText(state, ['name', 'label', 'stateName']);
                return {
                  'code': code.isNotEmpty ? code : _slugify(name),
                  'name': name.isNotEmpty ? name : _getStateName(code),
                  'country': 'NG',
                };
              }

              final name = state.toString();
              return {
                'code': _slugify(name),
                'name': name,
                'country': 'NG',
              };
            })
            .where((state) => state['name'].toString().isNotEmpty)
            .toList();

        states.sort(
            (a, b) => a['name'].toString().compareTo(b['name'].toString()));

        if (states.isNotEmpty) {
          print('Transformed ${states.length} states');
          return states;
        }
      }

      print('States API failed with status: ${response.statusCode}');
      return _getDefaultStates();
    } catch (e) {
      print('Exception in getTellmeStates: $e');
      return _getDefaultStates();
    }
  }

  /// 🏙️ Get cities for a specific state from TellMe Shipping plugin
  Future<List<Map<String, dynamic>>> getTellmeCities(String stateCode) async {
    try {
      print(
          'Fetching cities for state: $stateCode from TellMe delivery API...');
      final response = await http.get(
        _apiUri('delivery/places', {'state': stateCode}),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawCities = data is Map && data['cities'] is List
            ? data['cities'] as List
            : data is List
                ? data
                : <dynamic>[];

        final cities = rawCities
            .map<Map<String, dynamic>>((city) {
              if (city is Map) {
                final name =
                    _firstText(city, ['name', 'label', 'city', 'cityName']);
                final code =
                    _firstText(city, ['code', 'cityCode', 'id', 'slug']);
                final zone = _firstText(city, [
                  'shipping_zone',
                  'zoneId',
                  'deliveryZoneId',
                  'deliveryZone',
                ]);
                return {
                  'code': code.isNotEmpty ? code : _slugify(name),
                  'name': name,
                  'state': _firstText(city, ['state', 'stateCode']).isNotEmpty
                      ? _firstText(city, ['state', 'stateCode'])
                      : stateCode,
                  'country': 'NG',
                  'shipping_zone': zone.isNotEmpty ? zone : code,
                };
              }

              final name = city.toString();
              return {
                'code': _slugify(name),
                'name': name,
                'state': stateCode,
                'country': 'NG',
                'shipping_zone': _slugify(name),
              };
            })
            .where((city) => city['name'].toString().isNotEmpty)
            .toList();

        cities.sort(
            (a, b) => a['name'].toString().compareTo(b['name'].toString()));

        if (cities.isNotEmpty) {
          print(
              'Transformed ${cities.length} cities/areas for state $stateCode');
          return cities;
        }
      }

      print('Cities API failed with status: ${response.statusCode}');
      return _getDefaultCitiesForState(stateCode);
    } catch (e) {
      print('Exception in getTellmeCities: $e');
      return _getDefaultCitiesForState(stateCode);
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
        .replaceAll(
            RegExp(r'[^a-z0-9\s]'), '') // Remove special chars except spaces
        .replaceAll(RegExp(r'\s+'), '_') // Replace spaces with underscore
        .replaceAll(
            RegExp(r'_+'), '_') // Replace multiple underscores with single
        .replaceAll(
            RegExp(r'^_|_$'), ''); // Remove leading/trailing underscores
  }

  /// 📍 Helper method to get full state name from code
  String _getStateName(String code) {
    const stateNames = {
      'AB': 'Abia',
      'FC': 'Abuja',
      'AD': 'Adamawa',
      'AK': 'Akwa Ibom',
      'AN': 'Anambra',
      'BA': 'Bauchi',
      'BY': 'Bayelsa',
      'BE': 'Benue',
      'BO': 'Borno',
      'CR': 'Cross River',
      'DE': 'Delta',
      'EB': 'Ebonyi',
      'ED': 'Edo',
      'EK': 'Ekiti',
      'EN': 'Enugu',
      'GO': 'Gombe',
      'IM': 'Imo',
      'JI': 'Jigawa',
      'KD': 'Kaduna',
      'KN': 'Kano',
      'KT': 'Katsina',
      'KE': 'Kebbi',
      'KO': 'Kogi',
      'KW': 'Kwara',
      'LA': 'Lagos',
      'NA': 'Nasarawa',
      'NI': 'Niger',
      'OG': 'Ogun',
      'ON': 'Ondo',
      'OS': 'Osun',
      'OY': 'Oyo',
      'PL': 'Plateau',
      'RI': 'Rivers',
      'SO': 'Sokoto',
      'TA': 'Taraba',
      'YO': 'Yobe',
      'ZA': 'Zamfara',
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
      final shippingClasses =
          shippingData['shipping_classes'] as Map<String, dynamic>;

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

        print(
            '💰 Processing item: $productName (class: $shippingClass, qty: $quantity)');

        if (shippingClass.isNotEmpty &&
            shippingClasses.containsKey(shippingClass)) {
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

              print(
                  '💰 Item cost: $quantity x ₦$perItemCost = ₦$itemTotalCost');
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
      print('Calculating delivery for: ${cityData['name']}');

      final lines = <Map<String, dynamic>>[];
      for (final item in cartItems) {
        final variantId = _extractVariantId(item);
        if (variantId == null) continue;
        lines.add({
          'variantId': variantId,
          'quantity': int.tryParse(item['quantity']?.toString() ?? '') ?? 1,
        });
      }

      if (lines.isEmpty) {
        return {
          'success': false,
          'error':
              'Cart items need current TellMe product variants before delivery can be calculated.',
          'shipping_method': 'No Method Available',
          'shipping_cost': 0.0,
          'formatted_cost': _formatNaira(0),
          'shipping_options': [],
        };
      }

      final cityName = _firstText(cityData, ['name', 'city', 'label']);
      final state = _firstText(cityData, ['state', 'stateCode', 'state_code']);
      final response = await http.post(
        _apiUri('delivery/calculate'),
        headers: _jsonHeaders,
        body: json.encode({
          'state': state,
          'city': cityName,
          'lines': lines,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = json.decode(response.body);
        final delivery = decoded is Map && decoded['delivery'] is Map
            ? decoded['delivery'] as Map
            : decoded is Map
                ? decoded
                : <String, dynamic>{};
        final totalCost = _toNairaAmount(
          delivery['amount'] ?? delivery['cost'] ?? delivery['total'],
        );
        final zoneId =
            _firstText(delivery, ['zoneId', 'zone', 'deliveryZoneId'])
                    .isNotEmpty
                ? _firstText(delivery, ['zoneId', 'zone', 'deliveryZoneId'])
                : _cleanString(cityData['shipping_zone']);

        return {
          'success': true,
          'shipping_method':
              _firstText(delivery, ['method', 'label']).isNotEmpty
                  ? _firstText(delivery, ['method', 'label'])
                  : 'TellMe Delivery',
          'shipping_cost': totalCost,
          'formatted_cost': _formatNaira(totalCost),
          'shipping_description': 'Delivery to $cityName',
          'zone_id': zoneId,
          'method_id':
              'tellme_delivery_${zoneId.isNotEmpty ? zoneId : _slugify(cityName)}',
          'calculation_details': decoded,
        };
      }

      print(
          'Delivery calculation failed: ${response.statusCode} ${response.body}');
      return {
        'success': false,
        'error': 'Delivery calculation failed',
        'shipping_method': 'Unknown Method',
        'shipping_cost': 0.0,
        'formatted_cost': _formatNaira(0),
      };
    } catch (e) {
      print('Error calculating enhanced shipping: $e');
      return {
        'success': false,
        'error': 'Enhanced calculation error: $e',
        'shipping_method': 'Unknown Method',
        'shipping_cost': 0.0,
        'formatted_cost': _formatNaira(0),
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

      print(
          '💰 Shipping zones response: ${response.statusCode} - ${response.body}');

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
  Future<Map<String, dynamic>> getShippingMethodsForCity(
      Map<String, dynamic> cityData) async {
    try {
      print('Getting fallback shipping method for city: ${cityData['name']}');

      final zoneId = _cleanString(cityData['shipping_zone']).isNotEmpty
          ? _cleanString(cityData['shipping_zone'])
          : _slugify(_cleanString(cityData['name']));
      final cost = _toNairaAmount(
        cityData['shipping_cost'] ??
            cityData['cost'] ??
            cityData['amount'] ??
            1500,
      );

      return {
        'success': true,
        'city_name': cityData['name'],
        'zone_id': zoneId,
        'shipping_options': [
          {
            'id': 'tellme_$zoneId',
            'title': 'TellMe Delivery',
            'cost': cost,
            'formatted_cost': _formatNaira(cost),
            'description': 'Delivery to ${cityData['name']}',
            'zone': zoneId,
          }
        ],
      };
    } catch (e) {
      print('Error getting shipping methods for city: $e');
      return {
        'success': false,
        'error': 'Failed to get shipping methods: $e',
        'shipping_options': [],
      };
    }
  }

  /// 🔄 Calculate shipping for selected city (legacy method)
  Future<Map<String, dynamic>> calculateShippingForCity(
      Map<String, dynamic> cityData) async {
    try {
      print('🔄 Calculating shipping for: ${cityData['name']}');

      final shippingResult = await getShippingMethodsForCity(cityData);

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
  Future<Map<String, dynamic>> getWalletBalance([int? userId]) async {
    try {
      final apiResult = await _accountApi.getWalletBalance(userId: userId);
      if (apiResult['success'] == true) return apiResult;
      if (userId == null || userId <= 0) return apiResult;

      print('💰 Fetching wallet balance for user: $userId');
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/wallet/v1/balance?user_id=$userId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print(
          '💰 Wallet balance response: ${response.statusCode} - ${response.body}');

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
  Future<Map<String, dynamic>> getWalletTransactions(int? userId,
      {int limit = 10}) async {
    try {
      final apiResult = await _accountApi.getWalletHistory(
        userId: userId,
        limit: limit,
      );
      if (apiResult['success'] == true) return apiResult;
      if (userId == null || userId <= 0) return apiResult;

      print('📊 Fetching wallet transactions for user: $userId');
      final response = await http.get(
        Uri.parse(
            '$baseUrl/wp-json/wallet/v1/transactions?user_id=$userId&limit=$limit'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print(
          '📊 Wallet transactions response: ${response.statusCode} - ${response.body}');

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
  Future<Map<String, dynamic>> addWalletFunds(int? userId, double amount,
      {String? description}) async {
    try {
      final apiResult = await _accountApi.createWalletTopUp(
        userId: userId,
        amount: amount,
        description: description ?? 'Funds added via mobile app',
      );
      if (apiResult['success'] == true) return apiResult;
      if (userId == null || userId <= 0) return apiResult;

      print('➕ Adding ₦$amount to wallet for user: $userId');
      final response = await http.post(
        Uri.parse('$baseUrl/wp-json/wallet/v1/add-funds'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_id': userId,
          'amount':
              amount, // ✅ No kobo conversion needed - PHP handles this internally
          'description': description ?? 'Funds added via mobile app',
        }),
      );

      print(
          '➕ Add wallet funds response: ${response.statusCode} - ${response.body}');

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
    int? userId,
    double amount, {
    String? userIdText,
    String? orderId,
    String? description,
  }) async {
    try {
      print(
          'Debiting wallet through TellMe backend for user: ${userIdText ?? userId}');

      final apiResult = await _accountApi.debitWallet(
        userId: userId,
        userIdText: userIdText,
        amount: amount,
        orderId: orderId,
        description: description ?? 'Payment for Order #$orderId',
      );
      if (apiResult['success'] == true) {
        return apiResult;
      }

      final numericOrderId = int.tryParse(orderId ?? '');
      if (numericOrderId == null || userId == null || userId <= 0) {
        return {
          ...apiResult,
          'success': false,
          'error': apiResult['error'] ??
              'Wallet debit is not available for this backend order yet.',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/wp-json/wallet/v1/debit'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_id': userId,
          'amount': amount,
          'description': description ?? 'Payment for Order #$orderId',
          'order_id': numericOrderId,
        }),
      );

      print('Wallet debit response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data,
          'endpoint_used': 'legacy_debit',
        };
      }

      final errorData = json.decode(response.body);
      throw Exception(
        errorData['message'] ??
            'Wallet debit failed with status ${response.statusCode}',
      );
    } catch (e) {
      print('Wallet debit error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Format wallet balance for display in UI - FIXED VERSION
  String formatWalletBalance(Map<String, dynamic> balanceData) {
    if (balanceData['success'] == true && balanceData['balance'] != null) {
      final balance = balanceData['balance'];

      // Always use the raw amount and format it properly in Flutter
      // ✅ FIXED: Convert to double to handle both int and double from API
      final rawAmount = balance['raw'] ?? balance['amount'] ?? 0.0;
      final amount = rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse(rawAmount.toString()) ?? 0.0;
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
      final raw =
          balance is Map ? balance['raw'] ?? balance['amount'] : balance;
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? 0.0;
    }
    return 0.0;
  }

  /// ✅ Check if user has sufficient wallet balance for a purchase
  bool hasSufficientWalletBalance(
      Map<String, dynamic> balanceData, double requiredAmount) {
    final currentBalance = getWalletBalanceAmount(balanceData);
    return currentBalance >= requiredAmount;
  }

  /// 💳 Credit wallet (add funds) - for wallet top-up functionality - FIXED VERSION
  Future<Map<String, dynamic>> creditWallet(
    int? userId,
    double amount, [
    String description = 'Wallet Top-Up',
  ]) async {
    try {
      final referenceMatch =
          RegExp(r'Reference:\s*([A-Za-z0-9_\-]+)').firstMatch(description);
      final apiResult = await _accountApi.createWalletTopUp(
        userId: userId,
        amount: amount,
        reference: referenceMatch?.group(1),
        description: description,
      );
      if (apiResult['success'] == true) return apiResult;
      if (userId == null || userId <= 0) return apiResult;

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

      print(
          '💳 Credit wallet response: ${response.statusCode} - ${response.body}');

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
          'error': errorData['message'] ??
              'Failed to credit wallet - HTTP ${response.statusCode}',
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

  // Paystack payment initialization must happen on the TellMe backend.
  Future<Map<String, dynamic>> initializePaystackTransaction({
    required String email,
    required double amount,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('Initializing Paystack transaction on TellMe backend...');
      print('Email: $email, Amount: $amount, Reference: $reference');

      final result = await _accountApi.initializePaystackTransaction(
        email: email,
        amount: amount,
        reference: reference,
        metadata: metadata,
      );

      if (result['status'] == true) {
        print('Paystack transaction initialized successfully');
        return result;
      }

      return {
        'status': false,
        'message': result['message'] ??
            result['error'] ??
            'Payment initialization failed',
        'errors': result['errors'] ?? result['details'] ?? [],
      };
    } catch (e) {
      print('Paystack initialization error: $e');
      return {
        'status': false,
        'message': 'Payment initialization failed: $e',
        'error_type': 'backend_initialize_error',
        'original_error': e.toString(),
      };
    }
  }

  /// Verify Paystack transaction on the TellMe backend.
  Future<Map<String, dynamic>> verifyPaystackTransaction(
      String reference) async {
    try {
      print('Verifying Paystack transaction on TellMe backend: $reference');
      return await _accountApi.verifyPaystackTransaction(reference);
    } catch (e) {
      print('Payment verification error: $e');
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
      print('Creating TellMe order for customer: $customerId');

      final lines = <Map<String, dynamic>>[];
      for (final line in lineItems) {
        final variantId = _extractVariantId(line);
        if (variantId == null) {
          return {
            'error': true,
            'message':
                'Cart items need current TellMe variant IDs before checkout can continue.',
          };
        }

        lines.add({
          'variantId': variantId,
          'quantity': int.tryParse(line['quantity']?.toString() ?? '') ?? 1,
          if (_cleanString(line['variantLabel']).isNotEmpty)
            'variantLabel': _cleanString(line['variantLabel']),
          if (_stringOptions(line['selectedOptions']).isNotEmpty)
            'selectedOptions': _stringOptions(line['selectedOptions']),
        });
      }

      final email = billing['email'] ?? shipping['email'] ?? '';
      final firstName =
          billing['first_name'] ?? shipping['first_name'] ?? 'Customer';
      final lastName =
          billing['last_name'] ?? shipping['last_name'] ?? 'TellMe';
      final phone = billing['phone'] ?? shipping['phone'] ?? '';
      final city = shipping['city'] ?? billing['city'] ?? '';
      final state = shipping['state'] ?? billing['state'] ?? '';
      final addressLine1 = shipping['address_1'] ?? billing['address_1'] ?? '';
      final addressLine2 = shipping['address_2'] ?? billing['address_2'] ?? '';

      final orderData = {
        'customer': {
          'email': email,
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
          'addressLine1': addressLine1,
          if (addressLine2.isNotEmpty) 'addressLine2': addressLine2,
          'city': city,
          'state': state,
          if (metadata != null || paymentReference != null)
            'note': json.encode({
              if (paymentMethod != null) 'paymentMethod': paymentMethod,
              if (paymentMethodTitle != null)
                'paymentMethodTitle': paymentMethodTitle,
              if (paymentReference != null)
                'paymentReference': paymentReference,
              if (metadata != null) ...metadata,
              'mobileStatus': status,
            }),
        },
        'billingSameAsDelivery': true,
        'lines': lines,
      };

      final response = await http.post(
        _apiUri('checkout/orders'),
        headers: _jsonHeaders,
        body: json.encode(orderData),
      );

      print(
          'TellMe order creation response: ${response.statusCode} - ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = json.decode(response.body);
        final order = decoded is Map && decoded['order'] is Map
            ? decoded['order'] as Map
            : decoded is Map
                ? decoded
                : <String, dynamic>{};
        final normalized = order.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final orderId = normalized['id'] ??
            normalized['orderId'] ??
            normalized['orderNumber'];

        normalized['id'] = orderId;
        normalized['number'] =
            normalized['orderNumber'] ?? normalized['number'] ?? orderId;
        normalized['status'] = decoded is Map
            ? decoded['status'] ?? normalized['status'] ?? status
            : normalized['status'] ?? status;
        if (decoded is Map && decoded['payment'] != null) {
          normalized['payment'] = decoded['payment'];
        }
        normalized['raw'] = decoded;

        print('Order created successfully: $orderId');
        return normalized;
      }

      print(
          'Failed to create order: ${response.statusCode} - ${response.body}');
      return {
        'error': true,
        'message': 'Failed to create order',
        'status_code': response.statusCode,
        'response_body': response.body,
      };
    } catch (e) {
      print('Exception creating order: $e');
      return {'error': true, 'message': 'Exception creating order: $e'};
    }
  }

  /// 💰 Process wallet payment and create order (FIXED VERSION)
  Future<Map<String, dynamic>> processWalletPayment({
    required int? userId,
    required String? userIdText,
    required double totalAmount,
    required List<Map<String, dynamic>> lineItems,
    required Map<String, String> billing,
    required Map<String, String> shipping,
    Map<String, dynamic>? shippingLines,
    String? customerNote,
  }) async {
    try {
      print('Wallet payment process for user: ${userIdText ?? userId}');
      print('💰 Total amount: ₦$totalAmount');

      // 1️⃣ Check wallet balance
      final balanceData = await getWalletBalance(userId);
      if (balanceData['error'] != null) {
        throw Exception(
            'Failed to get wallet balance: ${balanceData['error']}');
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
        customerId: userId ?? 0,
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
        userIdText: userIdText,
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

  Future<Map<String, dynamic>?> loginCustomer(
      String email, String password) async {
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
        {
          'code': 'surulere',
          'name': 'Surulere',
          'state': 'LA',
          'country': 'NG'
        },
        {
          'code': 'victoria_island',
          'name': 'Victoria Island',
          'state': 'LA',
          'country': 'NG'
        },
      ],
    };
  }

  List<Map<String, dynamic>> _getDefaultStates() {
    return List<Map<String, dynamic>>.from(
        _getDefaultLocationData()['states'] as List);
  }

  List<Map<String, dynamic>> _getDefaultCitiesForState(String stateCode) {
    final defaultCities = List<Map<String, dynamic>>.from(
        _getDefaultLocationData()['cities'] as List);
    final filtered = defaultCities
        .where((city) => city['state']?.toString() == stateCode)
        .toList();
    return filtered.isNotEmpty ? filtered : defaultCities;
  }

  Map<String, dynamic> _getDefaultShippingData() {
    return {
      'shipping_options': [
        {
          'id': '1',
          'title': 'Standard Delivery',
          'cost': '1500',
          'zone': 'Nigeria'
        },
        {
          'id': '2',
          'title': 'Express Delivery',
          'cost': '2500',
          'zone': 'Nigeria'
        },
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
      String msg =
          parsed['message']?.toString() ?? 'Delete failed (HTTP $status)';
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
    try {
      return await _accountApi.deleteAccount(
        email: email,
        password: password,
        confirm: 'DELETE',
        feedback: feedback,
      );
    } catch (_) {
      // Fall back to the legacy endpoint while the new API is being deployed.
    }

    final uri = Uri.parse('$baseUrl/wp-json/tellme/v1/delete-account-password');

    final payload = <String, dynamic>{
      'email': email.trim(),
      'password': password,
      'confirm': 'DELETE',
      if (feedback != null && feedback.trim().isNotEmpty)
        'feedback': feedback.trim(),
    };

    try {
      final res = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
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
        'message': body['message']?.toString() ??
            'Delete failed (HTTP ${res.statusCode}).',
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

      String msg =
          parsed['message']?.toString() ?? 'Delete failed (HTTP $status)';
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
        authParams.addAll(data
            .map((key, value) => MapEntry(key.toString(), value.toString())));
      }

      final signature =
          _generateSignature(method.toUpperCase(), url, authParams);
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
