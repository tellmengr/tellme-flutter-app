// lib/sign_in_page.dart
import 'dart:ui';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:email_validator/email_validator.dart';

// 🔐 Social/Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsign;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'user_provider.dart';
import 'woocommerce_auth_service.dart';
import 'sign_up_page.dart';
import 'forgot_password_page.dart';
import 'celebration_theme_provider.dart';

// 🎨 Brand Colors (fallback colors only - will use celebration theme colors)
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue  = Color(0xFF0096FF);
const kRed         = Color(0xFFE53935);
const kGreen       = Color(0xFF43A047);
const kYellow      = Color(0xFFFFB300);

// ✅ Correct WEB client ID from google-services.json (client_type: 3)
const String kWebClientId =
    '559100902559-6e8to25stl4houpdhrai9g9ghqf2skgq.apps.googleusercontent.com';

class SignInPage extends StatefulWidget {
  final Map<String, dynamic>? pendingCheckoutData;
  final VoidCallback? onSignedIn;

  const SignInPage({Key? key, this.pendingCheckoutData, this.onSignedIn})
      : super(key: key);

  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage>
    with SingleTickerProviderStateMixin {
  final _formKey            = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading           = false;
  bool _obscurePassword     = true;

  // 🔐 Google Sign In v7.2.0
  final gsign.GoogleSignIn _googleSignIn = gsign.GoogleSignIn.instance;
  bool _isGoogleSignInInitialized = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);
    _animationController.forward();
    _initializeGoogleSignIn();
  }

  // ✅ Initialize: use WEB client ID on iOS only; omit on Android
  Future<void> _initializeGoogleSignIn() async {
    try {
      await _googleSignIn.initialize(
        serverClientId: Platform.isIOS ? kWebClientId : null,
      );
      _isGoogleSignInInitialized = true;
    } catch (e) {
      _isGoogleSignInInitialized = false;
      debugPrint('Failed to initialize Google Sign-In: $e');
    }
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (!_isGoogleSignInInitialized) {
      await _initializeGoogleSignIn();
    }
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Please enter your email';
    return EmailValidator.validate(s) ? null : 'Please enter a valid email';
  }

  void _openForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 50;
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final isDarkTheme = theme.brightness == Brightness.dark;

    // 🎨 CELEBRATION THEME INTEGRATION - Listen for theme changes
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;

    // Use celebration theme colors or fallback to brand colors
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kPrimaryBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];
    final badgeColor = currentTheme?.badgeColor ?? kRed;

    // Theme-aware colors for text
    final textPrimary = _getThemeColor(context, const Color(0xFF1A1A1A), Colors.white);
    final textSecondary = _getThemeColor(context, const Color(0xFF666666), Colors.white70);
    final textTertiary = _getThemeColor(context, const Color(0xFF888888), Colors.white54);

    return Scaffold(
      backgroundColor: primaryColor, // 🎨 Use celebration theme primary color
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 🎨 Layered gradient background with celebration theme
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors, // 🎨 Use celebration theme gradient colors
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // 💠 Soft glow shapes
          Positioned(
            top: -60,
            right: -40,
            child: _GlowCircle(diameter: 220, opacity: 0.10),
          ),
          Positioned(
            bottom: 80,
            left: -60,
            child: _GlowCircle(diameter: 180, opacity: 0.08),
          ),

          // ✅ Scroll-safe layout
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    top: keyboardVisible ? 8 : 20,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
                    child: Column(
                      mainAxisAlignment: keyboardVisible
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: keyboardVisible ? 0.0 : 1.0,
                          child: _Header(themeProvider: themeProvider),
                        ),

                        const SizedBox(height: 12),

                        // 🧊 Glass Card
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: _GlassCard(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 8),
                                  Text(
                                    'Welcome back',
                                    style: _getThemeTextStyle(
                                      context,
                                      lightColor: const Color(0xFF1A1A1A),
                                      darkColor: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Sign in to continue shopping',
                                    style: _getThemeTextStyle(
                                      context,
                                      lightColor: const Color(0xFF666666),
                                      darkColor: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Fields
                                  _buildEnhancedTextField(
                                    controller: _emailController,
                                    label: "Email address",
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: _validateEmail,
                                    textInputAction: TextInputAction.next,
                                    primaryColor: primaryColor, // 🎨 Pass theme color
                                    accentColor: accentColor,
                                    badgeColor: badgeColor,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildEnhancedTextField(
                                    controller: _passwordController,
                                    label: "Password",
                                    icon: Icons.lock_outline_rounded,
                                    obscureText: _obscurePassword,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                        color: primaryColor, // 🎨 Use theme color
                                      ),
                                      onPressed: () => setState(
                                          () => _obscurePassword = !_obscurePassword),
                                    ),
                                    validator: (v) {
                                      final s = v ?? '';
                                      if (s.isEmpty) return 'Please enter your password';
                                      if (s.length < 6) {
                                        return 'Password must be at least 6 characters';
                                      }
                                      return null;
                                    },
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _signIn(),
                                    primaryColor: primaryColor, // 🎨 Pass theme color
                                    accentColor: accentColor,
                                    badgeColor: badgeColor,
                                  ),

                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: true,
                                            onChanged: (_) {},
                                            activeColor: primaryColor, // 🎨 Use theme color
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          Text('Remember me',
                                              style: _getThemeTextStyle(
                                                context,
                                                lightColor: const Color(0xFF1A1A1A),
                                                darkColor: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.normal,
                                              )),
                                        ],
                                      ),
                                      TextButton(
                                        onPressed: _openForgotPassword,
                                        child: Text(
                                          "Forgot Password?",
                                          style: _getThemeTextStyle(
                                            context,
                                            lightColor: accentColor, // 🎨 Use theme color
                                            darkColor: accentColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Primary CTA with celebration theme
                                  _PrimaryCTA(
                                    label: "Sign In",
                                    onPressed: _isLoading ? null : () {
                                      FocusScope.of(context).unfocus();
                                      _signIn();
                                    },
                                    loading: _isLoading,
                                    primaryColor: primaryColor, // 🎨 Pass theme colors
                                    accentColor: accentColor,
                                  ),

                                  const SizedBox(height: 12),

                                  // Secondary CTA with celebration theme
                                  _SecondaryCTA(
                                    label: "Create Account",
                                    onPressed: _isLoading
                                        ? null
                                        : () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => const SignUpPage(),
                                              ),
                                            ),
                                    primaryColor: primaryColor, // 🎨 Pass theme colors
                                    accentColor: accentColor,
                                    isDarkTheme: isDarkTheme,
                                  ),

                                  const SizedBox(height: 22),

                                  // Divider
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: isDarkTheme
                                              ? Colors.white24
                                              : Colors.grey[400]
                                        )
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text(
                                          "Or continue with",
                                          style: _getThemeTextStyle(
                                            context,
                                            lightColor: const Color(0xFF888888),
                                            darkColor: Colors.white54,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: isDarkTheme
                                              ? Colors.white24
                                              : Colors.grey[400]
                                        )
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 18),

                                  // Socials (brand buttons)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _BrandButton(
                                          asset: 'assets/icons/google.png',
                                          fallbackIcon: Icons.g_mobiledata_rounded,
                                          label: 'Google',
                                          onTap: _signInWithGoogle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _BrandButton(
                                          asset: 'assets/icons/facebook.png',
                                          fallbackIcon: Icons.facebook_rounded,
                                          label: 'Facebook',
                                          onTap: _signInWithFacebook,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _BrandButton(
                                          asset: 'assets/icons/apple.png',
                                          fallbackIcon: Icons.apple_rounded,
                                          label: 'Apple',
                                          onTap: _signInWithApple,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Older SDKs sometimes misparse collection-if; use ternary
                        (!keyboardVisible)
                            ? SizedBox(height: size.height * 0.06)
                            : const SizedBox.shrink(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get theme-aware colors
  Color _getThemeColor(BuildContext context, Color lightColor, Color darkColor) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    return isDarkTheme ? darkColor : lightColor;
  }

  // Helper method to get theme-aware text style
  TextStyle _getThemeTextStyle(BuildContext context, {
    required Color lightColor,
    required Color darkColor,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: isDarkTheme ? darkColor : lightColor,
    );
  }

  // ---------------------- FIELD WIDGET ----------------------
  Widget _buildEnhancedTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    required Color primaryColor, // 🎨 Theme color
    required Color accentColor,
    required Color badgeColor,
  }) {
    final theme = Theme.of(context);
    final isDarkTheme = theme.brightness == Brightness.dark;

    // Theme-aware text and border colors
    final textColor = isDarkTheme ? Colors.white : const Color(0xFF1A1A1A);
    final labelColor = isDarkTheme ? Colors.white70 : const Color(0xFF666666);
    final borderColor = isDarkTheme ? Colors.white24 : Colors.grey.shade200;
    final fillColor = isDarkTheme ? Colors.white.withOpacity(0.1) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.10), // 🎨 Use theme color
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        style: TextStyle(
          fontSize: 15.5,
          color: textColor,
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          labelText: label,
          labelStyle: TextStyle(color: labelColor),
          prefixIcon: Icon(icon, color: primaryColor), // 🎨 Use theme color
          suffixIcon: suffix,
          filled: true,
          fillColor: fillColor,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: borderColor, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: primaryColor, width: 1.5), // 🎨 Use theme color
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: badgeColor, width: 1.3), // 🎨 Use theme badge color
          ),
        ),
      ),
    );
  }

  // ---------------------- AUTH METHODS ----------------------
  Future<void> _signIn() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final pass  = _passwordController.text;
      final authService  = WooCommerceAuthService();
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      final isAdmin = await authService.checkEmailIsAdmin(email);
      final ok      = await userProvider.signIn(email, pass);
      if (!ok) throw Exception('Invalid credentials.');
      if (isAdmin) await userProvider.setAdminFlag(true);

      // 🎨 Use celebration theme colors for success message
      final themeProvider = context.read<CelebrationThemeProvider?>();
      final successColor = themeProvider?.currentTheme.accentColor ?? kGreen;
      _showSnack('Signed in successfully!', successColor);
      _postLoginRedirect();
    } catch (e) {
      // 🎨 Use celebration theme colors for error message
      final themeProvider = context.read<CelebrationThemeProvider?>();
      final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;
      _showSnack(e.toString(), errorColor);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- GOOGLE SIGN-IN (v7.2.0) ----------------
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await _ensureGoogleSignInInitialized();

      final gsign.GoogleSignInAccount? gUser = await _googleSignIn.authenticate();
      if (gUser == null) {
        final themeProvider = context.read<CelebrationThemeProvider?>();
        final warningColor = themeProvider?.currentTheme.accentColor ?? kYellow;
        _showSnack('Google sign-in cancelled by user.', warningColor);
        return;
      }

      final gsign.GoogleSignInAuthentication gAuth = gUser.authentication;
      if (gAuth.idToken == null) {
        final themeProvider = context.read<CelebrationThemeProvider?>();
        final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;
        _showSnack('Failed to get Google ID token.', errorColor);
        return;
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken!,
      );

      final UserCredential userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      await _finishSocialLogin(userCred, provider: 'Google');
    } on gsign.GoogleSignInException catch (e) {
      final themeProvider = context.read<CelebrationThemeProvider?>();
      final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;
      _showSnack('Google sign-in error: ${e.description}', errorColor);
    } catch (e) {
      final themeProvider = context.read<CelebrationThemeProvider?>();
      final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;
      _showSnack('Google sign-in failed: $e', errorColor);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- FACEBOOK SIGN-IN ----------------
  Future<void> _signInWithFacebook() async {
    setState(() => _isLoading = true);
    try {
      final result = await FacebookAuth.instance.login(permissions: ['email']);
      if (result.status != LoginStatus.success) {
        final themeProvider = context.read<CelebrationThemeProvider?>();
        final warningColor = themeProvider?.currentTheme.accentColor ?? kYellow;
        _showSnack('Facebook sign-in cancelled.', warningColor);
        return;
      }

      final credential = FacebookAuthProvider.credential(
        result.accessToken!.tokenString,
      );

      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _finishSocialLogin(userCred, provider: 'Facebook');
    } catch (e) {
      final themeProvider = context.read<CelebrationThemeProvider?>();
      final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;
      _showSnack('Facebook sign-in failed: $e', errorColor);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- APPLE SIGN-IN ----------------
  Future<void> _signInWithApple() async {
    if (!Platform.isIOS) {
      final themeProvider = context.read<CelebrationThemeProvider?>();
      final warningColor = themeProvider?.currentTheme.accentColor ?? kYellow;
      _showSnack('Apple Sign-In only available on iOS.', warningColor);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final appleCred = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCred = OAuthProvider('apple.com').credential(
        idToken: appleCred.identityToken,
        accessToken: appleCred.authorizationCode,
      );

      final userCred =
          await FirebaseAuth.instance.signInWithCredential(oauthCred);
      await _finishSocialLogin(
        userCred,
        provider: 'Apple',
        fallbackName: appleCred.givenName ?? '',
      );
    } catch (e) {
      final themeProvider = context.read<CelebrationThemeProvider?>();
      final errorColor = themeProvider?.currentTheme.badgeColor ?? kRed;
      _showSnack('Apple sign-in failed: $e', errorColor);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- FINAL LOGIN FLOW HELPERS ----------------
  Future<void> _finishSocialLogin(
    UserCredential cred, {
    required String provider,
    String? fallbackName,
  }) async {
    final firebaseUser = cred.user;
    if (firebaseUser == null) {
      throw Exception('No user returned from $provider.');
    }

    final email = firebaseUser.email?.trim();
    final displayName =
        firebaseUser.displayName ?? (fallbackName ?? 'TellMe User');
    final photoUrl = firebaseUser.photoURL;

    if (email == null || email.isEmpty) {
      throw Exception('$provider did not return an email.');
    }

    final wc = WooCommerceAuthService();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final customer = await wc.ensureCustomer(
      email: email,
      firstName: displayName.split(' ').first,
      lastName: displayName.split(' ').length > 1
          ? displayName.split(' ').sublist(1).join(' ')
          : '',
      avatarUrl: photoUrl,
    );

    await userProvider.setLoggedInCustomer(customer);

    // 🎨 Use celebration theme colors for success message
    final themeProvider = context.read<CelebrationThemeProvider?>();
    final successColor = themeProvider?.currentTheme.accentColor ?? kGreen;
    _showSnack('Signed in with $provider successfully!', successColor);
    _postLoginRedirect();
  }

  void _postLoginRedirect() {
    if (widget.onSignedIn != null) {
      widget.onSignedIn!.call();
    } else if (widget.pendingCheckoutData != null) {
      Navigator.pushReplacementNamed(context, '/checkout');
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              bg == (context.read<CelebrationThemeProvider?>()?.currentTheme.badgeColor ?? kRed)
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// ---------- Pretty pieces ----------

class _GlowCircle extends StatelessWidget {
  final double diameter;
  final double opacity;
  const _GlowCircle({required this.diameter, this.opacity = 0.1, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
        boxShadow: [
          BoxShadow(
            blurRadius: 60,
            spreadRadius: 10,
            color: Colors.white.withOpacity(opacity * 0.8),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CelebrationThemeProvider? themeProvider;

  const _Header({required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    // 🎨 Use celebration theme greeting text if available
    final greetingText = themeProvider?.currentTheme.greetingText ?? "Welcome Back";
    final subText = themeProvider?.currentTheme.bannerText ?? "Sign in to continue";

    return Column(
      children: [
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: BackButton(color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          "TELLME",
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 6,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          greetingText, // 🎨 Use celebration theme greeting
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subText, // 🎨 Use celebration theme banner text
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: isDarkTheme
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: isDarkTheme
                    ? Colors.white.withOpacity(0.3)
                    : Colors.white.withOpacity(0.7),
                width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDarkTheme ? 0.3 : 0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PrimaryCTA extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color primaryColor; // 🎨 Theme colors
  final Color accentColor;

  const _PrimaryCTA({
    required this.label,
    required this.onPressed,
    this.loading = false,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, accentColor], // 🎨 Use celebration theme gradient
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.6,
                    ),
                  )
                : const Text(
                    'Sign In',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.6,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryCTA extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color primaryColor; // 🎨 Theme colors
  final Color accentColor;
  final bool isDarkTheme;

  const _SecondaryCTA({
    required this.label,
    required this.onPressed,
    required this.primaryColor,
    required this.accentColor,
    required this.isDarkTheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isDarkTheme
                ? Colors.white.withOpacity(0.8)
                : primaryColor, // 🎨 Use celebration theme color
            width: 1.8
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isDarkTheme
                ? Colors.white.withOpacity(0.9)
                : primaryColor, // 🎨 Use celebration theme color
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _BrandButton extends StatelessWidget {
  final String asset;
  final IconData fallbackIcon;
  final String label;
  final VoidCallback? onTap;

  const _BrandButton({
    required this.asset,
    required this.fallbackIcon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Ink(
      decoration: BoxDecoration(
        color: isDarkTheme
            ? Colors.white.withOpacity(0.1)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkTheme
              ? Colors.white.withOpacity(0.3)
              : Colors.grey[300]!,
          width: 1.2
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkTheme
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BrandLogo(asset: asset, fallbackIcon: fallbackIcon),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: isDarkTheme
                      ? Colors.white
                      : const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  final String asset;
  final IconData fallbackIcon;

  const _BrandLogo({required this.asset, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: 22,
      height: 22,
      errorBuilder: (_, __, ___) => Icon(fallbackIcon, size: 22),
    );
  }
}