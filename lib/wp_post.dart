class WpPost {
  final int id;
  final String slug;
  final String title;
  final String excerpt;
  final String contentHtml;
  final DateTime date;
  final String? featuredImage;

  WpPost({
    required this.id,
    required this.slug,
    required this.title,
    required this.excerpt,
    required this.contentHtml,
    required this.date,
    this.featuredImage,
  });

  String get excerptHtml => excerpt;

  factory WpPost.fromJson(Map<String, dynamic> json) {
    final rawTitle = _renderedOrText(json['title']);
    final rawExcerpt = _renderedOrText(json['excerpt']);
    final rawContent = json['bodyHtml'] ?? json['contentHtml'] ?? _renderedOrText(json['content']);
    final rawImage = json['coverImageUrl'] ?? json['featuredImage'];
    final rawDate = json['publishedAt'] ?? json['date'];

    return WpPost(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      slug: '${json['slug'] ?? json['id'] ?? ''}',
      title: _stripHtml(rawTitle),
      excerpt: _stripHtml(rawExcerpt),
      contentHtml: '$rawContent',
      date: DateTime.tryParse('$rawDate') ?? DateTime.now(),
      featuredImage: rawImage == null || '$rawImage'.isEmpty ? null : '$rawImage',
    );
  }

  static String _renderedOrText(dynamic value) {
    if (value is Map) return '${value['rendered'] ?? ''}';
    return '${value ?? ''}';
  }

  static String _stripHtml(String htmlText) {
    return htmlText.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}
