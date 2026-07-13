// lib/services/logistics_api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../config/app_config.dart';

class LogisticsApiService {
  final http.Client _client;
  final String? authToken;
  final Duration timeout;

  LogisticsApiService({
    http.Client? client,
    this.authToken,
    this.timeout = AppConfig.networkTimeout,
  }) : _client = client ?? http.Client();

  // ===== Headers =====

  Map<String, String> get _jsonHeaders {
    final token = authToken?.trim() ?? '';

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> get _defaultHeaders {
    final token = authToken?.trim() ?? '';

    return {
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ===== Delivery Endpoints =====

  Future<Map<String, dynamic>> createDelivery({
    required String customerId,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required String senderName,
    required String senderPhone,
    required String pickupAddress,
    double? pickupLatitude,
    double? pickupLongitude,
    required String dropoffAddress,
    double? dropoffLatitude,
    double? dropoffLongitude,
    required String receiverName,
    required String receiverPhone,
    required String packageDescription,
    String? packageCategory,
    double packageWeightKg = 0,
    String? deliveryNote,
  }) async {
    final uri = Uri.parse(
      ApiConfig.buildUrl(ApiConfig.createDelivery),
    );

    final body = {
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'senderName': senderName,
      'senderPhone': senderPhone,
      'pickupAddress': pickupAddress,
      'pickupLatitude': pickupLatitude,
      'pickupLongitude': pickupLongitude,
      'dropoffAddress': dropoffAddress,
      'dropoffLatitude': dropoffLatitude,
      'dropoffLongitude': dropoffLongitude,
      'receiverName': receiverName,
      'receiverPhone': receiverPhone,
      'packageDescription': packageDescription,
      'packageCategory': packageCategory,
      'packageWeightKg': packageWeightKg,
      'deliveryNote': deliveryNote ?? '',
    };

    final response = await _client
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> calculateDeliveryEstimate({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    double packageWeightKg = 0,
  }) async {
    final uri = Uri.parse(
      ApiConfig.buildUrl(ApiConfig.calculateEstimate),
    );

    final body = {
      'pickupLatitude': pickupLatitude,
      'pickupLongitude': pickupLongitude,
      'dropoffLatitude': dropoffLatitude,
      'dropoffLongitude': dropoffLongitude,
      'packageWeightKg': packageWeightKg,
    };

    final response = await _client
        .post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getMyDeliveries({
    required String customerId,
  }) async {
    final url = ApiConfig.buildUrl(
      ApiConfig.getDeliveries,
      params: {
        'customerId': customerId,
      },
    );

    final response = await _client
        .get(
          Uri.parse(url),
          headers: _defaultHeaders,
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getDeliveryById({
    required String deliveryId,
  }) async {
    final url = ApiConfig.buildUrl(
      '${ApiConfig.getDeliveryById}/$deliveryId',
    );

    final response = await _client
        .get(
          Uri.parse(url),
          headers: _defaultHeaders,
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

Future<Map<String, dynamic>> getDeliveryTracking({
  required String deliveryId,
}) async {
  final url = ApiConfig.trackingUrl(deliveryId);

  final response = await _client
      .get(Uri.parse(url), headers: _defaultHeaders)
      .timeout(timeout);

  return _handleResponse(response);
}


  // ===== Rider Lookup =====

  Future<Map<String, dynamic>> lookupRider({
    String? email,
    String? phone,
  }) async {
    final query = <String, String>{};

    if (email != null && email.trim().isNotEmpty) {
      query['email'] = email.trim();
    }

    if (phone != null && phone.trim().isNotEmpty) {
      query['phone'] = phone.trim();
    }

    final url = ApiConfig.buildUrl(
      ApiConfig.riderLookup,
      params: query,
    );

    final response = await _client
        .get(
          Uri.parse(url),
          headers: _defaultHeaders,
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  // ===== Admin Endpoints =====

  Future<Map<String, dynamic>> getAdminRiders() async {
    final url = ApiConfig.buildUrl(ApiConfig.adminRiders);

    final response = await _client
        .get(
          Uri.parse(url),
          headers: _defaultHeaders,
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getAdminDeliveries() async {
    final url = ApiConfig.buildUrl(ApiConfig.adminDeliveries);

    final response = await _client
        .get(
          Uri.parse(url),
          headers: _defaultHeaders,
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  // ===== Payment Endpoints =====

  Future<Map<String, dynamic>> initializePayment({
    required String deliveryRequestId,
    required String email,
  }) async {
    final url = ApiConfig.buildUrl(ApiConfig.initializePayment);

    final response = await _client
        .post(
          Uri.parse(url),
          headers: _jsonHeaders,
          body: jsonEncode({
            'deliveryRequestId': deliveryRequestId,
            'email': email,
          }),
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String reference,
  }) async {
    final url = ApiConfig.buildUrl(ApiConfig.verifyPayment);

    final response = await _client
        .post(
          Uri.parse(url),
          headers: _jsonHeaders,
          body: jsonEncode({
            'reference': reference,
          }),
        )
        .timeout(timeout);

    return _handleResponse(response);
  }

  // ===== Helper Methods =====

  Map<String, dynamic> _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    final body = response.body.trim();

    if (body.startsWith('<!DOCTYPE html') || body.startsWith('<html')) {
      throw Exception(
        'The logistics server returned a web page instead of delivery pricing data. Please check the logistics API URL.',
      );
    }

    if (body.isEmpty) {
      if (statusCode >= 200 && statusCode < 300) {
        return {
          'success': true,
          'data': null,
          'message': 'Request successful',
        };
      }

      throw Exception('Request failed with status code $statusCode');
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw Exception('Invalid server response: $body');
    }

    if (statusCode >= 200 && statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        'success': true,
        'data': decoded,
      };
    }

    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'] ??
          decoded['error'] ??
          decoded['title'] ??
          'Request failed with status code $statusCode';

      throw Exception(message);
    }

    throw Exception('Request failed with status code $statusCode');
  }

  void dispose() => _client.close();
}
