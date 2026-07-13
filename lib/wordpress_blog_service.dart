import 'dart:convert';
import 'package:http/http.dart' as http;

import 'wp_post.dart';

class WordPressBlogService {
  static const String _baseUrl = 'https://new.tellme.ng/api/blog/posts';

  final http.Client _client;

  WordPressBlogService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<WpPost>> fetchPosts({int page = 1, int perPage = 10}) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'page': page.toString(),
      'perPage': perPage.toString(),
    });

    final response = await _client.get(uri, headers: const {'Accept': 'application/json'});
    if (response.statusCode != 200) {
      throw Exception('Failed to load posts: ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final data = decoded['posts'] as List<dynamic>? ?? [];
    return data.map((e) => WpPost.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<WpPost> fetchPost(String slug) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/$slug'),
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load post: ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final data = decoded['post'] as Map<String, dynamic>? ?? decoded;
    return WpPost.fromJson(data);
  }
}
