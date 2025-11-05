import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:email_validator/email_validator.dart';
import 'dart:ui'; // for BackdropFilter
import 'user_provider.dart';
import 'celebration_theme_provider.dart';

// 🎨 Brand Colors - LIGHTER THEME
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue  = Color(0xFF0096FF);
const kLightBlue   = Color(0xFFE3F2FD); // Light background
const kVeryLightBlue = Color(0xFFF5F8FF); // Very light blue
const kRed         = Color(0xFFE53935);
const kGreen       = Color(0xFF43A047);
const kYellow      = Color(0xFFFFB300);

// Custom clipper for curved container
class ImprovedCurvedClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 60);
    path.quadraticBezierTo(0, size.height, 60, size.height);
    path.lineTo(size.width - 60, size.height);
    path.quadraticBezierTo(size.width, size.height, size.width, size.height - 60);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({Key? key}) : super(key: key);

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController    = TextEditingController();
  final _lastNameController     = TextEditingController();
  final _emailController        = TextEditingController();
  final _passwordController     = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _firstNameNode = FocusNode();
  final _lastNameNode  = FocusNode();
  final _emailNode     = FocusNode();
  final _passNode      = FocusNode();
  final _confirmNode   = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);
    _animationController.forward();
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Please enter your email';
    return EmailValidator.validate(s) ? null : 'Please enter a valid email';
  }

  // Show snackbar method
  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameNode.dispose();
    _lastNameNode.dispose();
    _emailNode.dispose();
    _passNode.dispose();
    _confirmNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<CelebrationThemeProvider?>();
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;
    final secondaryColor = currentTheme?.secondaryColor ?? kPrimaryBlue;
    final gradientColors = currentTheme?.gradient.colors ?? [kPrimaryBlue, kAccentBlue];
    final badgeColor = currentTheme?.badgeColor ?? kRed;

    final kb = MediaQuery.of(context).viewInsets.bottom; // keyboard height

    // Fixed sheet height; we won't resize the whole sheet when keyboard shows.
    const sheetHeightFactor = 0.86;

    return Scaffold(
      backgroundColor: secondaryColor,
      resizeToAvoidBottomInset: false, // <-- prevent Scaffold from jumping
      body: Stack(
        children: [
          // 🌈 Background Gradient - LIGHTER VERSION
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gradientColors[0] ?? kLightBlue,
                  gradientColors[1] ?? kVeryLightBlue,
                  Colors.white,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // ✨ Decorative circles with glow effect - LIGHTER
          Positioned(
            top: -50, right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentColor.withOpacity(0.15),
                    accentColor.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100, left: -80,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryColor.withOpacity(0.12),
                    primaryColor.withOpacity(0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ⚪ Curved white sheet with GLASS EFFECT
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipPath(
              clipper: ImprovedCurvedClipper(),
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: MediaQuery.of(context).size.height * sheetHeightFactor,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.08),
                          blurRadius: 40,
                          offset: const Offset(0, -8),
                        )
                      ],
                    ),
                    child: Padding(
                      // constant padding; we handle keyboard with AnimatedPadding below
                      padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        padding: EdgeInsets.only(bottom: kb), // push content only by keyboard height
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: _buildForm(context, themeProvider),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 👋 Top row: back button + title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accentColor.withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: primaryColor,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),

          // Title with better styling
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 78),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      "JOIN US TODAY",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                        letterSpacing: 1.4,
                        shadows: [
                          Shadow(
                            color: accentColor.withOpacity(0.3),
                            offset: const Offset(0, 2),
                            blurRadius: 8,
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🧾 SIGN UP FORM
  // ------------------------------------------------------------------
  Widget _buildForm(BuildContext context, CelebrationThemeProvider? themeProvider) {
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 60),

              _buildEnhancedTextField(
                controller: _firstNameController,
                focusNode: _firstNameNode,
                nextFocus: _lastNameNode,
                label: "First Name",
                icon: Icons.person_rounded,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your first name' : null,
                autofillHints: const [AutofillHints.givenName],
                themeProvider: themeProvider,
              ),
              const SizedBox(height: 16),

              _buildEnhancedTextField(
                controller: _lastNameController,
                focusNode: _lastNameNode,
                nextFocus: _emailNode,
                label: "Last Name",
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your last name' : null,
                autofillHints: const [AutofillHints.familyName],
                themeProvider: themeProvider,
              ),
              const SizedBox(height: 16),

              _buildEnhancedTextField(
                controller: _emailController,
                focusNode: _emailNode,
                nextFocus: _passNode,
                label: "Email Address",
                icon: Icons.email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: _validateEmail,
                autofillHints: const [AutofillHints.email],
                themeProvider: themeProvider,
              ),
              const SizedBox(height: 16),

              _buildEnhancedTextField(
                controller: _passwordController,
                focusNode: _passNode,
                nextFocus: _confirmNode,
                label: "Password",
                icon: Icons.lock_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                suffix: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: primaryColor),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter your password';
                  if (v.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
                autofillHints: const [AutofillHints.newPassword],
                themeProvider: themeProvider,
              ),
              const SizedBox(height: 16),

              _buildEnhancedTextField(
                controller: _confirmPasswordController,
                focusNode: _confirmNode,
                label: "Confirm Password",
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _isLoading ? null : _signUp(),
                suffix: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: primaryColor),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please confirm your password';
                  if (v != _passwordController.text) return 'Passwords do not match';
                  return null;
                },
                themeProvider: themeProvider,
              ),
              const SizedBox(height: 28),

              _buildPrimaryButton(
                label: "CREATE ACCOUNT",
                onPressed: _isLoading ? null : _signUp,
                isLoading: _isLoading,
                themeProvider: themeProvider,
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "Already have an account?",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
                ],
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                ),
                child: Text(
                  "SIGN IN INSTEAD",
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🎨 ENHANCED UI COMPONENTS - GLASS STYLE
  // ------------------------------------------------------------------
  Widget _buildEnhancedTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    FocusNode? nextFocus,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    bool obscureText = false,
    Widget? suffix,
    String? Function(String?)? validator,
    Iterable<String>? autofillHints,
    required CelebrationThemeProvider? themeProvider,
  }) {
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accentColor.withOpacity(0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onFieldSubmitted: (v) {
              if (onSubmitted != null) onSubmitted(v);
              if (nextFocus != null) FocusScope.of(context).requestFocus(nextFocus);
            },
            obscureText: obscureText,
            enabled: !_isLoading,
            autofillHints: autofillHints,
            scrollPadding: const EdgeInsets.only(bottom: 120), // gentle auto-scroll into view
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1A1A),
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withOpacity(0.12),
                      accentColor.withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primaryColor, size: 20),
              ),
              suffixIcon: suffix,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: accentColor.withOpacity(0.5),
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: kRed.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              focusedErrorBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(
                  color: kRed,
                  width: 2,
                ),
              ),
            ),
            validator: validator,
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    required CelebrationThemeProvider? themeProvider,
  }) {
    final currentTheme = themeProvider?.currentTheme;
    final primaryColor = currentTheme?.primaryColor ?? kPrimaryBlue;
    final accentColor = currentTheme?.accentColor ?? kAccentBlue;

    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [primaryColor, accentColor],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: primaryColor.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🔐 SIGN UP LOGIC — auto-login + navigate away
  // ------------------------------------------------------------------
  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final pass  = _passwordController.text;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      // 1) Create the account
      final created = await userProvider.signUp(
        email: email,
        password: pass,
        firstName: _firstNameController.text.trim(),
        lastName:  _lastNameController.text.trim(),
      );

      if (!mounted) return;

      if (!created) {
        _showSnack('Failed to create account. Please try again.', kRed);
        return;
      }

      // 2) Auto-login with same credentials - FIXED LINE
      final loggedIn = await userProvider.signIn(email, pass);
      if (!mounted) return;

      if (loggedIn) {
        _showSnack('Welcome, ${_firstNameController.text.trim()}!', kGreen);

        // 3) Leave auth flow completely (choose ONE approach).
        // A) If your root listens to auth state, this is usually perfect:
        Navigator.of(context).popUntil((route) => route.isFirst);

        // B) If you have a specific home route, use this instead:
        // Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
      } else {
        _showSnack('Account created. Please sign in to continue.', kYellow);
        Navigator.of(context).pop(); // back to Sign In
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('An error occurred: $e', kRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}