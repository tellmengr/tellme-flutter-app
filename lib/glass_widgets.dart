// lib/glass_widgets.dart
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;

/// 🧊 Reusable frosted glass container
class FrostedGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final double opacity; // 0..1

  const FrostedGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
    this.blur = 20,
    this.opacity = .22,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity((opacity + .08).clamp(0.0, 1.0)),
                Colors.white.withOpacity(opacity.clamp(0.0, 1.0)),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withOpacity(.35),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
            borderRadius: BorderRadius.circular(radius),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 🧊 Glassy primary (gradient) button
class GlassPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// Make colors optional; fall back to Theme if not provided.
  final Color? primaryColor;
  final Color? accentColor;

  const GlassPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primaryColor,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = primaryColor ?? scheme.primary;
    final a = accentColor ?? scheme.secondary;

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [p, a],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 🧊 Glassy outline button
class GlassOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const GlassOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withOpacity(.6), width: 1.6),
          backgroundColor: Colors.white.withOpacity(.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}
