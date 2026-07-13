import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'user_provider.dart';
import 'logistics_tracking_signalr_service.dart';
import 'logistics_rider_jobs_page.dart';
import 'services/google_maps_service.dart';
import 'config/api_config.dart';
import 'config/app_config.dart';
import 'services/logistics_api_service.dart';

// TellMe brand palette sampled from the logo.
const kPrimaryColor = Color(0xFF122DB2);
const kSecondaryColor = Color(0xFF0275F4);
const kAccentColor = Color(0xFF00CCFB);
const kHighlightColor = Color(0xFFF9045F);
const kSuccessGreen = Color(0xFF00B8DE);
const kWarningAmber = Color(0xFFFBBD08);
const kInfoBlue = Color(0xFF0E49D3);
const kBackgroundLight = Color(0xFFF4FAFF);
const kSurfaceWhite = Color(0xFFFFFFFF);
const kTextPrimary = Color(0xFF12215B);
const kTextSecondary = Color(0xFF627394);
const kBorderLight = Color(0xFFD9EAFB);
const kGlassOverlay = Color(0x1AFFFFFF);

// Legacy colors kept for compatibility
const kPrimaryBlue = kPrimaryColor;
const kAccentBlue = kSecondaryColor;
const kDeepBlue = kSecondaryColor;
const kSkyCyan = kAccentColor;
const kDotRed = kHighlightColor;
const kDotAmber = kWarningAmber;
const kDotNavy = Color(0xFF393C8D);
const kPageBackground = kBackgroundLight;
const kCardBorder = kBorderLight;
const kSoftPanel = Color(0xFFEAF6FF);

enum _LocationTarget { pickup, dropoff }

enum _PaymentPreference { payOnline, payOnDelivery }

enum _CustomerMapCameraMode { routeOverview, rider, destination }

class LogisticsPage extends StatefulWidget {
  const LogisticsPage({super.key});

  @override
  State<LogisticsPage> createState() => _LogisticsPageState();
}

class _LogisticsPageState extends State<LogisticsPage>
    with TickerProviderStateMixin {
  final LogisticsApiService _api = LogisticsApiService();
  final GoogleMapsService _mapsService = GoogleMapsService();

  final _formKey = GlobalKey<FormState>();

  late TabController _tabController;
  late AnimationController _headerAnimController;
  late Animation<double> _headerFadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final TextEditingController _senderNameController = TextEditingController();
  final TextEditingController _senderPhoneController = TextEditingController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropoffController = TextEditingController();
  final TextEditingController _receiverNameController = TextEditingController();
  final TextEditingController _receiverPhoneController =
      TextEditingController();
  final TextEditingController _packageDescriptionController =
      TextEditingController();
  final TextEditingController _packageWeightController =
      TextEditingController();
  final TextEditingController _deliveryNoteController = TextEditingController();
  final TextEditingController _trackingIdController = TextEditingController();

  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _dropoffFocusNode = FocusNode();

  Timer? _debounce;
  Timer? _estimateDebounce;

  bool _isSubmitting = false;
  bool _isLoadingMyDeliveries = false;
  bool _isTracking = false;
  String? _payingDeliveryId;

  _PaymentPreference _paymentPreference = _PaymentPreference.payOnline;

  bool _isSearchingAddress = false;
  bool _isGettingPickupLocation = false;
  bool _isGettingDropoffLocation = false;

  bool _isEstimatingDeliveryFee = false;
  String? _estimateErrorMessage;
  double? _estimatedDistanceKm;
  num? _estimatedDeliveryFee;
  bool _requiresManualQuote = false;

  _LocationTarget? _activeLocationTarget;

  List<Map<String, dynamic>> _addressSearchResults = [];

  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;

  List<dynamic> _myDeliveries = [];
  Map<String, dynamic>? _trackingResult;
  Map<String, dynamic>? _trackedDelivery;

  // Delivery OTP shown to the customer after the rider marks the package as picked up.
  // The backend must return these OTP fields only to the customer/user side.
  bool _isRefreshingDeliveryOtp = false;
  DateTime? _lastDeliveryOtpRefreshAt;

  // SignalR Live Tracking
  static final String _logisticsHubBaseUrl = ApiConfig.baseUrl;

  static const String _focusedTrackingMapStyle = r'''
[
  {
    "elementType": "geometry",
    "stylers": [{ "color": "#ffffff" }]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry.stroke",
    "stylers": [{ "color": "#e2e8ef" }]
  },
  {
    "featureType": "administrative",
    "elementType": "labels.text.fill",
    "stylers": [
      { "color": "#5f6b7a" },
      { "visibility": "on" }
    ]
  },
  {
    "featureType": "landscape",
    "elementType": "geometry",
    "stylers": [{ "color": "#ffffff" }]
  },
  {
    "featureType": "landscape.man_made",
    "elementType": "geometry",
    "stylers": [{ "color": "#ffffff" }]
  },
  {
    "featureType": "poi",
    "elementType": "geometry",
    "stylers": [{ "color": "#ffffff" }]
  },
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{ "color": "#eaf1f6" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{ "color": "#dce8f1" }]
  },
  {
    "featureType": "road.local",
    "elementType": "geometry",
    "stylers": [{ "color": "#f1f5f8" }]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      { "color": "#445466" },
      { "visibility": "on" }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.stroke",
    "stylers": [
      { "color": "#ffffff" },
      { "weight": 3 }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "labels",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{ "color": "#d9f1f8" }]
  }
]
''';

  StreamSubscription<Map<String, dynamic>>? _riderLocationSubscription;
  String? _activeLiveTrackingDeliveryId;
  LatLng? _liveRiderLatLng;
  LatLng? _livePickupLatLng;
  LatLng? _liveDropoffLatLng;
  int? _liveDeliveryStatusCode;
  String? _liveDeliveryStatusText;

  GoogleMapController? _trackingMapController;
  bool _isTrackingMapReady = false;
  bool _isFullScreenTrackingMap = false;
  _CustomerMapCameraMode _customerMapCameraMode =
      _CustomerMapCameraMode.routeOverview;
  DateTime? _lastTrackingCameraMoveAt;
  Set<Marker> _liveTrackingMarkers = {};
  Set<Polyline> _liveTrackingPolylines = {};
  List<LatLng> _riderMovementPath = [];
  BitmapDescriptor? _bikeMarkerIcon;
  bool _isBikeMarkerAssetLoaded = false;

  AnimationController? _bikeAnimationController;
  LatLng? _animatedRiderLatLng;
  double _riderBearing = 0;

  DateTime? _lastRiderLocationUpdate;
  int _liveRiderSignalRUpdateCount = 0;
  bool _isCustomerSignalRConnected = false;
  String _trackingLocationSource = '';
  String _currentRiderAddress = '';
  LatLng? _lastReverseGeocodedRiderLatLng;
  int _riderAddressLookupToken = 0;

  String get _trackingSourceLabel {
    if (_liveRiderSignalRUpdateCount > 0) return 'Live GPS';
    if (_trackingLocationSource.isNotEmpty) return _trackingLocationSource;
    return 'Awaiting signal';
  }

  bool get _hasConfirmedLiveSignalRUpdate => _liveRiderSignalRUpdateCount > 0;

  String? _lastSubmittedGuestCustomerId;
  Map<String, dynamic>? _loggedInRider;
  bool _isCheckingRiderAccess = false;

  @override
  void initState() {
    super.initState();

    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFadeAnimation = CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOutCubic,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadBikeMarkerIcon();

    _tabController = TabController(length: 3, vsync: this);

    _pickupFocusNode.addListener(() {
      if (_pickupFocusNode.hasFocus) {
        setState(() => _activeLocationTarget = _LocationTarget.pickup);
      }
    });

    _dropoffFocusNode.addListener(() {
      if (_dropoffFocusNode.hasFocus) {
        setState(() => _activeLocationTarget = _LocationTarget.dropoff);
      }
    });

    _headerAnimController.forward();
    _pulseController.repeat(reverse: true);

    Future.microtask(() async {
      _prefillUserDetails();
      await _checkLoggedInUserRiderAccess();
      if (!mounted) return;
      final isRiderAccount = _loggedInRider != null;
      if (!isRiderAccount) {
        await _loadMyDeliveries();
      }
    });
  }

  Future<BitmapDescriptor> _resizedBikeMarkerFromAsset(
    String assetPath, {
    int targetWidth = 110,
  }) async {
    final byteData = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      byteData.buffer.asUint8List(),
      targetWidth: targetWidth,
    );
    final frame = await codec.getNextFrame();
    final imageBytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (imageBytes == null)
      throw Exception('Could not convert bike marker image.');
    return BitmapDescriptor.fromBytes(imageBytes.buffer.asUint8List());
  }

  Future<void> _loadBikeMarkerIcon() async {
    try {
      _bikeMarkerIcon = await _resizedBikeMarkerFromAsset(
        'assets/images/bike_marker.png',
        targetWidth: 110,
      );
      _isBikeMarkerAssetLoaded = true;
    } catch (e) {
      _isBikeMarkerAssetLoaded = false;
      _bikeMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
    }
  }

  void _prefillUserDetails() {
    final user = context.read<UserProvider?>();
    final displayName = user?.userDisplayName?.trim() ?? '';
    if (displayName.isNotEmpty && _senderNameController.text.trim().isEmpty) {
      _senderNameController.text = displayName;
    }
  }

  @override
  void dispose() {
    _riderLocationSubscription?.cancel();
    _bikeAnimationController?.dispose();
    _headerAnimController.dispose();
    _pulseController.dispose();
    if (_activeLiveTrackingDeliveryId != null) {
      LogisticsTrackingSignalRService.instance.leaveDeliveryTrackingGroup(
        _activeLiveTrackingDeliveryId!,
      );
    }
    _debounce?.cancel();
    _estimateDebounce?.cancel();
    _tabController.dispose();
    _senderNameController.dispose();
    _senderPhoneController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    _receiverNameController.dispose();
    _receiverPhoneController.dispose();
    _packageDescriptionController.dispose();
    _packageWeightController.dispose();
    _deliveryNoteController.dispose();
    _trackingIdController.dispose();
    _pickupFocusNode.dispose();
    _dropoffFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkLoggedInUserRiderAccess() async {
    final user = context.read<UserProvider?>();

    final email = user?.userEmail?.trim().toLowerCase() ?? '';

    if (email.isEmpty) {
      if (!mounted) return;

      setState(() {
        _loggedInRider = null;
        _isCheckingRiderAccess = false;
      });

      return;
    }

    setState(() => _isCheckingRiderAccess = true);

    try {
      final rider = await _lookupRiderByEmail(email);

      if (!mounted) return;

      setState(() {
        _loggedInRider = rider;
      });

      if (rider != null) {
        debugPrint('[RiderAccess] Rider profile found for $email');
      } else {
        debugPrint('[RiderAccess] No rider profile found for $email');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _loggedInRider = null);
      debugPrint('[RiderAccess] Rider lookup failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isCheckingRiderAccess = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _lookupRiderByEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) return null;

    try {
      final result = await _api.lookupRider(email: cleanEmail);

      if (result['success'] == true && result['data'] is Map) {
        return Map<String, dynamic>.from(result['data']);
      }
      return null;
    } catch (e) {
      debugPrint(
        '[RiderAccess] Direct rider lookup failed. Trying admin riders fallback: $e',
      );
    }

    return _findRiderFromAdminListByEmail(cleanEmail);
  }

  Future<Map<String, dynamic>?> _findRiderFromAdminListByEmail(
    String email,
  ) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) return null;

    try {
      final result = await _api.getAdminRiders();

      if (result['success'] == true && result['data'] is List) {
        final riders = result['data'] as List;
        for (final rider in riders) {
          if (rider is! Map) continue;
          final riderEmail =
              rider['email']?.toString().trim().toLowerCase() ?? '';
          if (riderEmail == cleanEmail) {
            return Map<String, dynamic>.from(rider);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('[RiderAccess] Admin riders fallback failed: $e');
      return null;
    }
  }

  void _openRiderJobsPage() {
    final rider = _loggedInRider;

    if (rider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not assigned as a logistics rider.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final riderId = rider['id']?.toString() ?? '';
    final riderName =
        rider['fullName']?.toString() ?? rider['name']?.toString() ?? 'Rider';

    if (riderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider ID not found. Please contact admin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LogisticsRiderJobsPage(riderId: riderId, riderName: riderName),
      ),
    );
  }

  String _buildGuestCustomerId(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return 'guest_$cleanPhone';
  }

  String _currentCustomerId() {
    final user = context.read<UserProvider?>();

    if (user?.userEmail?.trim().isNotEmpty == true) {
      return user!.userEmail!.trim();
    }

    final senderPhone = _senderPhoneController.text.trim();

    if (senderPhone.isNotEmpty) {
      return _buildGuestCustomerId(senderPhone);
    }

    return _lastSubmittedGuestCustomerId ?? '';
  }

  Future<void> _submitDeliveryRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final user = context.read<UserProvider?>();

    final senderPhone = _senderPhoneController.text.trim();

    final customerPhone = senderPhone;

    final customerId = user?.userEmail?.trim().isNotEmpty == true
        ? user!.userEmail!.trim()
        : _buildGuestCustomerId(senderPhone);

    final customerName = user?.userDisplayName?.trim().isNotEmpty == true
        ? user!.userDisplayName!.trim()
        : _senderNameController.text.trim();

    final customerEmail = user?.userEmail?.trim() ?? '';

    final weight = double.tryParse(_packageWeightController.text.trim()) ?? 0;

    final selectedPaymentPreference = _paymentPreference;

    final rawDeliveryNote = _deliveryNoteController.text.trim();
    final paymentPreferenceText =
        selectedPaymentPreference == _PaymentPreference.payOnDelivery
        ? 'Payment option: Pay on Delivery'
        : 'Payment option: Pay Online';

    final deliveryNote = rawDeliveryNote.isEmpty
        ? paymentPreferenceText
        : '$rawDeliveryNote\n$paymentPreferenceText';

    setState(() => _isSubmitting = true);

    try {
      final result = await _api
          .createDelivery(
            customerId: customerId,
            customerName: customerName,
            customerPhone: customerPhone,
            customerEmail: customerEmail,
            senderName: _senderNameController.text.trim(),
            senderPhone: _senderPhoneController.text.trim(),
            pickupAddress: _pickupController.text.trim(),
            pickupLatitude: _pickupLatLng?.latitude,
            pickupLongitude: _pickupLatLng?.longitude,
            dropoffAddress: _dropoffController.text.trim(),
            dropoffLatitude: _dropoffLatLng?.latitude,
            dropoffLongitude: _dropoffLatLng?.longitude,
            receiverName: _receiverNameController.text.trim(),
            receiverPhone: _receiverPhoneController.text.trim(),
            packageDescription: _packageDescriptionController.text.trim(),
            packageWeightKg: weight,
            deliveryNote: deliveryNote,
          )
          .timeout(AppConfig.networkTimeout);

      if (!mounted) return;

      final success = result['success'] == true;

      if (success) {
        _lastSubmittedGuestCustomerId = customerId;

        final createdData = result['data'];

        if (createdData is Map) {
          _trackedDelivery = Map<String, dynamic>.from(createdData);
        }

        _clearForm();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selectedPaymentPreference == _PaymentPreference.payOnDelivery
                  ? 'Delivery request submitted. Payment can be made after delivery.'
                  : 'Delivery request submitted successfully.',
            ),
            backgroundColor: Colors.green,
          ),
        );

        await _loadMyDeliveries();

        if (mounted) {
          _tabController.animateTo(2);
        }
      } else {
        final message =
            result['message'] ??
            result['error'] ??
            'Failed to submit request. Please check your details and try again.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      debugPrint('Failed to submit delivery request: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to submit delivery request. Please check your connection and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _startPaymentForDelivery(Map<String, dynamic> delivery) async {
    final deliveryId = delivery['id']?.toString() ?? '';

    if (deliveryId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery ID not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_payingDeliveryId == deliveryId) return;

    final deliveryEmail = delivery['customerEmail']?.toString().trim() ?? '';
    final userEmail = context.read<UserProvider?>()?.userEmail?.trim() ?? '';
    final email = deliveryEmail.isNotEmpty ? deliveryEmail : userEmail;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email is required to make payment. Please sign in first.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _payingDeliveryId = deliveryId);

    try {
      final result = await _api
          .initializePayment(deliveryRequestId: deliveryId, email: email)
          .timeout(AppConfig.networkTimeout);

      final data = result['data'];

      if (data is! Map) {
        throw Exception('Invalid payment response.');
      }

      final authorizationUrl =
          data['authorizationUrl']?.toString() ??
          data['authorization_url']?.toString() ??
          '';
      final reference = data['reference']?.toString() ?? '';

      if (authorizationUrl.isEmpty || reference.isEmpty) {
        throw Exception('Payment authorization URL not returned.');
      }

      if (!mounted) return;

      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaystackCheckoutPage(
            authorizationUrl: authorizationUrl,
            reference: reference,
            onVerify: (ref) => _api.verifyPayment(reference: ref),
          ),
        ),
      );

      if (paid == true) {
        await _loadMyDeliveries();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successful.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment was not completed.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted && _payingDeliveryId == deliveryId) {
        setState(() => _payingDeliveryId = null);
      }
    }
  }

  Future<void> _loadMyDeliveries() async {
    final customerId = _currentCustomerId();

    if (customerId.isEmpty) {
      if (!mounted) return;

      setState(() {
        _myDeliveries = [];
        _isLoadingMyDeliveries = false;
      });

      return;
    }

    setState(() => _isLoadingMyDeliveries = true);

    try {
      final result = await _api
          .getMyDeliveries(customerId: customerId)
          .timeout(AppConfig.networkTimeout);

      if (!mounted) return;

      final success = result['success'] == true;
      final data = result['data'];

      setState(() {
        if (success && data is List) {
          _myDeliveries = data;
        } else {
          _myDeliveries = [];
        }
      });
    } catch (e) {
      if (!mounted) return;

      debugPrint('Failed to load deliveries: $e');

      setState(() {
        _myDeliveries = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingMyDeliveries = false);
      }
    }
  }

  Map<String, dynamic>? _findDeliveryByInput(String input) {
    final normalizedInput = input.trim().toLowerCase();

    if (normalizedInput.isEmpty) return null;

    for (final item in _myDeliveries) {
      if (item is! Map) continue;

      final fullId = item['id']?.toString().toLowerCase() ?? '';

      if (fullId.isEmpty) continue;

      if (fullId == normalizedInput || fullId.startsWith(normalizedInput)) {
        return Map<String, dynamic>.from(item);
      }
    }

    return null;
  }


  Map<String, dynamic> _mergeDeliveryMaps(Map? base, Map? incoming) {
    final merged = <String, dynamic>{};

    if (base != null) {
      merged.addAll(Map<String, dynamic>.from(base));
    }

    if (incoming != null) {
      merged.addAll(Map<String, dynamic>.from(incoming));
    }

    return merged;
  }

  Map<String, dynamic>? _deliveryMapFromTrackingResult(dynamic result) {
    if (result is! Map) return null;

    final data = result['data'] ?? result['Data'];

    if (data is Map) {
      final delivery =
          data['delivery'] ??
          data['Delivery'] ??
          data['deliveryRequest'] ??
          data['DeliveryRequest'] ??
          data['request'] ??
          data['Request'];

      if (delivery is Map) {
        return Map<String, dynamic>.from(delivery);
      }

      final hasDeliveryShape =
          data.containsKey('id') ||
          data.containsKey('Id') ||
          data.containsKey('deliveryStatus') ||
          data.containsKey('DeliveryStatus') ||
          data.containsKey('deliveryOtpCode') ||
          data.containsKey('DeliveryOtpCode');

      if (hasDeliveryShape) {
        return Map<String, dynamic>.from(data);
      }
    }

    return null;
  }

  void _upsertDeliveryInMyDeliveries(
    Map<String, dynamic> delivery, {
    bool refreshUi = true,
  }) {
    final id = _firstNonEmpty([delivery['id'], delivery['Id']]);
    if (id.isEmpty) return;

    bool changed = false;

    final updatedDeliveries = _myDeliveries.map((item) {
      if (item is! Map) return item;

      final itemId = _firstNonEmpty([item['id'], item['Id']]);
      if (itemId != id) return item;

      changed = true;
      return _mergeDeliveryMaps(item, delivery);
    }).toList();

    if (!changed) return;

    if (!refreshUi || !mounted) {
      _myDeliveries = updatedDeliveries;
      return;
    }

    setState(() {
      _myDeliveries = updatedDeliveries;
    });
  }

  String _deliveryOtpCode(Map? item) {
    if (item == null) return '';

    return _firstNonEmpty([
      item['deliveryOtpCode'],
      item['DeliveryOtpCode'],
      item['deliveryOTPCode'],
      item['DeliveryOTPCode'],
      item['deliveryOtp'],
      item['DeliveryOtp'],
      item['deliveryOTP'],
      item['DeliveryOTP'],
      item['otpCode'],
      item['OtpCode'],
      item['otp'],
      item['Otp'],
    ]);
  }

  String _deliveryOtpExpiresOnText(Map? item) {
    if (item == null) return '';

    return _firstNonEmpty([
      item['deliveryOtpExpiresOn'],
      item['DeliveryOtpExpiresOn'],
      item['otpExpiresOn'],
      item['OtpExpiresOn'],
      item['otpExpiry'],
      item['OtpExpiry'],
      item['expiresOn'],
      item['ExpiresOn'],
    ]);
  }

  String _deliveryOtpUsedOnText(Map? item) {
    if (item == null) return '';

    return _firstNonEmpty([
      item['deliveryOtpUsedOn'],
      item['DeliveryOtpUsedOn'],
      item['otpUsedOn'],
      item['OtpUsedOn'],
      item['usedOn'],
      item['UsedOn'],
    ]);
  }

  bool _deliveryOtpAvailableFlag(Map? item) {
    if (item == null) return false;

    final value =
        item['deliveryOtpAvailable'] ??
        item['DeliveryOtpAvailable'] ??
        item['otpAvailable'] ??
        item['OtpAvailable'] ??
        item['hasDeliveryOtp'] ??
        item['HasDeliveryOtp'];

    return value == true || value?.toString().toLowerCase() == 'true';
  }

  int _deliveryStatusNumberForOtp(Map delivery) {
    final id = _firstNonEmpty([delivery['id'], delivery['Id']]);
    final activeId = _activeLiveTrackingDeliveryId ?? '';
    final trackedId = _firstNonEmpty([
      _trackedDelivery?['id'],
      _trackedDelivery?['Id'],
    ]);
    final isActiveTrackedDelivery = id.isNotEmpty &&
        (id == activeId || id == trackedId);

    return _statusNumber(
      (isActiveTrackedDelivery ? _liveDeliveryStatusCode : null) ??
          delivery['deliveryStatusCode'] ??
          delivery['DeliveryStatusCode'] ??
          delivery['deliveryStatus'] ??
          delivery['DeliveryStatus'] ??
          delivery['status'] ??
          delivery['Status'],
    );
  }

  bool _shouldShowDeliveryOtpPanel(Map delivery) {
    final statusNumber = _deliveryStatusNumberForOtp(delivery);

    if (statusNumber == 5) return _deliveryOtpUsedOnText(delivery).isNotEmpty;
    if (statusNumber == 6 || statusNumber == 7) return false;

    return statusNumber == 3 ||
        statusNumber == 4 ||
        _deliveryOtpCode(delivery).isNotEmpty ||
        _deliveryOtpAvailableFlag(delivery);
  }

  Future<void> _copyDeliveryOtp(String otp) async {
    await Clipboard.setData(ClipboardData(text: otp));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delivery OTP copied.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _refreshDeliveryForOtp({
    String? deliveryId,
    bool silent = true,
  }) async {
    final id =
        deliveryId?.trim().isNotEmpty == true
            ? deliveryId!.trim()
            : _activeLiveTrackingDeliveryId ??
                _trackedDelivery?['id']?.toString() ??
                _trackedDelivery?['Id']?.toString() ??
                '';

    if (id.isEmpty || _isRefreshingDeliveryOtp) return;

    if (mounted) {
      setState(() => _isRefreshingDeliveryOtp = true);
    } else {
      _isRefreshingDeliveryOtp = true;
    }

    try {
      final result = await _api
          .getDeliveryTracking(deliveryId: id)
          .timeout(AppConfig.networkTimeout);

      final deliveryFromTracking = _deliveryMapFromTrackingResult(result);
      if (deliveryFromTracking == null) return;

      final mergedDelivery = _mergeDeliveryMaps(
        _findDeliveryByInput(id) ?? _trackedDelivery,
        deliveryFromTracking,
      );

      if (!mounted) return;

      setState(() {
        _trackingResult = result;
        if (_activeLiveTrackingDeliveryId == id ||
            _trackedDelivery?['id']?.toString() == id ||
            _trackedDelivery?['Id']?.toString() == id) {
          _trackedDelivery = mergedDelivery;
        }
      });

      _upsertDeliveryInMyDeliveries(mergedDelivery);
    } catch (e) {
      debugPrint('[CustomerOTP] Failed to refresh delivery OTP: $e');

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not refresh delivery OTP: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      _lastDeliveryOtpRefreshAt = DateTime.now();

      if (mounted) {
        setState(() => _isRefreshingDeliveryOtp = false);
      } else {
        _isRefreshingDeliveryOtp = false;
      }
    }
  }

  void _refreshDeliveryOtpIfNeeded(int liveStatusCode) {
    if (liveStatusCode != 3 && liveStatusCode != 4) return;
    if (_deliveryOtpCode(_trackedDelivery).isNotEmpty) return;

    final now = DateTime.now();
    if (_lastDeliveryOtpRefreshAt != null &&
        now.difference(_lastDeliveryOtpRefreshAt!).inSeconds < 15) {
      return;
    }

    _lastDeliveryOtpRefreshAt = now;

    Future<void>.microtask(() async {
      await _refreshDeliveryForOtp(silent: true);
    });
  }

  String _upperFirst(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  LatLng? _latLngFromDynamicMap(
    Map item,
    List<String> latitudeKeys,
    List<String> longitudeKeys,
  ) {
    double? lat;
    double? lng;

    for (final key in latitudeKeys) {
      final value = item[key] ?? item[_upperFirst(key)];
      if (value == null) continue;
      lat = double.tryParse(value.toString());
      if (lat != null) break;
    }

    for (final key in longitudeKeys) {
      final value = item[key] ?? item[_upperFirst(key)];
      if (value == null) continue;
      lng = double.tryParse(value.toString());
      if (lng != null) break;
    }

    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    return LatLng(lat, lng);
  }

  DateTime? _dateTimeFromDynamicMap(Map item, List<String> keys) {
    for (final key in keys) {
      final value = item[key] ?? item[_upperFirst(key)];
      if (value == null) continue;
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  Map<String, dynamic>? _latestTrackingMapFromResult(dynamic result) {
    if (result is! Map) return null;

    final data = result['data'];

    if (data is List && data.isNotEmpty) {
      for (final item in data) {
        if (item is Map) return Map<String, dynamic>.from(item);
      }
    }

    if (data is Map) {
      final trackingUpdates =
          data['trackingUpdates'] ??
          data['TrackingUpdates'] ??
          data['tracking'] ??
          data['Tracking'];

      if (trackingUpdates is List && trackingUpdates.isNotEmpty) {
        for (final item in trackingUpdates) {
          if (item is Map) return Map<String, dynamic>.from(item);
        }
      }
    }

    return null;
  }

  void _seedMapFromLatestTrackingResult(String deliveryId, dynamic result) {
    final latestTracking = _latestTrackingMapFromResult(result);

    final riderLatLng = latestTracking == null
        ? null
        : _latLngFromDynamicMap(
            latestTracking,
            ['latitude', 'lat'],
            ['longitude', 'lng', 'lon'],
          );

    if (riderLatLng == null) {
      if (!mounted) return;
      setState(() {
        _activeLiveTrackingDeliveryId = deliveryId;
      });
      return;
    }

    final delivery = _trackedDelivery ?? {};

    final pickupLatLng = _latLngFromDynamicMap(
      delivery,
      ['pickupLatitude'],
      ['pickupLongitude'],
    );

    final dropoffLatLng = _latLngFromDynamicMap(
      delivery,
      ['dropoffLatitude'],
      ['dropoffLongitude'],
    );

    final routeDestination = _customerTrackingDestination(
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );

    final recordedOn = latestTracking == null
        ? null
        : _dateTimeFromDynamicMap(latestTracking, [
            'recordedOn',
            'updatedAt',
            'timestamp',
            'createdOn',
          ]);

    if (!mounted) return;

    setState(() {
      _activeLiveTrackingDeliveryId = deliveryId;
      _liveRiderLatLng = riderLatLng;
      _animatedRiderLatLng = riderLatLng;
      _riderBearing = routeDestination == null
          ? 0
          : _calculateBearing(riderLatLng, routeDestination);
      _livePickupLatLng = pickupLatLng;
      _liveDropoffLatLng = dropoffLatLng;
      _liveDeliveryStatusCode = _statusNumber(
        delivery['deliveryStatus'] ?? delivery['status'],
      );
      _liveDeliveryStatusText = _formatDeliveryStatus(
        delivery['deliveryStatus'] ?? delivery['status'],
      );
      _lastRiderLocationUpdate = recordedOn ?? DateTime.now();
      _liveRiderSignalRUpdateCount = 0;
      _trackingLocationSource = 'Last saved rider GPS';
      _currentRiderAddress = '';
      _lastReverseGeocodedRiderLatLng = null;
      _riderMovementPath = [riderLatLng];

      _liveTrackingMarkers = {
        Marker(
          markerId: const MarkerId('rider_live_location'),
          position: riderLatLng,
          infoWindow: const InfoWindow(title: 'Rider current location'),
          icon:
              _bikeMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: _riderBearing,
        ),
        if (pickupLatLng != null)
          Marker(
            markerId: const MarkerId('pickup_location'),
            position: pickupLatLng,
            infoWindow: const InfoWindow(title: 'Pickup location'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
          ),
        if (dropoffLatLng != null)
          Marker(
            markerId: const MarkerId('dropoff_location'),
            position: dropoffLatLng,
            infoWindow: const InfoWindow(title: 'Drop-off location'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
          ),
      };

      _liveTrackingPolylines = {};
    });

    debugPrint(
      '[CustomerMap] Seeded rider=${riderLatLng.latitude},${riderLatLng.longitude} '
      'pickup=${pickupLatLng?.latitude},${pickupLatLng?.longitude} '
      'dropoff=${dropoffLatLng?.latitude},${dropoffLatLng?.longitude}',
    );

    _refreshCustomerRoadRoutePolyline(
      riderLatLng: riderLatLng,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );

    _updateCurrentRiderAddress(riderLatLng);

    _focusTrackingRouteCamera(
      riderLatLng: riderLatLng,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );
  }

  Future<void> _trackDelivery() async {
    final rawInput = _trackingIdController.text.trim();

    if (rawInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a delivery ID to track.')),
      );
      return;
    }

    String deliveryId = rawInput;

    final isFullGuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(rawInput);

    Map<String, dynamic>? matchedDelivery = _findDeliveryByInput(rawInput);

    if (!isFullGuid && matchedDelivery == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Delivery not found. Enter the full delivery ID or tap Track from your request list.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (matchedDelivery != null) {
      final fullId = matchedDelivery['id']?.toString() ?? '';

      if (fullId.isNotEmpty) {
        deliveryId = fullId;
        _trackingIdController.text = fullId;
      }
    }

    setState(() {
      _isTracking = true;
      _trackingResult = null;
      _trackedDelivery = matchedDelivery;
      _liveRiderLatLng = null;
      _livePickupLatLng = null;
      _liveDropoffLatLng = null;
      _liveDeliveryStatusCode = null;
      _liveDeliveryStatusText = null;
      _liveTrackingMarkers = {};
      _liveTrackingPolylines = {};
      _riderMovementPath = [];
      _animatedRiderLatLng = null;
      _riderBearing = 0;
      _lastRiderLocationUpdate = null;
      _lastTrackingCameraMoveAt = null;
      _isTrackingMapReady = false;
      _liveRiderSignalRUpdateCount = 0;
      _isCustomerSignalRConnected = false;
      _trackingLocationSource = '';
      _currentRiderAddress = '';
      _lastReverseGeocodedRiderLatLng = null;
      _activeLiveTrackingDeliveryId = null;
    });

    try {
      final result = await _api
          .getDeliveryTracking(deliveryId: deliveryId)
          .timeout(AppConfig.networkTimeout);

      if (!mounted) return;

      final success = result['success'] == true;

      if (!success) {
        final message =
            result['message'] ??
            result['error'] ??
            'Tracking failed. Please check the delivery ID and try again.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.toString()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final deliveryFromTracking = _deliveryMapFromTrackingResult(result);
      final mergedTrackedDelivery = _mergeDeliveryMaps(
        matchedDelivery ?? _trackedDelivery,
        deliveryFromTracking ?? {'id': deliveryId, 'deliveryStatus': 'Pending'},
      );

      setState(() {
        _trackingResult = result;
        _trackedDelivery = mergedTrackedDelivery;
        _activeLiveTrackingDeliveryId = deliveryId;
      });

      _upsertDeliveryInMyDeliveries(mergedTrackedDelivery, refreshUi: false);

      _seedMapFromLatestTrackingResult(deliveryId, result);

      await _startCustomerSignalRTracking(deliveryId);
    } catch (e) {
      if (!mounted) return;

      debugPrint('Tracking failed: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tracking failed. Please check the delivery ID and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isTracking = false);
      }
    }
  }

  Future<void> _trackFromDelivery(Map item) async {
    final fullId = item['id']?.toString() ?? '';

    if (fullId.isEmpty) return;

    setState(() {
      _trackingIdController.text = fullId;
      _trackedDelivery = Map<String, dynamic>.from(item);
      _trackingResult = null;
    });

    _tabController.animateTo(1);

    await Future.delayed(const Duration(milliseconds: 250));

    if (mounted) {
      await _trackDelivery();
    }
  }

  Future<void> _startCustomerSignalRTracking(String deliveryRequestId) async {
    try {
      if (deliveryRequestId.trim().isEmpty) return;

      if (_activeLiveTrackingDeliveryId != null &&
          _activeLiveTrackingDeliveryId != deliveryRequestId) {
        await LogisticsTrackingSignalRService.instance
            .leaveDeliveryTrackingGroup(_activeLiveTrackingDeliveryId!);
      }

      if (mounted) {
        setState(() => _activeLiveTrackingDeliveryId = deliveryRequestId);
      }

      await LogisticsTrackingSignalRService.instance.connect(
        hubBaseUrl: _logisticsHubBaseUrl,
      );

      await LogisticsTrackingSignalRService.instance.joinDeliveryTrackingGroup(
        deliveryRequestId,
      );

      _activeLiveTrackingDeliveryId = deliveryRequestId;

      if (mounted) {
        setState(() => _isCustomerSignalRConnected = true);
      }

      await _riderLocationSubscription?.cancel();

      _riderLocationSubscription = LogisticsTrackingSignalRService
          .instance
          .onRiderLocationUpdated
          .listen((data) {
            final incomingDeliveryId =
                data['deliveryId']?.toString() ??
                data['DeliveryId']?.toString() ??
                data['deliveryRequestId']?.toString() ??
                data['DeliveryRequestId']?.toString() ??
                data['DeliveryRequestID']?.toString() ??
                '';

            if (incomingDeliveryId != deliveryRequestId) {
              debugPrint(
                '[CustomerSignalR] Ignored update for another delivery. '
                'incoming=$incomingDeliveryId active=$deliveryRequestId data=$data',
              );
              return;
            }

            _handleRiderLocationUpdate(data);
          });

      debugPrint('[CustomerSignalR] Joined delivery group $deliveryRequestId');
    } catch (e) {
      debugPrint('[CustomerSignalR] Failed to start tracking: $e');

      if (mounted) {
        setState(() => _isCustomerSignalRConnected = false);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Live tracking connection failed: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final startLat = start.latitude * math.pi / 180;
    final startLng = start.longitude * math.pi / 180;
    final endLat = end.latitude * math.pi / 180;
    final endLng = end.longitude * math.pi / 180;

    final dLng = endLng - startLng;

    final y = math.sin(dLng) * math.cos(endLat);
    final x =
        math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLng);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  LatLng _lerpLatLng(LatLng start, LatLng end, double t) {
    return LatLng(
      start.latitude + ((end.latitude - start.latitude) * t),
      start.longitude + ((end.longitude - start.longitude) * t),
    );
  }

  bool _isSameLatLng(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 0.000001 &&
        (a.longitude - b.longitude).abs() < 0.000001;
  }

  String _customerEtaText({
    required LatLng riderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
  }) {
    final target = _customerTrackingDestination(
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );

    if (target == null) return 'ETA calculating';

    final meters = Geolocator.distanceBetween(
      riderLatLng.latitude,
      riderLatLng.longitude,
      target.latitude,
      target.longitude,
    );

    const assumedBikeSpeedKmh = 25.0;
    final minutes = (meters / 1000) / assumedBikeSpeedKmh * 60;
    final rounded = minutes.clamp(1, 180).ceil();

    return '$rounded min';
  }

  void _focusTrackingRouteCamera({
    required LatLng riderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
  }) {
    if (!_isTrackingMapReady || _trackingMapController == null) return;

    final destination = _customerTrackingDestination(
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );

    if (_isFullScreenTrackingMap &&
        _customerMapCameraMode == _CustomerMapCameraMode.destination &&
        destination != null) {
      _moveTrackingCameraToDestination(destination);
      return;
    }

    if (_isFullScreenTrackingMap &&
        _customerMapCameraMode == _CustomerMapCameraMode.rider) {
      _moveTrackingCameraSafely(riderLatLng);
      return;
    }

    if (destination == null) {
      _moveTrackingCameraSafely(riderLatLng);
      return;
    }

    final roadRoutePoints = _liveTrackingPolylines
        .where(
          (polyline) =>
              polyline.polylineId.value == 'customer_road_route_to_destination',
        )
        .expand((polyline) => polyline.points)
        .toList();

    final routeMatchesDestination =
        roadRoutePoints.isNotEmpty &&
        Geolocator.distanceBetween(
              roadRoutePoints.last.latitude,
              roadRoutePoints.last.longitude,
              destination.latitude,
              destination.longitude,
            ) <
            500;

    final points = routeMatchesDestination
        ? <LatLng>[riderLatLng, ...roadRoutePoints, destination]
        : <LatLng>[riderLatLng, destination];

    final distanceToDestination = Geolocator.distanceBetween(
      riderLatLng.latitude,
      riderLatLng.longitude,
      destination.latitude,
      destination.longitude,
    );

    if (distanceToDestination < 40) {
      _moveTrackingCameraSafely(riderLatLng);
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || !_isTrackingMapReady || _trackingMapController == null) {
        return;
      }

      _trackingMapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 85),
      );
    });
  }

  // ===============================
  // UPDATED: Using GoogleMapsService
  // ===============================

  Future<List<LatLng>> _fetchCustomerDirectionsPolyline({
    required LatLng origin,
    required LatLng destination,
  }) async {
    return await _mapsService.getDirections(
      origin: origin,
      destination: destination,
    );
  }

  List<LatLng> _decodeCustomerPolyline(String encoded) {
    final points = <LatLng>[];

    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final dLat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final dLng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  Future<void> _refreshCustomerRoadRoutePolyline({
    required LatLng riderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
  }) async {
    final destination = _customerTrackingDestination(
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );

    if (destination == null) return;

    try {
      final routePoints = await _fetchCustomerDirectionsPolyline(
        origin: riderLatLng,
        destination: destination,
      );

      if (!mounted || routePoints.length < 2) {
        if (mounted) {
          setState(() {
            _liveTrackingPolylines = Set<Polyline>.from(_liveTrackingPolylines)
              ..removeWhere(
                (p) =>
                    p.polylineId.value ==
                        'customer_road_route_to_destination' ||
                    p.polylineId.value ==
                        'customer_road_route_to_destination_border' ||
                    p.polylineId.value == 'pickup_to_dropoff_preview' ||
                    p.polylineId.value == 'rider_to_dropoff' ||
                    p.polylineId.value == 'rider_to_dropoff_visible',
              );
          });
        }
        return;
      }

      setState(() {
        final existing = Set<Polyline>.from(_liveTrackingPolylines)
          ..removeWhere(
            (p) =>
                p.polylineId.value == 'customer_road_route_to_destination' ||
                p.polylineId.value ==
                    'customer_road_route_to_destination_border' ||
                p.polylineId.value == 'pickup_to_dropoff_preview' ||
                p.polylineId.value == 'rider_to_dropoff' ||
                p.polylineId.value == 'rider_to_dropoff_visible',
          );

        _liveTrackingPolylines = {
          ...existing,
          Polyline(
            polylineId: const PolylineId(
              'customer_road_route_to_destination_border',
            ),
            points: routePoints,
            width: 10,
            color: Colors.white,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 10,
          ),
          Polyline(
            polylineId: const PolylineId('customer_road_route_to_destination'),
            points: routePoints,
            width: 6,
            color: kPrimaryBlue,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 11,
          ),
        };
      });

      _focusTrackingRouteCamera(
        riderLatLng: riderLatLng,
        pickupLatLng: pickupLatLng,
        dropoffLatLng: dropoffLatLng,
      );
    } catch (e) {
      debugPrint('[CustomerMap] Road route fetch failed: $e');
    }
  }

  LatLng? _customerTrackingDestination({
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
  }) {
    final statusNumber = _statusNumber(
      _liveDeliveryStatusCode ??
          _liveDeliveryStatusText ??
          _trackedDelivery?['deliveryStatus'] ??
          _trackedDelivery?['status'],
    );

    if ((statusNumber == 3 || statusNumber == 4) && dropoffLatLng != null) {
      return dropoffLatLng;
    }

    return pickupLatLng ?? dropoffLatLng;
  }

  Set<Circle> _customerDestinationCircles() {
    final destination = _customerTrackingDestination(
      pickupLatLng: _livePickupLatLng,
      dropoffLatLng: _liveDropoffLatLng,
    );

    if (destination == null) return <Circle>{};

    return {
      Circle(
        circleId: const CircleId('customer_active_destination_outer'),
        center: destination,
        radius: 55,
        fillColor: Colors.transparent,
        strokeColor: kPrimaryColor.withOpacity(0.28),
        strokeWidth: 2,
        zIndex: 4,
      ),
      Circle(
        circleId: const CircleId('customer_active_destination_inner'),
        center: destination,
        radius: 30,
        fillColor: kAccentColor.withOpacity(0.14),
        strokeColor: kPrimaryColor.withOpacity(0.62),
        strokeWidth: 2,
        zIndex: 5,
      ),
    };
  }

  void _applyAnimatedRiderMapState({
    required LatLng displayRiderLatLng,
    required LatLng actualRiderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
    required DateTime updatedAt,
  }) {
    _animatedRiderLatLng = displayRiderLatLng;
    _liveRiderLatLng = actualRiderLatLng;
    _livePickupLatLng = pickupLatLng;
    _liveDropoffLatLng = dropoffLatLng;
    _lastRiderLocationUpdate = updatedAt;

    final visibleMovementPath = <LatLng>[
      ..._riderMovementPath,
      if (_riderMovementPath.isEmpty ||
          !_isSameLatLng(_riderMovementPath.last, displayRiderLatLng))
        displayRiderLatLng,
    ];

    _liveTrackingMarkers = {
      Marker(
        markerId: const MarkerId('rider_live_location'),
        position: displayRiderLatLng,
        infoWindow: const InfoWindow(title: 'Rider current location'),
        icon:
            _bikeMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: _riderBearing,
      ),
      if (pickupLatLng != null)
        Marker(
          markerId: const MarkerId('pickup_location'),
          position: pickupLatLng,
          infoWindow: const InfoWindow(title: 'Pickup location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      if (dropoffLatLng != null)
        Marker(
          markerId: const MarkerId('dropoff_location'),
          position: dropoffLatLng,
          infoWindow: const InfoWindow(title: 'Drop-off location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };

    final existingRoadRoute = _liveTrackingPolylines.where(
      (p) =>
          p.polylineId.value == 'customer_road_route_to_destination' ||
          p.polylineId.value == 'customer_road_route_to_destination_border',
    );

    _liveTrackingPolylines = {...existingRoadRoute};
  }

  Future<void> _animateBikeMarkerTo({
    required LatLng targetLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
    required DateTime updatedAt,
  }) async {
    final startLatLng =
        _animatedRiderLatLng ?? _liveRiderLatLng ?? targetLatLng;

    _bikeAnimationController?.stop();
    _bikeAnimationController?.dispose();
    _bikeAnimationController = null;

    if (_isSameLatLng(startLatLng, targetLatLng)) {
      if (!mounted) return;

      setState(() {
        _applyAnimatedRiderMapState(
          displayRiderLatLng: targetLatLng,
          actualRiderLatLng: targetLatLng,
          pickupLatLng: pickupLatLng,
          dropoffLatLng: dropoffLatLng,
          updatedAt: updatedAt,
        );
      });

      _focusTrackingRouteCamera(
        riderLatLng: targetLatLng,
        pickupLatLng: pickupLatLng,
        dropoffLatLng: dropoffLatLng,
      );
      return;
    }

    _riderBearing = _calculateBearing(startLatLng, targetLatLng);

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _bikeAnimationController = controller;

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    controller.addListener(() {
      if (!mounted) return;

      final movingLatLng = _lerpLatLng(
        startLatLng,
        targetLatLng,
        animation.value,
      );

      setState(() {
        _applyAnimatedRiderMapState(
          displayRiderLatLng: movingLatLng,
          actualRiderLatLng: targetLatLng,
          pickupLatLng: pickupLatLng,
          dropoffLatLng: dropoffLatLng,
          updatedAt: updatedAt,
        );
      });
    });

    try {
      await controller.forward();
    } finally {
      if (mounted) {
        setState(() {
          _applyAnimatedRiderMapState(
            displayRiderLatLng: targetLatLng,
            actualRiderLatLng: targetLatLng,
            pickupLatLng: pickupLatLng,
            dropoffLatLng: dropoffLatLng,
            updatedAt: updatedAt,
          );
        });
        _focusTrackingRouteCamera(
          riderLatLng: targetLatLng,
          pickupLatLng: pickupLatLng,
          dropoffLatLng: dropoffLatLng,
        );
      }

      if (_bikeAnimationController == controller) {
        _bikeAnimationController = null;
      }

      controller.dispose();
    }
  }

  void _handleRiderLocationUpdate(Map<String, dynamic> data) {
    final lat = double.tryParse(data['latitude']?.toString() ?? '');
    final lng = double.tryParse(data['longitude']?.toString() ?? '');

    if (lat == null || lng == null || lat == 0 || lng == 0) return;

    final riderLatLng = LatLng(lat, lng);

    final delivery = _trackedDelivery ?? {};

    final pickupLatLng =
        _livePickupLatLng ??
        _latLngFromDynamicMap(
          delivery,
          ['pickupLatitude'],
          ['pickupLongitude'],
        );

    final dropoffLatLng =
        _liveDropoffLatLng ??
        _latLngFromDynamicMap(
          delivery,
          ['dropoffLatitude'],
          ['dropoffLongitude'],
        );

    final liveStatusCode = _statusNumber(
      data['deliveryStatusCode'] ??
          data['statusCode'] ??
          data['deliveryStatus'] ??
          data['status'],
    );
    final liveStatusText =
        data['deliveryStatus']?.toString() ??
        data['status']?.toString() ??
        (liveStatusCode == 0 ? null : _formatDeliveryStatus(liveStatusCode));

    final updatedAt = DateTime.now();

    if (!mounted) return;

    if (_riderMovementPath.isEmpty ||
        !_isSameLatLng(_riderMovementPath.last, riderLatLng)) {
      _riderMovementPath.add(riderLatLng);
    }

    if (_riderMovementPath.length > 120) {
      _riderMovementPath.removeAt(0);
    }

    setState(() {
      _liveRiderSignalRUpdateCount += 1;
      _isCustomerSignalRConnected = true;
      _trackingLocationSource = 'Live SignalR update';
      if (liveStatusCode != 0) {
        _liveDeliveryStatusCode = liveStatusCode;
      }
      if (liveStatusText != null && liveStatusText.trim().isNotEmpty) {
        _liveDeliveryStatusText = liveStatusText.trim();
      }
    });

    _refreshDeliveryOtpIfNeeded(liveStatusCode);

    _animateBikeMarkerTo(
      targetLatLng: riderLatLng,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
      updatedAt: updatedAt,
    );

    _refreshCustomerRoadRoutePolyline(
      riderLatLng: riderLatLng,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );

    _updateCurrentRiderAddress(riderLatLng);

    debugPrint(
      '[CustomerSignalR] Rider moved lat=$lat lng=$lng '
      'pickup=${pickupLatLng?.latitude},${pickupLatLng?.longitude} '
      'dropoff=${dropoffLatLng?.latitude},${dropoffLatLng?.longitude} '
      'liveCount=$_liveRiderSignalRUpdateCount data=$data',
    );
  }

  void _moveTrackingCameraSafely(LatLng riderLatLng) {
    if (!_isTrackingMapReady || _trackingMapController == null) return;

    _lastTrackingCameraMoveAt = DateTime.now();

    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || !_isTrackingMapReady || _trackingMapController == null) {
        return;
      }

      _trackingMapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: riderLatLng,
            zoom: 16.5,
            bearing: _riderBearing,
            tilt: 18,
          ),
        ),
      );
    });
  }

  void _moveTrackingCameraToDestination(LatLng destination) {
    if (!_isTrackingMapReady || _trackingMapController == null) return;

    _lastTrackingCameraMoveAt = DateTime.now();

    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || !_isTrackingMapReady || _trackingMapController == null) {
        return;
      }

      _trackingMapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: destination, zoom: 16.2, bearing: 0, tilt: 0),
        ),
      );
    });
  }

  void _clearForm() {
    _senderNameController.clear();
    _senderPhoneController.clear();
    _pickupController.clear();
    _dropoffController.clear();
    _receiverNameController.clear();
    _receiverPhoneController.clear();
    _packageDescriptionController.clear();
    _packageWeightController.clear();
    _deliveryNoteController.clear();

    setState(() {
      _pickupLatLng = null;
      _dropoffLatLng = null;
      _addressSearchResults = [];
      _activeLocationTarget = null;
      _paymentPreference = _PaymentPreference.payOnline;
      _estimateErrorMessage = null;
      _estimatedDistanceKm = null;
      _estimatedDeliveryFee = null;
      _requiresManualQuote = false;
    });

    _prefillUserDetails();
  }

  // ===============================
  // UPDATED: Using GoogleMapsService
  // ===============================

  Future<void> _searchAddress(
    String query, {
    required _LocationTarget target,
  }) async {
    setState(() {
      _activeLocationTarget = target;
    });

    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }

    _debounce = Timer(AppConfig.debounceDelay, () async {
      final cleanQuery = query.trim();

      if (cleanQuery.length < 3) {
        if (!mounted) return;
        setState(() => _addressSearchResults = []);
        return;
      }

      setState(() => _isSearchingAddress = true);

      try {
        final results = await _mapsService.searchAddress(cleanQuery);
        setState(() => _addressSearchResults = results);
      } catch (e) {
        debugPrint('Google Places search error: $e');
        setState(() => _addressSearchResults = []);
      } finally {
        if (mounted) {
          setState(() => _isSearchingAddress = false);
        }
      }
    });
  }

  Future<void> _selectAddressSuggestion(Map<String, dynamic> result) async {
    final placeId = result['place_id']?.toString();
    final description = result['description']?.toString() ?? '';

    if (_activeLocationTarget == null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _addressSearchResults = [];
    });

    try {
      final resultLat = num.tryParse(result['lat']?.toString() ?? '');
      final resultLng = num.tryParse(result['lng']?.toString() ?? '');

      double? lat = resultLat?.toDouble();
      double? lng = resultLng?.toDouble();
      String address =
          result['formatted_address']?.toString().trim().isNotEmpty == true
              ? result['formatted_address'].toString()
              : description;

      if (lat == null || lng == null) {
        if (placeId == null || placeId.isEmpty) return;

        final details = await _mapsService.getPlaceDetails(placeId);
        if (details == null) return;

        final location = details['geometry']['location'];
        lat = (location['lat'] as num).toDouble();
        lng = (location['lng'] as num).toDouble();
        address = details['formatted_address']?.toString() ?? description;
      }

      final latLng = LatLng(lat, lng);

      setState(() {
        if (_activeLocationTarget == _LocationTarget.pickup) {
          _pickupController.text = address;
          _pickupLatLng = latLng;
        } else {
          _dropoffController.text = address;
          _dropoffLatLng = latLng;
        }
      });

      _scheduleDeliveryEstimate();
    } catch (e) {
      debugPrint('Google place details error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not select address: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _useCurrentLocation({required _LocationTarget target}) async {
    setState(() {
      if (target == _LocationTarget.pickup) {
        _isGettingPickupLocation = true;
      } else {
        _isGettingDropoffLocation = true;
      }
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception('Location service is disabled. Please turn on GPS.');
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission permanently denied. Enable it from app settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);
      final address = await _reverseGeocode(latLng);

      if (!mounted) return;

      setState(() {
        if (target == _LocationTarget.pickup) {
          _pickupLatLng = latLng;
          if (address.trim().isNotEmpty) {
            _pickupController.text = address;
          }
        } else {
          _dropoffLatLng = latLng;
          if (address.trim().isNotEmpty) {
            _dropoffController.text = address;
          }
        }

        _addressSearchResults = [];
        _activeLocationTarget = target;
      });

      _scheduleDeliveryEstimate();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            target == _LocationTarget.pickup
                ? 'Pickup GPS location captured.'
                : 'Drop-off GPS location captured.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get location: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (target == _LocationTarget.pickup) {
            _isGettingPickupLocation = false;
          } else {
            _isGettingDropoffLocation = false;
          }
        });
      }
    }
  }

  Future<String> _reverseGeocode(LatLng latLng) async {
    return await _mapsService.reverseGeocode(latLng);
  }

  Future<void> _updateCurrentRiderAddress(LatLng latLng) async {
    final last = _lastReverseGeocodedRiderLatLng;
    if (last != null) {
      final metersMoved = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        latLng.latitude,
        latLng.longitude,
      );

      if (metersMoved < 35 && _currentRiderAddress.trim().isNotEmpty) {
        return;
      }
    }

    final token = ++_riderAddressLookupToken;
    _lastReverseGeocodedRiderLatLng = latLng;

    if (mounted && _currentRiderAddress.trim().isEmpty) {
      setState(() => _currentRiderAddress = 'Resolving rider address...');
    }

    try {
      final address = await _reverseGeocode(latLng);
      if (!mounted || token != _riderAddressLookupToken) return;

      final cleanAddress = address.trim();
      setState(() {
        _currentRiderAddress = cleanAddress.isEmpty
            ? 'Rider is near ${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}'
            : cleanAddress;
      });
    } catch (_) {
      if (!mounted || token != _riderAddressLookupToken) return;
      setState(() {
        _currentRiderAddress =
            'Rider is near ${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
      });
    }
  }

  Future<void> _onMapTap({
    required _LocationTarget target,
    required LatLng latLng,
  }) async {
    final address = await _reverseGeocode(latLng);

    if (!mounted) return;

    setState(() {
      if (target == _LocationTarget.pickup) {
        _pickupLatLng = latLng;
        if (address.trim().isNotEmpty) {
          _pickupController.text = address;
        }
      } else {
        _dropoffLatLng = latLng;
        if (address.trim().isNotEmpty) {
          _dropoffController.text = address;
        }
      }
    });

    _scheduleDeliveryEstimate();
  }

  void _scheduleDeliveryEstimate() {
    _estimateDebounce?.cancel();

    if (_pickupLatLng == null || _dropoffLatLng == null) {
      if (mounted) {
        setState(() {
          _estimateErrorMessage = null;
          _estimatedDistanceKm = null;
          _estimatedDeliveryFee = null;
          _requiresManualQuote = false;
        });
      }
      return;
    }

    _estimateDebounce = Timer(
      AppConfig.estimateDebounceDelay,
      _calculateDeliveryEstimate,
    );
  }

  Future<void> _calculateDeliveryEstimate() async {
    final pickup = _pickupLatLng;
    final dropoff = _dropoffLatLng;

    if (pickup == null || dropoff == null) return;

    final weight = double.tryParse(_packageWeightController.text.trim()) ?? 0;

    setState(() {
      _isEstimatingDeliveryFee = true;
      _estimateErrorMessage = null;
    });

    try {
      final result = await _api
          .calculateDeliveryEstimate(
            pickupLatitude: pickup.latitude,
            pickupLongitude: pickup.longitude,
            dropoffLatitude: dropoff.latitude,
            dropoffLongitude: dropoff.longitude,
            packageWeightKg: weight,
          )
          .timeout(AppConfig.networkTimeout);

      if (!mounted) return;

      final data = result['data'] is Map ? result['data'] : result;

      if (result['success'] == true && data is Map) {
        final distance = _firstNumber(data, [
          'distanceKm',
          'distance_km',
          'distance',
          'totalDistanceKm',
          'total_distance_km',
        ]);
        final fee = _firstNumber(data, [
          'estimatedPrice',
          'estimated_price',
          'estimatedFee',
          'deliveryFee',
          'fee',
          'price',
          'amount',
        ]);
        final manualQuote =
            data['requiresManualQuote'] == true ||
            data['requiresManualQuote']?.toString().toLowerCase() == 'true';

        setState(() {
          _estimatedDistanceKm = distance?.toDouble();
          _estimatedDeliveryFee = fee;
          _requiresManualQuote = manualQuote;
          _estimateErrorMessage = null;
        });
      } else {
        final message =
            result['message'] ??
            result['error'] ??
            'Could not calculate delivery fee.';

        setState(() {
          _estimateErrorMessage = message.toString();
          _estimatedDistanceKm = null;
          _estimatedDeliveryFee = null;
          _requiresManualQuote = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _estimateErrorMessage = e.toString().replaceFirst('Exception: ', '');
        _estimatedDistanceKm = null;
        _estimatedDeliveryFee = null;
        _requiresManualQuote = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isEstimatingDeliveryFee = false);
      }
    }
  }

  num? _firstNumber(Map<dynamic, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value;

      final parsed = num.tryParse(
        value?.toString().replaceAll(',', '').trim() ?? '',
      );
      if (parsed != null) return parsed;
    }

    return null;
  }

  bool _isValidPhone(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    final internationalPattern = RegExp(r'^\+[1-9]\d{7,14}$');
    final nigeriaLocalPattern = RegExp(r'^(070|080|081|090|091)\d{8}$');

    return internationalPattern.hasMatch(cleaned) ||
        nigeriaLocalPattern.hasMatch(cleaned);
  }

  String? _phoneValidator(String? value) {
    final phone = value?.trim() ?? '';

    if (phone.isEmpty) {
      return 'Enter phone number';
    }

    if (!_isValidPhone(phone)) {
      return 'Enter a valid phone number, e.g. +2348012345678 or 08012345678';
    }

    return null;
  }

  String? _requiredValidator(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }

    return null;
  }

  Set<Marker> _buildMarkers({
    required _LocationTarget target,
    required LatLng latLng,
  }) {
    return {
      Marker(
        markerId: MarkerId(
          target == _LocationTarget.pickup
              ? 'pickup_location'
              : 'dropoff_location',
        ),
        position: latLng,
        infoWindow: InfoWindow(
          title: target == _LocationTarget.pickup
              ? 'Pickup Location'
              : 'Drop-off Location',
        ),
      ),
    };
  }

  int _statusNumber(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;

    final text = value.toString().trim().toLowerCase();
    final parsed = int.tryParse(text);

    if (parsed != null) return parsed;

    if (text.contains('confirmed')) return 1;
    if (text.contains('assigned')) return 2;
    if (text.contains('picked')) return 3;
    if (text.contains('transit')) return 4;
    if (text.contains('delivered') || text.contains('completed')) return 5;
    if (text.contains('cancel')) return 6;
    if (text.contains('failed')) return 7;

    return 0;
  }

  String _formatDeliveryStatus(dynamic value) {
    switch (_statusNumber(value)) {
      case 0:
        return 'Pending';
      case 1:
        return 'Confirmed';
      case 2:
        return 'Rider Assigned';
      case 3:
        return 'Picked Up';
      case 4:
        return 'In Transit';
      case 5:
        return 'Delivered';
      case 6:
        return 'Cancelled';
      case 7:
        return 'Failed';
      default:
        return 'Pending';
    }
  }

  String _formatPaymentStatus(dynamic value) {
    if (value == null) return 'Unpaid';

    final text = value.toString();

    switch (text) {
      case '0':
        return 'Unpaid';
      case '1':
        return 'Pending';
      case '2':
        return 'Paid';
      case '3':
        return 'Refunded';
      default:
        return text;
    }
  }

  bool _isPayOnDelivery(Map item) {
    final note = item['deliveryNote']?.toString().toLowerCase() ?? '';
    final paymentMethod = item['paymentMethod']?.toString().toLowerCase() ?? '';
    final paymentOption = item['paymentOption']?.toString().toLowerCase() ?? '';

    return note.contains('pay on delivery') ||
        note.contains('payment on delivery') ||
        note.contains('cash on delivery') ||
        paymentMethod.contains('pay on delivery') ||
        paymentMethod.contains('payment on delivery') ||
        paymentMethod.contains('cash') ||
        paymentOption.contains('pay on delivery') ||
        paymentOption.contains('payment on delivery') ||
        paymentOption.contains('cash');
  }

  String _paymentDisplayText(Map item) {
    final paymentStatus = _formatPaymentStatus(item['paymentStatus']);

    if (_isPayOnDelivery(item) &&
        paymentStatus.toLowerCase() != 'paid' &&
        paymentStatus.toLowerCase() != 'refunded') {
      return 'Pay on Delivery';
    }

    return paymentStatus;
  }

  bool _canPay(Map item) {
    final paymentStatus = _formatPaymentStatus(
      item['paymentStatus'],
    ).toLowerCase();

    if (paymentStatus == 'paid') return false;
    if (paymentStatus == 'refunded') return false;

    final price = _deliveryPriceText(item);
    final hasPayablePrice = price != 'Awaiting quote' && price.trim() != '-';

    if (!hasPayablePrice) return false;

    if (_isPayOnDelivery(item)) {
      final deliveryStatus = _formatDeliveryStatus(
        item['deliveryStatus'] ?? item['status'],
      ).toLowerCase();

      return deliveryStatus.contains('delivered') ||
          deliveryStatus.contains('completed');
    }

    return true;
  }

  String _payButtonText(Map item) {
    if (_isPayOnDelivery(item)) {
      final deliveryStatus = _formatDeliveryStatus(
        item['deliveryStatus'] ?? item['status'],
      ).toLowerCase();

      if (deliveryStatus.contains('delivered') ||
          deliveryStatus.contains('completed')) {
        return 'Pay Now';
      }

      return 'Pay after delivery';
    }

    return 'Pay';
  }

  String _paymentUnavailableText(Map item) {
    if (_isPayOnDelivery(item)) {
      final deliveryStatus = _formatDeliveryStatus(
        item['deliveryStatus'] ?? item['status'],
      ).toLowerCase();

      if (deliveryStatus.contains('delivered') ||
          deliveryStatus.contains('completed')) {
        return 'Payment is available for this delivered request.';
      }

      return 'This request is set for Pay on Delivery. Payment will be available after delivery is completed.';
    }

    return 'Payment will be available once the delivery price is set.';
  }

  String _shortDeliveryId(String id) {
    return id.length >= 8 ? id.substring(0, 8).toUpperCase() : id;
  }

  Color _statusColor(String status) {
    final lower = status.toLowerCase();

    if (lower.contains('delivered')) return kSkyCyan;
    if (lower.contains('transit')) return kDotAmber;
    if (lower.contains('assigned')) return kDotNavy;
    if (lower.contains('picked')) return kAccentBlue;
    if (lower.contains('confirmed')) return kPrimaryBlue;
    if (lower.contains('cancel') || lower.contains('failed')) return kDotRed;

    return kDotAmber;
  }

  Color _paymentColor(String paymentStatus) {
    final lower = paymentStatus.toLowerCase();

    if (lower == 'paid') return kSkyCyan;
    if (lower == 'pending') return kDotAmber;
    if (lower.contains('pay on delivery')) return kPrimaryBlue;
    if (lower == 'refunded') return kDotNavy;
    return kDotRed;
  }

  String _moneyText(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '-';

    final parsed = num.tryParse(value.toString());

    if (parsed == null) return value.toString();

    return '₦${parsed.toStringAsFixed(0)}';
  }

  String _deliveryPriceText(Map item) {
    final finalPrice = item['finalPrice'];
    final estimatedPrice = item['estimatedPrice'];
    final quotedPrice = item['price'];
    final amount = item['amount'];

    if (finalPrice != null && finalPrice.toString().trim().isNotEmpty) {
      return _moneyText(finalPrice);
    }

    if (estimatedPrice != null && estimatedPrice.toString().trim().isNotEmpty) {
      return _moneyText(estimatedPrice);
    }

    if (quotedPrice != null && quotedPrice.toString().trim().isNotEmpty) {
      return _moneyText(quotedPrice);
    }

    if (amount != null && amount.toString().trim().isNotEmpty) {
      return _moneyText(amount);
    }

    return 'Awaiting quote';
  }

  Map? _latestAssignment(Map item) {
    final activeAssignment =
        item['activeAssignment'] ??
        item['ActiveAssignment'] ??
        item['currentAssignment'] ??
        item['CurrentAssignment'] ??
        item['assignment'] ??
        item['Assignment'];

    if (activeAssignment is Map) {
      return activeAssignment;
    }

    final assignedRider =
        item['assignedRider'] ??
        item['AssignedRider'] ??
        item['rider'] ??
        item['Rider'];

    if (assignedRider is Map) {
      return {'rider': assignedRider, 'isActive': true};
    }

    final assignments = item['assignments'] ?? item['Assignments'];

    if (assignments is! List || assignments.isEmpty) return null;

    final active = assignments.where((x) {
      if (x is! Map) return false;
      final isActive = x['isActive'] ?? x['IsActive'];
      return isActive == true || isActive?.toString().toLowerCase() == 'true';
    }).toList();

    final selected = active.isNotEmpty ? active.first : assignments.last;

    if (selected is Map) return selected;
    return null;
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }

  String _assignedRiderName(Map item) {
    final latest = _latestAssignment(item);

    if (latest != null) {
      final rider =
          latest['rider'] ??
          latest['Rider'] ??
          latest['assignedRider'] ??
          latest['AssignedRider'];

      if (rider is Map) {
        final name = _firstNonEmpty([
          rider['fullName'],
          rider['FullName'],
          rider['name'],
          rider['Name'],
          rider['riderName'],
          rider['RiderName'],
        ]);

        if (name.isNotEmpty) return name;
      }

      final name = _firstNonEmpty([
        latest['riderName'],
        latest['RiderName'],
        latest['assignedRiderName'],
        latest['AssignedRiderName'],
        latest['fullName'],
        latest['FullName'],
        latest['name'],
        latest['Name'],
      ]);

      if (name.isNotEmpty) return name;
    }

    return _firstNonEmpty([
      item['riderName'],
      item['RiderName'],
      item['assignedRiderName'],
      item['AssignedRiderName'],
      item['riderFullName'],
      item['RiderFullName'],
      item['assignedToName'],
      item['AssignedToName'],
    ]);
  }

  String _assignedRiderPhone(Map item) {
    final latest = _latestAssignment(item);

    if (latest != null) {
      final rider =
          latest['rider'] ??
          latest['Rider'] ??
          latest['assignedRider'] ??
          latest['AssignedRider'];

      if (rider is Map) {
        final phone = _firstNonEmpty([
          rider['phoneNumber'],
          rider['PhoneNumber'],
          rider['phone'],
          rider['Phone'],
          rider['riderPhone'],
          rider['RiderPhone'],
          rider['ridePhone'],
          rider['RidePhone'],
        ]);

        if (phone.isNotEmpty) return phone;
      }

      final phone = _firstNonEmpty([
        latest['riderPhone'],
        latest['RiderPhone'],
        latest['ridePhone'],
        latest['RidePhone'],
        latest['assignedRiderPhone'],
        latest['AssignedRiderPhone'],
        latest['phoneNumber'],
        latest['PhoneNumber'],
        latest['phone'],
        latest['Phone'],
      ]);

      if (phone.isNotEmpty) return phone;
    }

    final assignments = item['assignments'] ?? item['Assignments'];

    if (assignments is List && assignments.isNotEmpty) {
      final active = assignments.where((x) {
        if (x is! Map) return false;
        final isActive = x['isActive'] ?? x['IsActive'];
        return isActive == true || isActive?.toString().toLowerCase() == 'true';
      }).toList();

      final selected = active.isNotEmpty ? active.first : assignments.first;

      if (selected is Map) {
        final rider = selected['rider'] ?? selected['Rider'];

        if (rider is Map) {
          final phone = _firstNonEmpty([
            rider['phoneNumber'],
            rider['PhoneNumber'],
            rider['phone'],
            rider['Phone'],
            rider['riderPhone'],
            rider['RiderPhone'],
            rider['ridePhone'],
            rider['RidePhone'],
          ]);

          if (phone.isNotEmpty) return phone;
        }

        final phone = _firstNonEmpty([
          selected['riderPhone'],
          selected['RiderPhone'],
          selected['ridePhone'],
          selected['RidePhone'],
          selected['assignedRiderPhone'],
          selected['AssignedRiderPhone'],
          selected['phoneNumber'],
          selected['PhoneNumber'],
          selected['phone'],
          selected['Phone'],
        ]);

        if (phone.isNotEmpty) return phone;
      }
    }

    return _firstNonEmpty([
      item['riderPhone'],
      item['RiderPhone'],
      item['ridePhone'],
      item['RidePhone'],
      item['assignedRiderPhone'],
      item['AssignedRiderPhone'],
      item['riderPhoneNumber'],
      item['RiderPhoneNumber'],
      item['assignedToPhone'],
      item['AssignedToPhone'],
    ]);
  }

  String _riderDisplayText(Map item) {
    final riderName = _assignedRiderName(item);
    final riderPhone = _assignedRiderPhone(item);

    if (riderName.isNotEmpty || riderPhone.isNotEmpty) {
      return '$riderName${riderPhone.isNotEmpty ? ' • $riderPhone' : ''}';
    }

    final status = _formatDeliveryStatus(
      item['deliveryStatus'] ?? item['status'],
    );

    if (status.toLowerCase().contains('assigned') ||
        status.toLowerCase().contains('picked') ||
        status.toLowerCase().contains('transit')) {
      return 'Assigned rider details not available yet';
    }

    return '';
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';

    final text = value.toString();

    if (text.trim().isEmpty) return '';

    final parsed = DateTime.tryParse(text);

    if (parsed == null) return text;

    final local = parsed.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  List<Map<String, dynamic>> _timelineItems(Map delivery) {
    final items = <Map<String, dynamic>>[];

    final statusHistories = delivery['statusHistories'];

    if (statusHistories is List) {
      for (final item in statusHistories) {
        if (item is! Map) continue;

        final status = _formatDeliveryStatus(
          item['status'] ?? item['deliveryStatus'],
        );

        final note =
            item['note']?.toString() ??
            item['message']?.toString() ??
            'Status updated';

        final createdOn = item['createdOn'] ?? item['timestamp'];

        items.add({'title': status, 'message': note, 'date': createdOn});
      }
    }

    final trackingUpdates = delivery['trackingUpdates'];

    if (trackingUpdates is List) {
      for (final item in trackingUpdates) {
        if (item is! Map) continue;

        final message =
            item['message']?.toString() ??
            item['status']?.toString() ??
            'Tracking update';

        final createdOn = item['createdOn'] ?? item['timestamp'];

        items.add({
          'title': 'Tracking Update',
          'message': message,
          'date': createdOn,
        });
      }
    }

    final trackingData = _trackingResult?['data'];

    if (trackingData is List) {
      for (final item in trackingData) {
        if (item is! Map) continue;

        final message =
            item['message']?.toString() ??
            item['status']?.toString() ??
            'Tracking update';

        final createdOn = item['createdOn'] ?? item['timestamp'];

        items.add({
          'title': 'Tracking Update',
          'message': message,
          'date': createdOn,
        });
      }
    }

    if (items.isEmpty) {
      final createdOn = delivery['createdOn'];

      items.add({
        'title': _formatDeliveryStatus(
          delivery['deliveryStatus'] ?? delivery['status'],
        ),
        'message':
            'Your delivery request has been received and is being processed.',
        'date': createdOn,
      });
    }

    return items;
  }

  double _statusProgress(dynamic value) {
    final status = _statusNumber(value);

    if (status <= 0) return 0.15;
    if (status == 1) return 0.30;
    if (status == 2) return 0.45;
    if (status == 3) return 0.60;
    if (status == 4) return 0.80;
    if (status == 5) return 1.00;

    return 0.10;
  }

  void _openFullScreenTrackingMap() {
    final rider = _animatedRiderLatLng ?? _liveRiderLatLng;
    if (rider == null) return;

    setState(() {
      _trackingMapController = null;
      _isTrackingMapReady = false;
      _customerMapCameraMode = _CustomerMapCameraMode.routeOverview;
      _isFullScreenTrackingMap = true;
    });
  }

  void _closeFullScreenTrackingMap() {
    setState(() {
      _trackingMapController = null;
      _isTrackingMapReady = false;
      _customerMapCameraMode = _CustomerMapCameraMode.routeOverview;
      _isFullScreenTrackingMap = false;
    });
  }

  void _focusFullScreenCustomerDestination() {
    final destination = _customerTrackingDestination(
      pickupLatLng: _livePickupLatLng,
      dropoffLatLng: _liveDropoffLatLng,
    );
    if (destination == null) return;

    setState(() => _customerMapCameraMode = _CustomerMapCameraMode.destination);
    _moveTrackingCameraToDestination(destination);
  }

  void _focusFullScreenRider() {
    final rider = _animatedRiderLatLng ?? _liveRiderLatLng;
    if (rider == null) return;

    setState(() => _customerMapCameraMode = _CustomerMapCameraMode.rider);
    _moveTrackingCameraSafely(rider);
  }

  void _showFullScreenRouteOverview() {
    final rider = _animatedRiderLatLng ?? _liveRiderLatLng;
    if (rider == null) return;

    setState(
      () => _customerMapCameraMode = _CustomerMapCameraMode.routeOverview,
    );
    _focusTrackingRouteCamera(
      riderLatLng: rider,
      pickupLatLng: _livePickupLatLng,
      dropoffLatLng: _liveDropoffLatLng,
    );
  }

  Widget _fullScreenMapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    return Material(
      color: selected ? kPrimaryColor : kSurfaceWhite,
      borderRadius: BorderRadius.circular(8),
      elevation: 5,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: selected ? Colors.white : kPrimaryColor,
      ),
    );
  }

  Widget _buildFullScreenTrackingMap() {
    final rider = _animatedRiderLatLng ?? _liveRiderLatLng;
    final fallback = rider ?? _livePickupLatLng ?? _liveDropoffLatLng;
    final destination = _customerTrackingDestination(
      pickupLatLng: _livePickupLatLng,
      dropoffLatLng: _liveDropoffLatLng,
    );
    final initialMapTarget = rider ?? destination ?? fallback;
    final eta = rider == null
        ? 'Calculating'
        : _customerEtaText(
            riderLatLng: rider,
            pickupLatLng: _livePickupLatLng,
            dropoffLatLng: _liveDropoffLatLng,
          );
    final statusNumber = _statusNumber(
      _liveDeliveryStatusCode ??
          _liveDeliveryStatusText ??
          _trackedDelivery?['deliveryStatus'] ??
          _trackedDelivery?['status'],
    );
    final routeLabel = statusNumber == 3 || statusNumber == 4
        ? 'Rider heading to the delivery destination'
        : 'Rider heading to your pickup point';
    final address = _currentRiderAddress.trim().isEmpty
        ? 'Locating rider on the road...'
        : _currentRiderAddress.trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeFullScreenTrackingMap();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: kBackgroundLight,
          body: Stack(
            children: [
              Positioned.fill(
                child: initialMapTarget == null
                    ? const Center(child: CircularProgressIndicator())
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: initialMapTarget,
                          zoom: 16,
                        ),
                        markers: _liveTrackingMarkers,
                        polylines: _liveTrackingPolylines,
                        circles: _customerDestinationCircles(),
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: true,
                        buildingsEnabled: false,
                        trafficEnabled: false,
                        rotateGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                        minMaxZoomPreference: const MinMaxZoomPreference(
                          11,
                          20,
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 92, 12, 170),
                        onMapCreated: (controller) async {
                          _trackingMapController = controller;
                          _isTrackingMapReady = true;
                          try {
                            await controller.setMapStyle(
                              _focusedTrackingMapStyle,
                            );
                          } catch (_) {}
                          if (rider != null) {
                            _focusTrackingRouteCamera(
                              riderLatLng: rider,
                              pickupLatLng: _livePickupLatLng,
                              dropoffLatLng: _liveDropoffLatLng,
                            );
                          }
                        },
                      ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _fullScreenMapButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Close full-screen map',
                          onPressed: _closeFullScreenTrackingMap,
                        ),
                      ),
                      Positioned(
                        left: 68,
                        top: 15,
                        child: _premiumMapChip(
                          text: _trackingSourceLabel,
                          live: _hasConfirmedLiveSignalRUpdate,
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Column(
                          children: [
                            _fullScreenMapButton(
                              icon: Icons.route_rounded,
                              tooltip: 'Show complete route',
                              onPressed: _showFullScreenRouteOverview,
                              selected:
                                  _customerMapCameraMode ==
                                  _CustomerMapCameraMode.routeOverview,
                            ),
                            const SizedBox(height: 10),
                            _fullScreenMapButton(
                              icon: Icons.electric_bike_rounded,
                              tooltip: 'Focus rider and current street',
                              onPressed: _focusFullScreenRider,
                              selected:
                                  _customerMapCameraMode ==
                                  _CustomerMapCameraMode.rider,
                            ),
                            const SizedBox(height: 10),
                            _fullScreenMapButton(
                              icon: Icons.person_pin_circle_rounded,
                              tooltip: 'Focus your active location',
                              onPressed: _focusFullScreenCustomerDestination,
                              selected:
                                  _customerMapCameraMode ==
                                  _CustomerMapCameraMode.destination,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: kSurfaceWhite,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kBorderLight),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF6FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.electric_bike_rounded,
                                      color: kPrimaryColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          routeLabel,
                                          style: const TextStyle(
                                            color: kTextPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          address,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: kTextSecondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    eta,
                                    style: const TextStyle(
                                      color: kPrimaryColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreenTrackingMap) {
      return _buildFullScreenTrackingMap();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: kSurfaceWhite,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: kBackgroundLight,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildPremiumHeader(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSendTab(),
                    _buildTrackTab(),
                    _buildRequestsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumHeader() {
    final canGoBack = Navigator.canPop(context);

    return FadeTransition(
      opacity: _headerFadeAnimation,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: kSurfaceWhite,
          border: const Border(bottom: BorderSide(color: kBorderLight)),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          child: Column(
            children: [
              Row(
                children: [
                  _glassIconButton(
                    icon: canGoBack
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.local_shipping_rounded,
                    onTap: canGoBack ? () => Navigator.pop(context) : null,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TellMe Logistics',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kTextPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Dispatch, track, and pay from one clean desk',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isCheckingRiderAccess)
                    const SizedBox(
                      width: 42,
                      height: 42,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kPrimaryColor,
                          ),
                        ),
                      ),
                    )
                  else if (_loggedInRider != null)
                    _glassIconButton(
                      icon: Icons.electric_bike_rounded,
                      onTap: _openRiderJobsPage,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _buildPremiumStatsRow(),
              const SizedBox(height: 14),
              _buildPremiumTabBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassIconButton({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F8FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorderLight),
          ),
          child: Icon(icon, color: kPrimaryColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildPremiumStatsRow() {
    final activeRequests = _myDeliveries.where((item) {
      if (item is! Map) return false;
      final status = _formatDeliveryStatus(
        item['deliveryStatus'] ?? item['status'],
      ).toLowerCase();
      return !status.contains('delivered') &&
          !status.contains('completed') &&
          !status.contains('cancel') &&
          !status.contains('failed');
    }).length;

    return Row(
      children: [
        Expanded(
          child: _premiumMetricPill(
            icon: Icons.flash_on_rounded,
            label: 'Booking',
            value: 'Instant',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _premiumMetricPill(
            icon: Icons.sensors_rounded,
            label: 'Tracking',
            value: _isCustomerSignalRConnected ? 'Live' : 'Ready',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _premiumMetricPill(
            icon: Icons.route_rounded,
            label: 'Active',
            value: '$activeRequests',
          ),
        ),
      ],
    );
  }

  Widget _premiumMetricPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumTabBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F3FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: kPrimaryColor,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.16),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: kTextSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.add_road_rounded, size: 18), text: 'Book'),
          Tab(icon: Icon(Icons.radar_rounded, size: 18), text: 'Track'),
          Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Orders'),
        ],
      ),
    );
  }

  // Send Tab
  Widget _buildSendTab() {
    return _premiumPageScroll(
      children: [
        _buildPremiumHeroCard(),
        const SizedBox(height: 16),
        _buildPremiumForm(),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildTrackTab() {
    return _premiumPageScroll(
      children: [_buildPremiumTrackingCard(), const SizedBox(height: 30)],
    );
  }

  Widget _buildRequestsTab() {
    return RefreshIndicator(
      color: kHighlightColor,
      onRefresh: _loadMyDeliveries,
      child: _premiumPageScroll(
        alwaysScrollable: true,
        children: [_buildPremiumHistoryCard(), const SizedBox(height: 30)],
      ),
    );
  }

  Widget _premiumPageScroll({
    required List<Widget> children,
    bool alwaysScrollable = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(constraints.maxWidth, 640.0);
        return ListView(
          physics: alwaysScrollable
              ? const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                )
              : const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            (constraints.maxWidth - maxWidth) / 2 + 16,
            16,
            (constraints.maxWidth - maxWidth) / 2 + 16,
            30,
          ),
          children: children,
        );
      },
    );
  }

  // Premium Hero Card
  Widget _buildPremiumHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kSecondaryColor, kPrimaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderLight),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: kHighlightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.near_me_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Book a delivery run',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Clear pricing, live rider movement, and secure payment.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFD7E8FF),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.route_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Add pickup, drop-off, package details, then confirm in one flow.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFEFF8FF),
                      fontWeight: FontWeight.w600,
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

  // Premium Form
  Widget _buildPremiumForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _premiumSectionCard(
            icon: Icons.person_rounded,
            title: 'Sender Details',
            subtitle: 'Contact info for the person sending the package',
            children: [
              _premiumTextField(
                controller: _senderNameController,
                label: 'Full name',
                icon: Icons.badge_rounded,
                validator: (v) => _requiredValidator(v, 'Enter sender name'),
              ),
              const SizedBox(height: 12),
              _premiumTextField(
                controller: _senderPhoneController,
                label: 'Phone number',
                icon: Icons.call_rounded,
                keyboardType: TextInputType.phone,
                validator: _phoneValidator,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _premiumSectionCard(
            icon: Icons.route_rounded,
            title: 'Route Details',
            subtitle: 'Where should we pick up and deliver?',
            children: [
              _premiumStepIndicator(
                number: '1',
                title: 'Pickup point',
                color: kHighlightColor,
              ),
              const SizedBox(height: 10),
              _premiumLocationField(
                target: _LocationTarget.pickup,
                controller: _pickupController,
                focusNode: _pickupFocusNode,
                label: 'Pickup address',
              ),
              _buildPremiumAddressSuggestions(_LocationTarget.pickup),
              const SizedBox(height: 10),
              _premiumLocationActions(_LocationTarget.pickup),
              const SizedBox(height: 12),
              if (_pickupLatLng != null)
                _premiumMiniMap(
                  target: _LocationTarget.pickup,
                  latLng: _pickupLatLng!,
                ),
              const SizedBox(height: 16),
              _premiumStepIndicator(
                number: '2',
                title: 'Drop-off point',
                color: kSuccessGreen,
              ),
              const SizedBox(height: 10),
              _premiumLocationField(
                target: _LocationTarget.dropoff,
                controller: _dropoffController,
                focusNode: _dropoffFocusNode,
                label: 'Drop-off address',
              ),
              _buildPremiumAddressSuggestions(_LocationTarget.dropoff),
              const SizedBox(height: 10),
              _premiumLocationActions(_LocationTarget.dropoff),
              const SizedBox(height: 12),
              if (_dropoffLatLng != null)
                _premiumMiniMap(
                  target: _LocationTarget.dropoff,
                  latLng: _dropoffLatLng!,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _premiumSectionCard(
            icon: Icons.person_pin_rounded,
            title: 'Receiver Details',
            subtitle: 'Who will receive the package?',
            children: [
              _premiumTextField(
                controller: _receiverNameController,
                label: 'Full name',
                icon: Icons.person_pin_rounded,
                validator: (v) => _requiredValidator(v, 'Enter receiver name'),
              ),
              const SizedBox(height: 12),
              _premiumTextField(
                controller: _receiverPhoneController,
                label: 'Phone number',
                icon: Icons.smartphone_rounded,
                keyboardType: TextInputType.phone,
                validator: _phoneValidator,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _premiumSectionCard(
            icon: Icons.inventory_2_rounded,
            title: 'Package Info',
            subtitle: 'Details help us serve you better',
            children: [
              _premiumTextField(
                controller: _packageDescriptionController,
                label: 'Description',
                icon: Icons.description_rounded,
                maxLines: 2,
                validator: (v) => _requiredValidator(v, 'Describe the package'),
              ),
              const SizedBox(height: 12),
              _premiumTextField(
                controller: _packageWeightController,
                label: 'Weight (kg)',
                icon: Icons.scale_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isEmpty) return 'Enter weight';
                  final weight = double.tryParse(text);
                  if (weight == null || weight <= 0)
                    return 'Enter valid weight';
                  return null;
                },
                onChanged: (_) => _scheduleDeliveryEstimate(),
              ),
              const SizedBox(height: 12),
              _premiumTextField(
                controller: _deliveryNoteController,
                label: 'Special instructions',
                icon: Icons.note_alt_rounded,
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPremiumEstimateCard(),
          const SizedBox(height: 14),
          _buildPremiumPaymentSelector(),
          const SizedBox(height: 20),
          _premiumPrimaryButton(
            label: _isSubmitting ? 'Processing...' : 'Confirm Shipment',
            icon: Icons.rocket_launch_rounded,
            isLoading: _isSubmitting,
            onPressed: _isSubmitting ? null : _submitDeliveryRequest,
          ),
        ],
      ),
    );
  }

  Widget _premiumSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: kSurfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderLight),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF6FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: kPrimaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kTextPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: kTextSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _premiumStepIndicator({
    required String number,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: kTextPrimary,
          ),
        ),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: 12),
            child: Divider(color: kBorderLight, thickness: 1),
          ),
        ),
      ],
    );
  }

  Widget _premiumTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      maxLines: maxLines,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: kTextPrimary,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: kTextSecondary,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6FF),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: kPrimaryColor, size: 20),
        ),
        filled: true,
        fillColor: const Color(0xFFFBFDFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kHighlightColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kHighlightColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _premiumLocationField({
    required _LocationTarget target,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      onChanged: (value) => _searchAddress(value, target: target),
      validator: (value) => _requiredValidator(value, 'Enter $label'),
      textInputAction: TextInputAction.search,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: kTextPrimary,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: kTextSecondary,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6FF),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.location_on_rounded,
            color: kPrimaryColor,
            size: 20,
          ),
        ),
        suffixIcon: _isSearchingAddress && _activeLocationTarget == target
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kHighlightColor,
                  ),
                ),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFFBFDFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kHighlightColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kHighlightColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPremiumAddressSuggestions(_LocationTarget target) {
    if (_activeLocationTarget != target || _addressSearchResults.isEmpty)
      return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: kSurfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderLight),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: math.min(_addressSearchResults.length, 5),
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: kBorderLight),
        itemBuilder: (context, index) {
          final item = _addressSearchResults[index];
          final title = item['structured_formatting'] is Map
              ? item['structured_formatting']['main_text']?.toString() ??
                    item['description']?.toString() ??
                    'Address'
              : item['main_text']?.toString() ??
                    item['description']?.toString() ??
                    'Address';
          final subtitle = item['structured_formatting'] is Map
              ? item['structured_formatting']['secondary_text']?.toString() ??
                    ''
              : item['secondary_text']?.toString() ?? '';
          return ListTile(
            dense: true,
            minLeadingWidth: 28,
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.place_rounded,
                color: kPrimaryColor,
                size: 18,
              ),
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: kTextPrimary,
                fontSize: 13,
              ),
            ),
            subtitle: subtitle.isEmpty
                ? null
                : Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kTextSecondary, fontSize: 11),
                  ),
            onTap: () => _selectAddressSuggestion(item),
          );
        },
      ),
    );
  }

  Widget _premiumLocationActions(_LocationTarget target) {
    final isLoading = target == _LocationTarget.pickup
        ? _isGettingPickupLocation
        : _isGettingDropoffLocation;
    final selected = target == _LocationTarget.pickup
        ? _pickupLatLng
        : _dropoffLatLng;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isLoading
                ? null
                : () => _useCurrentLocation(target: target),
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded, size: 18),
            label: Text(isLoading ? 'Getting GPS...' : 'Use my location'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimaryColor,
              side: const BorderSide(color: kBorderLight),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected != null
                ? kSuccessGreen.withOpacity(0.12)
                : const Color(0xFFFBFDFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected != null
                  ? kSuccessGreen.withOpacity(0.3)
                  : kBorderLight,
            ),
          ),
          child: Icon(
            selected != null
                ? Icons.check_circle_rounded
                : Icons.gps_off_rounded,
            color: selected != null ? kSuccessGreen : kTextSecondary,
            size: 18,
          ),
        ),
      ],
    );
  }

  Widget _premiumMiniMap({
    required _LocationTarget target,
    required LatLng latLng,
  }) {
    final isPickup = target == _LocationTarget.pickup;
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderLight),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: latLng, zoom: 15),
              markers: _buildMarkers(target: target, latLng: latLng),
              onTap: (point) => _onMapTap(target: target, latLng: point),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: kSurfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isPickup ? kHighlightColor : kSuccessGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPickup ? 'Pickup' : 'Drop-off',
                      style: const TextStyle(
                        color: kTextPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumEstimateCard() {
    final waitingForLocations = _pickupLatLng == null || _dropoffLatLng == null;
    final hasPrice = _estimatedDeliveryFee != null && !_requiresManualQuote;
    final hasDistance = _estimatedDistanceKm != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kSuccessGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.calculate_rounded,
                  color: kSuccessGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery Estimate',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kTextPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Auto-calculated from route and weight',
                      style: TextStyle(
                        fontSize: 12,
                        color: kTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isEstimatingDeliveryFee)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kHighlightColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _premiumEstimateBox(
                  label: 'Distance',
                  value: hasDistance
                      ? '${_estimatedDistanceKm!.toStringAsFixed(1)} km'
                      : '-',
                  icon: Icons.straighten_rounded,
                  color: kInfoBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _premiumEstimateBox(
                  label: 'Estimated Fee',
                  value: _requiresManualQuote
                      ? 'Custom quote'
                      : hasPrice
                      ? _moneyText(_estimatedDeliveryFee)
                      : '-',
                  icon: Icons.payments_rounded,
                  color: kHighlightColor,
                ),
              ),
            ],
          ),
          if (_estimateErrorMessage != null) ...[
            const SizedBox(height: 12),
            _premiumNoticeBox(
              icon: Icons.error_outline,
              color: kHighlightColor,
              text: _estimateErrorMessage!,
            ),
          ] else if (_requiresManualQuote) ...[
            const SizedBox(height: 12),
            _premiumNoticeBox(
              icon: Icons.support_agent_rounded,
              color: kWarningAmber,
              text: 'This route needs a custom quote. We\'ll contact you.',
            ),
          ] else if (waitingForLocations) ...[
            const SizedBox(height: 12),
            _premiumNoticeBox(
              icon: Icons.info_outline,
              color: kInfoBlue,
              text: 'Select both locations to calculate the fee.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _premiumEstimateBox({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    color: kTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumPaymentSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kHighlightColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.credit_card_rounded,
                  color: kHighlightColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Method',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kTextPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Choose how you\'d like to pay',
                      style: TextStyle(
                        fontSize: 12,
                        color: kTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _paymentOptionCard(
                  value: _PaymentPreference.payOnline,
                  title: 'Pay Online',
                  subtitle: 'Card checkout',
                  icon: Icons.credit_card_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _paymentOptionCard(
                  value: _PaymentPreference.payOnDelivery,
                  title: 'Pay on Delivery',
                  subtitle: 'Pay when received',
                  icon: Icons.handshake_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentOptionCard({
    required _PaymentPreference value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _paymentPreference == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentPreference = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? kPrimaryColor : const Color(0xFFFBFDFF),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? kPrimaryColor : kBorderLight),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : kPrimaryColor,
              size: 22,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : kTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white70 : kTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumNoticeBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon ?? Icons.check_rounded, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // Premium Tracking Card
  Widget _buildPremiumTrackingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderLight),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.045),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kHighlightColor,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.track_changes_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track Shipment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kTextPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Enter your delivery ID to get live updates',
                      style: TextStyle(
                        fontSize: 12,
                        color: kTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _premiumTextField(
            controller: _trackingIdController,
            label: 'Delivery ID',
            icon: Icons.tag_rounded,
          ),
          const SizedBox(height: 14),
          _premiumPrimaryButton(
            label: _isTracking ? 'Searching...' : 'Track Now',
            icon: Icons.search_rounded,
            isLoading: _isTracking,
            onPressed: _isTracking ? null : _trackDelivery,
          ),
          if (_activeLiveTrackingDeliveryId != null) ...[
            const SizedBox(height: 18),
            _buildPremiumLiveMap(),
          ],
          if (_trackingResult != null || _trackedDelivery != null) ...[
            const SizedBox(height: 16),
            _buildPremiumTrackingResult(),
          ],
        ],
      ),
    );
  }

  Widget _buildPremiumLiveMap() {
    final rider = _animatedRiderLatLng ?? _liveRiderLatLng;
    final fallback = rider ?? _livePickupLatLng ?? _liveDropoffLatLng;
    final destination = _customerTrackingDestination(
      pickupLatLng: _livePickupLatLng,
      dropoffLatLng: _liveDropoffLatLng,
    );
    final initialMapTarget = destination ?? fallback;
    if (fallback == null) {
      return _premiumNoticeBox(
        icon: Icons.gps_fixed_rounded,
        color: kInfoBlue,
        text: 'Waiting for rider GPS signal...',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorderLight),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialMapTarget!,
                    zoom: 15,
                  ),
                  markers: _liveTrackingMarkers,
                  polylines: _liveTrackingPolylines,
                  circles: _customerDestinationCircles(),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: true,
                  buildingsEnabled: false,
                  mapToolbarEnabled: false,
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                  onMapCreated: (controller) async {
                    _trackingMapController = controller;
                    _isTrackingMapReady = true;
                    try {
                      await controller.setMapStyle(_focusedTrackingMapStyle);
                    } catch (_) {}
                    if (rider != null) {
                      _focusTrackingRouteCamera(
                        riderLatLng: rider,
                        pickupLatLng: _livePickupLatLng,
                        dropoffLatLng: _liveDropoffLatLng,
                      );
                    }
                  },
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _premiumMapChip(
                    text: _trackingSourceLabel,
                    live: _hasConfirmedLiveSignalRUpdate,
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Material(
                    color: kSurfaceWhite,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 4,
                    child: IconButton(
                      tooltip: 'Open full-screen map',
                      onPressed: _openFullScreenTrackingMap,
                      icon: const Icon(Icons.fullscreen_rounded),
                      color: kPrimaryColor,
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: kSurfaceWhite,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 4,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: rider == null
                          ? null
                          : () => _focusTrackingRouteCamera(
                              riderLatLng: rider,
                              pickupLatLng: _livePickupLatLng,
                              dropoffLatLng: _liveDropoffLatLng,
                            ),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.center_focus_strong_rounded,
                          color: kPrimaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFDFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorderLight),
          ),
          child: Column(
            children: [
              _premiumInfoRow(
                label: 'Source',
                value: _trackingSourceLabel,
                icon: _hasConfirmedLiveSignalRUpdate
                    ? Icons.wifi_rounded
                    : Icons.history_rounded,
              ),
              _currentRiderAddressRow(hasRiderLocation: rider != null),
              if (rider != null)
                _premiumInfoRow(
                  label: 'ETA',
                  value: _customerEtaText(
                    riderLatLng: rider,
                    pickupLatLng: _livePickupLatLng,
                    dropoffLatLng: _liveDropoffLatLng,
                  ),
                  icon: Icons.timer_rounded,
                ),
              if (_lastRiderLocationUpdate != null)
                _premiumInfoRow(
                  label: 'Updated',
                  value: _formatDate(
                    _lastRiderLocationUpdate!.toIso8601String(),
                  ),
                  icon: Icons.update_rounded,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _currentRiderAddressRow({required bool hasRiderLocation}) {
    final address = _currentRiderAddress.trim();
    final displayText = !hasRiderLocation
        ? 'Waiting for rider current address...'
        : address.isEmpty
        ? 'Resolving rider address...'
        : address;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, size: 16, color: kPrimaryColor),
          const SizedBox(width: 8),
          const Text(
            'Current address:',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              displayText,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumMapChip({required String text, required bool live}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kSurfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: live ? kSuccessGreen : kWarningAmber,
                  shape: BoxShape.circle,
                  boxShadow: live
                      ? [
                          BoxShadow(
                            color: kSuccessGreen.withOpacity(
                              0.5 * _pulseAnimation.value,
                            ),
                            blurRadius: 6,
                          ),
                        ]
                      : [],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: live ? kSuccessGreen : kTextPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumInfoRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: kPrimaryColor),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: kTextPrimary,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumTrackingResult() {
    final delivery = _trackedDelivery ?? <String, dynamic>{};
    final id =
        delivery['id']?.toString() ?? _activeLiveTrackingDeliveryId ?? '';
    final status = _formatDeliveryStatus(
      delivery['deliveryStatus'] ?? delivery['status'],
    );
    final payment = _paymentDisplayText(delivery);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  color: _statusColor(status),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shipment #${_shortDeliveryId(id)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
              ),
              _premiumStatusBadge(status, _statusColor(status)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _AnimatedStatusBar(
              value: _statusProgress(
                delivery['deliveryStatus'] ?? delivery['status'],
              ),
              color: _statusColor(status),
              backgroundColor: kBorderLight,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _premiumStatusBadge(payment, _paymentColor(payment)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _deliveryPriceText(delivery),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _premiumRouteBox(delivery),
          _buildDeliveryOtpPanel(delivery),
          if (_riderDisplayText(delivery).isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.electric_bike_rounded,
                  size: 16,
                  color: kPrimaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _riderDisplayText(delivery),
                    style: const TextStyle(fontSize: 12, color: kTextPrimary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryOtpPanel(
    Map delivery, {
    bool compact = false,
  }) {
    if (!_shouldShowDeliveryOtpPanel(delivery)) return const SizedBox.shrink();

    final id = _firstNonEmpty([delivery['id'], delivery['Id']]);
    final statusNumber = _deliveryStatusNumberForOtp(delivery);
    final otp = _deliveryOtpCode(delivery);
    final usedOn = _deliveryOtpUsedOnText(delivery);
    final expiresOn = _deliveryOtpExpiresOnText(delivery);
    final otpUsed = usedOn.isNotEmpty || statusNumber == 5;
    final hasActiveOtp = otp.isNotEmpty && !otpUsed;

    final Color accentColor = hasActiveOtp
        ? kHighlightColor
        : otpUsed
            ? kSuccessGreen
            : kWarningAmber;

    final title = hasActiveOtp
        ? 'Delivery Confirmation Code'
        : otpUsed
            ? 'Delivery OTP Verified'
            : 'Delivery OTP pending';

    final message = hasActiveOtp
        ? 'Give this code to the rider only after your package has been handed over to you.'
        : otpUsed
            ? 'The confirmation code has already been verified for this delivery.'
            : 'The code will appear here after the rider marks the package as picked up.';

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: compact ? 10 : 12),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.11),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.34)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 32 : 38,
                height: compact ? 32 : 38,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasActiveOtp
                      ? Icons.password_rounded
                      : otpUsed
                          ? Icons.verified_rounded
                          : Icons.lock_clock_rounded,
                  color: accentColor,
                  size: compact ? 18 : 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: kTextPrimary,
                        fontSize: compact ? 12 : 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: TextStyle(
                        color: kTextSecondary,
                        fontSize: compact ? 10.5 : 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasActiveOtp) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 14,
                vertical: compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor.withOpacity(0.32)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      otp,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kTextPrimary,
                        fontSize: compact ? 22 : 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy OTP',
                    onPressed: () => _copyDeliveryOtp(otp),
                    icon: const Icon(Icons.copy_rounded),
                    color: kPrimaryColor,
                  ),
                ],
              ),
            ),
            if (expiresOn.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: kTextSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Expires: ${_formatDate(expiresOn)}',
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ] else if (!otpUsed) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isRefreshingDeliveryOtp
                    ? null
                    : () => _refreshDeliveryForOtp(
                          deliveryId: id.isEmpty ? null : id,
                          silent: false,
                        ),
                icon: _isRefreshingDeliveryOtp
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  _isRefreshingDeliveryOtp ? 'Checking...' : 'Check for OTP',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: kPrimaryColor,
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _premiumStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _premiumRouteBox(Map delivery) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.trip_origin_rounded,
                size: 16,
                color: kHighlightColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  delivery['pickupAddress']?.toString() ?? '-',
                  style: const TextStyle(fontSize: 12, color: kTextPrimary),
                ),
              ),
            ],
          ),
          const Divider(height: 14, color: kBorderLight),
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 16,
                color: kSuccessGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  delivery['dropoffAddress']?.toString() ?? '-',
                  style: const TextStyle(fontSize: 12, color: kTextPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _premiumTimelineTile({
    required String title,
    required String message,
    dynamic date,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kHighlightColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kHighlightColor.withOpacity(0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              Container(width: 2, height: 40, color: kBorderLight),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kSurfaceWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary,
                      fontSize: 12,
                    ),
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (_formatDate(date).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(date),
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Premium History Card
  Widget _buildPremiumHistoryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderLight),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.045),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: kInfoBlue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: kInfoBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Orders',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kTextPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Pull down to refresh',
                            style: TextStyle(
                              fontSize: 12,
                              color: kTextSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _glassActionButton(
                icon: Icons.refresh_rounded,
                onTap: _loadMyDeliveries,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingMyDeliveries)
            ...List.generate(3, (_) => const _RequestCardSkeleton())
          else if (_myDeliveries.isEmpty)
            _EmptyState(
              icon: Icons.inventory_2_rounded,
              title: 'No shipments yet',
              message: 'Your delivery requests will appear here.',
              actionLabel: 'Send a package',
              onAction: () => _tabController.animateTo(0),
            )
          else
            ..._myDeliveries.whereType<Map>().map(
              (item) => _premiumDeliveryCard(item),
            ),
        ],
      ),
    );
  }

  Widget _premiumDeliveryCard(Map item) {
    final id = item['id']?.toString() ?? '';
    final status = _formatDeliveryStatus(
      item['deliveryStatus'] ?? item['status'],
    );
    final payment = _paymentDisplayText(item);
    final paying = _payingDeliveryId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: _statusColor(status),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shipment #${_shortDeliveryId(id)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kTextPrimary,
                      ),
                    ),
                    Text(
                      _formatDate(item['createdOn']).isEmpty
                          ? 'Date N/A'
                          : _formatDate(item['createdOn']),
                      style: const TextStyle(
                        fontSize: 11,
                        color: kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _premiumStatusBadge(status, _statusColor(status)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _AnimatedStatusBar(
              value: _statusProgress(item['deliveryStatus'] ?? item['status']),
              color: _statusColor(status),
              backgroundColor: kBorderLight,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 10),
          _premiumRouteBox(item),
          _buildDeliveryOtpPanel(item, compact: true),
          if (_riderDisplayText(item).isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.electric_bike_rounded,
                  size: 15,
                  color: kPrimaryColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _riderDisplayText(item),
                    style: const TextStyle(fontSize: 11, color: kTextPrimary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _premiumMiniInfo(label: 'Price', value: _deliveryPriceText(item)),
              const SizedBox(width: 8),
              _premiumMiniInfo(label: 'Payment', value: payment),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _premiumOutlineButton(
                  label: 'Details',
                  icon: Icons.info_outline,
                  onPressed: () => _showDeliveryDetails(item),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _premiumSmallButton(
                  label: 'Track',
                  icon: Icons.track_changes_rounded,
                  onPressed: id.isEmpty ? null : () => _trackFromDelivery(item),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _premiumSmallButton(
                  label: paying
                      ? '...'
                      : (_isPayOnDelivery(item)
                            ? 'Pay later'
                            : _payButtonText(item)),
                  icon: Icons.payment_rounded,
                  isLoading: paying,
                  backgroundColor: _canPay(item)
                      ? kSuccessGreen
                      : kTextSecondary,
                  onPressed: (!_canPay(item) || paying)
                      ? null
                      : () => _startPaymentForDelivery(
                          Map<String, dynamic>.from(item),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _premiumMiniInfo({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kSurfaceWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: kTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumSmallButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool isLoading = false,
    Color backgroundColor = kPrimaryColor,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon ?? Icons.check_rounded, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  Widget _premiumOutlineButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimaryColor,
        side: const BorderSide(color: kBorderLight),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  Widget _glassActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFFBFDFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorderLight),
        ),
        child: Icon(icon, color: kPrimaryColor, size: 20),
      ),
    );
  }

  void _showDeliveryDetails(Map item) {
    final status = _formatDeliveryStatus(
      item['deliveryStatus'] ?? item['status'],
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: kSurfaceWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: kBorderLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.local_shipping_rounded,
                          color: _statusColor(status),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Shipment #${_shortDeliveryId(item['id']?.toString() ?? '')}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary,
                          ),
                        ),
                      ),
                      _premiumStatusBadge(status, _statusColor(status)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _AnimatedStatusBar(
                      value: _statusProgress(
                        item['deliveryStatus'] ?? item['status'],
                      ),
                      color: _statusColor(status),
                      backgroundColor: kBorderLight,
                    ),
                  ),
                  _buildDeliveryOtpPanel(item),
                  _detailSectionTitle('Route'),
                  _detailRow(
                    'Pickup',
                    item['pickupAddress']?.toString() ?? '-',
                  ),
                  _detailRow(
                    'Drop-off',
                    item['dropoffAddress']?.toString() ?? '-',
                  ),
                  _detailSectionTitle('People'),
                  _detailRow('Sender', item['senderName']?.toString() ?? '-'),
                  _detailRow(
                    'Sender Phone',
                    item['senderPhone']?.toString() ?? '-',
                  ),
                  _detailRow(
                    'Receiver',
                    item['receiverName']?.toString() ?? '-',
                  ),
                  _detailRow(
                    'Receiver Phone',
                    item['receiverPhone']?.toString() ?? '-',
                  ),
                  if (_riderDisplayText(item).isNotEmpty)
                    _detailRow('Rider', _riderDisplayText(item)),
                  _detailSectionTitle('Package'),
                  _detailRow(
                    'Description',
                    item['packageDescription']?.toString() ?? '-',
                  ),
                  _detailRow('Weight', '${item['packageWeightKg'] ?? '-'} kg'),
                  _detailRow('Price', _deliveryPriceText(item)),
                  _detailRow('Payment', _paymentDisplayText(item)),
                  if ((item['deliveryNote']?.toString() ?? '').isNotEmpty)
                    _detailRow('Note', item['deliveryNote'].toString()),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: kHighlightColor,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: kTextPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PaystackCheckoutPage extends StatefulWidget {
  final String authorizationUrl;
  final String reference;
  final Future<Map<String, dynamic>> Function(String reference) onVerify;

  const PaystackCheckoutPage({
    super.key,
    required this.authorizationUrl,
    required this.reference,
    required this.onVerify,
  });

  @override
  State<PaystackCheckoutPage> createState() => _PaystackCheckoutPageState();
}

class _PaystackCheckoutPageState extends State<PaystackCheckoutPage> {
  late final WebViewController _controller;
  bool _isVerifying = false;
  bool _isPageLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setBackgroundColor(Colors.white)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() => _isPageLoading = true);
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isPageLoading = false);
            }
          },
          onNavigationRequest: (request) {
            final url = request.url;

            if (url.contains('reference=') ||
                url.toLowerCase().contains('callback') ||
                url.toLowerCase().contains('payment/callback')) {
              _verifyAndClose();
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  Future<void> _verifyAndClose() async {
    if (_isVerifying) return;

    setState(() => _isVerifying = true);

    try {
      final result = await widget.onVerify(widget.reference);
      final success = result['success'] == true;

      if (!mounted) return;

      Navigator.pop(context, success);
    } catch (_) {
      if (!mounted) return;

      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Complete Payment',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isVerifying ? null : _verifyAndClose,
            child: const Text(
              'Verify',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isPageLoading && !_isVerifying)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Opening secure payment page...',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          if (_isVerifying)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Verifying payment...',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandDot extends StatelessWidget {
  final Color color;

  const _BrandDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)],
      ),
    );
  }
}

class _AnimatedStatusBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color backgroundColor;
  final double minHeight;

  const _AnimatedStatusBar({
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.minHeight = 5,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: minHeight,
        color: backgroundColor,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, animatedValue, _) {
            return Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: animatedValue,
                child: Container(
                  height: minHeight,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6FF),
              shape: BoxShape.circle,
              border: Border.all(color: kBorderLight, width: 1.5),
            ),
            child: Icon(icon, size: 32, color: kPrimaryColor.withOpacity(0.72)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestCardSkeleton extends StatefulWidget {
  const _RequestCardSkeleton();

  @override
  State<_RequestCardSkeleton> createState() => _RequestCardSkeletonState();
}

class _RequestCardSkeletonState extends State<_RequestCardSkeleton>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _bar({double width = double.infinity, double height = 12}) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Color.lerp(
              kBorderLight,
              const Color(0xFFEAF6FF),
              _controller.value,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(child: _bar(width: 38, height: 38)),
              const SizedBox(width: 12),
              Expanded(child: _bar(width: 120, height: 13)),
              _bar(width: 60, height: 20),
            ],
          ),
          const SizedBox(height: 12),
          _bar(height: 4),
          const SizedBox(height: 12),
          _bar(width: 180, height: 11),
          const SizedBox(height: 8),
          _bar(width: 140, height: 11),
        ],
      ),
    );
  }
}
