// lib/blog_list_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'wordpress_blog_service.dart';
import 'wp_post.dart';
import 'blog_post_page.dart';
import 'blog_notification_provider.dart';

class BlogListPage extends StatefulWidget {
  const BlogListPage({super.key});

  @override
  State<BlogListPage> createState() => _BlogListPageState();
}

class _BlogListPageState extends State<BlogListPage> {
  final WordPressBlogService _service = WordPressBlogService();

  final List<WpPost> _posts = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  final int _perPage = 10;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPosts(reset: true);
  }

  Future<void> _loadPosts({required bool reset}) async {
    if (reset) {
      setState(() {
        _isInitialLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _page = 1;
        _posts.clear();
        _error = null;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
        _error = null;
      });
    }

    try {
      final newPosts = await _service.fetchPosts(page: _page, perPage: _perPage);

      setState(() {
        _posts.addAll(newPosts);
        _hasMore = newPosts.length == _perPage;
        if (_hasMore) _page += 1;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });

      // ✅ Mark latest post as "seen" to clear NEW badge
      if (_posts.isNotEmpty && mounted) {
        final latestId = _posts.first.id;
        final blogNotif = context.read<BlogNotificationProvider?>();
        if (blogNotif != null) {
          await blogNotif.markAllRead(latestId);
        }
      }
    } catch (e) {
      setState(() {
        _isInitialLoading = false;
        _isLoadingMore = false;
        _error = 'Failed to load posts: $e';
      });
    }
  }

  Future<void> _refresh() async {
    await _loadPosts(reset: true);
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Our Blog'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadPosts(reset: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _posts.length + 1, // +1 for load-more footer
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            if (!_hasMore) return const SizedBox.shrink();
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: TextButton.icon(
                  onPressed: () => _loadPosts(reset: false),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load more posts'),
                ),
              ),
            );
          }

          final post = _posts[index];
          return _buildPostCard(post);
        },
      ),
    );
  }

  Widget _buildPostCard(WpPost post) {
    final plainExcerpt =
        post.excerptHtml.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlogPostPage(postId: post.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.featuredImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    post.featuredImage!,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                ),
              if (post.featuredImage != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(post.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plainExcerpt,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
