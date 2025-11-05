import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'home_page.dart';
import 'category_page.dart';  // ✅ Your existing Categories screen
import 'cart_page.dart';
import 'wishlist_page.dart';
import 'profile_page.dart';

class BottomNavShell extends StatefulWidget {
  const BottomNavShell({super.key});

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  int _selectedIndex = 0;

  // ✅ Persistent tabs (state preserved with IndexedStack)
  final List<Widget> _pages = [
    HomePage(),       // 0: Home
    CategoryPage(),   // 1: Categories
  ];

  void _onItemTapped(int index) {
    switch (index) {
      case 0: // 🏠 Home
      case 1: // 🗂 Categories
        setState(() => _selectedIndex = index);
        break;

      case 2: // 🛒 Cart (push, not a persistent tab)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CartPage(
              selectedIndex: 0,
              onBackToHome: (int idx) => setState(() => _selectedIndex = idx),
            ),
          ),
        );
        break;

      case 3: // 💖 Wishlist (push)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WishlistPage(
              selectedIndex: 0,
              onBackToHome: (int idx) => setState(() => _selectedIndex = idx),
            ),
          ),
        );
        break;

      case 4: // 👤 Profile (push)
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfilePage()),
        );
        break;
    }
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return false; // don’t close app; go back to Home
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.category), // ✅ Categories tab
              label: 'Categories',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  const Icon(Icons.shopping_cart),
                  if (cart.totalQuantity > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '${cart.totalQuantity}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Cart',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.favorite),
              label: 'Wishlist',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
