// lib/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  final Widget next;

  /// Minimum time the splash should remain visible AFTER the first frame paints.
  final Duration minDuration;

  /// Overlay centered logo block (off by default for a clean poster).
  final bool showLogo;

  /// Show a tiny spinner under the logo (only if [showLogo] is true).
  final bool showSpinner;

  /// Full-screen poster image (BoxFit.cover).
  final String posterAsset;

  /// Optional solid color seen only for a split second during Android 12 handoff.
  final Color backgroundColor;

  /// Optional blue tint over the poster (0 = none). Default is 0 (off).
  final double tintOpacity;

  /// Tint color (used only if [tintOpacity] > 0).
  final Color tintColor;

  /// Handoff transition into [next].
  final Duration transitionDuration;

  const SplashScreen({
    super.key,
    required this.next,
    this.minDuration = const Duration(milliseconds: 1000),
    this.showLogo = false,
    this.showSpinner = true,
    this.posterAsset = 'assets/images/splash_bg_android.png',
    this.backgroundColor = const Color(0xFF0B46C5),
    this.tintOpacity = 0.0,
    this.tintColor = const Color(0xFF0B46C5),
    this.transitionDuration = const Duration(milliseconds: 250),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  ImageProvider get _poster => AssetImage(widget.posterAsset);

  bool _didNavigate = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _scale = Tween(begin: 0.985, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));

    _ac.forward();

    // Start the visible-duration timer AFTER first frame to guarantee the poster is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(widget.minDuration, _navigate);
    });
  }

  void _navigate() {
    if (!mounted || _didNavigate) return;
    _didNavigate = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: widget.transitionDuration,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache poster to avoid first-frame jank/blur.
    precacheImage(_poster, context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status/navigation icons look best on the blue handoff color.
      value: SystemUiOverlayStyle.light,
      child: WillPopScope(
        // Prevent back press during splash.
        onWillPop: () async => false,
        child: Scaffold(
          // Briefly visible during Android 12 native → Flutter handoff.
          backgroundColor: widget.backgroundColor,
          body: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1) Full-screen poster
                  Image(
                    image: _poster,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.high,
                  ),

                  // 2) Optional tint (off by default)
                  if (widget.tintOpacity > 0)
                    Container(color: widget.tintColor.withOpacity(widget.tintOpacity)),

                  // 3) Optional centered logo + spinner
                  if (widget.showLogo)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/tellme_logo.png',
                            width: 160,
                            fit: BoxFit.contain,
                          ),
                          if (widget.showSpinner) ...[
                            const SizedBox(height: 18),
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
