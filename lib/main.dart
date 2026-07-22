// -------------------- IMPORTS MUST COME FIRST --------------------
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import 'firebase_options.dart';

// ðŸ”” Notifications
import 'notification_service.dart';
import 'notification_provider.dart';
import 'blog_notification_provider.dart';

// ðŸ›’ Providers
import 'cart_provider.dart';
import 'wishlist_provider.dart';
import 'user_settings_provider.dart';
import 'user_provider.dart';
import 'celebration_theme_provider.dart';

// ðŸ“„ Pages
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
import 'support_chat_page.dart';

// âœ… WooCommerce + Product Page
import 'woocommerce_auth_service.dart';
import 'product_detail_page.dart';
import 'wallet_history_page.dart';

// -------------------- GLOBAL NAVIGATOR KEY --------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final Future<bool> _firebaseInitialization;

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

// -------------------- REQUIRED: FCM BACKGROUND HANDLER --------------------
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  debugPrint(
      'ðŸ“© [BG] FCM message: ${message.messageId} data=${message.data}');
}

// -------------------- SMALL BOOT GUARD --------------------
Future<T?> guard<T>(Future<T> fut, {String label = ''}) async {
  try {
    return await fut;
  } catch (e, st) {
    debugPrint(
        'âš ï¸ Boot step failed${label.isNotEmpty ? " ($label)" : ""}: $e');
    debugPrint('$st');
    return null;
  }
}

Future<bool> _initializeFirebaseSafely(
    {String label = 'Firebase.initializeApp'}) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 5));
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      final app = Firebase.app();
      debugPrint('Firebase ready: ${app.options.projectId}');
    } catch (e) {
      debugPrint('Firebase ready, but options could not be read: $e');
    }

    return true;
  } catch (e, st) {
    debugPrint('Firebase startup skipped ($label): $e');
    debugPrint('$st');
    return false;
  }
}

Future<void> _ensureMinSplash(DateTime t0, Duration min) async {
  final elapsed = DateTime.now().difference(t0);
  final remain = min - elapsed;

  if (remain > Duration.zero) {
    await Future.delayed(remain);
  }
}

// -------------------- ANALYTICS HELPER --------------------
class AnalyticsHelper {
  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  static Future<void> logAppStart() async {
    await _analytics.logEvent(name: 'app_start');
    debugPrint('ðŸ“Š Event logged: app_start');
  }

  static Future<void> logViewProduct(int productId, String name) async {
    await _analytics.logEvent(
      name: 'view_product',
      parameters: {'product_id': productId, 'product_name': name},
    );
    debugPrint('ðŸ›ï¸ Event logged: view_product â†’ $name');
  }

  static Future<void> logAddToCart(int productId, String name) async {
    await _analytics.logEvent(
      name: 'add_to_cart',
      parameters: {'product_id': productId, 'product_name': name},
    );
    debugPrint('ðŸ›’ Event logged: add_to_cart â†’ $name');
  }

  static Future<void> logCheckoutStart(double total) async {
    await _analytics.logEvent(
      name: 'checkout_start',
      parameters: {'total_value': total},
    );
    debugPrint('ðŸ’³ Event logged: checkout_start â†’ â‚¦$total');
  }
}

// -------------------- PUSH HANDLERS --------------------
Future<void> _handlePushData(Map<String, dynamic> data) async {
  debugPrint('ðŸ”” Push data received: $data');

  final rawId = (data['productId'] ??
          data['productID'] ??
          data['product_id'] ??
          data['pid'] ??
          data['id'])
      ?.toString()
      .trim();

  if (rawId != null && rawId.isNotEmpty) {
    final id = int.tryParse(rawId);
    debugPrint('ðŸ§­ Deep link product id parsed: $id (raw: $rawId)');

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

          await AnalyticsHelper.logViewProduct(
            id,
            product['name'] ?? 'Unknown',
          );
          return;
        }
      } catch (e) {
        debugPrint('âš ï¸ Fetch-by-id failed: $e (falling back to Search)');
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

  final route = data['route']?.toString();

  if (route != null && route.isNotEmpty) {
    debugPrint('ðŸ§­ Navigating to named route: $route');
    navigatorKey.currentState?.pushNamed(route);
    return;
  }

  final ctx2 = navigatorKey.currentContext;

  if (ctx2 != null) {
    ScaffoldMessenger.of(ctx2).showSnackBar(
      const SnackBar(content: Text('Opened from notification')),
    );
  }
}

Future<void> _handlePush(RemoteMessage m) async => _handlePushData(m.data);

// -------------------- TOKEN LOGGING --------------------
Future<void> _printAndCopyFcmToken() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();

    if (token != null) {
      debugPrint('ðŸ”‘ FCM token: $token');

      if (kDebugMode) {
        await Clipboard.setData(ClipboardData(text: token));
      }
    }
  } catch (e, st) {
    debugPrint('âš ï¸ getToken failed: $e');
    debugPrint('$st');
  }
}

// ==================== SUPER-LIGHT MAIN ====================
Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      // IMPORTANT:
      // WidgetsFlutterBinding.ensureInitialized() and runApp() must be inside
      // the same zone. This fixes the Flutter "Zone mismatch" startup error.
      WidgetsFlutterBinding.ensureInitialized();

      HttpOverrides.global = MyHttpOverrides();

      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('Flutter framework error: ${details.exceptionAsString()}');

        if (details.stack != null) {
          debugPrint('${details.stack}');
        }
      };
      ErrorWidget.builder = (FlutterErrorDetails details) {
        debugPrint('Flutter build error: ${details.exceptionAsString()}');
        return const _StartupErrorFallback();
      };

      // Start Firebase exactly once, then let the bootstrap await this same
      // operation before constructing providers that access Firebase.instance.
      _firebaseInitialization = _initializeFirebaseSafely(
        label: 'main startup',
      );

      // Paint Flutter immediately. Apple should never see a blank native screen
      // while Firebase, FCM, fonts, or network startup work is happening.
      runApp(const _MinimalBootApp());
    },
    (error, stack) {
      debugPrint('ðŸ”¥ Uncaught error in main zone: $error');
      debugPrint('$stack');
    },
  );
}

class _StartupErrorFallback extends StatelessWidget {
  const _StartupErrorFallback();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF0B46C5),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'TellMe is starting. Please close and reopen the app if this continues.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A tiny shell that draws the poster and runs only light init.
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

// -------------------- APP BOOTSTRAP --------------------
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({super.key});

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  UserSettingsProvider? _userSettings;

  @override
  void initState() {
    super.initState();
    _bootAsync();
  }

  Future<void> _bootAsync() async {
    final t0 = DateTime.now();

    try {
      await _doBootSteps().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint(
            'âš ï¸ Boot timed out after 8s, continuing to app anyway.',
          );
          return;
        },
      );
    } catch (e, st) {
      debugPrint('âš ï¸ Boot failed unexpectedly: $e');
      debugPrint('$st');
    }

    if (!mounted) return;

    await _ensureMinSplash(t0, const Duration(seconds: 2));

    final userSettings = _userSettings ?? UserSettingsProvider();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => NotificationProvider()),
            ChangeNotifierProvider(create: (_) => BlogNotificationProvider()),
            ChangeNotifierProvider(create: (_) => CartProvider()),
            ChangeNotifierProvider(create: (_) => WishlistProvider()),
            ChangeNotifierProvider.value(value: userSettings),
            ChangeNotifierProvider(create: (_) => UserProvider()..initialize()),
            ChangeNotifierProvider(create: (_) => CelebrationThemeProvider()),
          ],
          child: const MyApp(),
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  Future<void> _doBootSteps() async {
    final firebaseReady = await _firebaseInitialization;
    if (!firebaseReady) {
      throw StateError('Firebase initialization did not complete.');
    }

    try {
      final app = Firebase.app();
      debugPrint('ðŸ”¥ Firebase projectId: ${app.options.projectId}');
    } catch (e) {
      debugPrint('âš ï¸ Could not read Firebase app options: $e');
    }

    final userSettings = UserSettingsProvider();

    await guard(
      userSettings.loadSettings().timeout(const Duration(seconds: 5)),
      label: 'userSettings.loadSettings',
    );

    _userSettings = userSettings;
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

  const _PosterImage(
    this.asset, {
    super.key,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: alignment,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return const ColoredBox(
            color: Color(0xFF0B46C5),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        },
      ),
    );
  }
}

// -------------------- POST-LAUNCH INITIALIZER --------------------
class _PostLaunchInitializer extends StatefulWidget {
  final Widget child;

  const _PostLaunchInitializer({required this.child});

  @override
  State<_PostLaunchInitializer> createState() => _PostLaunchInitializerState();
}

class _PostLaunchInitializerState extends State<_PostLaunchInitializer> {
  bool _started = false;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;

      _started = true;

      Future.delayed(
        const Duration(seconds: 3),
        _runBackgroundStartup,
      );
    });
  }

  Future<void> _runBackgroundStartup() async {
    if (!mounted) return;

    await guard(
      AnalyticsHelper.logAppStart().timeout(const Duration(seconds: 5)),
      label: 'Analytics logAppStart post-launch',
    );

    await guard(
      context.read<NotificationProvider>().load(),
      label: 'NotificationProvider.load post-launch',
    );

    await guard(
      NotificationService.init(
        onTap: (RemoteMessage m) async {
          final ctx = navigatorKey.currentContext;

          if (ctx != null) {
            await guard(
              ctx.read<NotificationProvider>().handleMessage(
                    m,
                    fromTap: true,
                  ),
              label: 'NotificationProvider.onTap',
            );
          }

          await guard(_handlePush(m), label: '_handlePush');
        },
        onLocalTap: (Map<String, dynamic> data) async {
          await guard(
            _handlePushData(data),
            label: '_handlePushData(local)',
          );
        },
      ).timeout(const Duration(seconds: 8)),
      label: 'NotificationService.init post-launch',
    );

    try {
      _onMessageSub ??= FirebaseMessaging.onMessage.listen(
        (RemoteMessage m) async {
          final ctx = navigatorKey.currentContext;

          if (ctx != null) {
            await guard(
              ctx.read<NotificationProvider>().handleMessage(
                    m,
                    fromTap: false,
                  ),
              label: 'NotificationProvider.onMessage',
            );
          }
        },
      );
    } catch (e, st) {
      debugPrint('âš ï¸ onMessage.listen failed: $e\n$st');
    }

    try {
      _onMessageOpenedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (RemoteMessage m) async {
          final ctx = navigatorKey.currentContext;

          if (ctx != null) {
            await guard(
              ctx.read<NotificationProvider>().handleMessage(
                    m,
                    fromTap: true,
                  ),
              label: 'NotificationProvider.onMessageOpenedApp',
            );
          }

          await guard(
            _handlePush(m),
            label: '_handlePush(openedApp)',
          );
        },
      );
    } catch (e, st) {
      debugPrint('âš ï¸ onMessageOpenedApp.listen failed: $e\n$st');
    }

    final initialMessage = await guard(
      FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 5)),
      label: 'getInitialMessage post-launch',
    );

    if (initialMessage != null) {
      final ctx = navigatorKey.currentContext;

      if (ctx != null) {
        await guard(
          ctx.read<NotificationProvider>().handleMessage(
                initialMessage,
                fromTap: true,
              ),
          label: 'NotificationProvider.initialMessage',
        );
      }

      await guard(
        _handlePush(initialMessage),
        label: '_handlePush(initial)',
      );
    }

    await guard(
      _printAndCopyFcmToken().timeout(const Duration(seconds: 5)),
      label: 'print fcm token post-launch',
    );
  }

  @override
  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedSub?.cancel();
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
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
          ),
          themeMode: settings.themeMode,
          home: const _PostLaunchInitializer(
            child: BottomNavShell(),
          ),
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
            '/support-chat': (context) => const SupportChatPage(),
            '/about': (context) => const AboutPage(),
            '/wallet-history': (context) => const WalletHistoryPage(),
            '/checkout': (context) {
              final args = ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;

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
          onUnknownRoute: (settings) {
            return MaterialPageRoute(builder: (_) => const ProfilePage());
          },
        );
      },
    );
  }
}
