// lib/woocommerce_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'tellme_account_api.dart';

class WooCommerceService {
  // New TellMe backend API for product/category data.
  static const String catalogueBaseUrl = "https://tellme.ng/api/v1";

  // Kept for existing non-catalog methods until auth/orders/shipping are moved.
  static const String siteBase = "https://tellme.ng";

  static const Duration requestTimeout = Duration(seconds: 15);
  static const int maxRetries = 2;
  final TellmeAccountApi _accountApi = TellmeAccountApi();

  String _buildCatalogueUrl(String endpoint, [Map<String, String>? extra]) {
    final uri = Uri.parse("$catalogueBaseUrl/$endpoint").replace(
      queryParameters: {
        ...?extra,
      },
    );

    return uri.toString();
  }

  Map<String, String> _headersJson() {
    return {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "User-Agent": "TellMeApp/1.0",
    };
  }

  Map<String, String> _headersGet() {
    return {
      "Accept": "application/json",
      "User-Agent": "TellMeApp/1.0",
    };
  }

  String _sessionFromSetCookie(String? setCookie) {
    if (setCookie == null || setCookie.trim().isEmpty) return "";

    for (final name in const [
      "tm_customer_session",
      "tellme_customer_session",
      "tellme_session",
      "customer_session",
    ]) {
      final match = RegExp("$name=([^;,]+)").firstMatch(setCookie);
      final value = match?.group(1)?.trim() ?? "";
      if (value.isNotEmpty) return Uri.decodeComponent(value);
    }

    return "";
  }

  Future<http.Response?> _safeCatalogueGet(
    String endpoint, {
    Map<String, String>? extra,
  }) async {
    final url = _buildCatalogueUrl(endpoint, extra);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: _headersGet())
            .timeout(requestTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
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

  List<dynamic> _extractList(dynamic decoded, String key) {
    if (decoded is List) return decoded;
    if (decoded is Map && decoded[key] is List) {
      return decoded[key] as List<dynamic>;
    }
    return <dynamic>[];
  }

  String _stringValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != "null") {
        return text;
      }
    }

    return "";
  }

  String _priceValue(Map<String, dynamic> product) {
    final variants = product["variants"];

    if (variants is List && variants.isNotEmpty) {
      final firstVariant = variants.first;

      if (firstVariant is Map) {
        final variant = firstVariant.cast<String, dynamic>();
        final price = variant["price"];

        if (price is Map) {
          final amount = price["amount"];

          if (amount is num) {
            return (amount / 100).toStringAsFixed(0);
          }

          final rawAmount = num.tryParse(amount?.toString() ?? "");
          if (rawAmount != null) {
            return (rawAmount / 100).toStringAsFixed(0);
          }
        }

        final directVariantPrice = variant["price"] ??
            variant["amount"] ??
            variant["sellingPrice"] ??
            variant["regularPrice"];

        if (directVariantPrice is num) {
          return directVariantPrice.toStringAsFixed(0);
        }

        final directText = directVariantPrice?.toString() ?? "";
        final cleaned = directText.replaceAll(RegExp(r"[^0-9.]"), "");
        if (cleaned.isNotEmpty) return cleaned;
      }
    }

    final raw = _stringValue(product, const [
      "price",
      "salePrice",
      "sale_price",
      "sellingPrice",
      "selling_price",
      "currentPrice",
      "current_price",
      "regularPrice",
      "regular_price",
      "amount",
      "minPrice",
      "min_price",
    ]);

    if (raw.isEmpty) return "0";

    final cleaned = raw.replaceAll(RegExp(r"[^0-9.]"), "");
    if (cleaned.isEmpty) return "0";

    return cleaned;
  }

  String _stockStatus(Map<String, dynamic> product) {
    final direct = product["stock_status"] ??
        product["stockStatus"] ??
        product["availability"];

    if (direct != null) {
      final text = direct.toString().toLowerCase();
      if (text == "in_stock") return "instock";
      if (text == "out_of_stock") return "outofstock";
      return text;
    }

    final variants = product["variants"];
    if (variants is List && variants.isNotEmpty) {
      final firstVariant = variants.first;

      if (firstVariant is Map) {
        final status = firstVariant["stockStatus"]?.toString().toLowerCase();
        if (status == "in_stock") return "instock";
        if (status == "out_of_stock") return "outofstock";
      }
    }

    return "instock";
  }

  String _absoluteImageUrl(String value) {
    final image = value.trim();
    if (image.isEmpty) return "";

    if (image.startsWith("http://") || image.startsWith("https://")) {
      return image;
    }

    if (image.startsWith("//")) {
      return "https:$image";
    }

    if (image.startsWith("/")) {
      return "$siteBase$image";
    }

    return "$siteBase/$image";
  }

  List<dynamic> _normalizeImages(Map<String, dynamic> product) {
    final candidates = <String>[];

    final rawImages = product["images"];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is String) {
          candidates.add(item);
        } else if (item is Map) {
          final map = item.cast<String, dynamic>();
          final src = _stringValue(map, const [
            "src",
            "url",
            "image",
            "imageUrl",
            "thumbnail",
            "thumbnailUrl",
          ]);
          if (src.isNotEmpty) candidates.add(src);
        }
      }
    }

    final directImage = _stringValue(product, const [
      "image",
      "imageUrl",
      "image_url",
      "thumbnail",
      "thumbnailUrl",
      "thumbnail_url",
      "featuredImage",
      "featured_image",
      "photo",
      "photoUrl",
      "photo_url",
    ]);

    if (directImage.isNotEmpty) {
      candidates.add(directImage);
    }

    final seen = <String>{};
    return candidates
        .map(_absoluteImageUrl)
        .where((src) => src.isNotEmpty && seen.add(src))
        .map((src) => {"src": src})
        .toList();
  }

  String _priceFromVariant(Map<String, dynamic> variant) {
    final price = variant["price"];

    if (price is Map) {
      final amount = price["amount"];

      if (amount is num) {
        return (amount / 100).toStringAsFixed(0);
      }

      final rawAmount = num.tryParse(amount?.toString() ?? "");
      if (rawAmount != null) {
        return (rawAmount / 100).toStringAsFixed(0);
      }
    }

    final directPrice = variant["price"] ??
        variant["amount"] ??
        variant["sellingPrice"] ??
        variant["regularPrice"];

    if (directPrice is num) {
      return directPrice.toStringAsFixed(0);
    }

    final cleaned =
        directPrice?.toString().replaceAll(RegExp(r"[^0-9.]"), "") ?? "";
    return cleaned.isNotEmpty ? cleaned : "0";
  }

  List<dynamic> _normalizeAttributes(Map<String, dynamic> product) {
    final existing = product["attributes"];
    if (existing is List && existing.isNotEmpty) return existing;

    final options = product["options"];
    if (options is! List) return <dynamic>[];

    return options
        .whereType<Map>()
        .map((option) {
          final name = option["name"]?.toString() ?? "";
          final values = option["values"];

          return {
            "name": name,
            "visible": true,
            "variation": true,
            "options": values is List
                ? values.map((value) => value.toString()).toList()
                : <String>[],
          };
        })
        .where((attribute) =>
            attribute["name"].toString().isNotEmpty &&
            attribute["options"] is List &&
            (attribute["options"] as List).isNotEmpty)
        .toList();
  }

  List<dynamic> _normalizeVariations(Map<String, dynamic> product) {
    final existing = product["variations"];
    if (existing is List && existing.isNotEmpty) return existing;

    final variants = product["variants"];
    if (variants is! List) return <dynamic>[];

    return variants.whereType<Map>().map((item) {
      final variant = item.cast<String, dynamic>();
      final price = _priceFromVariant(variant);
      final stockStatus =
          variant["stockStatus"]?.toString().toLowerCase() ?? "in_stock";

      return {
        ...variant,
        "id": variant["id"],
        "sku": variant["sku"] ?? "",
        "price": price,
        "regular_price": price,
        "sale_price": "",
        "stock_status": stockStatus == "out_of_stock"
            ? "outofstock"
            : stockStatus == "in_stock"
                ? "instock"
                : stockStatus,
      };
    }).toList();
  }

  String _productType(
    Map<String, dynamic> product,
    List<dynamic> attributes,
    List<dynamic> variations,
  ) {
    final existingType = product["type"]?.toString() ?? "";
    if (existingType.isNotEmpty && existingType.toLowerCase() != "null") {
      return existingType;
    }

    if (attributes.isNotEmpty || variations.isNotEmpty) {
      return "variable";
    }

    return "simple";
  }

  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> product) {
    final rawId = product["legacyId"] ?? product["id"];
    final numericId = int.tryParse(rawId?.toString() ?? "");

    final images = _normalizeImages(product);
    final attributes = _normalizeAttributes(product);
    final variations = _normalizeVariations(product);
    final variants =
        product["variants"] is List ? product["variants"] as List : <dynamic>[];
    final firstVariant = variants.whereType<Map>().isNotEmpty
        ? variants.whereType<Map>().first.cast<String, dynamic>()
        : <String, dynamic>{};

    final categoryName = product["category"]?.toString() ?? "";
    final categorySlug = product["categorySlug"]?.toString() ?? "";
    final price = _priceValue(product);
    final regularPrice = _stringValue(product, const [
      "regularPrice",
      "regular_price",
      "compareAtPrice",
      "compare_at_price",
      "oldPrice",
      "old_price",
      "price",
    ]).replaceAll(RegExp(r"[^0-9.]"), "");

    return {
      ...product,
      "id": numericId ?? rawId,
      "backendId": product["id"],
      "product_id": numericId ?? rawId,
      "variant_id": firstVariant["id"],
      "variantId": firstVariant["id"],
      "legacyId": product["legacyId"],
      "sku": firstVariant["sku"] ?? product["sku"] ?? "",
      "name": product["name"] ?? "",
      "slug": product["slug"] ?? "",
      "description": product["description"] ?? "",
      "short_description": product["shortDescription"] ??
          product["short_description"] ??
          product["description"] ??
          "",
      "price": price,
      "regular_price": regularPrice.isNotEmpty ? regularPrice : price,
      "sale_price": product["salePrice"]?.toString() ??
          product["sale_price"]?.toString() ??
          "",
      "images": images,
      "stock_status": _stockStatus(product),
      "type": _productType(product, attributes, variations),
      "attributes": attributes,
      "options": product["options"] ?? attributes,
      "variants": variants.isNotEmpty ? variants : variations,
      "variations": variations,
      "average_rating": product["average_rating"] ??
          product["averageRating"] ??
          product["rating_average"] ??
          product["ratingAverage"] ??
          product["review_average"] ??
          product["reviewAverage"] ??
          (product["reviews"] is Map
              ? (product["reviews"] as Map)["average"]
              : null) ??
          product["rating"] ??
          "0",
      "rating_count": product["rating_count"] ??
          product["ratingCount"] ??
          product["review_count"] ??
          product["reviewCount"] ??
          product["reviews_count"] ??
          product["reviewsCount"] ??
          (product["reviews"] is Map
              ? (product["reviews"] as Map)["count"]
              : null) ??
          0,
      "total_sales": product["total_sales"] ??
          product["totalSales"] ??
          product["sales"] ??
          0,
      "date_created": product["date_created"] ??
          product["dateCreated"] ??
          product["createdAt"] ??
          product["created_at"] ??
          DateTime.now().toIso8601String(),
      "categories": categoryName.isNotEmpty
          ? [
              {
                "name": categoryName,
                "slug": categorySlug,
              }
            ]
          : <dynamic>[],
    };
  }

  List<dynamic> _normalizeProducts(List<dynamic> products) {
    return products.map((item) {
      if (item is Map<String, dynamic>) {
        return _normalizeProduct(item);
      }

      if (item is Map) {
        return _normalizeProduct(item.cast<String, dynamic>());
      }

      return item;
    }).toList();
  }

  Map<String, dynamic> _normalizeCategory(Map<String, dynamic> category) {
    final children = category["children"];

    return {
      ...category,
      "id": category["id"] ?? category["slug"],
      "name": category["name"] ?? "",
      "slug": category["slug"] ?? "",
      "parent": category["parent"] ?? 0,
      "count": category["count"] ?? 0,
      "children": children is List ? children : <dynamic>[],
    };
  }

  List<dynamic> _normalizeCategories(List<dynamic> categories) {
    return categories.map((item) {
      if (item is Map<String, dynamic>) {
        return _normalizeCategory(item);
      }

      if (item is Map) {
        return _normalizeCategory(item.cast<String, dynamic>());
      }

      return item;
    }).toList();
  }

  Future<List<dynamic>> getProducts({int page = 1, int perPage = 20}) async {
    final response = await _safeCatalogueGet(
      "products",
      extra: {
        "page": "$page",
        "per_page": "$perPage",
      },
    );

    if (response == null) return <dynamic>[];

    try {
      final decoded = json.decode(response.body);
      final products = _extractList(decoded, "data");
      return _normalizeProducts(products);
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<PagedProducts> getProductsPaged({
    int page = 1,
    int perPage = 20,
    int? categoryId,
  }) async {
    final params = <String, String>{
      "page": "$page",
      "per_page": "$perPage",
    };

    if (categoryId != null) {
      params["category"] = "$categoryId";
    }

    final response = await _safeCatalogueGet("products", extra: params);

    if (response == null) {
      return const PagedProducts(items: [], total: 0, totalPages: 0);
    }

    try {
      final decoded = json.decode(response.body);
      final products = _normalizeProducts(_extractList(decoded, "data"));

      final pagination = decoded is Map && decoded["pagination"] is Map
          ? (decoded["pagination"] as Map)
          : const {};

      final total = pagination["total"] is num
          ? (pagination["total"] as num).toInt()
          : decoded is Map && decoded["total"] is num
              ? (decoded["total"] as num).toInt()
              : products.length;

      final totalPages = pagination["total_pages"] is num
          ? (pagination["total_pages"] as num).toInt()
          : decoded is Map && decoded["totalPages"] is num
              ? (decoded["totalPages"] as num).toInt()
              : 0;

      return PagedProducts(
        items: products,
        total: total,
        totalPages: totalPages,
      );
    } catch (_) {
      return const PagedProducts(items: [], total: 0, totalPages: 0);
    }
  }

  Future<List<dynamic>> getProductsByCategory(
    String categoryId, {
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _safeCatalogueGet(
      "products",
      extra: {
        "category": categoryId,
        "page": "$page",
        "per_page": "$perPage",
      },
    );

    if (response == null) return <dynamic>[];

    try {
      final decoded = json.decode(response.body);
      final products = _extractList(decoded, "data");
      return _normalizeProducts(products);
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>?> getProductDetails(int productId) async {
    final response = await _safeCatalogueGet("products/$productId");

    if (response == null) return null;

    try {
      final decoded = json.decode(response.body);

      if (decoded is Map && decoded["data"] is Map) {
        return _normalizeProduct(
          (decoded["data"] as Map).cast<String, dynamic>(),
        );
      }

      if (decoded is Map<String, dynamic>) {
        return _normalizeProduct(decoded);
      }

      if (decoded is Map) {
        return _normalizeProduct(decoded.cast<String, dynamic>());
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getShippingClassDetails(int classId) async {
    return null;
  }

  Future<List<dynamic>> getParentCategories() async {
    final response = await _safeCatalogueGet("categories");

    if (response == null) return <dynamic>[];

    try {
      final decoded = json.decode(response.body);
      final categories = _extractList(decoded, "categories");
      return _normalizeCategories(categories);
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> getSubCategories(String parentId) async {
    final categories = await getParentCategories();

    for (final item in categories) {
      if (item is! Map) continue;

      final id = item["id"]?.toString();
      final slug = item["slug"]?.toString();

      if (id != parentId && slug != parentId) continue;

      final children = item["children"];
      if (children is List) {
        return _normalizeCategories(children);
      }
    }

    return <dynamic>[];
  }

  Future<Map<String, dynamic>?> signInCustomer(
    String email,
    String password,
  ) async {
    final uri = Uri.parse("$siteBase/api/auth/login");

    try {
      final response = await http
          .post(
            uri,
            headers: _headersJson(),
            body: json.encode({
              "login": email.trim(),
              "password": password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map) return null;

      final map = decoded.cast<String, dynamic>();
      final rawUser = map["user"] ?? map["customer"] ?? map["data"];

      if (rawUser is! Map) return null;

      final user = rawUser.cast<String, dynamic>();
      final normalizedEmail = (user["email"] ?? email.trim()).toString();

      final token = (map["token"] ??
              map["session"] ??
              map["sessionToken"] ??
              map["accessToken"] ??
              _sessionFromSetCookie(response.headers["set-cookie"]))
          .toString();

      print("TellMe login session received: ${token.isNotEmpty}");

      return {
        "user": {
          "id": user["id"] ?? user["legacyId"] ?? normalizedEmail,
          "email": normalizedEmail,
          "first_name": user["firstName"] ?? user["first_name"] ?? "",
          "last_name": user["lastName"] ?? user["last_name"] ?? "",
          "username": user["username"] ??
              user["name"] ??
              user["email"] ??
              normalizedEmail,
          ...user,
        },
        "session": token,
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> logoutAllSessions({String? email}) async {
    return false;
  }

  Future<Map<String, dynamic>?> signInCustomerSecure(
    String email,
    String password,
  ) async {
    return signInCustomer(email, password);
  }

  @deprecated
  Future<Map<String, dynamic>?> signInCustomerLegacy(
    String email,
    String password,
  ) async {
    return null;
  }

  Future<List<Map<String, dynamic>>> getCustomerOrders(
      [int? customerId]) async {
    return _accountApi.getOrders(userId: customerId);
  }

  Future<Map<String, dynamic>?> getCustomerDetails(int customerId) async {
    return _accountApi.getMe(userId: customerId);
  }

  Future<Map<String, dynamic>?> updateCustomer(
    int customerId, {
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    return _accountApi.updateProfile(
      userId: customerId,
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
    );
  }

  Future<Map<String, dynamic>?> getCustomerByEmail(String email) async {
    return null;
  }

  Future<Map<String, dynamic>?> createCustomer({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    return null;
  }

  Future<Map<String, dynamic>?> getCustomer(int customerId) async {
    return getCustomerDetails(customerId);
  }

  Future<bool> updateCustomerPassword(
    int customerId,
    String newPassword,
  ) async {
    return false;
  }

  Future<Map<String, dynamic>> calculateEnhancedShippingForCity({
    required Map<String, dynamic> cityData,
    required List<Map<String, dynamic>> cartItems,
  }) async {
    return {
      "success": false,
      "error": "Shipping endpoint not connected yet",
      "shipping_cost": 0.0,
      "formatted_cost": "NGN 0.00",
    };
  }

  Future<Map<String, dynamic>> getShippingMethodsForCity(
    Map<String, dynamic> cityData,
  ) async {
    return {
      "success": false,
      "error": "Shipping endpoint not connected yet",
      "shipping_options": const <Map<String, dynamic>>[],
    };
  }
}

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
