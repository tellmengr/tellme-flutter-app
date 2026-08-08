// lib/wallet_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tellme_account_api.dart';

class WalletService {
  static const String baseUrl = 'https://tellme.ng';
  static const Duration timeout = Duration(seconds: 25);

  final TellmeAccountApi _accountApi = TellmeAccountApi();

  /// Fetch recent wallet transactions.
  ///
  /// The new TellMe backend authenticates with the saved session token, so
  /// [userId] can be null when the logged-in customer has a new hex customer ID.
  /// Numeric IDs are only used for the old WordPress fallback.
  Future<Map<String, dynamic>> getWalletTransactions(
    int? userId, {
    int limit = 50,
  }) async {
    try {
      final result = await _accountApi.getWalletHistory(
        userId: userId,
        limit: limit,
      );
      if (result['success'] == true) return result;

      if (userId == null || userId <= 0) {
        return result;
      }
    } catch (_) {
      // Fall back to the legacy endpoint only when a numeric legacy ID exists.
    }

    if (userId == null || userId <= 0) {
      return <String, dynamic>{
        'success': false,
        'error': 'Please sign out and sign in again to view wallet history',
        'code': 'missing_wallet_session',
      };
    }

    final uri = Uri.parse(
      '$baseUrl/wp-json/wallet/v1/transactions?user_id=$userId&limit=$limit',
    );

    try {
      final response = await http.get(uri,
          headers: {'Content-Type': 'application/json'}).timeout(timeout);

      final body = response.body.isEmpty ? '{}' : response.body;

      if (response.statusCode == 200) {
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

      final error = _decodeError(body);
      return <String, dynamic>{
        'success': false,
        'error': error?['message'] ?? 'HTTP ${response.statusCode}',
        'code': error?['code'] ?? 'unknown_error',
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Network error: $e',
        'code': 'network_error',
      };
    }
  }

  /// Fetch wallet balance.
  ///
  /// The new TellMe backend authenticates with the saved session token, so
  /// [userId] can be null when the logged-in customer has a new hex customer ID.
  /// Numeric IDs are only used for the old WordPress fallback.
  Future<Map<String, dynamic>> getWalletBalance([int? userId]) async {
    try {
      final result = await _accountApi.getWalletBalance(userId: userId);
      if (result['success'] == true) return result;

      if (userId == null || userId <= 0) {
        return result;
      }
    } catch (_) {
      // Fall back to the legacy endpoint only when a numeric legacy ID exists.
    }

    if (userId == null || userId <= 0) {
      return <String, dynamic>{
        'success': false,
        'error': 'Please sign out and sign in again to view wallet balance',
        'code': 'missing_wallet_session',
      };
    }

    final uri = Uri.parse('$baseUrl/wp-json/wallet/v1/balance?user_id=$userId');

    try {
      final response = await http.get(uri,
          headers: {'Content-Type': 'application/json'}).timeout(timeout);

      final body = response.body.isEmpty ? '{}' : response.body;

      if (response.statusCode == 200) {
        final decoded = json.decode(body);
        if (decoded is Map && decoded['success'] == true) {
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

      final error = _decodeError(body);
      return <String, dynamic>{
        'success': false,
        'error': error?['message'] ?? 'HTTP ${response.statusCode}',
        'code': error?['code'] ?? 'unknown_error',
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Network error: $e',
        'code': 'network_error',
      };
    }
  }

  Map<String, dynamic>? _decodeError(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}
