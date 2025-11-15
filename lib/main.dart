// -------------------- IMPORTS MUST COME FIRST --------------------
import 'dart:io';
import 'dart:convert';
import 'dart:async'; // ✅ For runZonedGuarded

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard (copy token)
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart'; // ✅ For kDebugMode

// 🔔 Notifications
import 'notification_service.dart';
import 'notification_provider.dart';

// 🛒 Providers
import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'user_settings_provider.dart';
import 'user_provider.dart';
import 'celebration_theme_provider.dart';

// 📄 Pages
import 'cart_page.dart';
import 'settings_page.dart';
import 'sign_in_page.dart';
import 'sign_up_page.dart';
import 'bottom_nav_shell.dart';
import 'checkout_page.dart';
import 'profile_page.dart';
import 'wishlist_page.dart';
import 'search_page.dart';
import 'my_orders_page.dart';

import 'edit_profile_page.dart';
import 'addresses_page.dart';
import 'notifications_settings_page.dart';
import 'privacy_security_page.dart';
import 'help_center_page.dart';
import 'about_page.dart';

// ✅ WooCommerce + Product Page
import 'woocommerce_auth_service.dart';
import 'product_detail_page.dart';
import 'wallet_history_page.dart';

// -------------------- GLOBAL NAVIGATOR KEY --------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

// -------------------- REQUIRED: FCM BACKGROUND HANDLER --------------------
// Must be a top-level function. Runs when a message arrives and the app is terminated/backgrounded.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ✅ Initialize in background isolate
  await Firebase.initializeApp();
  debugPrint('📩 [BG] FCM message: ${message.messageId} data=${message.data}');
}

// -------------------- SMALL BOOT GUARD --------------------
Future<T?> guard<T>(Future<T> fut, {String label = ''}) async {
  try {
    return await fut;
  } catch (e, st) {
    debugPrint('⚠️ Boot step failed${label.isNotEmpty ? " ($label)" : ""}: $e');
    debugPrint('$st');
    return null;
  }
}

// ✅ Enforce a minimum splash/poster time from a timestamp
Future<void> _ensureMinSplash(DateTime t0, Duration min) async {
  final elapsed = DateTime.now().difference(t0);
  final remain = min - elapsed;
  if (remain > Duration.zero) {
    await Future.delayed(remain);
  }
}

// -------------------- ANALYTICS HELPER --------------------
// 🔐 Make analytics lazy so it only touches Firebase after init
class AnalyticsHelper {
  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  static Future<void> logAppStart() async {
    await _analytics.logEvent(name: 'app_start');
    debugPrint('📊 Event logged: app_start');
  }

  static Future<void> logViewProduct(int productId, String name) async {
    await _analytics.logEvent(
      name: 'view_product',
      parameters: {'product_id': productId, 'product_name': name},
    );
    debugPrint('🛍️ Event logged: view_product → $name');
  }

  static Future<void> logAddToCart(int productId, String name) async {
    await _analytics.logEvent(
      name: 'add_to_cart',
      parameters: {'product_id': productId, 'product_name': name},
    );
    debugPrint('🛒 Event logged: add_to_cart → $name');
  }

  static Future<void> logCheckoutStart(double total) async {
    await _analytics.logEvent(
      name: 'checkout_start',
      parameters: {'total_value': total},
    );
    debugPrint('💳 Event logged: checkout_start → ₦$total');
  }

  static Future<void> triggerInAppTest() async {
    await _analytics.logEvent(name: 'on_foreground_test');
    debugPrint('🚀 Fired Analytics: on_foreground_test');
  }
}

// -------------------- PUSH HANDLERS --------------------
Future<void> _handlePushData(Map<String, dynamic> data) async {
  final ctx = navigatorKey.currentContext;
  debugPrint('🔔 Push data received: $data');

  // 1️⃣ Deep link to product if productId/id exists
  final rawId = (data['productId'] ??
          data['productID'] ??
          data['product_id'] ??
          data['pid'] ??
          data['id'])
      ?.toString()
      .trim();

  if (rawId != null && rawId.isNotEmpty) {
    final id = int.tryParse(rawId);
    debugPrint('🧭 Deep link product id parsed: $id (raw: $rawId)');

    if (id != null) {
      try {
        final svc = WooCommerceAuthService();
        final product = await svc.searchProductById(id);
        if (product != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => ProductDetailPage(product: product),
            ),
          );
          await AnalyticsHelper.logViewProduct(id, product['name'] ?? 'Unknown');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Fetch-by-id failed: $e (falling back to Search)');
      }

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => SearchPage(
            initialQuery: '$id',
            initialSearchType: 'id',
          ),
        ),
      );
      return;
    }
  }

  // 2️⃣ Generic route (e.g. /cart, /wishlist)
  final route = data['route']?.toString();
  if (route != null && route.isNotEmpty) {
    debugPrint('🧭 Navigating to named route: $route');
    navigatorKey.currentState?.pushNamed(route);
    return;
  }

  // 3️⃣ Fallback → show toast
  final ctx2 = navigatorKey.currentContext;
  if (ctx2 != null) {
    ScaffoldMessenger.of(ctx2).showSnackBar(
      const SnackBar(content: Text('Opened from notification')),
    );
  }
}

Future<void> _handlePush(RemoteMessage m) async => _handlePushData(m.data);

// -------------------- TOKEN + FID LOGGING --------------------
Future<void> _printAndCopyFcmToken() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      debugPrint('🔑 FCM token: $token');
      // Only copy to clipboard in debug to avoid surprising users
      if (kDebugMode) {
        await Clipboard.setData(ClipboardData(text: token));
      }
    }
  } catch (e, st) {
    debugPrint('⚠️ getToken failed: $e');
    debugPrint('$st');
  }
}

// ==================== SUPER-LIGHT MAIN ====================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  await runZonedGuarded<Future<void>>(
    () async {
      // ✅ Initialize Firebase ONCE, before anything else uses it
      try {
        await Firebase.initializeApp();
        debugPrint('✅ Firebase initialized in main()');
      } catch (e, st) {
        debugPrint('❌ Firebase.initializeApp failed in main(): $e');
        debugPrint('$st');
      }

      // ✅ Register background handler after init
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Draw poster immediately (Firebase is already ready at this point)
      runApp(const _MinimalBootApp());
    },
    (error, stack) {
      // Global crash guard – this prevents silent white-screen on release
      debugPrint('🔥 Uncaught error in main zone: $error');
      debugPrint('$stack');
    },
  );
}

// A tiny shell that draws the poster and runs heavy init behind it.
class _MinimalBootApp extends StatelessWidget {
  const _MinimalBootApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Bootstrap(),
    );
  }
}

// -------------------- APP BOOTSTRAP (does heavy init behind the poster) --------------------
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({super.key});
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  // Keep these so we can still navigate even if boot fails / times out
  UserSettingsProvider? _userSettings;
  CelebrationThemeProvider? _themeProvider;

  @override
  void initState() {
    super.initState();
    _bootAsync();
  }

  Future<void> _bootAsync() async {
    final t0 = DateTime.now();

    try {
      // ⏱️ Give all boot steps at most 15 seconds in total.
      await _doBootSteps().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint(
            '⚠️ Boot timed out after 15s, continuing to app anyway (failing open).',
          );
          return;
        },
      );
    } catch (e, st) {
      debugPrint('⚠️ Boot failed unexpectedly: $e');
      debugPrint('$st');
      // We swallow errors so the app still moves past splash.
    }

    if (!mounted) return;

    // Keep your minimum splash time
    await _ensureMinSplash(t0, const Duration(seconds: 3));

    final userSettings = _userSettings ?? UserSettingsProvider();
    final themeProvider = _themeProvider ?? CelebrationThemeProvider();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => NotificationProvider()..load(),
            ),
            ChangeNotifierProvider(create: (_) => CartProvider()),
            ChangeNotifierProvider(create: (_) => WishlistProvider()),
            ChangeNotifierProvider.value(value: userSettings),
            ChangeNotifierProvider(create: (_) => UserProvider()..initialize()),
            ChangeNotifierProvider.value(value: themeProvider),
          ],
          child: const MyApp(),
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  /// 🔧 All heavy startup work moved here so we can wrap it with timeout/try-catch.
  Future<void> _doBootSteps() async {
    // ✅ Firebase is already initialized in main(); this is just a safety fallback.
    if (Firebase.apps.isEmpty) {
      await guard(
        Firebase.initializeApp(),
        label: 'Firebase.initializeApp (fallback)',
      );
    }

    // (Optional) projectId log
    try {
      final app = Firebase.app();
      debugPrint('🔥 Firebase projectId: ${app.options.projectId}');
    } catch (e) {
      debugPrint('⚠️ Could not read Firebase app options: $e');
    }

    // ✅ Ask for notification permission (Android 13+ + iOS)
    await guard(
      FirebaseMessaging.instance.requestPermission(),
      label: 'FCM requestPermission',
    );

    await guard(AnalyticsHelper.logAppStart(), label: 'Analytics logAppStart');

    // 🔔 Local notification service → taps handled via NotificationProvider + _handlePush
    await guard(
      NotificationService.init(
        onTap: (RemoteMessage m) async {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
            await guard(
              ctx.read<NotificationProvider>().handleMessage(m, fromTap: true),
              label: 'NotificationProvider.onTap',
            );
          }
          await guard(_handlePush(m), label: '_handlePush');
        },
        onLocalTap: (Map<String, dynamic> data) async {
          await guard(_handlePushData(data), label: '_handlePushData(local)');
        },
      ),
      label: 'NotificationService.init',
    );

    // 🔔 Foreground FCM messages
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage m) async {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          await guard(
            ctx.read<NotificationProvider>().handleMessage(m, fromTap: false),
            label: 'NotificationProvider.onMessage',
          );
        }
      });
    } catch (e, st) {
      debugPrint('⚠️ onMessage.listen failed: $e\n$st');
    }

    // 🔔 FCM when user taps a notification and opens/resumes the app
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) async {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          await guard(
            ctx.read<NotificationProvider>().handleMessage(m, fromTap: true),
            label: 'NotificationProvider.onMessageOpenedApp',
          );
        }
        await guard(_handlePush(m), label: '_handlePush(openedApp)');
      });
    } catch (e, st) {
      debugPrint('⚠️ onMessageOpenedApp.listen failed: $e\n$st');
    }

    // 🔔 App launched from a terminated state via notification tap
    final initialMessage = await guard(
      FirebaseMessaging.instance.getInitialMessage(),
      label: 'getInitialMessage',
    );
    if (initialMessage != null) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        await guard(
          ctx
              .read<NotificationProvider>()
              .handleMessage(initialMessage, fromTap: true),
          label: 'NotificationProvider.initialMessage',
        );
      }
      await guard(_handlePush(initialMessage), label: '_handlePush(initial)');
    }

    await guard(_printAndCopyFcmToken(), label: 'print fcm token');

    // 🔧 Load user settings + celebration theme
    final userSettings = UserSettingsProvider();
    await guard(userSettings.loadSettings(), label: 'userSettings.loadSettings');
    _userSettings = userSettings;

    final themeProvider = CelebrationThemeProvider();
    _themeProvider = themeProvider;
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0B46C5),
      body: _PosterOnly(),
    );
  }
}

// ---------- Aspect-ratio aware poster ----------
class _PosterOnly extends StatelessWidget {
  const _PosterOnly({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final ratio = size.height / size.width;

    String asset;
    if (ratio < 1.90) {
      asset = 'assets/images/splash_poster_16_9.png';
    } else if (ratio < 2.08) {
      asset = 'assets/images/splash_poster_18_9.png';
    } else {
      asset = 'assets/images/splash_poster_20_9.png';
    }

    return _PosterImage(
      asset,
      alignment: const Alignment(0, -0.1),
    );
  }
}

class _PosterImage extends StatelessWidget {
  final String asset;
  final Alignment alignment;
  const _PosterImage(this.asset, {super.key, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
  }
}

// -------------------- FIAM BOOTSTRAPPER (SIMPLIFIED) --------------------
class _FiamBootstrapper extends StatefulWidget {
  final Widget child;
  const _FiamBootstrapper({required this.child});

  @override
  State<_FiamBootstrapper> createState() => _FiamBootstrapperState();
}

class _FiamBootstrapperState extends State<_FiamBootstrapper>
    with WidgetsBindingObserver {
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_bootstrapped) {
        _bootstrapped = true;
        await AnalyticsHelper.triggerInAppTest();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await AnalyticsHelper.triggerInAppTest();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// -------------------- APP --------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserSettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'TellMe.ng Shop',
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            fontFamily: GoogleFonts.inter().fontFamily,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            fontFamily: GoogleFonts.inter().fontFamily,
          ),
          themeMode: settings.themeMode,
          home: const _FiamBootstrapper(child: BottomNavShell()),
          routes: <String, WidgetBuilder>{
            '/signin': (context) => const SignInPage(),
            '/signup': (context) => const SignUpPage(),
            '/settings': (context) => const SettingsPage(),
            '/cart': (context) => const CartPage(),
            '/profile': (context) => const ProfilePage(),
            '/wishlist': (context) => const WishlistPage(),
            '/search': (context) => const SearchPage(),
            '/myorders': (context) => const MyOrdersPage(),
            '/editprofile': (context) => const EditProfilePage(),
            '/addresses': (context) => const AddressesPage(),
            '/notifications': (context) => const NotificationsSettingsPage(),
            '/privacy': (context) => const PrivacySecurityPage(),
            '/help': (context) => const HelpCenterPage(),
            '/about': (context) => const AboutPage(),
            '/wallet-history': (context) => const WalletHistoryPage(),
            '/checkout': (context) {
              final args =
                  ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

              final List<dynamic> cartItems =
                  (args?['cartItems'] as List?)?.cast<dynamic>() ??
                      const <dynamic>[];

              final double subtotal = (args?['subtotal'] is num)
                  ? (args!['subtotal'] as num).toDouble()
                  : 0.0;

              final double shipping = (args?['shipping'] is num)
                  ? (args!['shipping'] as num).toDouble()
                  : 0.0;

              final double total = (args?['total'] is num)
                  ? (args!['total'] as num).toDouble()
                  : (subtotal + shipping);

              return CheckoutPage(
                cartItems: cartItems,
                subtotal: subtotal,
                shipping: shipping,
                total: total,
              );
            },
          },
          onUnknownRoute: (settings) =>
              MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      },
    );
  }
}
