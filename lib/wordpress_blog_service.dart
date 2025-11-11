// lib/wordpress_blog_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'wp_post.dart';

class WordPressBlogService {
  /// TellMe.ng REST API base URL
  static const String _baseUrl = 'https://tellme.ng/wp-json/wp/v2';

  final http.Client _client;

  WordPressBlogService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch a page of posts (10 per page by default)
  Future<List<WpPost>> fetchPosts({
    int page = 1,
    int perPage = 10,
  }) async {
    final uri = Uri.parse('$_baseUrl/posts').replace(
      queryParameters: <String, String>{
        'per_page': perPage.toString(), // 👈 10 posts per page
        'page': page.toString(),
        '_embed': '1',                  // include embedded data like featured media
        'status': 'publish',
      },
    );

    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load posts: ${response.statusCode}');
    }

    final List<dynamic> data = json.decode(response.body) as List<dynamic>;
    return data
        .map((e) => WpPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a single post by ID
  Future<WpPost> fetchPost(int id) async {
    final uri = Uri.parse('$_baseUrl/posts/$id').replace(
      queryParameters: const <String, String>{
        '_embed': '1',
      },
    );

    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load post: ${response.statusCode}');
    }

    final Map<String, dynamic> data =
        json.decode(response.body) as Map<String, dynamic>;
    return WpPost.fromJson(data);
  }
}
