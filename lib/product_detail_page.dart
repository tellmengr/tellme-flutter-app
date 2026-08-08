import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'product_detail_classic.dart';
import 'product_detail_gallery.dart';
import 'product_detail_modern.dart';
import 'product_detail_standard.dart';
import 'product_detail_swipe.dart';
import 'tellme_live_chat_service.dart';
import 'user_provider.dart';
import 'user_settings_provider.dart';

class ProductDetailPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_reportProductPresence());
    });
  }

  Future<void> _reportProductPresence() async {
    final product = widget.product;
    final user = context.read<UserProvider>();
    final name = _productText(product, const ['name', 'title']);
    final sku = _productText(product, const ['sku']);
    final id = _productText(
      product,
      const ['id', 'product_id', 'productId', 'backendId'],
    );
    final slug = _productText(product, const ['slug']);

    try {
      await TellMeLiveChatService.instance.updateSession(
        currentPage: name.isEmpty ? 'App: Product' : 'Product: $name',
        currentPageUrl: _productUrl(product, slug: slug, sku: sku, id: id),
        currentProductSku: sku,
        currentProductId: id,
        name: user.userDisplayName,
        email: user.userEmail,
      );
    } catch (_) {
      // Chat presence is best-effort and should never block product browsing.
    }
  }

  static String _productText(Map<String, dynamic> product, List<String> keys) {
    for (final key in keys) {
      final value = product[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '';
  }

  static String _productUrl(
    Map<String, dynamic> product, {
    required String slug,
    required String sku,
    required String id,
  }) {
    final explicitUrl = _productText(product, const [
      'url',
      'permalink',
      'productUrl',
      'product_url',
      'webUrl',
      'web_url',
    ]);
    if (explicitUrl.startsWith('http')) return explicitUrl;

    if (slug.isNotEmpty) {
      return 'https://tellme.ng/products/${Uri.encodeComponent(slug)}';
    }

    if (sku.isNotEmpty) {
      return 'https://tellme.ng/shop?sku=${Uri.encodeQueryComponent(sku)}';
    }

    if (id.isNotEmpty) {
      return 'https://tellme.ng/products/${Uri.encodeComponent(id)}';
    }

    return 'https://tellme.ng';
  }

  @override
  Widget build(BuildContext context) {
    return Selector<UserSettingsProvider, ProductDetailStyle>(
      selector: (_, s) => s.productDetailStyle,
      builder: (context, style, _) {
        final child = _buildForStyle(style, widget.product);

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
          child: KeyedSubtree(
            key: ValueKey<ProductDetailStyle>(style),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildForStyle(
      ProductDetailStyle? style, Map<String, dynamic> product) {
    switch (style) {
      case ProductDetailStyle.classic:
        return ProductDetailClassic(product: product);
      case ProductDetailStyle.gallery:
        return ProductDetailGallery(product: product);
      case ProductDetailStyle.standard:
        return ProductDetailStandard(product: product);
      case ProductDetailStyle.swipe:
        return ProductDetailSwipe(product: product);
      case ProductDetailStyle.modern:
        return ProductDetailModern(product: product);
      case null:
        return ProductDetailClassic(product: product);
    }
  }
}
