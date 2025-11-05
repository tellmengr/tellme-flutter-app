// lib/woocommerce_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class WooCommerceService {
  // 🌍 WooCommerce REST API base
  static const String baseUrl  = "https://tellme.ng/wp-json/wc/v3";
  static const String siteBase = "https://tellme.ng"; // ✅ for custom endpoints

  // 🔑 WooCommerce API credentials (keep yours here)
  static const String consumerKey    = "ck_0d41e4b1b9151e611ced4220bed993ac87afb94d";
  static const String consumerSecret = "cs_125a35108b788b64900b292f4ea4d678e461637e";

  // ⚙️ Config
  static const bool allowInsecureSSL = false;
  static const Duration requestTimeout = Duration(seconds: 15);
  static const int maxRetries = 2;

  // ------------------------------------------------------------
  // 🔧 Build REST URL (no auth by default; we use Basic Auth header)
  // ------------------------------------------------------------
  String _buildUrl(String endpoint, [Map<String, String>? extra]) {
    final uri = Uri.parse("$baseUrl/$endpoint").replace(queryParameters: {
      ...?extra,
    });
    return uri.toString();
  }

  Map<String, String> _authHeadersJson() {
    final token = base64Encode(utf8.encode('$consumerKey:$consumerSecret'));
    return {
      "Authorization": "Basic $token",
      "Accept": "application/json",
      "Content-Type": "application/json",
      "Connection": "keep-alive",
      "User-Agent": "TellMeApp/1.0",
    };
  }

  Map<String, String> _authHeadersGet() {
    final token = base64Encode(utf8.encode('$consumerKey:$consumerSecret'));
    return {
      "Authorization": "Basic $token",
      "Accept": "application/json",
      "Connection": "keep-alive",
      "User-Agent": "TellMeApp/1.0",
    };
  }

  // ------------------------------------------------------------
  // 🔁 Safe GET with retry and fallback to query-string auth
  // ------------------------------------------------------------
  Future<http.Response?> _safeGet(String endpoint, {Map<String, String>? extra}) async {
    final url = _buildUrl(endpoint, extra);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        // Primary: Basic Auth header
        final r = await http
            .get(Uri.parse(url), headers: _authHeadersGet())
            .timeout(requestTimeout);

        if (r.statusCode == 200) return r;

        // Fallback once: query-string auth (some hosts strip Authorization)
        if ((r.statusCode == 401 || r.statusCode == 403) && attempt == 0) {
          final altUrl = Uri.parse("$baseUrl/$endpoint").replace(queryParameters: {
            "consumer_key": consumerKey,
            "consumer_secret": consumerSecret,
            ...?extra,
          }).toString();

          final alt = await http
              .get(Uri.parse(altUrl), headers: {
                "Accept": "application/json",
                "Connection": "keep-alive",
                "User-Agent": "TellMeApp/1.0",
              })
              .timeout(requestTimeout);

          if (alt.statusCode == 200) return alt;
          // otherwise let retry loop continue
        }
      } on TimeoutException {
        // retry
      } on SocketException {
        // retry
      } on HandshakeException {
        // retry
      } catch (_) {
        // retry
      }

      if (attempt < maxRetries) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  // ------------------------------------------------------------
  // 🔁 Safe PUT with retry (Basic Auth)
  // ------------------------------------------------------------
  Future<http.Response?> _safePut(String endpoint, Map<String, dynamic> data) async {
    final url = _buildUrl(endpoint);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final r = await http
            .put(Uri.parse(url), headers: _authHeadersJson(), body: json.encode(data))
            .timeout(requestTimeout);

        if (r.statusCode == 200) return r;

        // Fallback to query auth once (rarely needed for PUT)
        if ((r.statusCode == 401 || r.statusCode == 403) && attempt == 0) {
          final altUrl = Uri.parse("$baseUrl/$endpoint").replace(queryParameters: {
            "consumer_key": consumerKey,
            "consumer_secret": consumerSecret,
          }).toString();

          final alt = await http
              .put(Uri.parse(altUrl), headers: _authHeadersJson(), body: json.encode(data))
              .timeout(requestTimeout);

          if (alt.statusCode == 200) return alt;
        }
      } catch (_) {}

      if (attempt < maxRetries) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  // ------------------------------------------------------------
  // 🔁 Safe POST (absolute URL) with retry (Basic Auth)
  // ------------------------------------------------------------
  Future<http.Response?> _safePostAbsUrl(Uri uri, Map<String, dynamic> data) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final r = await http
            .post(uri, headers: _authHeadersJson(), body: json.encode(data))
            .timeout(const Duration(seconds: 20));

        // Custom endpoints may return 200/201 for success, or 4xx with details
        return r;
      } on TimeoutException {
      } on SocketException {
      } on HandshakeException {
      } catch (_) {}

      if (attempt < maxRetries) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  // ===================================================================
  // 🔐 AUTH for CUSTOMERS — REAL PASSWORD VALIDATION (custom endpoints)
  // ===================================================================
  Future<Map<String, dynamic>?> signInCustomer(String email, String password) async {
    final uri = Uri.parse("$siteBase/wp-json/tellme/v1/login");
    try {
      final resp = await _safePostAbsUrl(uri, {
        "email": email.trim(),
        "password": password,
      });

      if (resp == null) return null;

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is Map && data['success'] == true && data['user'] != null) {
          return {
            "user": data['user'],
            "session": data['session'],
          };
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> logoutAllSessions({String? email}) async {
    final uri = Uri.parse("$siteBase/wp-json/tellme/v1/logout-all");
    try {
      final Map<String, dynamic> payload =
          email != null ? {"email": email} : <String, dynamic>{};
      final resp = await _safePostAbsUrl(uri, payload);
      return (resp != null && resp.statusCode == 200);
    } catch (_) {
      return false;
    }
  }

  // ===================================================================
  // 🛍️ PRODUCTS (paging-ready)
  // ===================================================================

  /// Simple list (kept for backward compatibility)
  Future<List<dynamic>> getProducts({int page = 1, int perPage = 20}) async {
    final response = await _safeGet(
      "products",
      extra: {
        "status": "publish",
        "per_page": "$perPage",
        "page": "$page",
        "orderby": "date",
        "order": "desc",
      },
    );

    if (response == null) return [];
    try {
      final data = json.decode(response.body);
      return (data is List) ? data : <dynamic>[];
    } catch (_) {
      return [];
    }
  }

  /// Preferred: returns items + server paging headers.
  Future<PagedProducts> getProductsPaged({
    int page = 1,
    int perPage = 20,
    int? categoryId,
  }) async {
    final params = <String, String>{
      "status": "publish",
      "per_page": "$perPage",
      "page": "$page",
      "orderby": "date",
      "order": "desc",
    };
    if (categoryId != null) params["category"] = "$categoryId";

    final r = await _safeGet("products", extra: params);
    if (r == null) {
      return const PagedProducts(items: [], total: 0, totalPages: 0);
    }

    final total      = int.tryParse(r.headers["x-wp-total"] ?? "") ?? 0;
    final totalPages = int.tryParse(r.headers["x-wp-totalpages"] ?? "") ?? 0;

    try {
      final items = json.decode(r.body) as List<dynamic>;
      return PagedProducts(items: items, total: total, totalPages: totalPages);
    } catch (_) {
      return PagedProducts(items: const [], total: total, totalPages: totalPages);
    }
  }

  Future<List<dynamic>> getProductsByCategory(
    int categoryId, {
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _safeGet(
      "products",
      extra: {
        "category": "$categoryId",
        "per_page": "$perPage",
        "page": "$page",
        "orderby": "date",
        "order": "desc",
        "status": "publish",
      },
    );

    if (response == null) return [];
    try {
      final data = json.decode(response.body);
      return (data is List) ? data : <dynamic>[];
    } catch (_) {
      return [];
    }
  }

  /// 🔍 Single product details (used by CartProvider cache)
  Future<Map<String, dynamic>?> getProductDetails(int productId) async {
    final response = await _safeGet("products/$productId");
    if (response == null) return null;
    try {
      final data = json.decode(response.body);
      return (data is Map<String, dynamic>) ? data : null;
    } catch (_) {
      return null;
    }
  }

  /// 🚚 Shipping class details (name, etc.) for a given class id
  Future<Map<String, dynamic>?> getShippingClassDetails(int classId) async {
    final response = await _safeGet("products/shipping_classes/$classId");
    if (response == null) return null;
    try {
      final data = json.decode(response.body);
      return (data is Map<String, dynamic>) ? data : null;
    } catch (_) {
      return null;
    }
  }

  // ===================================================================
  // 🗂️ CATEGORIES
  // ===================================================================
  Future<List<dynamic>> getParentCategories() async {
    final response = await _safeGet(
      "products/categories",
      extra: {"parent": "0", "per_page": "100"},
    );

    if (response == null) return [];
    try {
      final data = json.decode(response.body);
      return (data is List) ? data : <dynamic>[];
    } catch (_) {
      return [];
    }
  }

  Future<List<dynamic>> getSubCategories(int parentId) async {
    final response = await _safeGet(
      "products/categories",
      extra: {"parent": "$parentId", "per_page": "100"},
    );

    if (response == null) return [];
    try {
      final data = json.decode(response.body);
      return (data is List) ? data : <dynamic>[];
    } catch (_) {
      return [];
    }
  }

  // ===================================================================
  // 🧾 ORDERS / CUSTOMERS
  // ===================================================================
  Future<List<Map<String, dynamic>>> getCustomerOrders(int customerId) async {
    final response = await _safeGet(
      "orders",
      extra: {
        "customer": "$customerId",
        "per_page": "100",
        "orderby": "date",
        "order": "desc",
      },
    );

    if (response == null) return [];
    try {
      final List<dynamic> orders = json.decode(response.body);
      return orders.map((o) => (o as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getCustomerDetails(int customerId) async {
    final response = await _safeGet("customers/$customerId");
    if (response == null) return null;
    try {
      final data = json.decode(response.body);
      return (data is Map<String, dynamic>) ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateCustomer(
    int customerId, {
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (firstName != null) data['first_name'] = firstName;
    if (lastName  != null) data['last_name']  = lastName;
    if (email     != null) data['email']      = email;
    if (phone     != null) data['billing']    = {'phone': phone};

    final response = await _safePut("customers/$customerId", data);
    if (response == null) return null;
    try {
      final map = json.decode(response.body);
      return (map is Map<String, dynamic>) ? map : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCustomerByEmail(String email) async {
    final response = await _safeGet(
      "customers",
      extra: {"email": email, "per_page": "1"},
    );

    if (response == null) return null;
    try {
      final List<dynamic> customers = json.decode(response.body);
      if (customers.isNotEmpty) {
        return (customers.first as Map).cast<String, dynamic>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @deprecated
  Future<Map<String, dynamic>?> signInCustomerLegacy(
      String email, String password) async {
    // Legacy (insecure) path — kept only for reference.
    final customer = await getCustomerByEmail(email);
    return customer;
  }

  /// Use this one (calls /tellme/v1/login)
  Future<Map<String, dynamic>?> signInCustomerSecure(
      String email, String password) async {
    return await signInCustomer(email, password);
  }

  Future<Map<String, dynamic>?> createCustomer({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final Map<String, dynamic> data = <String, dynamic>{
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'username': email.split('@')[0],
      'password': password,
    };

    try {
      final url = _buildUrl("customers");
      final response = await http
          .post(Uri.parse(url), headers: _authHeadersJson(), body: json.encode(data))
          .timeout(requestTimeout);

      if (response.statusCode == 201) {
        final map = json.decode(response.body);
        return (map is Map<String, dynamic>) ? map : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCustomer(int customerId) async {
    return await getCustomerDetails(customerId);
  }

  Future<bool> updateCustomerPassword(int customerId, String newPassword) async {
    final Map<String, dynamic> data = <String, dynamic>{'password': newPassword};
    final response = await _safePut("customers/$customerId", data);
    if (response == null) return false;

    final ok = response.statusCode == 200;
    if (ok) {
      // Belt & braces: also tell server to destroy all sessions
      await logoutAllSessions().catchError((_) {});
    }
    return ok;
  }

  // ===================================================================
  // 🚚 SHIPPING (Custom endpoints used by your CartProvider)
  // ===================================================================
  Future<Map<String, dynamic>> calculateEnhancedShippingForCity({
    required Map<String, dynamic> cityData,
    required List<Map<String, dynamic>> cartItems,
  }) async {
    final uri = Uri.parse("$siteBase/wp-json/tellme/v1/shipping/calc");

    try {
      final resp = await _safePostAbsUrl(uri, {
        "city": cityData,
        "items": cartItems,
      });

      if (resp == null) {
        return {
          'success': false,
          'error': 'No response from server',
          'shipping_cost': 0.0,
          'formatted_cost': '₦0.00',
        };
      }

      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body is Map) {
          final map = body.cast<String, dynamic>();
          final costNum = double.tryParse(map['shipping_cost']?.toString() ?? '0') ?? 0.0;
          final formatted = map['formatted_cost']?.toString() ?? '₦${costNum.toStringAsFixed(2)}';
          return {
            'success': map['success'] == true,
            'shipping_cost': costNum,
            'formatted_cost': formatted,
            'breakdown': map['breakdown'],
            'method': map['method'],
          };
        }
      }

      return {
        'success': false,
        'error': 'Server returned ${resp.statusCode}',
        'shipping_cost': 0.0,
        'formatted_cost': '₦0.00',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Calculation error: $e',
        'shipping_cost': 0.0,
        'formatted_cost': '₦0.00',
      };
    }
  }

  Future<Map<String, dynamic>> getShippingMethodsForCity(
      Map<String, dynamic> cityData) async {
    final uri = Uri.parse("$siteBase/wp-json/tellme/v1/shipping/methods");

    try {
      final resp = await _safePostAbsUrl(uri, {"city": cityData});

      if (resp == null) {
        return {
          'success': false,
          'error': 'No response from server',
          'shipping_options': const <Map<String, dynamic>>[],
        };
      }

      final body = json.decode(resp.body);
      if (resp.statusCode == 200 && body is Map) {
        final map = body.cast<String, dynamic>();
        final raw = map['shipping_options'];
        List<Map<String, dynamic>> opts = [];
        if (raw is List) {
          opts = raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
        // Normalize numeric cost + formatted
        opts = opts.map((o) {
          final cost = double.tryParse(o['cost']?.toString() ?? '0') ?? 0.0;
          final formatted = o['formatted_cost']?.toString() ?? '₦${cost.toStringAsFixed(2)}';
          return {
            ...o,
            'cost': cost,
            'formatted_cost': formatted,
          };
        }).toList();

        return {
          'success': map['success'] == true,
          'shipping_options': opts,
        };
      }

      return {
        'success': false,
        'error': 'Server returned ${resp.statusCode}',
        'shipping_options': const <Map<String, dynamic>>[],
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Request error: $e',
        'shipping_options': const <Map<String, dynamic>>[],
      };
    }
  }
}

// ----------------------
// Paging result model
// ----------------------
class PagedProducts {
  final List<dynamic> items;
  final int total;
  final int totalPages;
  const PagedProducts({
    required this.items,
    required this.total,
    required this.totalPages,
  });
}
