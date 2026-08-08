import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'slider_service.dart';

class HomePageSliderCarousel extends StatefulWidget {
  const HomePageSliderCarousel({super.key});

  @override
  State<HomePageSliderCarousel> createState() => _HomePageSliderCarouselState();
}

class _HomePageSliderCarouselState extends State<HomePageSliderCarousel> {
  final PageController _pageController = PageController();
  final SliderService _service = SliderService();

  int _currentPage = 0;
  Timer? _timer;

  List<AppSlide> _slides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final got = await _service.fetchSlides();
      if (!mounted) return;
      setState(() {
        _slides = got.where((s) => s.image.isNotEmpty).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
    _startAutoSlide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _timer?.cancel();
    if (_slides.isEmpty) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage =
          ((_pageController.page?.round() ?? 0) + 1) % _slides.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopAutoSlide() => _timer?.cancel();
  void _refresh() => _load();

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_slides.isEmpty) return _buildFallbackHero();

    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          GestureDetector(
            onPanDown: (_) => _stopAutoSlide(),
            onPanEnd: (_) => _startAutoSlide(),
            onLongPress: _refresh, // refresh from WP
            child: PageView.builder(
              controller: _pageController,
              itemCount: _slides.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final s = _slides[index];
                final showTitle = s.title.trim().isNotEmpty;
                final showSubtitle = s.subtitle.trim().isNotEmpty;
                final showButton = s.buttonText.trim().isNotEmpty;
                final showCopy = showTitle || showSubtitle || showButton;

                // ALWAYS full-bleed image
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          s.image,
                          fit: BoxFit.cover, // ← fills entire card
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Color(0xFF1565C0)),
                          loadingBuilder: (ctx, child, prog) {
                            if (prog == null) return child;
                            return const ColoredBox(color: Color(0xFFE3F2FD));
                          },
                        ),
                        // Subtle overlay (kept even with no text for polish)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black
                                    .withOpacity(showCopy ? 0.66 : 0.10),
                                Colors.black
                                    .withOpacity(showCopy ? 0.32 : 0.04),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        if (showCopy)
                          Positioned(
                            left: 24,
                            right: 70,
                            top: 0,
                            bottom: 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (showTitle)
                                  Text(
                                    s.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 31,
                                      height: 0.98,
                                      fontWeight: FontWeight.w900,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black45,
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (showSubtitle) ...[
                                  const SizedBox(height: 7),
                                  Text(
                                    s.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black45,
                                          blurRadius: 7,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (showButton) ...[
                                  const SizedBox(height: 20),
                                  Material(
                                    color: const Color(0xFFFFCC18),
                                    borderRadius: BorderRadius.circular(13),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(13),
                                      onTap: () => _open(s.buttonUrl),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 14,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              s.buttonText,
                                              style: const TextStyle(
                                                color: Color(0xFF061437),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        // Whole banner tappable if URL exists
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(onTap: () => _open(s.buttonUrl)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Page indicators
          Positioned(
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: isActive ? 24 : 8,
                  decoration: BoxDecoration(
                    color:
                        isActive ? Colors.white : Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackHero() {
    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF004AAD),
            Color(0xFF0096FF),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            bottom: -30,
            child: Icon(
              Icons.shopping_bag_rounded,
              size: 170,
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'TellMe.ng',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Fresh deals, fast delivery, trusted shopping.',
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
