import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async'; // Added for timeout functionality
import 'dart:io'; // Added for network diagnostics
import 'package:http/http.dart' as http;
import 'cart_provider.dart';
import 'woocommerce_auth_service.dart';
import 'user_provider.dart';
import 'payment_integration.dart';
import 'order_confirmation_page.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'profile_page.dart'; // or wherever your ProfilePage is located
import 'loyalty_service.dart'; // same file we used in cart

// ============================================================
// 🚨 ENHANCED PAYSTACK ERROR HANDLING - ENUMS AND EXCEPTIONS
// ============================================================

enum PaymentErrorType {
  networkError,
  networkTimeout,
  paystackError,
  userError,
  unknown,
}

class PaymentException implements Exception {
  final String message;
  final PaymentErrorType type;

  PaymentException(this.message, this.type);

  @override
  String toString() => message;
}

class CheckoutPage extends StatefulWidget {
  final List<dynamic> cartItems;
  final double subtotal;
  final double shipping;
  final double total;

  // 💰 Wallet top-up parameters
  final bool isWalletTopUp;
  final double? walletTopUpAmount;

  // ✅ NEW: Loyalty coming from the cart
  final LoyaltyDiscount? loyalty;

  const CheckoutPage({
    Key? key,
    required this.cartItems,
    required this.subtotal,
    required this.shipping,
    required this.total,
    this.isWalletTopUp = false,
    this.walletTopUpAmount,
    this.loyalty, // ✅ NEW (optional)
  }) : super(key: key);

  @override
  _CheckoutPageState createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _shipToSameAddress = true;

  // 🆕 Buy Now / normal cart helper
  List<Map<String, dynamic>> _getCartItems() {
    try {
      final routeArgs = ModalRoute.of(context)?.settings.arguments;
      if (routeArgs is Map && routeArgs['is_buy_now'] == true) {
        final buyNowItem = routeArgs['buy_now_item'];
        if (buyNowItem is Map) {
          return [Map<String, dynamic>.from(buyNowItem)];
        }
      }
    } catch (e) {
      print('Buy Now detection error: $e');
    }
    return List<Map<String, dynamic>>.from(widget.cartItems);
  }

  // 🆕 Smart subtotal for Buy Now vs normal cart
  double get _getSubtotal {
    try {
      final routeArgs = ModalRoute.of(context)?.settings.arguments;
      if (routeArgs is Map && routeArgs['is_buy_now'] == true) {
        final buyNowItem = routeArgs['buy_now_item'];
        if (buyNowItem is Map) {
          final price = (buyNowItem['price'] ?? 0.0);
          final qty = (buyNowItem['quantity'] ?? 1);
          final double p = price is num
              ? price.toDouble()
              : double.tryParse(price.toString()) ?? 0.0;
          final int q = qty is int ? qty : int.tryParse(qty.toString()) ?? 1;
          return p * q;
        }
      }
    } catch (e) {
      print('Buy Now subtotal error: $e');
    }
    return widget.subtotal;
  }

  // If you still use this anywhere, just point it to the real final total
  double get _getTotal => _calculateFinalTotal();

  // 💳 ENHANCED: Payment Method Selection
  String _selectedPaymentMethod = 'paystack'; // Default to Paystack
  Map<String, dynamic>? _walletBalance;
  bool _isLoadingWallet = false;
  String? _walletError;

  // 🚨 NEW: Enhanced Paystack Error Handling Properties
  int _paystackRetryCount = 0;
  static const int _maxRetryAttempts = 3;
  bool _showPaymentMethodAlternatives = false;
  String? _lastPaymentError;
  PaymentErrorType? _lastErrorType;

  // Billing Address Controllers
  final _billingFirstNameController = TextEditingController();
  final _billingLastNameController = TextEditingController();
  final _billingCompanyController = TextEditingController();
  final _billingAddressController = TextEditingController();
  final _billingAddress2Controller = TextEditingController();
  final _billingPostalCodeController = TextEditingController();
  final _billingPhoneController = TextEditingController();

  // Shipping Address Controllers
  final _shippingFirstNameController = TextEditingController();
  final _shippingLastNameController = TextEditingController();
  final _shippingCompanyController = TextEditingController();
  final _shippingAddressController = TextEditingController();
  final _shippingAddress2Controller = TextEditingController();
  final _shippingPostalCodeController = TextEditingController();

  // 🚚 Dynamic Plugin Data
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  List<Map<String, dynamic>> _cities = [];
  List<Map<String, dynamic>> _shippingMethods = [];
  Map<String, dynamic> _shippingData = {};

  String? _selectedBillingCountry;
  String? _selectedBillingState;
  String? _selectedBillingCity;
  String? _selectedShippingCountry;
  String? _selectedShippingState;
  String? _selectedShippingCity;
  String? _selectedShippingMethod;

  bool _isLoadingLocationData = true;
  bool _isLoadingShippingData = true;
  bool _isLoadingBillingCities = false;
  bool _isLoadingShippingCities = false;

  // ✨ NEW: Dynamic Shipping Cost Calculation
  double? _calculatedShippingCost;
  bool _isCalculatingShipping = false;
  String? _shippingCalculationError;

  // 💳 Paystack Integration
  String? _paystackReference;
  bool _paymentInitialized = false;
  bool _awaitingPaymentConfirmation = false;

  // 🔗 Payment Integration Service
  late PaymentIntegration paymentIntegration;

  // 💰 FIXED: Added authService as class field for proper organization
  late WooCommerceAuthService authService;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();

    // 💰 Initialize authService FIRST before any other operations
    authService = WooCommerceAuthService();

    _loadInitialData();
    _initializeUserData();
    _loadWalletBalance(); // 💳 ENHANCED: Load wallet balance with fallbacks

    // 🔗 Initialize PaymentIntegration service
    paymentIntegration = PaymentIntegration(wooCommerceService: authService);

    // 💰 If this is a wallet top-up, force Paystack payment method
    if (widget.isWalletTopUp) {
      _selectedPaymentMethod = 'paystack';
    }
  }

  // 💰 ENHANCED: Load Wallet Balance with Multiple Fallback Methods
  Future<void> _loadWalletBalance() async {
    try {
      _safeSetState(() {
        _isLoadingWallet = true;
        _walletError = null;
      });

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        _safeSetState(() {
          _walletError = 'User not logged in';
          _walletBalance = null;
          _isLoadingWallet = false;
        });
        return;
      }

      final userId = int.tryParse(user['id'].toString());
      print('💰 Loading wallet balance for user ID: $userId');

      // ✅ FIXED: Use the actual service method from WooCommerceAuthService
      final walletResult = await authService.getWalletBalance(userId);

      _safeSetState(() {
        if (walletResult != null && walletResult['success'] == true) {
          _walletBalance = walletResult;
          _walletError = null;
          print('✅ Wallet balance loaded successfully');
        } else {
          _walletError = walletResult?['error']?.toString() ??
              'Please sign out and sign in again to refresh your wallet session.';
          _walletBalance = null;
          print(
              '❌ Wallet balance loading failed: ${walletResult?['error'] ?? 'Unknown error'}');
        }
        _isLoadingWallet = false;
      });
    } catch (e) {
      print('❌ Exception loading wallet balance: $e');
      _safeSetState(() {
        _walletError = 'Wallet balance could not be loaded. Please try again.';
        _walletBalance = null;
        _isLoadingWallet = false;
      });
    }
  }

  // 💰 FIXED: Check if wallet has sufficient balance
  bool _hasInsufficientWalletBalance() {
    if (_walletBalance == null || _walletBalance!['success'] != true)
      return true;

    try {
      final currentBalance =
          authService.getWalletBalanceAmount(_walletBalance!);
      final finalTotal = _calculateFinalTotal();

      print(
          '💰 Wallet balance check: ₦$currentBalance vs ₦$finalTotal required');
      return currentBalance < finalTotal;
    } catch (e) {
      print('❌ Error checking wallet balance: $e');
      return true;
    }
  }

  // 🔢 NEW: How much loyalty discount to apply to this checkout
  double _getLoyaltyDiscountAmount() {
    // Loyalty never applies to wallet top-ups
    if (widget.isWalletTopUp) return 0.0;

    final LoyaltyDiscount? loyalty = widget.loyalty;
    if (loyalty == null) return 0.0;
    if (!loyalty.eligible) return 0.0;
    if (loyalty.discount <= 0) return 0.0;

    return loyalty.discount;
  }

  // 🧮 NEW: Single source of truth for final total
  double _calculateFinalTotal() {
    // 💰 Wallet top-up: ignore shipping & loyalty
    if (widget.isWalletTopUp) {
      return widget.walletTopUpAmount ?? 0.0;
    }

    final double shippingCost = _calculatedShippingCost ?? 0.0;
    final double loyaltyDiscount = _getLoyaltyDiscountAmount();

    double total = widget.subtotal + shippingCost - loyaltyDiscount;

    // Just in case, never go below zero
    if (total < 0) total = 0.0;

    return total;
  }

  // 🧩 ADD THIS MISSING FUNCTION TO FIX THE BUILD ERROR
  void _showLoadingDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(message),
            ],
          ),
          actions: [],
        );
      },
    );
  }

  // ============================================================
  // 🔄 ENHANCED: Combined Data Loading with TellMe Plugin Endpoints
  // ============================================================
  Future<void> _loadInitialData() async {
    try {
      _safeSetState(() {
        _isLoadingLocationData = true;
        _isLoadingShippingData = true;
      });

      print('📡 Loading your payment page ...');

      // 🌍 Load countries (Nigeria focused)
      _countries = [
        {'code': 'NG', 'name': 'Nigeria'}
      ];
      _selectedBillingCountry = 'NG';
      _selectedShippingCountry = 'NG';

      // 🏛️ Load Nigerian states from TellMe plugin
      print('📍 Fetching Nigerian states from TellMe plugin...');
      final pluginStates = await authService.getTellmeStates();
      if (!mounted) return;

      // 🚚 Load shipping data from custom plugin
      print('🚚 Loading custom shipping data...');
      final shippingData = await authService.getShippingZones();
      if (!mounted) return;

      _safeSetState(() {
        _states = _deduplicateStates(pluginStates);
        _shippingData = shippingData;
        _shippingMethods = List<Map<String, dynamic>>.from(
            shippingData['shipping_options'] ?? []);
        _isLoadingLocationData = false;
        _isLoadingShippingData = false;
      });

      print('✅ Initial data loaded successfully:');
      print('   Countries: ${_countries.length}');
      print('   States: ${_states.length}');
      print('   Shipping methods: ${_shippingMethods.length}');

      // 🏙️ Load default cities for Lagos if available
      if (_states.isNotEmpty) {
        final lagosState = _states.firstWhere(
          (state) =>
              state['code'] == 'LA' ||
              state['name'].toLowerCase().contains('lagos'),
          orElse: () => _states.first,
        );
        if (lagosState.isNotEmpty) {
          await _loadCitiesForState(lagosState['code'], isBilling: true);
        }
      }
    } catch (e) {
      print('❌ Error loading initial data: $e');
      if (!mounted) return;
      _setDefaultData();
    }
  }

  // ============================================================
  // 🏙️ ENHANCED: Dynamic City Loading from TellMe Plugin
  // ============================================================
  Future<void> _loadCitiesForState(String stateCode,
      {bool isBilling = false, bool isShipping = false}) async {
    try {
      if (isBilling) {
        _safeSetState(() => _isLoadingBillingCities = true);
      }
      if (isShipping) {
        _safeSetState(() => _isLoadingShippingCities = true);
      }

      print('🏙️ Fetching cities for state: $stateCode from TellMe plugin...');
      final fetchedCities = await authService.getTellmeCities(stateCode);
      if (!mounted) return;

      _safeSetState(() {
        if (isBilling || (!isBilling && !isShipping)) {
          // Update cities for billing or when called generally
          _cities = _deduplicateCities(fetchedCities);
          _selectedBillingCity = null; // Reset city selection
        }
        if (isShipping) {
          // For shipping, we might want to store separately or update the same list
          _cities = _deduplicateCities(fetchedCities);
          _selectedShippingCity = null; // Reset shipping city selection
        }
        _isLoadingBillingCities = false;
        _isLoadingShippingCities = false;
      });

      print('✅ Loaded ${fetchedCities.length} cities for state: $stateCode');
    } catch (e) {
      print('❌ Error loading cities for state $stateCode: $e');
      _safeSetState(() {
        _isLoadingBillingCities = false;
        _isLoadingShippingCities = false;
      });
    }
  }

  // ============================================================
  // ✨ NEW: Dynamic Shipping Cost Calculation
  // ============================================================
  Future<void> _calculateDynamicShippingCost() async {
    // 🔒 Wallet top-up: never calculate shipping
    if (widget.isWalletTopUp) {
      _safeSetState(() {
        _calculatedShippingCost = 0.0;
        _shippingCalculationError = null;
        _isCalculatingShipping = false;
      });
      return;
    }

    // Determine which city to use for shipping calculation
    String? targetCity =
        _shipToSameAddress ? _selectedBillingCity : _selectedShippingCity;
    String? targetState =
        _shipToSameAddress ? _selectedBillingState : _selectedShippingState;

    if (targetCity == null || targetState == null) {
      print('🚚 Cannot calculate shipping: City or state not selected');
      _safeSetState(() {
        _calculatedShippingCost = null;
        _shippingCalculationError = null;
      });
      return;
    }

    try {
      _safeSetState(() {
        _isCalculatingShipping = true;
        _shippingCalculationError = null;
      });

      print(
          '🚚 Calculating dynamic shipping cost for city: $targetCity, state: $targetState');

      // Find the selected city data
      final selectedCityData = _cities.firstWhere(
        (city) => city['code'] == targetCity,
        orElse: () => {
          'code': targetCity,
          'name': targetCity,
          'state': targetState,
          'country': 'NG',
        },
      );

      print('🎯 Selected city data: $selectedCityData');

      // Get cart provider and calculate shipping
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final shippingResult =
          await cartProvider.calculateShippingForCity(selectedCityData);
      if (!mounted) return;

      _safeSetState(() {
        if (shippingResult['success'] == true) {
          _calculatedShippingCost =
              (shippingResult['shipping_cost'] as num?)?.toDouble() ?? 0.0;
        } else {
          _calculatedShippingCost = null;
          _shippingCalculationError =
              shippingResult['error'] ?? 'Unknown shipping calculation error';
        }
        _isCalculatingShipping = false;
      });

      print('✅ Dynamic shipping cost calculated: ₦$_calculatedShippingCost');
    } catch (e) {
      print('❌ Error calculating dynamic shipping: $e');
      _safeSetState(() {
        _calculatedShippingCost = null;
        _shippingCalculationError =
            'Failed to calculate shipping cost: ${e.toString()}';
        _isCalculatingShipping = false;
      });
    }
  }

  // ============================================================
  // 🔍 ENHANCED: Data Deduplication & Filtering
  // ============================================================
  List<Map<String, dynamic>> _deduplicateStates(
      List<Map<String, dynamic>> states) {
    final seen = <String>{};
    return states.where((state) {
      final key = '${state['code']}_${state['country'] ?? 'NG'}';
      return seen.add(key);
    }).toList();
  }

  List<Map<String, dynamic>> _deduplicateCities(
      List<Map<String, dynamic>> cities) {
    final seen = <String>{};
    return cities.where((city) {
      final key = '${city['code']}_${city['state']}_${city['country'] ?? 'NG'}';
      return seen.add(key);
    }).toList();
  }

  void _setDefaultData() {
    _safeSetState(() {
      _countries = [
        {'code': 'NG', 'name': 'Nigeria'}
      ];
      _states = [
        {'code': 'LA', 'name': 'Lagos', 'country': 'NG'},
        {'code': 'AB', 'name': 'Abuja (FCT)', 'country': 'NG'},
        {'code': 'KN', 'name': 'Kano', 'country': 'NG'},
        {'code': 'RV', 'name': 'Rivers', 'country': 'NG'},
        {'code': 'OG', 'name': 'Ogun', 'country': 'NG'},
      ];
      _cities = [
        {'code': 'ikeja', 'name': 'Ikeja', 'state': 'LA', 'country': 'NG'},
        {
          'code': 'surulere',
          'name': 'Surulere',
          'state': 'LA',
          'country': 'NG'
        },
        {
          'code': 'victoria_island',
          'name': 'Victoria Island',
          'state': 'LA',
          'country': 'NG'
        },
      ];
      _shippingMethods = [
        {
          'id': '1',
          'title': 'Standard Delivery',
          'cost': '1500',
          'zone': 'Nigeria'
        },
        {
          'id': '2',
          'title': 'Express Delivery',
          'cost': '2500',
          'zone': 'Nigeria'
        },
      ];
      _selectedBillingCountry = 'NG';
      _selectedBillingState = 'LA';
      _isLoadingLocationData = false;
      _isLoadingShippingData = false;
    });
  }

  void _initializeUserData() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;

    if (user != null) {
      _billingFirstNameController.text = user['first_name'] ?? '';
      _billingLastNameController.text = user['last_name'] ?? '';

      if (user['billing'] != null) {
        final billing = user['billing'];
        _billingCompanyController.text = billing['company'] ?? '';
        _billingAddressController.text = billing['address_1'] ?? '';
        _billingAddress2Controller.text = billing['address_2'] ?? '';
        _billingPostalCodeController.text = billing['postcode'] ?? '';
        _billingPhoneController.text = billing['phone'] ?? '';
        _selectedBillingCountry = billing['country'] ?? 'NG';
        _selectedBillingState = billing['state'];
        _selectedBillingCity = billing['city'];
      }
    }
  }

  List<Map<String, dynamic>> _getStatesForCountry(String? countryCode) {
    if (countryCode == null) return [];
    return _states
        .where((state) => (state['country'] ?? 'NG') == countryCode)
        .toList();
  }

  List<Map<String, dynamic>> _getCitiesForState(String? stateCode) {
    if (stateCode == null) return [];
    return _cities.where((city) => city['state'] == stateCode).toList();
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      symbol: '₦',
      decimalDigits: 2,
      locale: 'en_NG',
    );
    return formatter.format(amount);
  }

  // ✅ NEW: Helper methods to build address data from form fields
  Map<String, dynamic> _buildBillingAddressData() {
    return {
      'firstName': _billingFirstNameController.text,
      'lastName': _billingLastNameController.text,
      'company': _billingCompanyController.text,
      'address1': _billingAddressController.text,
      'address2': _billingAddress2Controller.text,
      'city': _selectedBillingCity ?? '',
      'state': _selectedBillingState ?? '',
      'postcode': _billingPostalCodeController.text,
      'country': _selectedBillingCountry ?? 'NG',
      'phone': _billingPhoneController.text,
    };
  }

  Map<String, dynamic> _buildShippingAddressData() {
    return {
      'firstName': _shippingFirstNameController.text,
      'lastName': _shippingLastNameController.text,
      'company': _shippingCompanyController.text,
      'address1': _shippingAddressController.text,
      'address2': _shippingAddress2Controller.text,
      'city': _selectedShippingCity ?? '',
      'state': _selectedShippingState ?? '',
      'postcode': _shippingPostalCodeController.text,
      'country': _selectedShippingCountry ?? 'NG',
    };
  }

  // ============================================================
  // 🚨 ENHANCED PAYSTACK PAYMENT PROCESSING WITH ROBUST ERROR HANDLING
  // ============================================================

  /// 💳 Enhanced Paystack Payment Processing with comprehensive error handling
  Future<void> _processPaystackPayment() async {
    try {
      setState(() => _isLoading = true);

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        throw PaymentException(
            'User not logged in', PaymentErrorType.userError);
      }

      // Shipping cost (for metadata only – amount itself comes from _calculateFinalTotal)
      final double shippingCost = _calculatedShippingCost ?? 0.0;

      // 💚 Loyalty info (for metadata)
      final LoyaltyDiscount? loyalty = widget.loyalty;
      final double loyaltyDiscount = _getLoyaltyDiscountAmount();

      // 💸 This is the amount Paystack must actually charge
      final double finalTotal = _calculateFinalTotal();

      // Generate unique reference
      final reference =
          'TM_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

      print(
          '🔄 Attempting Paystack payment initialization (attempt ${_paystackRetryCount + 1}/$_maxRetryAttempts)');
      print('   Subtotal: ${widget.subtotal}');
      print('   Shipping: $shippingCost');
      print('   Loyalty discount: $loyaltyDiscount');
      print('   Final total to charge: $finalTotal');

      // Enhanced payment initialization with comprehensive error handling
      final paymentData = await _initializePaystackWithTimeout(
        authService: authService,
        email: user['email'],
        amount: finalTotal,
        reference: reference,
        metadata: {
          'customer_id': user['id'],
          'customer_name':
              '${_billingFirstNameController.text} ${_billingLastNameController.text}',
          'customer_phone': _billingPhoneController.text,
          'order_items': widget.cartItems.length,
          'app_name': 'TellMe.ng',
          'platform': 'flutter_app',
          'shipping_method': 'dynamic_calculation',
          'shipping_cost': shippingCost.toString(),
          'shipping_address':
              '${_billingAddressController.text}, ${_selectedBillingCity}, ${_selectedBillingState}',

          // 💰 Wallet top-up metadata
          'is_wallet_topup': widget.isWalletTopUp.toString(),
          'wallet_amount': widget.walletTopUpAmount?.toString() ?? '0',

          // 💚 Loyalty metadata
          'loyalty_eligible': (loyalty?.eligible ?? false).toString(),
          'loyalty_label': loyalty?.label ?? 'TellMe Loyalty',
          'loyalty_discount': loyaltyDiscount.toString(),
        },
      );

      if (paymentData['status'] == true) {
        setState(() {
          _paystackReference = reference;
          _paymentInitialized = true;
          _paystackRetryCount = 0; // Reset retry count on success
          _showPaymentMethodAlternatives = false;
          _lastPaymentError = null;
          _lastErrorType = null;
        });

        // Launch Paystack payment with enhanced user experience
        final paymentUrl = paymentData['data']['authorization_url'];
        await _launchPaymentWithTracking(paymentUrl, reference);
      } else {
        final errorMessage =
            paymentData['message'] ?? 'Unknown payment initialization error';
        throw PaymentException('Payment initialization failed: $errorMessage',
            PaymentErrorType.paystackError);
      }
    } catch (e) {
      await _handlePaymentError(e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔄 Initialize Paystack transaction with DNS optimization and timeout handling
  Future<Map<String, dynamic>> _initializePaystackWithTimeout({
    required WooCommerceAuthService authService,
    required String email,
    required double amount,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('🔄 Attempting Paystack initialization with DNS optimization...');

      // Strategy 1: Extended timeout (60s) to accommodate slow DNS
      try {
        return await authService
            .initializePaystackTransaction(
          email: email,
          amount: amount,
          reference: reference,
          metadata: metadata,
        )
            .timeout(
          Duration(seconds: 60), // Extended from 30s to 60s
          onTimeout: () {
            throw PaymentException(
                'Payment request timed out after 60 seconds. Your DNS resolution is slow.',
                PaymentErrorType.networkTimeout);
          },
        );
      } catch (e) {
        print('📡 Standard connection failed: $e');

        // Strategy 2: Try direct IP connection (bypass DNS entirely)
        if (e.toString().contains('Failed host lookup') ||
            e.toString().contains('timeout')) {
          print('🔄 Trying direct IP connection to bypass DNS...');
          return await _tryDirectIPConnection(
              email, amount, reference, metadata);
        }
        rethrow;
      }
    } catch (e) {
      // Categorize and re-throw with appropriate error type
      if (e is PaymentException) {
        rethrow;
      } else if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('api.paystack.co')) {
        throw PaymentException(
            'DNS resolution failed. Your network cannot find api.paystack.co. Try switching networks.',
            PaymentErrorType.networkError);
      } else if (e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        throw PaymentException(
            'Network connection failed. Please check your internet settings.',
            PaymentErrorType.networkError);
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('timeout')) {
        throw PaymentException(
            'Connection timed out. Your DNS is too slow. Try mobile data or different WiFi.',
            PaymentErrorType.networkTimeout);
      } else {
        throw PaymentException('Payment initialization failed: ${e.toString()}',
            PaymentErrorType.unknown);
      }
    }
  }

  /// 🎯 Try direct IP connection to bypass DNS issues
  Future<Map<String, dynamic>> _tryDirectIPConnection(
    String email,
    double amount,
    String reference,
    Map<String, dynamic>? metadata,
  ) async {
    return {
      'status': false,
      'message':
          'Payment initialization must be handled by the TellMe backend. Please try again.',
    };
  }

  /// 🚨 Comprehensive error handling with user-friendly messages and recovery options
  Future<void> _handlePaymentError(dynamic error) async {
    print('❌ Payment error: $error');

    PaymentErrorType errorType;
    String userFriendlyMessage;

    if (error is PaymentException) {
      errorType = error.type;
      userFriendlyMessage = error.message;
    } else {
      // Fallback error categorization
      final errorString = error.toString().toLowerCase();

      if (errorString.contains('failed host lookup') ||
          errorString.contains('network') ||
          errorString.contains('socket')) {
        errorType = PaymentErrorType.networkError;
        userFriendlyMessage =
            'Cannot connect to payment server. Please check your internet connection.';
      } else if (errorString.contains('timeout')) {
        errorType = PaymentErrorType.networkTimeout;
        userFriendlyMessage = 'Payment request timed out. Please try again.';
      } else if (errorString.contains('user not logged in')) {
        errorType = PaymentErrorType.userError;
        userFriendlyMessage = 'Please log in to continue with payment.';
      } else {
        errorType = PaymentErrorType.unknown;
        userFriendlyMessage = 'Payment failed: ${error.toString()}';
      }
    }

    setState(() {
      _lastPaymentError = userFriendlyMessage;
      _lastErrorType = errorType;
      _paystackRetryCount++;
    });

    // Show enhanced error dialog with recovery options
    await _showEnhancedPaymentErrorDialog(
      errorType: errorType,
      message: userFriendlyMessage,
      canRetry: _paystackRetryCount < _maxRetryAttempts,
    );
  }

  /// 📱 Enhanced payment error dialog with multiple recovery options
  Future<void> _showEnhancedPaymentErrorDialog({
    required PaymentErrorType errorType,
    required String message,
    required bool canRetry,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                _getErrorIcon(errorType),
                color: _getErrorColor(errorType),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _getErrorTitle(errorType),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _getErrorColor(errorType),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),

              // Show specific troubleshooting tips based on error type
              _buildTroubleshootingTips(errorType),

              if (_paystackRetryCount >= _maxRetryAttempts) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Alternative Payment Option',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You can use Bank Transfer to complete your order. You\'ll receive bank details after placing the order.',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            // Cancel button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _showPaymentMethodAlternatives =
                      _paystackRetryCount >= _maxRetryAttempts;
                });
              },
              child: const Text('Cancel'),
            ),

            // Retry button (if retries available)
            if (canRetry) ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _processPaystackPayment(); // Retry the payment
                },
                icon: const Icon(Icons.refresh),
                label: Text(
                    'Try Again (${_maxRetryAttempts - _paystackRetryCount} left)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),

              // Network diagnostics button for network errors
              if (errorType == PaymentErrorType.networkError) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _runNetworkDiagnostics();
                  },
                  icon: const Icon(Icons.network_check),
                  label: const Text('Test Network'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                ),
              ],
            ],

            // Switch to Bank Transfer button (if max retries reached)
            if (!canRetry) ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _selectedPaymentMethod = 'bank_transfer';
                    _showPaymentMethodAlternatives = true;
                  });
                  _showBankTransferConfirmationDialog();
                },
                icon: const Icon(Icons.account_balance),
                label: const Text('Use Bank Transfer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 🔧 Build troubleshooting tips based on error type
  Widget _buildTroubleshootingTips(PaymentErrorType errorType) {
    switch (errorType) {
      case PaymentErrorType.networkError:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Network Troubleshooting',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('• Check your internet connection',
                  style: TextStyle(color: Colors.blue.shade700)),
              Text('• Try switching between WiFi and mobile data',
                  style: TextStyle(color: Colors.blue.shade700)),
              Text('• Restart your internet connection',
                  style: TextStyle(color: Colors.blue.shade700)),
              Text('• Move to an area with better signal strength',
                  style: TextStyle(color: Colors.blue.shade700)),
            ],
          ),
        );

      case PaymentErrorType.networkTimeout:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_off, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Connection Timeout',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('• Your connection may be slow',
                  style: TextStyle(color: Colors.amber.shade700)),
              Text('• Try again with a stronger internet connection',
                  style: TextStyle(color: Colors.amber.shade700)),
              Text('• Wait a moment before retrying',
                  style: TextStyle(color: Colors.amber.shade700)),
            ],
          ),
        );

      case PaymentErrorType.paystackError:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.payment, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Payment Service Issue',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('• The payment service may be temporarily unavailable',
                  style: TextStyle(color: Colors.red.shade700)),
              Text('• Try again in a few minutes',
                  style: TextStyle(color: Colors.red.shade700)),
              Text('• Use Bank Transfer as an alternative',
                  style: TextStyle(color: Colors.red.shade700)),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /// 📱 Bank Transfer confirmation dialog
  Future<void> _showBankTransferConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.account_balance, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Switch to Bank Transfer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You\'ve chosen to pay via Bank Transfer.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How it works:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('1. Complete your order',
                        style: TextStyle(color: Colors.green.shade700)),
                    Text('2. You\'ll receive bank account details',
                        style: TextStyle(color: Colors.green.shade700)),
                    Text('3. Transfer the total amount to the provided account',
                        style: TextStyle(color: Colors.green.shade700)),
                    Text(
                        '4. Your order will be processed after payment confirmation',
                        style: TextStyle(color: Colors.green.shade700)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _selectedPaymentMethod =
                      'paystack'; // Switch back to Paystack
                  _showPaymentMethodAlternatives = false;
                });
              },
              child: const Text('Back to Paystack'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _processPayment(); // Process the order with bank transfer
              },
              icon: const Icon(Icons.check),
              label: const Text('Continue with Bank Transfer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 🎨 Helper methods for error dialog styling
  IconData _getErrorIcon(PaymentErrorType errorType) {
    switch (errorType) {
      case PaymentErrorType.networkError:
        return Icons.wifi_off;
      case PaymentErrorType.networkTimeout:
        return Icons.timer_off;
      case PaymentErrorType.paystackError:
        return Icons.payment;
      case PaymentErrorType.userError:
        return Icons.person_off;
      default:
        return Icons.error_outline;
    }
  }

  Color _getErrorColor(PaymentErrorType errorType) {
    switch (errorType) {
      case PaymentErrorType.networkError:
        return Colors.blue;
      case PaymentErrorType.networkTimeout:
        return Colors.amber.shade700;
      case PaymentErrorType.paystackError:
        return Colors.red;
      case PaymentErrorType.userError:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getErrorTitle(PaymentErrorType errorType) {
    switch (errorType) {
      case PaymentErrorType.networkError:
        return 'Connection Problem';
      case PaymentErrorType.networkTimeout:
        return 'Request Timeout';
      case PaymentErrorType.paystackError:
        return 'Payment Service Error';
      case PaymentErrorType.userError:
        return 'User Error';
      default:
        return 'Payment Error';
    }
  }

  // ============================================================
  // 💳 ENHANCED: Multi-Payment Method Processing
  // ============================================================
  Future<void> _processPayment() async {
    // 💰 SPECIAL HANDLING FOR WALLET TOP-UP - FIXED DETECTION
    final isWalletTopUp =
        widget.isWalletTopUp == true && widget.walletTopUpAmount != null;

    if (isWalletTopUp) {
      await _processWalletTopUpPayment();
      return;
    }

    if (!_formKey.currentState!.validate()) {
      _showErrorDialog(
          'Form Error', 'Please fill in all required fields correctly.');
      return;
    }

    // If Paystack has failed multiple times, guide user to Bank Transfer
    if (_selectedPaymentMethod == 'paystack' &&
        _paystackRetryCount >= _maxRetryAttempts) {
      _showBankTransferSuggestionDialog();
      return;
    }

    switch (_selectedPaymentMethod) {
      case 'wallet':
        await _processWalletPayment();
        break;
      case 'paystack':
        await _processPaystackPayment();
        break;
      case 'bank_transfer':
        await _processBankTransferOrder();
        break;
      default:
        _showErrorDialog(
            'Payment Error', 'Please select a valid payment method.');
    }
  }

  // 💰 NEW: Dedicated Wallet Top-Up Payment Processing
  Future<void> _processWalletTopUpPayment() async {
    try {
      setState(() => _isLoading = true);

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      _showProgressDialog(
          'Processing Top-Up', 'Setting up your wallet top-up...');

      // ✅ DIRECT PAYSTACK PAYMENT FOR WALLET TOP-UP (no order creation)
      final reference =
          'TM_WALLET_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

      print('💰 Processing wallet top-up: ₦${widget.walletTopUpAmount}');

      final paymentData = await _initializePaystackWithTimeout(
        authService: authService,
        email: user['email'],
        amount: widget.walletTopUpAmount!,
        reference: reference,
        metadata: {
          'customer_id': user['id'],
          'customer_name': '${user['first_name']} ${user['last_name']}',
          'app_name': 'TellMe.ng',
          'platform': 'flutter_app',
          'is_wallet_topup': 'true',
          'wallet_amount': widget.walletTopUpAmount!.toString(),
          'transaction_type': 'wallet_topup',
        },
      );

      if (paymentData['status'] == true) {
        // 👇👇 IMPORTANT: close the "Processing Top-Up" dialog BEFORE WebView
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        setState(() {
          _paystackReference = reference;
          _paymentInitialized = true;
        });

        // Launch Paystack payment
        final paymentUrl = paymentData['data']['authorization_url'];
        await _launchWalletTopUpPayment(paymentUrl, reference);
      } else {
        // Also ensure dialog is closed on failure
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        throw Exception(
            paymentData['message'] ?? 'Top-up initialization failed');
      }
    } catch (e) {
      // ✅ FIX: Ensure dialog is dismissed on error
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      print('❌ Wallet top-up error: $e');
      _showErrorDialog('Top-Up Error', e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 💰 NEW: Dedicated Wallet Top-Up Payment Launch
  Future<void> _launchWalletTopUpPayment(
      String paymentUrl, String reference) async {
    print('🚀 Launching Paystack WebView for wallet top-up: $reference');

    setState(() {
      _awaitingPaymentConfirmation = true;
    });

    await _showWalletTopUpWebView(paymentUrl, reference);
  }

  // 💰 NEW: Dedicated Wallet Top-Up WebView
  Future<void> _showWalletTopUpWebView(
      String paymentUrl, String reference) async {
    if (!mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PaystackWebViewDialog(
          paymentUrl: paymentUrl,
          reference: reference,
          onPaymentComplete:
              (bool success, String? transactionReference) async {
            Navigator.of(context).pop(); // Close WebView dialog

            if (success && transactionReference != null) {
              print('✅ Wallet top-up payment completed: $transactionReference');
              setState(() {
                _paystackReference = transactionReference;
              });

              // Automatically verify payment and credit wallet
              await _verifyWalletTopUpPayment();
            } else {
              print('❌ Wallet top-up payment failed or was cancelled');
              setState(() {
                _paymentInitialized = false;
                _paystackReference = null;
                _awaitingPaymentConfirmation = false;
              });

              _showErrorDialog('Top-Up Failed',
                  'Payment was not completed. Please try again.');
            }
          },
          onCancel: () {
            Navigator.of(context).pop(); // Close WebView dialog
            setState(() {
              _paymentInitialized = false;
              _paystackReference = null;
              _awaitingPaymentConfirmation = false;
            });
          },
        );
      },
    );
  }

  // 💰 FIXED: Wallet Top-Up Verification - NO MORE PERPETUAL LOADING
  Future<void> _verifyWalletTopUpPayment() async {
    if (_paystackReference == null) return;

    try {
      setState(() {
        _isLoading = true;
        _awaitingPaymentConfirmation = false;
      });

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      // Show verification progress
      _showProgressDialog(
          'Verifying Payment', 'Please wait while we confirm your top-up...');

      // ✅ STEP 1: Verify payment with Paystack
      final verification =
          await authService.verifyPaystackTransaction(_paystackReference!);
      print('🔍 Verification response: ${verification['data']['status']}');

      if (verification['data']['status'] != 'success') {
        Navigator.of(context, rootNavigator: true)
            .pop(); // Close progress dialog
        throw Exception(
            'Payment verification failed. Please contact support if amount was debited.');
      }

      // Update progress
      Navigator.of(context, rootNavigator: true)
          .pop(); // Close verification dialog
      _showProgressDialog('Crediting Wallet',
          'Payment confirmed! Adding funds to your wallet...');

      // ✅ STEP 2: Credit the wallet directly
      final creditResult = await authService.creditWallet(
        int.tryParse(user['id'].toString()),
        widget.walletTopUpAmount!,
        'Wallet top-up via Paystack - Reference: $_paystackReference',
      );

      print('💳 Credit wallet response: ${creditResult['success']}');

      // ✅ STEP 3: Close ALL dialogs BEFORE navigation
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop(); // Close credit dialog
      }

      // ✅ STEP 4: Add delay to ensure clean state transition
      await Future.delayed(Duration(milliseconds: 500));

      if (creditResult['success'] == true) {
        print('💰 Wallet credited successfully!');

        // ✅ STEP 5: SUCCESS - Clear states and navigate
        if (mounted) {
          setState(() {
            _isLoading = false;
            _paystackReference = null;
            _paymentInitialized = false;
            _awaitingPaymentConfirmation = false;
          });

          // ✅ FIXED: Use simpler navigation approach
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => ProfilePage()),
            (route) => false,
          );

          // ✅ FIXED: Show success message with proper timing
          await Future.delayed(Duration(milliseconds: 300));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '💰 Wallet topped up successfully! ₦${widget.walletTopUpAmount} added'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        throw Exception(
            'Wallet credit failed: ${creditResult['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('❌ Wallet top-up verification error: $e');

      // ✅ FIXED: ERROR - Clean up but DON'T navigate away
      if (mounted) {
        // Close any progress dialogs
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        setState(() {
          _isLoading = false;
          _paystackReference = null;
          _paymentInitialized = false;
          _awaitingPaymentConfirmation = false;
        });

        // Show error message but stay on current page
        _showErrorDialog('Top-Up Issue',
            'Payment was successful but we encountered an issue: ${e.toString()}\n\nYour funds are safe. Please contact support if this persists.');
      }
    } finally {
      // ✅ FIXED: FINALLY - Only update state if still mounted
      if (mounted) {
        setState(() {
          _isLoading = false;
          _awaitingPaymentConfirmation = false;
        });
      }
    }
  }

  /// 📱 Show suggestion dialog when Paystack fails repeatedly
  Future<void> _showBankTransferSuggestionDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Payment Method Suggestion',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paystack payment has failed multiple times. This is usually due to network connectivity issues.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended: Use Bank Transfer',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bank Transfer is reliable and doesn\'t depend on network connectivity for payment processing.',
                      style: TextStyle(color: Colors.green.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Reset and try Paystack again
                setState(() {
                  _paystackRetryCount = 0;
                  _lastPaymentError = null;
                  _lastErrorType = null;
                });
                _processPaystackPayment();
              },
              child: const Text('Try Paystack Again'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _selectedPaymentMethod = 'bank_transfer';
                });
                _processPayment();
              },
              icon: const Icon(Icons.account_balance),
              label: const Text('Use Bank Transfer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  // 💰 FIXED: Wallet Payment Processing with guaranteed navigation
  Future<void> _processWalletPayment() async {
    try {
      setState(() => _isLoading = true);

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      // Check wallet balance again
      if (_hasInsufficientWalletBalance()) {
        throw Exception('Insufficient wallet balance for this purchase');
      }

      _showProgressDialog(
          'Processing Wallet Payment', 'Deducting amount from your wallet...');

      // ✅ NEW: Pass real customer data to PaymentIntegration
      final result = await paymentIntegration.processPayment(
        paymentMethod: 'wallet',
        cartItems: widget.cartItems,
        totalAmount: _calculateFinalTotal(),
        context: context,
        customerData: {
          'id': user['id'],
          'email': user['email'],
        },
        billingAddress: _buildBillingAddressData(),
        shippingAddress:
            _shipToSameAddress ? null : _buildShippingAddressData(),
      );

      // ✅ FIX: Use rootNavigator to ensure dialog dismissal
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // ✅ ENHANCED: Check for explicit order creation flags
      if (result != null &&
          result['success'] == true &&
          (result['order_created'] == true || result['orderData'] != null)) {
        print('💰 Wallet payment successful, refreshing balance...');
        await _loadWalletBalance();
        print('💰 Wallet balance refreshed!');

        // Clear cart
        final cartProvider = Provider.of<CartProvider>(context, listen: false);
        cartProvider.clearCart();

        // ✅ FIX: Use pushAndRemoveUntil to completely clear navigation stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => OrderConfirmationPage(
              orderDetails: result['orderData'] ?? result,
            ),
          ),
          (route) => false, // Remove all previous routes
        );

        return; // Exit early to avoid finally block
      } else {
        throw Exception(result?['message'] ?? 'Wallet payment failed');
      }
    } catch (e) {
      // ✅ FIX: Use rootNavigator for error dismissal too
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      print('❌ Wallet payment error: $e');
      _showErrorDialog('Wallet Payment Error', e.toString());
    } finally {
      // Only update state if we haven't navigated away
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🏦 FIXED: Bank Transfer Processing with guaranteed navigation
  Future<void> _processBankTransferOrder() async {
    try {
      setState(() => _isLoading = true);

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      _showProgressDialog(
          'Creating Order', 'Setting up your bank transfer order...');

      // ✅ NEW: Pass real customer data to PaymentIntegration
      final result = await paymentIntegration.processPayment(
        paymentMethod: 'bank_transfer',
        cartItems: widget.cartItems,
        totalAmount: _calculateFinalTotal(),
        context: context,
        customerData: {
          'id': user['id'],
          'email': user['email'],
        },
        billingAddress: _buildBillingAddressData(),
        shippingAddress:
            _shipToSameAddress ? null : _buildShippingAddressData(),
      );

      // ✅ FIX: Use rootNavigator to ensure dialog dismissal
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // ✅ ENHANCED: Check for explicit order creation flags
      if (result != null &&
          result['success'] == true &&
          (result['order_created'] == true || result['orderData'] != null)) {
        print(
            '✅ Bank transfer order created successfully, navigating to confirmation...');

        // Clear cart
        final cartProvider = Provider.of<CartProvider>(context, listen: false);
        cartProvider.clearCart();

        // ✅ FIX: Use pushAndRemoveUntil to completely clear navigation stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => OrderConfirmationPage(
              orderDetails: result['orderData'] ?? result,
            ),
          ),
          (route) => false, // Remove all previous routes
        );

        return; // Exit early to avoid finally block
      } else {
        throw Exception(result?['message'] ?? 'Bank transfer order failed');
      }
    } catch (e) {
      // ✅ FIX: Use rootNavigator for error dismissal too
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      print('❌ Bank Transfer order error: $e');
      _showErrorDialog('Order Error', e.toString());
    } finally {
      // Only update state if we haven't navigated away
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getPaymentMethodTitle() {
    switch (_selectedPaymentMethod) {
      case 'wallet':
        return 'TellMe Wallet';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'paystack':
        return 'Paystack';
      default:
        return 'Paystack';
    }
  }

  Future<void> _launchPaymentWithTracking(String url, String reference) async {
    print('🚀 Launching Paystack WebView for payment: $reference');

    setState(() {
      _awaitingPaymentConfirmation = true;
    });

    // Open payment in WebView instead of external browser
    await _showPaystackWebView(url, reference);
  }

  // ✅ ADD THE _showPaystackWebView METHOD RIGHT HERE:
  Future<void> _showPaystackWebView(String paymentUrl, String reference) async {
    if (!mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PaystackWebViewDialog(
          paymentUrl: paymentUrl,
          reference: reference,
          onPaymentComplete:
              (bool success, String? transactionReference) async {
            Navigator.of(context).pop(); // Close WebView dialog

            if (success && transactionReference != null) {
              print('✅ Payment completed successfully: $transactionReference');
              setState(() {
                _paystackReference = transactionReference;
              });

              // Automatically verify payment and create order
              await _verifyPaymentAndCreateOrder();
            } else {
              print('❌ Payment failed or was cancelled');
              setState(() {
                _paymentInitialized = false;
                _paystackReference = null;
                _awaitingPaymentConfirmation = false;
              });

              _showErrorDialog('Payment Failed',
                  'Payment was not completed. Please try again.');
            }
          },
          onCancel: () {
            Navigator.of(context).pop(); // Close WebView dialog
            setState(() {
              _paymentInitialized = false;
              _paystackReference = null;
              _awaitingPaymentConfirmation = false;
            });
          },
        );
      },
    );
  }

  // ============================================================
  // 💳 UPDATED: Paystack verification and order creation (Safe + Stable)
  // ============================================================
  Future<void> _verifyPaymentAndCreateOrder() async {
    if (_paystackReference == null) return;

    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _awaitingPaymentConfirmation = false;
        });
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) throw Exception('User not logged in');

      _showProgressDialog(
        'Verifying Payment',
        'Please wait while we confirm your payment...',
      );

      // 🔍 Verify payment with Paystack
      final verification =
          await authService.verifyPaystackTransaction(_paystackReference!);

      if (verification['data']['status'] != 'success') {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        throw Exception(
            'Payment verification failed. Please contact support if amount was debited.');
      }

      // ✅ Close verification dialog before continuing
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // 💰 Wallet Top-Up flow (NO order creation)
      if (widget.isWalletTopUp && widget.walletTopUpAmount != null) {
        _showProgressDialog(
          'Crediting Wallet',
          'Payment confirmed! Adding funds to your wallet...',
        );

        final creditResult = await authService.creditWallet(
          int.tryParse(user['id'].toString()),
          widget.walletTopUpAmount!,
          'Wallet top-up via Paystack - Reference: $_paystackReference',
        );

        // ✅ Ensure all dialogs are closed before navigation
        while (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        if (creditResult != null && creditResult['success'] == true) {
          print('💰 Wallet credited successfully!');

          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => ProfilePage()),
            (route) => false,
          );

          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('💰 Wallet topped up successfully!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          });
        } else {
          throw Exception(
              'Wallet credit failed: ${creditResult?['error'] ?? 'Unknown error'}');
        }

        return; // 🚫 stop here (don't continue to order flow)
      }

      // 🛒 Regular order creation flow
      _showProgressDialog(
        'Creating Order',
        'Payment confirmed! Creating your order...',
      );

      final result = await paymentIntegration.processPayment(
        paymentMethod: 'card',
        cartItems: widget.cartItems,
        totalAmount: _calculateFinalTotal(),
        context: context,
        paymentReference: _paystackReference,
        customerData: {
          'id': user['id'],
          'email': user['email'],
        },
        billingAddress: _buildBillingAddressData(),
        shippingAddress:
            _shipToSameAddress ? null : _buildShippingAddressData(),
      );

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (result != null &&
          result['success'] == true &&
          result['orderData'] != null) {
        print(
            '✅ Order confirmation triggered for order: ${result['orderData']['id']}');

        final cartProvider = Provider.of<CartProvider>(context, listen: false);
        cartProvider.clearCart();

        if (!mounted) return;

        // ✅ Navigate to confirmation page and stop async work
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => OrderConfirmationPage(
              orderDetails: result['orderData'],
            ),
          ),
          (route) => false,
        );
        return;
      } else {
        throw Exception(result?['message'] ?? 'Order creation failed');
      }
    } catch (e) {
      print('❌ Payment verification error: $e');

      while (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment verification failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      if (widget.isWalletTopUp && mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => ProfilePage()),
          (route) => false,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 🧩 Simple reusable dialogs (progress + error)
  // ============================================================

  void _showProgressDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.orange),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// 🔧 Run comprehensive network diagnostics for Paystack connectivity
  Future<void> _runNetworkDiagnostics() async {
    _showLoadingDialog(
        'Network Diagnostics', 'Testing connection to Paystack...');

    try {
      final diagnostics = await _performNetworkTests();
      Navigator.of(context).pop(); // Close loading dialog
      _showNetworkDiagnosticsResults(diagnostics);
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _showErrorDialog('Diagnostics Failed', 'Unable to run network tests: $e');
    }
  }

  /// 🔍 Perform actual network connectivity tests
  Future<Map<String, dynamic>> _performNetworkTests() async {
    final results = <String, dynamic>{};

    // Test 1: Basic internet connectivity
    try {
      final response = await http
          .get(
            Uri.parse('https://www.google.com'),
          )
          .timeout(Duration(seconds: 10));
      results['internet'] = {
        'status': 'success',
        'message': 'Internet connection is working',
        'details': 'Status code: ${response.statusCode}'
      };
    } catch (e) {
      results['internet'] = {
        'status': 'failed',
        'message': 'No internet connection',
        'details': e.toString()
      };
    }

    // Test 2: DNS resolution for both Paystack domains
    try {
      final apiAddresses = await InternetAddress.lookup('api.paystack.co');
      results['api_dns'] = {
        'status': 'success',
        'message': 'API DNS resolution successful',
        'details':
            'api.paystack.co → ${apiAddresses.map((a) => a.address).join(', ')}'
      };
    } catch (e) {
      results['api_dns'] = {
        'status': 'failed',
        'message': 'Cannot resolve api.paystack.co',
        'details': e.toString()
      };
    }

    try {
      final checkoutAddresses =
          await InternetAddress.lookup('checkout.paystack.com');
      results['checkout_dns'] = {
        'status': 'success',
        'message': 'Checkout DNS resolution successful',
        'details':
            'checkout.paystack.com → ${checkoutAddresses.map((a) => a.address).join(', ')}'
      };
    } catch (e) {
      results['checkout_dns'] = {
        'status': 'failed',
        'message': 'Cannot resolve checkout.paystack.com',
        'details': e.toString()
      };
    }

    // Test 3: Paystack API accessibility (the problematic one)
    try {
      final response = await http.get(
        Uri.parse('https://api.paystack.co/transaction/initialize'),
        headers: {
          'Authorization': 'Bearer pk_test_dummy',
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 15));

      results['paystack_api'] = {
        'status': 'success',
        'message': 'Paystack API is reachable',
        'details': 'Status code: ${response.statusCode}'
      };
    } catch (e) {
      results['paystack_api'] = {
        'status': 'failed',
        'message': 'Cannot reach Paystack API',
        'details': e.toString()
      };
    }

    // Test 4: Paystack Checkout accessibility (should work based on user's observation)
    try {
      final response = await http.get(
        Uri.parse('https://checkout.paystack.com'),
        headers: {
          'User-Agent': 'TellMe-Flutter-App/1.0',
        },
      ).timeout(Duration(seconds: 15));

      results['paystack_checkout'] = {
        'status': 'success',
        'message': 'Paystack Checkout is reachable',
        'details': 'Status code: ${response.statusCode}'
      };
    } catch (e) {
      results['paystack_checkout'] = {
        'status': 'failed',
        'message': 'Cannot reach Paystack Checkout',
        'details': e.toString()
      };
    }

    return results;
  }

  /// 📊 Show network diagnostics results to user
  void _showNetworkDiagnosticsResults(Map<String, dynamic> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.network_check, color: Colors.blue),
            const SizedBox(width: 12),
            const Text('Network Diagnostics'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDiagnosticItem(
                  'Internet Connection',
                  results['internet'],
                  Icons.wifi,
                ),
                const SizedBox(height: 12),
                _buildDiagnosticItem(
                  'API DNS (api.paystack.co)',
                  results['api_dns'],
                  Icons.dns,
                ),
                const SizedBox(height: 12),
                _buildDiagnosticItem(
                  'Checkout DNS (checkout.paystack.com)',
                  results['checkout_dns'],
                  Icons.dns,
                ),
                const SizedBox(height: 12),
                _buildDiagnosticItem(
                  'Paystack API Server',
                  results['paystack_api'],
                  Icons.api,
                ),
                const SizedBox(height: 12),
                _buildDiagnosticItem(
                  'Paystack Checkout Server',
                  results['paystack_checkout'],
                  Icons.payment,
                ),
                const SizedBox(height: 16),
                _buildDiagnosticSuggestions(results),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (_shouldShowRetryOption(results))
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processPaystackPayment();
              },
              child: const Text('Try Payment Again'),
            ),
        ],
      ),
    );
  }

  /// 🔧 Build individual diagnostic test result
  Widget _buildDiagnosticItem(
      String title, Map<String, dynamic> result, IconData icon) {
    final isSuccess = result['status'] == 'success';
    final color = isSuccess ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Spacer(),
              Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                color: color,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            result['message'],
            style: TextStyle(color: Colors.grey[700]),
          ),
          if (result['details'] != null) ...[
            const SizedBox(height: 4),
            Text(
              result['details'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 💡 Build diagnostic suggestions based on test results
  Widget _buildDiagnosticSuggestions(Map<String, dynamic> results) {
    final suggestions = <String>[];

    if (results['internet']['status'] == 'failed') {
      suggestions.add('Check your internet connection');
      suggestions.add('Try switching between WiFi and mobile data');
      return _buildSuggestionWidget('Internet Issues', suggestions, Colors.red);
    }

    // Check for DNS timeout pattern (based on user's PowerShell results)
    final apiDNS = results['api_dns']['status'] == 'success';
    final checkoutDNS = results['checkout_dns']['status'] == 'success';
    final apiReachable = results['paystack_api']['status'] == 'success';
    final checkoutReachable =
        results['paystack_checkout']['status'] == 'success';

    // Pattern: DNS works but HTTP fails (timeout issues)
    if (apiDNS && checkoutDNS && !apiReachable) {
      suggestions.add('✨ DNS Timeout Issue Detected!');
      suggestions.add('✅ DNS can resolve domains (like your PowerShell test)');
      suggestions.add('❌ But HTTP connections timeout due to slow DNS');
      suggestions.add('');
      suggestions.add('Your diagnostic results show:');
      suggestions.add('• DNS timeouts: "timeout was 2 seconds"');
      suggestions.add('• Mobile hotspot DNS: 192.168.43.1 (unreliable)');
      suggestions.add('• Eventually resolves but too slow for app');
      suggestions.add('');
      suggestions.add('Solutions:');
      suggestions.add('• Switch to mobile data (bypass WiFi/hotspot)');
      suggestions.add('• Change DNS to 8.8.8.8 or 1.1.1.1');
      suggestions.add('• Move closer to WiFi source');
      suggestions.add('• Try different network entirely');
      suggestions.add('• App will now try direct IP connection automatically');
      return _buildSuggestionWidget(
          'DNS Timeout Issue', suggestions, Colors.orange);
    }

    // Check for selective domain blocking
    if (!apiReachable && checkoutReachable) {
      suggestions.add('✨ Selective blocking detected!');
      suggestions.add('✅ checkout.paystack.com is accessible');
      suggestions.add('❌ api.paystack.co is blocked');
      suggestions.add('');
      suggestions.add('Possible causes:');
      suggestions.add('• Corporate firewall blocking API endpoints');
      suggestions.add('• Mobile carrier restricting API access');
      suggestions.add('• DNS filtering service blocking APIs');
      suggestions.add('');
      suggestions.add('Solutions to try:');
      suggestions.add('• Switch to mobile data (if on WiFi)');
      suggestions.add('• Use VPN to bypass restrictions');
      suggestions.add('• Change DNS to 8.8.8.8 or 1.1.1.1');
      suggestions.add('• Use Bank Transfer as alternative');
      return _buildSuggestionWidget(
          'Selective API Blocking', suggestions, Colors.orange);
    }

    if (!apiDNS && !checkoutDNS) {
      suggestions.add('DNS cannot resolve Paystack domains');
      suggestions.add('Try changing DNS to 8.8.8.8 or 1.1.1.1');
      suggestions.add('Restart your router/modem');
      suggestions.add('Contact your ISP about DNS issues');
      return _buildSuggestionWidget(
          'DNS Resolution Failed', suggestions, Colors.red);
    }

    if (!apiReachable && !checkoutReachable) {
      suggestions.add('Cannot reach any Paystack servers');
      suggestions.add('Paystack may be temporarily unavailable');
      suggestions.add('Try again in a few minutes');
      suggestions.add('Use Bank Transfer as alternative');
      return _buildSuggestionWidget(
          'Paystack Unavailable', suggestions, Colors.amber);
    }

    if (apiReachable && checkoutReachable) {
      suggestions.add('All Paystack services are accessible!');
      suggestions.add('The payment should work now.');
      suggestions.add('Try the payment again.');
      return _buildSuggestionWidget(
          'All Systems Operational', suggestions, Colors.green);
    }

    // Fallback
    suggestions.add('Mixed connectivity results detected');
    suggestions.add('Try payment again or use Bank Transfer');
    return _buildSuggestionWidget('Mixed Results', suggestions, Colors.grey);
  }

  /// 🎨 Build styled suggestion widget
  Widget _buildSuggestionWidget(
      String title, List<String> suggestions, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...suggestions
              .map((suggestion) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      suggestion.startsWith('•') ? suggestion : '• $suggestion',
                      style: TextStyle(color: color),
                    ),
                  ))
              .toList(),
        ],
      ),
    );
  }

  /// 🔄 Check if retry option should be shown based on diagnostics
  bool _shouldShowRetryOption(Map<String, dynamic> results) {
    return results['internet']['status'] == 'success' &&
        results['paystack_api']['status'] == 'success';
  }

  @override
  Widget build(BuildContext context) {
    final primaryBlue = const Color(0xFF1565C0); // Deep blue
    final skyBlue = const Color(0xFF42A5F5); // Sky blue
    final accentGreen = const Color(0xFF2E7D32); // Secure green

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.isWalletTopUp ? '💰 Wallet Top-Up' : 'Secure Checkout'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.isWalletTopUp
                  ? [
                      Color(0xFF10B981),
                      Color(0xFF059669)
                    ] // Green gradient for wallet top-up
                  : [primaryBlue, skyBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
      ),
      body: (_isLoadingLocationData || _isLoadingShippingData)
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: skyBlue),
                  const SizedBox(height: 16),
                  const Text(
                    'Loading checkout data from TellMe plugin...',
                    style: TextStyle(fontSize: 14),
                  ),
                  if (_awaitingPaymentConfirmation) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Payment in progress...',
                      style: TextStyle(
                        color: skyBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 💰 Wallet Top-Up Header
                    if (widget.isWalletTopUp) ...[
                      _buildWalletTopUpHeader(),
                      const SizedBox(height: 24),
                    ],

                    // 🔒 Security Badge
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accentGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accentGreen.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user,
                              color: accentGreen, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.isWalletTopUp
                                  ? '💰 Secure wallet top-up via Paystack'
                                  : '🔒 Secure checkout powered by Paystack',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Order Summary
                    _buildOrderSummary(),
                    const SizedBox(height: 24),

                    // ✨ Dynamic Shipping Cost Display (skip for wallet top-up)
                    if (!widget.isWalletTopUp) ...[
                      _buildDynamicShippingSection(),
                      const SizedBox(height: 24),
                    ],

                    // Billing Address (skip for wallet top-up)
                    if (!widget.isWalletTopUp) ...[
                      _buildSectionTitle('Billing Address'),
                      _buildBillingAddressForm(),
                      const SizedBox(height: 24),
                    ],

                    // Ship to same address checkbox (skip for wallet top-up)
                    if (!widget.isWalletTopUp) ...[
                      CheckboxListTile(
                        title: const Text('Ship to same address'),
                        value: _shipToSameAddress,
                        onChanged: (value) {
                          setState(() {
                            _shipToSameAddress = value ?? true;
                          });
                          _calculateDynamicShippingCost();
                        },
                        activeColor: primaryBlue,
                        checkColor: Colors.white,
                      ),

                      // Shipping Address (if different)
                      if (!_shipToSameAddress) ...[
                        const SizedBox(height: 16),
                        _buildSectionTitle('Shipping Address'),
                        _buildShippingAddressForm(),
                        const SizedBox(height: 24),
                      ],
                    ],

                    // Final Order Summary
                    _buildFinalOrderSummary(),
                    const SizedBox(height: 24),

                    // 💳 Enhanced Payment Method Selection
                    _buildPaymentMethodSection(),
                    const SizedBox(height: 24),

                    // 💳 Blue-themed Complete Order Button
                    _buildEnhancedCompleteOrderButton(),
                    const SizedBox(height: 16),

                    // ✨ Payment button status indicator (skip for wallet top-up)
                    if (!widget.isWalletTopUp &&
                        _calculatedShippingCost == null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: skyBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: skyBlue.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: primaryBlue, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Please select a city to calculate shipping costs before proceeding.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: primaryBlue.withOpacity(0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Payment methods info
                    _buildPaymentMethodsInfo(),
                  ],
                ),
              ),
            ),
    );
  }

  /////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////// Block where I fixed
  // 💰 Build wallet top-up header
  Widget _buildWalletTopUpHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Text(
                '💰 Wallet Top-Up',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'You are adding ₦${NumberFormat("#,###").format(widget.walletTopUpAmount)} to your wallet',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Payment method: Paystack',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 💳 ENHANCED: Payment Method Selection Widget with Error State Handling
  Widget _buildPaymentMethodSection() {
    if (widget.isWalletTopUp) {
      return _buildSimpleWalletPaymentMethodSelection();
    } else {
      return _buildEnhancedPaymentMethodSelection();
    }
  }

  // SIMPLE WALLET PAYMENT METHOD SELECTION
  Widget _buildSimpleWalletPaymentMethodSelection() {
    // Force Paystack for wallet top-up
    _selectedPaymentMethod = 'paystack';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Method',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 12),

          // Forced Paystack for wallet top-up
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Color(0xFF10B981), width: 2),
              borderRadius: BorderRadius.circular(8),
              color: Color(0xFF10B981).withOpacity(0.1),
            ),
            child: Row(
              children: [
                Icon(Icons.payment, color: Color(0xFF10B981)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Paystack - Required for Wallet Top-Up',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF10B981),
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

  // ENHANCED PAYMENT METHOD SELECTION (for regular purchases)
  Widget _buildEnhancedPaymentMethodSelection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Method',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 12),

          // Show payment error summary if there was an error
          if (_lastPaymentError != null && _showPaymentMethodAlternatives) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Paystack payment failed after $_paystackRetryCount attempts. Consider using Bank Transfer instead.',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Wallet Option (with enhanced error handling)
          if (_walletBalance != null && _walletBalance!['success'] == true)
            _buildPaymentMethodTile(
              value: 'wallet',
              icon: '👛',
              title: 'Pay with Wallet',
              subtitle: _buildWalletSubtitle(),
              isEnabled: !_hasInsufficientWalletBalance(),
              trailing: _isLoadingWallet
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            )
          else if (_isLoadingWallet)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading wallet information...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          else if (_walletError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '👛 Wallet: $_walletError',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: 12),

          // Paystack Card Payment with Error State
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _selectedPaymentMethod == 'paystack'
                    ? Colors.orange
                    : Colors.grey.shade300,
                width: _selectedPaymentMethod == 'paystack' ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: _selectedPaymentMethod == 'paystack'
                  ? Colors.orange.shade50
                  : (_lastErrorType != null &&
                          _paystackRetryCount >= _maxRetryAttempts
                      ? Colors.red.shade50
                      : Colors.white),
            ),
            child: RadioListTile<String>(
              title: Row(
                children: [
                  Text('💳', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay with Card',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          _lastErrorType != null &&
                                  _paystackRetryCount >= _maxRetryAttempts
                              ? 'Payment failed - experiencing connection issues'
                              : 'Visa, Mastercard, Verve • Powered by Paystack',
                          style: TextStyle(
                            fontSize: 12,
                            color: _lastErrorType != null &&
                                    _paystackRetryCount >= _maxRetryAttempts
                                ? Colors.red.shade600
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_lastErrorType != null &&
                      _paystackRetryCount >= _maxRetryAttempts) ...[
                    Icon(Icons.warning, color: Colors.red, size: 16),
                  ],
                ],
              ),
              value: 'paystack',
              groupValue: _selectedPaymentMethod,
              activeColor: Colors.orange,
              onChanged: (value) {
                setState(() {
                  _selectedPaymentMethod = value!;
                  // Reset error state when switching back to Paystack
                  if (value == 'paystack') {
                    _paystackRetryCount = 0;
                    _lastPaymentError = null;
                    _lastErrorType = null;
                    _showPaymentMethodAlternatives = false;
                  }
                });
              },
            ),
          ),

          SizedBox(height: 12),

          // Bank Transfer option - highlighted if Paystack failed
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _selectedPaymentMethod == 'bank_transfer'
                    ? Colors.green
                    : Colors.grey.shade300,
                width: _selectedPaymentMethod == 'bank_transfer' ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: _selectedPaymentMethod == 'bank_transfer'
                  ? Colors.green.shade50
                  : (_showPaymentMethodAlternatives
                      ? Colors.green.shade50
                      : Colors.white),
            ),
            child: RadioListTile<String>(
              title: Row(
                children: [
                  Text('🏦', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Bank Transfer',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            if (_showPaymentMethodAlternatives) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'RECOMMENDED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          'Transfer money directly to our bank account',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              value: 'bank_transfer',
              groupValue: _selectedPaymentMethod,
              activeColor: Colors.green,
              onChanged: (value) {
                setState(() {
                  _selectedPaymentMethod = value!;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodTile({
    required String value,
    required String icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    Widget? trailing,
  }) {
    final isSelected = _selectedPaymentMethod == value;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? Colors.orange : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isEnabled
            ? (isSelected ? Colors.orange.withOpacity(0.1) : Colors.white)
            : Colors.grey[100],
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: _selectedPaymentMethod,
        onChanged: isEnabled
            ? (String? newValue) {
                setState(() {
                  _selectedPaymentMethod = newValue ?? 'paystack';
                });
              }
            : null,
        activeColor: Colors.orange,
        title: Row(
          children: [
            Text(icon, style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isEnabled ? Colors.black : Colors.grey,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isEnabled ? Colors.grey[600] : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  // BLUE-THEMED: Complete Order Button with Error State Handling
  Widget _buildEnhancedCompleteOrderButton() {
    final finalTotal = widget.isWalletTopUp
        ? (widget.walletTopUpAmount ?? 0.0)
        : _calculateFinalTotal();

    final bool isPaystackFailed = _selectedPaymentMethod == 'paystack' &&
        _paystackRetryCount >= _maxRetryAttempts;

    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        gradient: isPaystackFailed || widget.isWalletTopUp
            ? null
            : LinearGradient(
                colors: [
                  Color(0xFF1565C0),
                  Color(0xFF42A5F5)
                ], // deep blue → sky blue
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: isPaystackFailed || widget.isWalletTopUp
            ? (widget.isWalletTopUp ? Color(0xFF10B981) : Colors.grey[400])
            : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isPaystackFailed || widget.isWalletTopUp
                    ? (widget.isWalletTopUp ? Color(0xFF10B981) : Colors.grey)
                    : Color(0xFF1565C0))
                .withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (_isLoading ||
                (!widget.isWalletTopUp && _calculatedShippingCost == null))
            ? null
            : _processPayment,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Processing...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isPaystackFailed) ...[
                    const Icon(Icons.warning, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                  ] else ...[
                    Icon(_getPaymentIcon(), size: 20, color: Colors.white),
                    const SizedBox(width: 12),
                  ],
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.isWalletTopUp
                            ? 'Top Up Wallet'
                            : _getCompleteOrderButtonText(finalTotal),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (!isPaystackFailed)
                        Text(
                          widget.isWalletTopUp
                              ? '₦${NumberFormat("#,###").format(widget.walletTopUpAmount)}'
                              : _formatCurrency(finalTotal),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  // ONLY ADD THESE MISSING METHODS (remove the duplicate ones):

  String _getCompleteOrderButtonText(double total) {
    return 'Complete Order';
  }

  // ENHANCED: Wallet Subtitle with Better Error Handling
  String _buildWalletSubtitle() {
    if (_walletBalance == null || _walletBalance!['success'] != true) {
      return 'Wallet unavailable';
    }

    try {
      final currentBalance =
          authService.getWalletBalanceAmount(_walletBalance!);
      final finalTotal = _calculateFinalTotal();
      final formattedBalance = authService.formatWalletBalance(_walletBalance!);

      if (currentBalance < finalTotal) {
        final shortfall = finalTotal - currentBalance;
        return 'Available: $formattedBalance (₦${shortfall.toStringAsFixed(2)} short)';
      } else {
        return 'Available: $formattedBalance';
      }
    } catch (e) {
      return 'Wallet error: ${e.toString()}';
    }
  }

  // Helper methods for payment button
  IconData _getPaymentIcon() {
    if (widget.isWalletTopUp) return Icons.account_balance_wallet;

    switch (_selectedPaymentMethod) {
      case 'wallet':
        return Icons.account_balance_wallet;
      case 'bank_transfer':
        return Icons.account_balance;
      default:
        return Icons.lock;
    }
  }

  Widget _buildPaymentMethodsInfo() {
    String infoText;
    IconData infoIcon;
    Color infoColor;

    if (widget.isWalletTopUp) {
      infoText = 'Complete your wallet top-up with secure Paystack payment';
      infoIcon = Icons.account_balance_wallet;
      infoColor = Color(0xFF10B981);
    } else {
      switch (_selectedPaymentMethod) {
        case 'wallet':
          infoText = 'Instant payment using your TellMe wallet balance';
          infoIcon = Icons.flash_on;
          infoColor = Colors.green;
          break;
        case 'bank_transfer':
          infoText = 'You will receive bank details after placing your order';
          infoIcon = Icons.account_balance;
          infoColor = Colors.blue;
          break;
        default:
          infoText = 'We accept all major cards, bank transfers, and USSD';
          infoIcon = Icons.credit_card;
          infoColor = Colors.grey[600]!;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(infoIcon, color: infoColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              infoText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////where I fixed
  // ✨ NEW: Dynamic Shipping Cost Display Section
  Widget _buildDynamicShippingSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Dynamic Shipping Calculation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isCalculatingShipping)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.orange,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Calculating shipping cost...',
                      style: TextStyle(color: Colors.orange[800]),
                    ),
                  ],
                ),
              )
            else if (_shippingCalculationError != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _shippingCalculationError!,
                        style: TextStyle(color: Colors.red[800]),
                      ),
                    ),
                  ],
                ),
              )
            else if (_calculatedShippingCost != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Shipping Cost Calculated',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _formatCurrency(_calculatedShippingCost!),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Select a city below to calculate accurate shipping costs based on your location and cart items.',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
          ],
        ),
      ),
    );
  }

// NEW — wallet top-up must ignore shipping completely

  Widget _buildOrderSummary() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isWalletTopUp ? 'Top-Up Details' : 'Order Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // For wallet top-up, show the top-up amount
            if (widget.isWalletTopUp) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Top-Up Amount:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '₦${NumberFormat("#,###").format(widget.walletTopUpAmount)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Show current wallet balance if available
              if (_walletBalance != null &&
                  _walletBalance!['success'] == true) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Current Balance:'),
                      Text(
                        // ✅ FIXED: Use proper wallet balance formatting
                        authService.formatWalletBalance(_walletBalance!),
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New Balance:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        // ✅ FIXED: Use proper helper methods for balance calculation
                        _formatCurrency(authService
                                .getWalletBalanceAmount(_walletBalance!) +
                            widget.walletTopUpAmount!),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              // Regular cart items
              ...widget.cartItems
                  .map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${item['name']} × ${item['quantity']}',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                            Text(
                              _formatCurrency(
                                  (double.tryParse(item['price'].toString()) ??
                                          0.0) *
                                      (item['quantity'] ?? 1)),
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.orange,
        ),
      ),
    );
  }

  // ============================================================
  // 🏠 ENHANCED: Dynamic Billing Address Form with TellMe Plugin
  // ============================================================
  Widget _buildBillingAddressForm() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _billingFirstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter first name';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _billingLastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter last name';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _billingCompanyController,
              decoration: const InputDecoration(
                labelText: 'Company (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 🌍 Country Dropdown
            DropdownButtonFormField<String>(
              value: _selectedBillingCountry,
              decoration: const InputDecoration(
                labelText: 'Country *',
                border: OutlineInputBorder(),
              ),
              items: _countries.map((country) {
                return DropdownMenuItem<String>(
                  value: country['code'],
                  child: Text(country['name']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedBillingCountry = value;
                  _selectedBillingState = null;
                  _selectedBillingCity = null;
                  _calculatedShippingCost = null; // Reset shipping calculation
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a country';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 🏛️ ENHANCED: Dynamic State Dropdown with TellMe Plugin
            DropdownButtonFormField<String>(
              value: _selectedBillingState,
              decoration: InputDecoration(
                labelText: 'State *',
                border: const OutlineInputBorder(),
                suffixIcon: _isLoadingLocationData
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.orange),
                      )
                    : null,
              ),
              items: _getStatesForCountry(_selectedBillingCountry).map((state) {
                return DropdownMenuItem<String>(
                  value: state['code'],
                  child: Text(state['name']),
                );
              }).toList(),
              onChanged: (value) async {
                setState(() {
                  _selectedBillingState = value;
                  _selectedBillingCity = null;
                  _calculatedShippingCost = null; // Reset shipping calculation
                });

                // 🚀 LOAD CITIES DYNAMICALLY from TellMe Plugin
                if (value != null) {
                  await _loadCitiesForState(value, isBilling: true);
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a state';
                }
                return null;
              },
            ),

            // Show loading indicator for cities
            if (_isLoadingBillingCities)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.orange, strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Loading cities...',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // 🏙️ ENHANCED: Dynamic City Dropdown with TellMe Plugin + Shipping Calculation
            DropdownButtonFormField<String>(
              value: (_selectedBillingCity != null &&
                      _getCitiesForState(_selectedBillingState)
                          .map((city) => city['code'])
                          .contains(_selectedBillingCity))
                  ? _selectedBillingCity
                  : null, // ✅ Prevent crash if value not in list
              decoration: InputDecoration(
                labelText: 'City *',
                border: const OutlineInputBorder(),
                suffixIcon: _isLoadingBillingCities
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.orange),
                      )
                    : null,
              ),
              items: _getCitiesForState(_selectedBillingState).map((city) {
                return DropdownMenuItem<String>(
                  value: city['code'],
                  child: Text(city['name']),
                );
              }).toList(),
              onChanged: (value) async {
                setState(() {
                  _selectedBillingCity = value;
                });

                // ✨ TRIGGER DYNAMIC SHIPPING CALCULATION when city is selected (skip for wallet top-up)
                if (value != null && !widget.isWalletTopUp) {
                  await _calculateDynamicShippingCost();
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a city';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            TextFormField(
              controller: _billingAddressController,
              decoration: const InputDecoration(
                labelText: 'Street Address *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter street address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _billingAddress2Controller,
              decoration: const InputDecoration(
                labelText: 'Apartment, suite, etc. (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _billingPostalCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Postal Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _billingPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter phone number';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 🚚 ENHANCED: Dynamic Shipping Address Form with TellMe Plugin
  // ============================================================
  Widget _buildShippingAddressForm() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _shippingFirstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (!_shipToSameAddress &&
                          (value == null || value.isEmpty)) {
                        return 'Please enter first name';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _shippingLastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (!_shipToSameAddress &&
                          (value == null || value.isEmpty)) {
                        return 'Please enter last name';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shippingCompanyController,
              decoration: const InputDecoration(
                labelText: 'Company (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Shipping Country Dropdown
            DropdownButtonFormField<String>(
              value: _selectedShippingCountry,
              decoration: const InputDecoration(
                labelText: 'Country *',
                border: OutlineInputBorder(),
              ),
              items: _countries
                  .map((country) => DropdownMenuItem<String>(
                        value: (country['code'] ?? '').toString(),
                        child: Text((country['name'] ?? '').toString()),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedShippingCountry = value;
                  _selectedShippingState = null;
                  _selectedShippingCity = null;
                  _calculatedShippingCost = null; // Reset shipping calculation
                });
              },
              validator: (value) {
                if (!_shipToSameAddress && (value == null || value.isEmpty)) {
                  return 'Please select a country';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // ENHANCED: Shipping State Dropdown with TellMe Plugin
            DropdownButtonFormField<String>(
              value: _selectedShippingState,
              decoration: InputDecoration(
                labelText: 'State *',
                border: const OutlineInputBorder(),
                suffixIcon: _isLoadingLocationData
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.orange),
                      )
                    : null,
              ),
              items:
                  _getStatesForCountry(_selectedShippingCountry).map((state) {
                return DropdownMenuItem<String>(
                  value: state['code'],
                  child: Text(state['name']),
                );
              }).toList(),
              onChanged: (value) async {
                setState(() {
                  _selectedShippingState = value;
                  _selectedShippingCity = null;
                  _calculatedShippingCost = null; // Reset shipping calculation
                });

                // 🚀 LOAD CITIES DYNAMICALLY from TellMe Plugin
                if (value != null) {
                  await _loadCitiesForState(value, isShipping: true);
                }
              },
              validator: (value) {
                if (!_shipToSameAddress && (value == null || value.isEmpty)) {
                  return 'Please select a state';
                }
                return null;
              },
            ),

            // Show loading indicator for shipping cities
            if (_isLoadingShippingCities)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.orange, strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Loading cities...',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // ENHANCED: Shipping City Dropdown with TellMe Plugin + Shipping Calculation
            DropdownButtonFormField<String>(
              value: _selectedShippingCity,
              decoration: InputDecoration(
                labelText: 'City *',
                border: const OutlineInputBorder(),
                suffixIcon: _isLoadingShippingCities
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.orange),
                      )
                    : null,
              ),
              items: _getCitiesForState(_selectedShippingState).map((city) {
                return DropdownMenuItem<String>(
                  value: city['code'],
                  child: Text(city['name']),
                );
              }).toList(),
              onChanged: (value) async {
                setState(() {
                  _selectedShippingCity = value;
                });

                // ✨ TRIGGER DYNAMIC SHIPPING CALCULATION when shipping city is selected
                if (value != null &&
                    !_shipToSameAddress &&
                    !widget.isWalletTopUp) {
                  await _calculateDynamicShippingCost();
                }
              },
              validator: (value) {
                if (!_shipToSameAddress && (value == null || value.isEmpty)) {
                  return 'Please select a city';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _shippingAddressController,
              decoration: const InputDecoration(
                labelText: 'Street Address *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (!_shipToSameAddress && (value == null || value.isEmpty)) {
                  return 'Please enter street address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shippingAddress2Controller,
              decoration: const InputDecoration(
                labelText: 'Apartment, suite, etc. (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shippingPostalCodeController,
              decoration: const InputDecoration(
                labelText: 'Postal Code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalOrderSummary() {
    // ✨ Use calculated dynamic shipping cost instead of fixed methods
    final double shippingCost = _calculatedShippingCost ?? 0.0;

    // 🔥 Loyalty: only relevant for normal orders (not wallet top-ups)
    final LoyaltyDiscount? loyalty = widget.loyalty;
    final bool hasLoyaltyDiscount = !widget.isWalletTopUp &&
        loyalty != null &&
        loyalty.eligible &&
        loyalty.discount > 0;

    final double discount = hasLoyaltyDiscount ? loyalty!.discount : 0.0;

    // Base amount to display in the first row
    final double baseAmount = widget.isWalletTopUp
        ? (widget.walletTopUpAmount ?? 0.0)
        : _getSubtotal; // ← use _getSubtotal instead of widget.subtotal

    // Final total (single source of truth)
    final double finalTotal = _calculateFinalTotal();

    return Card(
      elevation: 2,
      child: Padding(
        padding:
            const EdgeInsets.all(16.0), // FIXED: Added 'padding:' parameter
        child: Column(
          children: [
            // Row: Subtotal / Top-up amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.isWalletTopUp ? 'Top-Up Amount:' : 'Subtotal:'),
                Text(
                  widget.isWalletTopUp
                      ? '₦${NumberFormat("#,###").format(baseAmount)}'
                      : _formatCurrency(baseAmount),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Skip shipping (and loyalty) for wallet top-up
            if (!widget.isWalletTopUp) ...[
              // Shipping row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('Shipping:'),
                      if (_isCalculatingShipping) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            color: Colors.orange,
                            strokeWidth: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _calculatedShippingCost != null
                        ? _formatCurrency(shippingCost)
                        : (_isCalculatingShipping ? 'Calculating...' : 'TBD'),
                    style: TextStyle(
                      color: _calculatedShippingCost != null
                          ? Colors.black
                          : Colors.grey,
                    ),
                  ),
                ],
              ),

              // ✅ Loyalty discount row (only if discount > 0)
              if (hasLoyaltyDiscount) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (loyalty!.imageUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Image.network(
                              loyalty.imageUrl,
                              height: 24,
                              fit: BoxFit.contain,
                            ),
                          ),
                        Text(
                          loyalty.label.isNotEmpty
                              ? loyalty.label
                              : 'TellMe Loyalty Discount',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '-${_formatCurrency(discount)}',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(),
            ],

            // Final total row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isWalletTopUp ? 'Total to Pay:' : 'Total:',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.isWalletTopUp
                      ? '₦${NumberFormat("#,###").format(baseAmount)}'
                      : _formatCurrency(finalTotal),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _billingFirstNameController.dispose();
    _billingLastNameController.dispose();
    _billingCompanyController.dispose();
    _billingAddressController.dispose();
    _billingAddress2Controller.dispose();
    _billingPostalCodeController.dispose();
    _billingPhoneController.dispose();
    _shippingFirstNameController.dispose();
    _shippingLastNameController.dispose();
    _shippingCompanyController.dispose();
    _shippingAddressController.dispose();
    _shippingAddress2Controller.dispose();
    _shippingPostalCodeController.dispose();
    super.dispose();
  }
}

// ✅ FINAL FIX: PaystackWebViewDialog that handles order creation BEFORE closing
class PaystackWebViewDialog extends StatefulWidget {
  final String paymentUrl;
  final String reference;
  final Function(bool success, String? reference) onPaymentComplete;
  final VoidCallback onCancel;

  const PaystackWebViewDialog({
    Key? key,
    required this.paymentUrl,
    required this.reference,
    required this.onPaymentComplete,
    required this.onCancel,
  }) : super(key: key);

  @override
  _PaystackWebViewDialogState createState() => _PaystackWebViewDialogState();
}

class _PaystackWebViewDialogState extends State<PaystackWebViewDialog> {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  bool _paymentCompleted = false; // ✅ CRITICAL: Prevent multiple calls
  String _currentUrl = '';
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PaystackChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (_paymentCompleted) return; // ✅ Prevent duplicate calls

          final msg = message.message.toLowerCase();
          print('📩 JS Message from Paystack: $msg');
          if (msg.contains('payment-success') ||
              msg.contains('success') ||
              msg.contains('completed')) {
            _handlePaymentSuccess();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _isLoading = true;
            });

            // ✅ CRITICAL: Check payment status on every URL change
            _checkPaymentStatus(url);
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _isLoading = false;
            });

            print('✅ Finished loading: $url');

            // ✅ CRITICAL: Check payment status when page finishes loading
            _checkPaymentStatus(url);

            // ✅ Inject JavaScript to detect success text
            await _webViewController.runJavaScriptReturningResult('''
              const observer = new MutationObserver(() => {
                if (document.body.innerText.toLowerCase().includes('payment successful')) {
                  PaystackChannel.postMessage('payment-success');
                }
              });
              observer.observe(document.body, { childList: true, subtree: true });
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            // ✅ CRITICAL: Check payment status on navigation requests
            _checkPaymentStatus(request.url);
            return NavigationDecision.navigate;
          },
        ),
      );

    _webViewController.loadRequest(Uri.parse(widget.paymentUrl));
  }

  // ✅ CRITICAL: Check payment status from URL patterns
  void _checkPaymentStatus(String url) {
    if (_paymentCompleted) return; // ✅ Prevent duplicate processing

    final urlLower = url.toLowerCase();
    print('🔍 Checking Paystack URL: $urlLower');

    // ✅ Common Paystack Success URL patterns
    if (urlLower.contains('checkout.paystack.com/close') ||
        urlLower.contains('checkout.paystack.com/success') ||
        urlLower.contains('status=success') ||
        urlLower.contains('transaction_status=success') ||
        urlLower.contains('verified') ||
        urlLower.contains('completed') ||
        urlLower.contains('done') ||
        urlLower.contains('receipt') ||
        urlLower.contains('thank')) {
      print('🎉 Detected Payment SUCCESS from URL');
      _handlePaymentSuccess();
      return;
    }

    // ❌ Failure/Cancel patterns
    if (urlLower.contains('failed') ||
        urlLower.contains('cancel') ||
        urlLower.contains('decline')) {
      print('💔 Detected Payment FAILURE/CANCEL');
      _handlePaymentFailure();
      return;
    }
  }

  // ✅ CRITICAL: Handle payment success - DON'T close dialog yet
  void _handlePaymentSuccess() {
    if (_paymentCompleted || !mounted) return;

    _paymentCompleted = true; // ✅ Mark as completed
    _statusCheckTimer?.cancel();

    print('✅ Processing payment success...');
    print('✅ Payment completed successfully: ${widget.reference}');

    // ✅ CRITICAL: Call the callback but DON'T close the dialog yet
    // The parent will handle the order creation and close the dialog when done
    widget.onPaymentComplete(true, widget.reference);
  }

  // ✅ Handle payment failure
  void _handlePaymentFailure() {
    if (_paymentCompleted || !mounted) return;

    _paymentCompleted = true;
    _statusCheckTimer?.cancel();

    print('❌ Payment failed or was cancelled');

    // ✅ Close dialog and notify parent of failure
    Navigator.of(context).pop();
    widget.onPaymentComplete(false, null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(10),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payment, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Secure Payment',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _showCancelConfirmation,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Loading bar
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Loading secure payment...'),
                  ],
                ),
              ),

            // ✅ Show processing message when payment is being processed
            if (_paymentCompleted)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  border: Border(
                      bottom: BorderSide(color: Colors.green.withOpacity(0.3))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Payment successful! Processing your order...',
                        style: TextStyle(
                          color: Colors.green[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    ),
                  ],
                ),
              ),

            // WebView
            Expanded(child: WebViewWidget(controller: _webViewController)),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.blue, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _paymentCompleted
                              ? 'Payment complete! Creating your order...'
                              : 'Complete your payment above. The app will automatically continue when done.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _paymentCompleted
                                ? Colors.green[700]
                                : Colors.grey[700],
                            fontWeight: _paymentCompleted
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reference: ${widget.reference}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCancelConfirmation() {
    if (_paymentCompleted)
      return; // ✅ Don't allow cancel if payment is processing

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Payment?'),
          content: const Text('Are you sure you want to cancel this payment?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue Payment'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Close WebView
                widget.onCancel();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );
  }
}
