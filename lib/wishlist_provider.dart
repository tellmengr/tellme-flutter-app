import 'package:flutter/foundation.dart';

class WishlistProvider with ChangeNotifier {
  final List<dynamic> _wishlist = [];

  List<dynamic> get items => List.unmodifiable(_wishlist);

  bool contains(dynamic product) {
    if (product == null) return false;
    final id = product['id'] ?? product['product_id'];
    return _wishlist.any((p) => (p['id'] ?? p['product_id']) == id);
  }

  void toggle(dynamic product) {
    if (contains(product)) {
      remove(product);
    } else {
      add(product);
    }
  }

  void add(dynamic product) {
    if (product == null) return;
    final id = product['id'] ?? product['product_id'];
    if (!_wishlist.any((p) => (p['id'] ?? p['product_id']) == id)) {
      _wishlist.add(product);
      notifyListeners();
    }
  }

  void remove(dynamic product) {
    final id = product['id'] ?? product['product_id'];
    _wishlist.removeWhere((p) => (p['id'] ?? p['product_id']) == id);
    notifyListeners();
  }

  void clear() {
    _wishlist.clear();
    notifyListeners();
  }

  int get count => _wishlist.length;
}
