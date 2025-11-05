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
      setState(() {
        _slides = got.where((s) => s.image.isNotEmpty).toList();
        _loading = false;
      });
    } catch (_) {
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
      final nextPage = ((_pageController.page?.round() ?? 0) + 1) % _slides.length;
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
      return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
    }
    if (_slides.isEmpty) return const SizedBox.shrink();

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

                // ALWAYS full-bleed image
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                          errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1565C0)),
                          loadingBuilder: (ctx, child, prog) {
                            if (prog == null) return child;
                            return const ColoredBox(color: Color(0xFFE3F2FD));
                          },
                        ),
                        // Subtle overlay (kept even with no text for polish)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.10),
                                Colors.transparent,
                              ],
                            ),
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
                    color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
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
}
