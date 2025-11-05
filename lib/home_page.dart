// home_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'user_settings_provider.dart';
import 'cart_provider.dart';
import 'user_provider.dart';

import 'home_page_grid.dart';            // AdvancedProductGridView
import 'home_page_list.dart';            // AdvancedProductListView
import 'home_page_slider_carousel.dart'; // Top marketing slider
import 'home_page_staggered.dart';       // ✅ now wired to parent scroll + paging
import 'home_page_modern.dart';
import 'woocommerce_service.dart';
import 'home_page_carousel.dart';        // ProductSnapCarousel (the snap carousel)

import 'app_header.dart';
import 'settings_page.dart';
import 'search_page.dart';
import 'celebration_theme_provider.dart';
import 'my_orders_page.dart';
import 'profile_page.dart';

// 👇 Added: WhatsApp helper
import 'whatsapp_helper.dart';


const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue  = Color(0xFF0096FF);
const kWhite       = Colors.white;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final WooCommerceService _wooService = WooCommerceService();

  // data
  final List<dynamic> _products = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String _errorMessage = "";

  // paging
  int _page = 1;
  final int _perPage = 20;
  bool _hasMore = true;

  // lifecycle + scroll
  bool _mountedFlag = false;
  final ScrollController _scrollCtrl = ScrollController();
  bool _loadMoreScheduled = false; // debouncer against double calls

  @override
  void initState() {
    super.initState();
    _mountedFlag = true;
    _attachScrollListener();
    _loadProducts(reset: true);
  }

  @override
  void dispose() {
    _mountedFlag = false;
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _attachScrollListener() {
    _scrollCtrl.addListener(() {
      final pos = _scrollCtrl.position;
      // within 300 px from bottom
      if (pos.pixels >= pos.maxScrollExtent - 300) {
        _triggerLoadMore();
      }
    });
  }

  void _triggerLoadMore() {
    if (!_mountedFlag) return;
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;
    if (_loadMoreScheduled) return;
    _loadMoreScheduled = true;
    Future.microtask(() async {
      await _loadProducts(reset: false);
      _loadMoreScheduled = false;
    });
  }

  Future<void> _loadProducts({required bool reset}) async {
    if (!_mountedFlag) return;

    if (reset) {
      setState(() {
        _isInitialLoading = true;
        _hasError = false;
        _errorMessage = "";
        _products.clear();
        _page = 1;
        _hasMore = true;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      debugPrint('📦 Fetching page=$_page perPage=$_perPage');
      final items = await _wooService.getProducts(page: _page, perPage: _perPage);

      if (!_mountedFlag) return;

      if (reset) {
        _products
          ..clear()
          ..addAll(items);
      } else {
        _products.addAll(items);
      }

      // Cache for fast cart
      if (_products.isNotEmpty) {
        final cart = Provider.of<CartProvider>(context, listen: false);
        await cart.cacheProducts(
          _products.whereType<Map<String, dynamic>>().toList(),
        );
      }

      // Update paging flags
      if (items.length < _perPage) {
        _hasMore = false;
        debugPrint('✅ No more pages (got ${items.length} < $_perPage) | total=${_products.length}');
      } else {
        _page += 1;
        debugPrint('➡️ Ready for next page: $_page | totalSoFar=${_products.length}');
      }

      setState(() {
        _isInitialLoading = false;
        _isLoadingMore = false;
        _hasError = _products.isEmpty;
        _errorMessage = _products.isEmpty ? "No products available." : "";
      });
    } catch (e) {
      if (!_mountedFlag) return;
      setState(() {
        if (reset) _isInitialLoading = false;
        _isLoadingMore = false;
        _hasError = true;
        _errorMessage = "⚠️ Failed to load products: $e";
      });
    }
  }

  Future<void> _refreshProducts() async {
    await _loadProducts(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<UserSettingsProvider>();
    final layout = settings.homePageStyle;

    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;

    final primaryColor   = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor    = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kPrimaryBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppHeader(
        title: "TellMe.ng",
        showMenu: true,
        showBackButton: false,
        useGradient: true,
        showTitle: false,
        showWishlist: true,
        showCart: true,
        showNotifications: true,
        foregroundColor: Colors.white,
      ),
      drawer: _buildDrawer(context, themeProvider),

      // 👇 Added: WhatsApp floating button at bottom-right
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Chat on WhatsApp',
        onPressed: () {
          final user = context.read<UserProvider?>();
          final email = user?.userEmail;
          final prefill = 'Hello TellMe support 👋'
              '${email != null && email.isNotEmpty ? " — I am $email" : ""}. '
              'I need help with my order.';
          openWhatsAppChat(
            phoneE164: '2347054139575', // ← replace with your support number (no +, no spaces)
            prefill: prefill,
            context: context,
          );
        },
        child: const Icon(Icons.chat),
      ),

      body: Column(
        children: [
          // 🔍 Search
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(30),
              shadowColor: Colors.black26,
              child: TextField(
                readOnly: true,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()));
                },
                decoration: InputDecoration(
                  hintText: "Search categories, products, sku, product id...",
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.search, color: primaryColor),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide(color: primaryColor, width: 1.2),
                  ),
                ),
              ),
            ),
          ),

          // 🧭 Body
          Expanded(child: _buildBody(layout, primaryColor)),
        ],
      ),
    );
  }

  Widget _buildBody(HomePageStyle layout, Color primaryColor) {
    if (_isInitialLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 12),
            const Text("Fetching products..."),
          ],
        ),
      );
    }

    if (_hasError && _products.isEmpty) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: _refreshProducts,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const HomePageSliderCarousel(),
            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  _buildLayoutSelector(layout, primaryColor),
                ],
              ),
            ),

            const SizedBox(height: 8),
            _buildLayout(layout),
            const SizedBox(height: 8),

            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context, CelebrationThemeProvider? themeProvider) {
    final userProvider  = Provider.of<UserProvider>(context);
    final cart          = Provider.of<CartProvider>(context);
    final currentTheme  = themeProvider?.currentTheme;

    // Theme-aware colors for the drawer
    final primaryColor   = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor    = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kPrimaryBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];
    final badgeColor     = currentTheme?.badgeColor ?? Colors.red;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              gradient: currentTheme?.drawerGradient ??
                  LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            ),
            accountName: Text(
              userProvider.isLoggedIn ? userProvider.userDisplayName ?? "Guest User" : "Guest",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(
              userProvider.isLoggedIn ? userProvider.userEmail ?? "guest@example.com" : "Please sign in to continue",
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(
                userProvider.isLoggedIn ? Icons.person : Icons.person_outline,
                color: primaryColor,
                size: 40,
              ),
            ),
          ),
          if (!userProvider.isLoggedIn) ...[
            ListTile(
              leading: Icon(Icons.login, color: primaryColor),
              title: const Text("Sign In"),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/signin');
              },
            ),
            ListTile(
              leading: Icon(Icons.app_registration, color: primaryColor),
              title: const Text("Sign Up"),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/signup');
              },
            ),
          ],
          if (userProvider.isLoggedIn)
            ListTile(
              leading: Icon(Icons.person, color: primaryColor),
              title: const Text("My Profile"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
              },
            ),
          ListTile(
            leading: Icon(Icons.shopping_cart, color: primaryColor),
            title: const Text("My Cart"),
            trailing: cart.totalQuantity > 0
                ? Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(12)
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Text(
                      '${cart.totalQuantity}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  )
                : null,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/cart');
            },
          ),
          ListTile(
            leading: Icon(Icons.history, color: primaryColor),
            title: const Text("Orders"),
            onTap: () {
              Navigator.pop(context);
              if (userProvider.isLoggedIn) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage()));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please sign in to view your orders")),
                );
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (context.mounted && Navigator.canPop(context)) {
                    Navigator.pushNamed(context, '/signin');
                  }
                });
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.settings, color: primaryColor),
            title: const Text("Settings"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
          ),
          if (userProvider.isLoggedIn)
            ListTile(
              leading: Icon(Icons.logout, color: primaryColor),
              title: const Text("Logout"),
              onTap: () {
                userProvider.signOut();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("You have been logged out.")),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLayoutSelector(HomePageStyle layout, Color primaryColor) {
    Color colorFor(HomePageStyle style) => layout == style ? kWhite : Colors.white70;
    return Container(
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: "Grid View",
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: Icon(Icons.grid_view_rounded, color: colorFor(HomePageStyle.grid)),
            onPressed: () => context.read<UserSettingsProvider>().setHomePageStyle(HomePageStyle.grid),
          ),
          IconButton(
            tooltip: "List View",
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: Icon(Icons.view_list_rounded, color: colorFor(HomePageStyle.list)),
            onPressed: () => context.read<UserSettingsProvider>().setHomePageStyle(HomePageStyle.list),
          ),
          IconButton(
            tooltip: "Carousel View",
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: Icon(Icons.slideshow_rounded, color: colorFor(HomePageStyle.carousel)),
            onPressed: () => context.read<UserSettingsProvider>().setHomePageStyle(HomePageStyle.carousel),
          ),
          IconButton(
            tooltip: "Modern View",
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: Icon(Icons.style, color: colorFor(HomePageStyle.modern)),
            onPressed: () => context.read<UserSettingsProvider>().setHomePageStyle(HomePageStyle.modern),
          ),
          IconButton(
            tooltip: "Staggered View",
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: Icon(Icons.view_quilt_rounded, color: colorFor(HomePageStyle.staggered)),
            onPressed: () => context.read<UserSettingsProvider>().setHomePageStyle(HomePageStyle.staggered),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              "No Internet or Timeout",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            const SizedBox(height: 8),
            Text(_errorMessage, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadProducts(reset: true),
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayout(HomePageStyle layout) {
    switch (layout) {
      case HomePageStyle.list:
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: AdvancedProductListView(
            products: _products,
            isLoading: _isInitialLoading,
          ),
        );

      case HomePageStyle.carousel:
        // 🔗 Snap carousel hooked to the same paging flags used by the grid
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: ProductSnapCarousel(
            products: _products,
            isLoading: _isInitialLoading,

            // 🔁 server-side paging flags
            onLoadMore: () => _loadProducts(reset: false),
            isLoadingMore: _isLoadingMore,
            canLoadMore: _hasMore,

            // 🖼️ layout
            height: 330,
            topGap: 16,
            // autoPlayInterval: const Duration(seconds: 5), // optional
          ),
        );

      case HomePageStyle.staggered:
        // ✅ now wired to parent scroll + reveal paging + server paging
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: HomePageStaggered(
            products: _products,
            isLoading: _isInitialLoading,
            title: "",
            showTitle: true,
            maxItems: 0, // remove cap; use pageSize for reveal
            parentScrollController: _scrollCtrl,
            pageSize: 20,
            canLoadMore: _hasMore,
            isLoadingMore: _isLoadingMore,
            onLoadMore: () => _loadProducts(reset: false),
          ),
        );

      case HomePageStyle.modern:
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: HomePageModern(
            products: _products,
            isLoading: _isInitialLoading,
            title: "",
            showTitle: true,
            maxItems: 99999,
          ),
        );

      case HomePageStyle.grid:
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: AdvancedProductGridView(
            products: _products,
            isLoading: _isInitialLoading,

            // 🔑 wire infinite scroll to parent
            parentScrollController: _scrollCtrl,

            // 👇 show everything we have locally; reveal in chunks
            maxItems: 99999,
            pageSize: 24,

            // 🔁 server-side paging flags
            canLoadMore: _hasMore,
            isLoadingMore: _isLoadingMore,

            // 🚚 ask parent to fetch next page from Woo
            onLoadMore: () => _loadProducts(reset: false),
          ),
        );
    }
  }
}