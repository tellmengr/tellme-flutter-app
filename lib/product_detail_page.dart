import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ✅ Correct imports for all your detail layouts
import 'product_detail_classic.dart';
import 'product_detail_gallery.dart';
import 'product_detail_standard.dart';
import 'product_detail_modern.dart';
import 'product_detail_swipe.dart';
import 'user_settings_provider.dart';


class ProductDetailPage extends StatelessWidget {
  final Map<String, dynamic> product;

  const ProductDetailPage({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the style changes, not on unrelated settings updates.
    return Selector<UserSettingsProvider, ProductDetailStyle>(
      selector: (_, s) => s.productDetailStyle,
      builder: (context, style, _) {
        final child = _buildForStyle(style, product);

        // 🎬 Smooth transition if user changes style inside the app
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (widget, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
              child: widget,
            ),
          ),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          // Key ensures AnimatedSwitcher knows when the style actually changed
          child: KeyedSubtree(
            key: ValueKey<ProductDetailStyle>(style),
            child: child,
          ),
        );
      },
    );
  }

  /// 🔹 Central mapping for all product detail styles
  Widget _buildForStyle(ProductDetailStyle? style, Map<String, dynamic> product) {
    switch (style) {
      case ProductDetailStyle.classic:
        return ProductDetailClassic(product: product);

      case ProductDetailStyle.gallery:
        return ProductDetailGallery(product: product);

      case ProductDetailStyle.standard:
        return ProductDetailStandard(product: product);

      case ProductDetailStyle.swipe: // ✅ use the new enum value
        return ProductDetailSwipe(product: product); // ✅ use the new widget

      case ProductDetailStyle.modern:
        return ProductDetailModern(product: product);

      case null:
      default:
        // Fallback if style is null/unknown
        return ProductDetailClassic(product: product);
    }
  }
}
