import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'cart_page.dart';
import 'wishlist_page.dart';
import 'celebration_theme_provider.dart';
import 'notification_provider.dart';           // ✅ NEW
import 'notifications_settings_page.dart';     // ✅ tap target (or your notifications page)

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final bool showMenu;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final TextStyle? titleStyle;
  final bool useGradient;
  final bool showTitle;
  final bool showWishlist;
  final bool showCart;
  final bool showNotifications;                // ✅ NEW

  const AppHeader({
    Key? key,
    required this.title,
    this.showBackButton = true,
    this.showMenu = false,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
    this.titleStyle,
    this.useGradient = false,
    this.showTitle = true,
    this.showWishlist = false,
    this.showCart = true,
    this.showNotifications = false,            // ✅ NEW (defaults to off)
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;

    final gradientColors = useGradient
        ? (currentTheme?.gradient.colors ?? [const Color(0xFF004AAD), const Color(0xFF0096FF)])
        : null;

    // Use primaryColor for background when celebration theme is active
    final bgColor = useGradient
        ? Colors.transparent
        : (backgroundColor ?? currentTheme?.primaryColor ?? const Color(0xFF1565C0));

    // Ensure proper contrast - always use white for foreground when celebration theme is active
    final fgColor = foregroundColor ?? Colors.white;

    return Container(
      decoration: useGradient && gradientColors != null
          ? BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            )
          : null,
      child: AppBar(
        automaticallyImplyLeading: showBackButton,
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        elevation: useGradient ? 0 : 4,
        shadowColor: Colors.black26,
        centerTitle: true,

        leading: showMenu
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : (showBackButton
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  )
                : const SizedBox()),

        title: showTitle
            ? Text(
                title,
                style: titleStyle ??
                    const TextStyle(
                      fontFamily: 'Book Antiqua',
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
              )
            : null,

        actions: [
          if (actions != null) ...actions!,

          // 🔔 Notifications bell with live badge
          if (showNotifications)
            Consumer<NotificationProvider>(
              builder: (context, notif, _) {
                final count = notif.unreadCount;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                      onPressed: () async {
                        // mark as read and open page
                        await notif.markAllRead();
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationsSettingsPage()),
                          );
                        }
                      },
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: currentTheme?.badgeColor ?? Colors.red,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (currentTheme?.badgeColor ?? Colors.red).withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          // 💖 Wishlist badge
          if (showWishlist)
            Consumer<WishlistProvider>(
              builder: (context, wishlist, child) {
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.favorite_border, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const WishlistPage()),
                        );
                      },
                    ),
                    if (wishlist.count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: currentTheme?.badgeColor ?? Colors.pink,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (currentTheme?.badgeColor ?? Colors.pink).withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            wishlist.count > 99 ? '99+' : '${wishlist.count}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          // 🛒 Cart badge
          if (showCart)
            Consumer<CartProvider>(
              builder: (context, cart, child) {
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                      onPressed: () {
                        Navigator.pushNamed(context, '/cart');
                      },
                    ),
                    if (cart.totalQuantity > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: currentTheme?.badgeColor ?? Colors.red,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (currentTheme?.badgeColor ?? Colors.red).withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            cart.totalQuantity > 99 ? '99+' : '${cart.totalQuantity}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          const SizedBox(width: 4),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class SimpleThemes {
  static const blue = Color(0xFF2196F3);
  static const green = Color(0xFF4CAF50);
  static const purple = Color(0xFF9C27B0);
  static const orange = Color(0xFFFF9800);
  static const red = Color(0xFFF44336);
  static const teal = Color(0xFF009688);
  static const indigo = Color(0xFF3F51B5);
  static const pink = Color(0xFFE91E63);
}