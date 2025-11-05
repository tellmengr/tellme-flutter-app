// lib/wallet_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class WalletService {
  static const String baseUrl = 'https://tellme.ng';

  /// Fetch recent wallet transactions for a user.
  Future<Map<String, dynamic>> getWalletTransactions(
    int userId, {
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/wp-json/wallet/v1/transactions?user_id=$userId&limit=$limit',
    );

    try {
      final res = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 25));

      final body = res.body.isEmpty ? '{}' : res.body;

      if (res.statusCode == 200) {
        final decoded = json.decode(body);
        if (decoded is Map && decoded['success'] == true) {
          return <String, dynamic>{
            'success': true,
            'transactions': List<Map<String, dynamic>>.from(
              (decoded['transactions'] ?? const []) as List,
            ),
            'count': decoded['count'],
            'user_id': decoded['user_id'],
            'timestamp': decoded['timestamp'],
          };
        }
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to retrieve wallet transactions',
          'details': decoded,
        };
      }

      Map<String, dynamic>? err;
      try {
        final decodedErr = json.decode(body);
        if (decodedErr is Map) err = Map<String, dynamic>.from(decodedErr);
      } catch (_) {}

      return <String, dynamic>{
        'success': false,
        'error': (err?['message'] ?? 'HTTP ${res.statusCode}'),
        'code': err?['code'] ?? 'unknown_error',
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Network error: $e',
        'code': 'network_error',
      };
    }
  }

  /// Fetch wallet balance for a user.
  Future<Map<String, dynamic>> getWalletBalance(int userId) async {
    final uri = Uri.parse(
      '$baseUrl/wp-json/wallet/v1/balance?user_id=$userId',
    );

    try {
      final res = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 25));

      final body = res.body.isEmpty ? '{}' : res.body;

      if (res.statusCode == 200) {
        final decoded = json.decode(body);
        if (decoded is Map && decoded['success'] == true) {
          // Normalize to a strictly-typed map so the function signature matches.
          return <String, dynamic>{
            'success': true,
            'balance': decoded['balance'],
            'user_id': decoded['user_id'],
            'timestamp': decoded['timestamp'],
          };
        }
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to retrieve wallet balance',
          'details': decoded,
        };
      }

      Map<String, dynamic>? err;
      try {
        final decodedErr = json.decode(body);
        if (decodedErr is Map) err = Map<String, dynamic>.from(decodedErr);
      } catch (_) {}

      return <String, dynamic>{
        'success': false,
        'error': (err?['message'] ?? 'HTTP ${res.statusCode}'),
        'code': err?['code'] ?? 'unknown_error',
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Network error: $e',
        'code': 'network_error',
      };
    }
  }
}
