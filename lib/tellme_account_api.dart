import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TellmeAccountApi {
  static const String baseUrl = 'https://tellme.ng/api/v1';
  static const Duration timeout = Duration(seconds: 25);

  static const List<String> _sessionKeys = [
    'tellme_session',
    'tm_customer_session',
    'customer_session',
  ];

  Future<String> _sessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _sessionKeys) {
      final value = prefs.getString(key)?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<Map<String, String>> _headers() async {
    final session = await _sessionToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'TellMeApp/1.0',
      if (session.isNotEmpty) 'Authorization': 'Bearer $session',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$baseUrl/$cleanPath').replace(queryParameters: query);
  }

  Map<String, String> _userQuery(int? userId) {
    if (userId == null || userId <= 0) return <String, String>{};
    return {'user_id': userId.toString()};
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};

    try {
      final decoded = json.decode(response.body);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return {'data': decoded};
    } catch (_) {
      return {'message': response.body};
    }
  }

  Map<String, dynamic> _failure(http.Response response) {
    final body = _decodeBody(response);
    final error = body['error'];

    return {
      'success': false,
      'status_code': response.statusCode,
      'error': error is Map
          ? error['message'] ?? error['code'] ?? 'Request failed'
          : body['message'] ?? error ?? 'Request failed',
      'details': body,
    };
  }

  Map<String, dynamic>? _normalizeUser(Map<String, dynamic> body) {
    final raw = body['user'] ?? body['customer'] ?? body['data'];
    if (raw is! Map) return null;

    final user = raw.cast<String, dynamic>();
    return {
      ...user,
      'id': user['id'] ?? user['customerId'] ?? user['customer_id'],
      'first_name': user['first_name'] ?? user['firstName'] ?? '',
      'last_name': user['last_name'] ?? user['lastName'] ?? '',
      'email': user['email'] ?? '',
      'phone': user['phone'] ?? user['billing_phone'] ?? '',
    };
  }

  List<Map<String, dynamic>> _normalizeList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>?> getMe({int? userId}) async {
    final response = await http
        .get(
          _uri('account/me', _userQuery(userId)),
          headers: await _headers(),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return _normalizeUser(_decodeBody(response));
  }

  Future<List<Map<String, dynamic>>> getOrders({int? userId}) async {
    final response = await http
        .get(
          _uri('account/orders', _userQuery(userId)),
          headers: await _headers(),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_failure(response)['error']);
    }

    final body = _decodeBody(response);
    return _normalizeList(body['orders'] ?? body['data']);
  }

  Future<Map<String, dynamic>?> updateProfile({
    int? userId,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    final response = await http
        .patch(
          _uri('account/profile'),
          headers: await _headers(),
          body: json.encode({
            if (userId != null && userId > 0) 'user_id': userId,
            if (firstName != null) 'firstName': firstName,
            if (lastName != null) 'lastName': lastName,
            if (email != null) 'email': email,
            if (phone != null) 'phone': phone,
          }),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return _normalizeUser(_decodeBody(response));
  }

  Future<Map<String, dynamic>> deleteAccount({
    required String email,
    required String password,
    required String confirm,
    String? feedback,
  }) async {
    final response = await http
        .post(
          _uri('account/delete'),
          headers: await _headers(),
          body: json.encode({
            'email': email,
            'password': password,
            'confirm': confirm,
            if (feedback != null && feedback.trim().isNotEmpty)
              'feedback': feedback.trim(),
          }),
        )
        .timeout(timeout);

    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return {
        'success': body['success'] ?? true,
        'message': body['message'] ?? 'Account deleted',
        'data': body,
      };
    }

    return _failure(response);
  }

  Future<Map<String, dynamic>> getWalletBalance({int? userId}) async {
    final response = await http
        .get(
          _uri('wallet/balance', _userQuery(userId)),
          headers: await _headers(),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _failure(response);
    }

    final body = _decodeBody(response);
    final balance = body['balance'] is Map
        ? (body['balance'] as Map).cast<String, dynamic>()
        : {
            'raw': body['balance'] ?? body['amount'] ?? 0,
            'currency': body['currency'] ?? 'NGN',
            'currency_symbol': body['currency_symbol'] ?? 'NGN',
          };

    return {
      'success': true,
      'balance': balance,
      'user_id': body['user_id'] ?? body['customerId'] ?? userId,
      'timestamp': body['timestamp'] ?? DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> getWalletHistory({
    int? userId,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      ..._userQuery(userId),
    };

    final response = await http
        .get(
          _uri('wallet/history', query),
          headers: await _headers(),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _failure(response);
    }

    final body = _decodeBody(response);
    final transactions = _normalizeList(
      body['transactions'] ?? body['history'] ?? body['data'],
    );

    return {
      'success': true,
      'transactions': transactions,
      'count': body['count'] ?? transactions.length,
      'user_id': body['user_id'] ?? body['customerId'] ?? userId,
      'timestamp': body['timestamp'] ?? DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> createWalletTopUp({
    int? userId,
    required double amount,
    String? reference,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await http
        .post(
          _uri('wallet/topups'),
          headers: await _headers(),
          body: json.encode({
            if (userId != null && userId > 0) 'user_id': userId,
            'amount': amount,
            if (reference != null && reference.isNotEmpty)
              'reference': reference,
            if (description != null && description.isNotEmpty)
              'description': description,
            if (metadata != null) 'metadata': metadata,
          }),
        )
        .timeout(timeout);

    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return {
        'success': body['success'] ?? true,
        'message': body['message'] ?? 'Wallet top-up recorded',
        'transaction_id':
            body['transaction_id'] ?? body['topupId'] ?? body['id'],
        'amount_added': body['amount_added'] ?? body['amount'] ?? amount,
        'amount_credited': body['amount_credited'] ?? body['amount'] ?? amount,
        'new_balance': body['new_balance'],
        'payment': body['payment'],
        'data': body,
        'timestamp': body['timestamp'] ?? DateTime.now().toIso8601String(),
      };
    }

    return _failure(response);
  }

  Future<Map<String, dynamic>> initializePaystackTransaction({
    required String email,
    required double amount,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await http
        .post(
          _uri('payments/paystack/initialize'),
          headers: await _headers(),
          body: json.encode({
            'email': email,
            'amount': amount,
            'reference': reference,
            if (metadata != null) 'metadata': metadata,
          }),
        )
        .timeout(timeout);

    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return {
        ...body,
        'status': body['status'] ?? true,
      };
    }

    return {
      ..._failure(response),
      'status': false,
      'message': body['message'] ?? _failure(response)['error'],
    };
  }

  Future<Map<String, dynamic>> verifyPaystackTransaction(
      String reference) async {
    final response = await http
        .post(
          _uri('payments/paystack/verify'),
          headers: await _headers(),
          body: json.encode({'reference': reference}),
        )
        .timeout(timeout);

    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return {
        ...body,
        'status': body['status'] ?? true,
        'data': body['data'] ?? {'status': 'failed'},
      };
    }

    return {
      ..._failure(response),
      'status': false,
      'message': body['message'] ?? _failure(response)['error'],
      'data': body['data'] ?? {'status': 'failed'},
    };
  }
}
