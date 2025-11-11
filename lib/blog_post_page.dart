// lib/blog_post_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'wp_post.dart';
import 'wordpress_blog_service.dart';

class BlogPostPage extends StatefulWidget {
  final int postId;

  const BlogPostPage({super.key, required this.postId});

  @override
  State<BlogPostPage> createState() => _BlogPostPageState();
}

class _BlogPostPageState extends State<BlogPostPage> {
  late final WordPressBlogService _service;
  late Future<WpPost> _futurePost;

  @override
  void initState() {
    super.initState();
    _service = WordPressBlogService();
    _futurePost = _service.fetchPost(widget.postId);
  }

  Future<void> _openExternalLink(String url) async {
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link')),
      );
      return;
    }

    if (!await canLaunchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
      return;
    }

    // 👇 open in browser outside the app
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Our Blog'),
      ),
      body: FutureBuilder<WpPost>(
        future: _futurePost,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: GoogleFonts.inter(),
              ),
            );
          }

          final post = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.featuredImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      post.featuredImage!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  post.title,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(post.date),
                  style: GoogleFonts.inter(color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // HTML rendered as native Flutter widgets
                Html(
                  data: post.contentHtml,
                  style: {
                    "body": Style(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontSize: FontSize(16),
                      lineHeight: const LineHeight(1.5),
                    ),
                    "a": Style(
                      color: Theme.of(context).colorScheme.primary,
                      textDecoration: TextDecoration.underline,
                    ),
                  },

                  // ✅ flutter_html 3.0.0 signature: (url, attributes, element)
                  onLinkTap: (url, attributes, element) {
                    if (url == null) return;
                    _openExternalLink(url);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}
