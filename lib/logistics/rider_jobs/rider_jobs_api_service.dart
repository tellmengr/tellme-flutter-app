// lib/logistics/rider_jobs/rider_jobs_api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../config/app_config.dart';

class RiderJobsApiService {
  final String? authToken;
  final Duration timeout;

  RiderJobsApiService({
    this.authToken,
    this.timeout = AppConfig.networkTimeout,
  });

  Map<String, String> get jsonHeaders {
    final token = authToken?.trim() ?? '';

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> get defaultHeaders {
    final token = authToken?.trim() ?? '';

    return {
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<dynamic>> loadRiderJobs({required String riderId}) async {
    final uri = Uri.parse(ApiConfig.riderJobsUrl(riderId));

    final response = await http
        .get(uri, headers: defaultHeaders)
        .timeout(timeout);

    final decoded = _decodeResponse(response);

    if (decoded['success'] == true && decoded['data'] is List) {
      return decoded['data'] as List<dynamic>;
    }

    throw Exception(
      decoded['message']?.toString() ?? 'Could not load rider jobs.',
    );
  }

  Future<void> updateDeliveryStatus({
    required String deliveryRequestId,
    required int newStatus,
    required String note,
    required String riderId,
  }) async {
    final uri = Uri.parse(ApiConfig.riderStatusUrl(deliveryRequestId));

    final body = {
      'newStatus': newStatus,
      'note': note,
      'changedByUserId': riderId,
    };

    final response = await http
        .post(uri, headers: jsonHeaders, body: jsonEncode(body))
        .timeout(timeout);

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Status update failed.',
      );
    }

    if (decoded['success'] == false) {
      throw Exception(
        decoded['message']?.toString() ?? 'Status update failed.',
      );
    }
  }

  Future<void> sendRiderLocation({
    required String deliveryRequestId,
    required String riderId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
  }) async {
    final uri = Uri.parse(
      ApiConfig.riderLocationUrl(
        deliveryRequestId: deliveryRequestId,
        riderId: riderId,
      ),
    );

    final body = {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy ?? 0.0,
      'speed': speed ?? 0.0,
      'heading': heading ?? 0.0,
    };

    final response = await http
        .post(uri, headers: jsonHeaders, body: jsonEncode(body))
        .timeout(timeout);

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Location API update failed.',
      );
    }

    if (decoded['success'] == false) {
      throw Exception(
        decoded['message']?.toString() ?? 'Location API update failed.',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final body = response.body.trim();

    if (body.isEmpty) {
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'data': null,
        'message': response.statusCode >= 200 && response.statusCode < 300
            ? 'Request successful'
            : 'Request failed with status code ${response.statusCode}',
      };
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'data': decoded,
      };
    } catch (_) {
      return {
        'success': false,
        'message': body,
        'statusCode': response.statusCode,
      };
    }
  }
}
