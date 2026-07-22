import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'cart_page.dart';
import 'cart_provider.dart';
import 'category_page.dart';
import 'home_page.dart';
import 'logistics_page.dart';
import 'profile_page.dart';
import 'support_chat_page.dart';
import 'tellme_live_chat_service.dart';
import 'user_provider.dart';

class BottomNavShell extends StatefulWidget {
  const BottomNavShell({super.key});

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  int _selectedIndex = 0;

  // Persistent tabs. Cart and Profile are still opened as pushed pages.
  // Bottom nav mapping:
  // 0 = Home
  // 1 = Categories
  // 2 = Cart       -> pushed
  // 3 = Logistics  -> persistent tab
  // 4 = Profile    -> pushed
  final List<Widget> _pages = const [
    HomePage(),
    CategoryPage(),
    LogisticsPage(),
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportChatPresence();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  int _stackIndexFromSelectedIndex() {
    switch (_selectedIndex) {
      case 0:
        return 0; // Home
      case 1:
        return 1; // Categories
      case 3:
        return 2; // Logistics
      default:
        return 0;
    }
  }

  void _onItemTapped(int index) {
    switch (index) {
      case 0: // Home
      case 1: // Categories
      case 3: // Logistics
        setState(() => _selectedIndex = index);
        _reportChatPresence();
        break;

      case 2: // Cart
        unawaited(_reportChatPresence(currentPage: 'App: Cart'));
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CartPage(
              selectedIndex: 0,
              onBackToHome: (int idx) {
                setState(() => _selectedIndex = idx);
                _reportChatPresence();
              },
            ),
          ),
        ).then((_) => _reportChatPresence());
        break;

      case 4: // Profile
        unawaited(_reportChatPresence(currentPage: 'App: Profile'));
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfilePage()),
        ).then((_) => _reportChatPresence());
        break;
    }
  }

  String _currentChatPage() {
    switch (_selectedIndex) {
      case 1:
        return 'App: Categories';
      case 3:
        return 'App: Logistics';
      default:
        return 'App: Home';
    }
  }

  Future<void> _reportChatPresence({String? currentPage}) async {
    if (!mounted) return;

    final user = context.read<UserProvider>();
    try {
      await TellMeLiveChatService.instance.startPresence(
        currentPage: currentPage ?? _currentChatPage(),
        name: user.userDisplayName,
        email: user.userEmail,
      );
    } catch (_) {
      // Presence is best-effort; shopping should keep working if chat is offline.
    }
  }

  Future<void> _openLiveChat() async {
    await _reportChatPresence(currentPage: 'App: Live Chat');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SupportChatPage()),
    );
    await _reportChatPresence();
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      _reportChatPresence();
      return false; // Go back to Home instead of closing the app.
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final cartBadgeText =
        cart.totalQuantity > 99 ? '99+' : cart.totalQuantity.toString();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: KeyedSubtree(
          key: ValueKey<int>(_stackIndexFromSelectedIndex()),
          child: _pages[_stackIndexFromSelectedIndex()],
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
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.category_outlined),
              activeIcon: Icon(Icons.category),
              label: 'Categories',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_cart_outlined),
                  if (cart.totalQuantity > 0) _CartBadge(text: cartBadgeText),
                ],
              ),
              activeIcon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_cart),
                  if (cart.totalQuantity > 0) _CartBadge(text: cartBadgeText),
                ],
              ),
              label: 'Cart',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping_outlined),
              activeIcon: Icon(Icons.local_shipping),
              label: 'Logistics',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: FloatingActionButton.small(
          heroTag: 'tellme-live-chat',
          tooltip: 'Live chat',
          onPressed: _openLiveChat,
          backgroundColor: const Color(0xFF004AAD),
          foregroundColor: Colors.white,
          child: const Icon(Icons.support_agent_rounded),
        ),
      ),
    );
  }
}

class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -6,
      top: -5,
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
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
