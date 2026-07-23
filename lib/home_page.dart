import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'user_settings_provider.dart';
import 'cart_provider.dart';
import 'user_provider.dart';
import 'home_page_grid.dart';
import 'home_page_list.dart';
import 'home_page_slider_carousel.dart';
import 'home_page_staggered.dart';
import 'home_page_modern.dart';
import 'woocommerce_service.dart';
import 'home_page_carousel.dart';
import 'app_header.dart';
import 'settings_page.dart';
import 'search_page.dart';
import 'celebration_theme_provider.dart';
import 'my_orders_page.dart';
import 'profile_page.dart';
import 'blog_list_page.dart';
import 'blog_notification_provider.dart';
import 'whatsapp_helper.dart';
      body: Column(
        children: [
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
              child: TextField(
                readOnly: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
                decoration: InputDecoration(
                  hintText: "Search categories, products, sku, product id...",
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.search, color: primaryColor),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 20,
                  ),
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
          Expanded(
            child: _buildBody(layout, settings, primaryColor),
          ),
        ],
      ),
    );
  }

  Drawer _buildDrawer(
    BuildContext context,
    CelebrationThemeProvider? themeProvider,
  ) {
    final userProvider = Provider.of<UserProvider>(context);
    final cart = Provider.of<CartProvider>(context);
    final blogNotif = context.watch<BlogNotificationProvider?>();
    final hasNewBlog = blogNotif?.hasNewPost ?? false;

    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final gradientColors =
        currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];
    final badgeColor = currentTheme?.badgeColor ?? Colors.red;

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
              userProvider.isLoggedIn
                  ? userProvider.userDisplayName ?? "Guest User"
                  : "Guest",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(
              userProvider.isLoggedIn
                  ? userProvider.userEmail ?? "guest@example.com"
                  : "Please sign in to continue",
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${cart.totalQuantity}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
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
            title: const Text("My Orders"),
            onTap: () {
              Navigator.pop(context);

              if (userProvider.isLoggedIn) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyOrdersPage()),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Please sign in to view your orders"),
                  ),
                );

                Future.delayed(const Duration(milliseconds: 500), () {
                  if (context.mounted) {
                    Navigator.pushNamed(context, '/signin');
                  }
                });
              }
            },
          ),

          // 🚚 TellMe Logistics
          ListTile(
            leading: Icon(Icons.local_shipping_outlined, color: primaryColor),
            title: const Text("TellMe Logistics"),
            subtitle: const Text("Send package or track delivery"),
            onTap: () {
              Navigator.pop(context);
              _openLogisticsPage();
            },
          ),

          ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.article_outlined, color: primaryColor),
                if (hasNewBlog)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                const Text("Our Blog"),
                if (hasNewBlog)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      "NEW",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BlogListPage()),
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.settings, color: primaryColor),
            title: const Text("Settings"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
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
                  const SnackBar(
                    content: Text("You have been logged out."),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    HomePageStyle layout,
    UserSettingsProvider settings,
    Color primaryColor,
  ) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }

    final productCount = _products.length;

    return RefreshIndicator(
      onRefresh: _refreshProducts,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const HomePageSliderCarousel(),
            const SizedBox(height: 12),
            if (_hasError && _products.isEmpty)
              _buildErrorState()
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$productCount products',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    _buildLayoutToggle(layout, settings),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildLayout(layout),
            ],
            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final message = _productLoadErrorMessage();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E8F5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 46, color: kPrimaryBlue),
            const SizedBox(height: 12),
            const Text(
              'Unable to show products',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF07172F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Color(0xFF4C5F78),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _loadProducts(reset: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayout(HomePageStyle layout) {
    switch (layout) {
      case HomePageStyle.list:
        return AdvancedProductListView(
          products: _products,
          isLoading: _isInitialLoading,
        );

      case HomePageStyle.carousel:
        return ProductSnapCarousel(
          products: _products,
          isLoading: _isInitialLoading,
          onLoadMore: () => _loadProducts(reset: false),
          isLoadingMore: _isLoadingMore,
          canLoadMore: _hasMore,
        );

      case HomePageStyle.staggered:
        return HomePageStaggered(
          products: _products,
          isLoading: _isInitialLoading,
          title: "",
          showTitle: true,
          parentScrollController: _scrollCtrl,
          pageSize: 20,
          canLoadMore: _hasMore,
          isLoadingMore: _isLoadingMore,
          onLoadMore: () => _loadProducts(reset: false),
        );

      case HomePageStyle.modern:
        return HomePageModern(
          products: _products,
          isLoading: _isInitialLoading,
          title: "",
          showTitle: true,
          maxItems: 99999,
        );

      case HomePageStyle.grid:
      default:
        return AdvancedProductGridView(
          products: _products,
          isLoading: _isInitialLoading,
          parentScrollController: _scrollCtrl,
          maxItems: 99999,
          pageSize: 24,
          canLoadMore: _hasMore,
          isLoadingMore: _isLoadingMore,
          onLoadMore: () => _loadProducts(reset: false),
        );
    }
  }

  Widget _buildLayoutToggle(
    HomePageStyle current,
    UserSettingsProvider settings,
  ) {
    Widget buildTile(HomePageStyle style, IconData icon) {
      final bool isActive = current == style;

      return InkWell(
        onTap: () => settings.setHomePageStyle(style),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive ? kPrimaryBlue : kPrimaryBlue.withOpacity(0.55),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isActive ? 0.18 : 0.08),
                blurRadius: isActive ? 6 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 18,
            color: Colors.white,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildTile(HomePageStyle.grid, Icons.grid_view_rounded),
        buildTile(HomePageStyle.list, Icons.view_list_rounded),
        buildTile(HomePageStyle.carousel, Icons.view_carousel_rounded),
        buildTile(HomePageStyle.staggered, Icons.dashboard_customize_rounded),
        buildTile(HomePageStyle.modern, Icons.auto_awesome_rounded),
      ],
    );
  }
}
