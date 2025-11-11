import 'dart:convert';
import 'package:http/http.dart' as http;

/// Model: represents the loyalty discount response from the API.
class LoyaltyDiscount {
  final bool eligible;
  final double discount; // amount in Naira
  final String label;
  final String imageUrl;

  LoyaltyDiscount({
    required this.eligible,
    required this.discount,
    required this.label,
    required this.imageUrl,
  });

  factory LoyaltyDiscount.fromJson(Map<String, dynamic> json) {
    return LoyaltyDiscount(
      eligible: json['eligible'] == true,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      label: json['label'] ?? '',
      imageUrl: json['image'] ?? '',
    );
  }

  factory LoyaltyDiscount.empty() {
    return LoyaltyDiscount(
      eligible: false,
      discount: 0.0,
      label: '',
      imageUrl: '',
    );
  }
}

/// Service: talks to your WordPress loyalty endpoint.
class LoyaltyService {
  // 🔁 Replace this with your real domain if needed
  static const String _baseUrl = 'https://tellme.ng';

  static Future<LoyaltyDiscount> fetchLoyaltyDiscount({
    required int userId,
    required double cartTotal,
  }) async {
    final uri = Uri.parse('$_baseUrl/wp-json/tellme-loyalty/v1/discount');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'cart_total': cartTotal,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return LoyaltyDiscount.fromJson(data);
      } else {
        // You can log response.body for debugging
        return LoyaltyDiscount.empty();
      }
    } catch (e) {
      // Network error, timeout, etc.
      return LoyaltyDiscount.empty();
    }
  }
}
