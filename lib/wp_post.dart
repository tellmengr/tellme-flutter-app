class WpPost {
  final int id;
  final String title;
  final String excerpt;
  final String contentHtml;
  final DateTime date;
  final String? featuredImage;

  WpPost({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.contentHtml,
    required this.date,
    this.featuredImage,
  });

  /// Backward-compatible alias so code using `excerptHtml` still works
  String get excerptHtml => excerpt;

  factory WpPost.fromJson(Map<String, dynamic> json) {
    final rawTitle = (json['title']?['rendered'] ?? '') as String;
    final rawExcerpt = (json['excerpt']?['rendered'] ?? '') as String;
    final rawContent = (json['content']?['rendered'] ?? '') as String;

    String? imageUrl;
    try {
      // Works if API called with ?_embed for featured images
      final media = json['_embedded']['wp:featuredmedia'][0];
      imageUrl = media['source_url'] as String?;
    } catch (_) {
      imageUrl = null;
    }

    return WpPost(
      id: json['id'] as int,
      title: _stripHtml(rawTitle),
      excerpt: _stripHtml(rawExcerpt),
      contentHtml: rawContent, // keep HTML for detail page
      date: DateTime.parse(json['date'] as String),
      featuredImage: imageUrl,
    );
  }

  /// Utility to strip basic HTML tags (for list/excerpt display)
  static String _stripHtml(String htmlText) {
    final regex = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false);
    return htmlText.replaceAll(regex, '').trim();
  }
}
