import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'config/api_config.dart';
import 'logistics_tracking_signalr_service.dart';
import 'logistics/rider_jobs/delivery_status_code.dart';
import 'logistics/rider_jobs/rider_jobs_api_service.dart';

const _kPrimaryBlue = Color(0xFF122DB2);
const _kAccentBlue = Color(0xFF0275F4);
const _kCyan = Color(0xFF00CCFB);
const _kPink = Color(0xFFF9045F);
const _kYellow = Color(0xFFFBBD08);
const _kNavyDot = Color(0xFF393C8D);
const _kPageBackground = Color(0xFFF4FAFF);
const _kCardBorder = Color(0xFFD9EAFB);
const _kSoftPanel = Color(0xFFEAF6FF);
const _kTextPrimary = Color(0xFF12215B);
const _kTextSecondary = Color(0xFF627394);


class _LocationCheckResult {
  final Position position;
  final LatLng targetLatLng;
  final double distanceMeters;
  final String targetName;

  const _LocationCheckResult({
    required this.position,
    required this.targetLatLng,
    required this.distanceMeters,
    required this.targetName,
  });
}

class _PickupProofData {
  final String pickupContactName;
  final String packageCondition;

  const _PickupProofData({
    required this.pickupContactName,
    required this.packageCondition,
  });
}

class _DeliveryProofData {
  final String receiverName;
  final String deliveryOtp;
  final String deliveryNote;

  const _DeliveryProofData({
    required this.receiverName,
    required this.deliveryOtp,
    required this.deliveryNote,
  });
}

class _DirectionsRouteResult {
  final List<LatLng> points;
  final String? etaText;

  const _DirectionsRouteResult({
    required this.points,
    this.etaText,
  });
}

class LogisticsRiderJobsPage extends StatefulWidget {
  final String riderId;
  final String? riderName;
  final String? authToken;

  const LogisticsRiderJobsPage({
    super.key,
    required this.riderId,
    this.riderName,
    this.authToken,
  });

  @override
  State<LogisticsRiderJobsPage> createState() => _LogisticsRiderJobsPageState();
}

class _LogisticsRiderJobsPageState extends State<LogisticsRiderJobsPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static final String _hubBaseUrl = ApiConfig.baseUrl;
  static const String _googleApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  static const double _pickupArrivalRadiusMeters = 250;
  static const double _dropoffArrivalRadiusMeters = 300;

  // Keep this false until AndroidManifest.xml contains the required
  // FOREGROUND_SERVICE and FOREGROUND_SERVICE_LOCATION permissions.
  // With false, tracking still works while the rider page is open, and the
  // app will not crash on Android 14+ because of missing foreground-service permission.
  static const bool _enableAndroidForegroundServiceTracking = false;

  // Bright street-first map: keep local roads readable without dense buildings.
  static const String _focusedMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [
      { "color": "#ffffff" }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry.stroke",
    "stylers": [
      { "color": "#e2e8ef" }
    ]
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
    "stylers": [
      { "color": "#ffffff" }
    ]
  },
  {
    "featureType": "landscape.man_made",
    "elementType": "geometry",
    "stylers": [
      { "color": "#ffffff" }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "geometry",
    "stylers": [
      { "color": "#ffffff" }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [
      { "visibility": "off" }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [
      { "color": "#eaf1f6" }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [
      { "color": "#dce8f1" }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "geometry",
    "stylers": [
      { "color": "#f1f5f8" }
    ]
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
    "stylers": [
      { "visibility": "off" }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      { "color": "#d9f1f8" }
    ]
  }
]
''';

  bool _isLoading = false;
  bool _isLiveTracking = false;

  String? _activeTrackingDeliveryId;
  String? _startingTrackingDeliveryId;
  String? _markingPickedUpDeliveryId;
  String? _markingDeliveredDeliveryId;
  Timer? _riderTrackingTimer;
  StreamSubscription<Position>? _riderPositionSubscription;
  late final RiderJobsApiService _apiService;

  List<dynamic> _jobs = [];

  // ===============================
  // RIDER SIDE LIVE MAP
  // ===============================
  LatLng? _currentRiderLatLng;
  LatLng? _animatedRiderLatLng;
  LatLng? _activePickupLatLng;
  LatLng? _activeDropoffLatLng;

  GoogleMapController? _riderMapController;
  bool _isRiderMapReady = false;
  bool _isFullScreenRiderMap = false;
  bool _isFollowingRider = false;
  Map<String, dynamic>? _fullScreenMapJob;
  DateTime? _lastRiderCameraMoveAt;

  Set<Marker> _riderMapMarkers = {};
  Set<Polyline> _riderMapPolylines = {};
  List<LatLng> _riderMovementPath = [];

  BitmapDescriptor? _bikeMarkerIcon;
  bool _isBikeMarkerAssetLoaded = false;

  AnimationController? _bikeAnimationController;
  double _riderBearing = 0;

  DateTime? _lastLocationSentAt;
  String? _currentRiderStreetText;
  String? _activeRoadEtaText;
  DateTime? _lastReverseGeocodeAt;
  LatLng? _lastRouteFetchOrigin;
  LatLng? _lastRouteFetchDestination;
  DateTime? _lastRouteFetchAt;
  DateTime? _lastTrackingErrorShownAt;
  DateTime? _lastAcceptedPositionAt;
  DateTime? _lastPositionStreamEventAt;
  DateTime? _lastApiLocationPersistedAt;
  LatLng? _lastPublishedRiderLatLng;
  bool _isPublishingRiderPosition = false;

  @override
  void initState() {
    super.initState();

    _apiService = RiderJobsApiService(authToken: widget.authToken);

    WidgetsBinding.instance.addObserver(this);
    _loadBikeMarkerIcon();
    _loadRiderJobs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _riderTrackingTimer?.cancel();
    _riderPositionSubscription?.cancel();
    _bikeAnimationController?.dispose();

    if (_activeTrackingDeliveryId != null) {
      LogisticsTrackingSignalRService.instance.leaveDeliveryTrackingGroup(
        _activeTrackingDeliveryId!,
      );
    }

    _riderMapController?.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _isLiveTracking &&
        _activeTrackingDeliveryId != null) {
      _loadRiderJobs();
    }
  }

  void _showTrackingErrorOnce(String message) {
    final now = DateTime.now();

    if (_lastTrackingErrorShownAt != null &&
        now.difference(_lastTrackingErrorShownAt!).inSeconds < 45) {
      return;
    }

    _lastTrackingErrorShownAt = now;
    _showSnack(message, Colors.red);
  }

  bool _shouldRefreshRoute({
    required LatLng current,
    required LatLng? destination,
  }) {
    final now = DateTime.now();

    if (destination == null) {
      _lastRouteFetchOrigin = current;
      _lastRouteFetchDestination = null;
      _lastRouteFetchAt = now;
      return true;
    }

    final destinationChanged =
        _lastRouteFetchDestination == null ||
        !_isSameLatLng(_lastRouteFetchDestination!, destination);

    if (_lastRouteFetchOrigin == null ||
        _lastRouteFetchAt == null ||
        destinationChanged) {
      _lastRouteFetchOrigin = current;
      _lastRouteFetchDestination = destination;
      _lastRouteFetchAt = now;
      return true;
    }

    final metersMoved = Geolocator.distanceBetween(
      _lastRouteFetchOrigin!.latitude,
      _lastRouteFetchOrigin!.longitude,
      current.latitude,
      current.longitude,
    );

    final secondsSinceLastFetch = now.difference(_lastRouteFetchAt!).inSeconds;

    if (metersMoved >= 40 || secondsSinceLastFetch >= 30) {
      _lastRouteFetchOrigin = current;
      _lastRouteFetchDestination = destination;
      _lastRouteFetchAt = now;
      return true;
    }

    return false;
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

    if (imageBytes == null) {
      throw Exception('Could not convert bike marker image to bytes.');
    }

    return BitmapDescriptor.fromBytes(imageBytes.buffer.asUint8List());
  }

  Future<void> _loadBikeMarkerIcon() async {
    try {
      debugPrint(
        '[RiderMap] Loading bike marker asset: assets/images/bike_marker.png',
      );

      _bikeMarkerIcon = await _resizedBikeMarkerFromAsset(
        'assets/images/bike_marker.png',
        targetWidth: 110,
      );

      _isBikeMarkerAssetLoaded = true;
      debugPrint('[RiderMap] Bike marker asset loaded successfully.');
    } catch (e) {
      _isBikeMarkerAssetLoaded = false;
      _bikeMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
      debugPrint(
        '[RiderMap] Bike marker asset failed. Using default marker: $e',
      );
    }
  }

  Future<void> _loadRiderJobs() async {
    if (widget.riderId.trim().isEmpty) {
      _showSnack('Rider ID is missing.', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final jobs = await _apiService.loadRiderJobs(riderId: widget.riderId);

      if (!mounted) return;

      setState(() {
        _jobs = jobs;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[RiderJobs] Failed to load rider jobs: $e');
      _showSnack('Failed to load rider jobs: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, dynamic>? _mapFrom(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, dynamic>? _deliveryMap(Map<String, dynamic> item) {
    return _mapFrom(
      item['delivery'] ??
          item['Delivery'] ??
          item['deliveryRequest'] ??
          item['DeliveryRequest'],
    );
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

  dynamic _firstRawNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return value;
      }
    }

    return null;
  }

  String _deliveryRequestId(Map<String, dynamic> item) {
    final delivery = _deliveryMap(item);

    return _firstNonEmpty([
      item['deliveryRequestId'],
      item['DeliveryRequestId'],
      item['deliveryId'],
      item['DeliveryId'],
      delivery?['id'],
      delivery?['Id'],
      delivery?['deliveryRequestId'],
      delivery?['DeliveryRequestId'],

      // Last fallback only. item['id'] is usually the assignment ID.
      item['id'],
      item['Id'],
    ]);
  }

  String _assignmentId(Map<String, dynamic> item) {
    return _firstNonEmpty([
      item['id'],
      item['Id'],
      item['assignmentId'],
      item['AssignmentId'],
    ]);
  }

  String _shortId(String id) {
    return id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
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

  dynamic _jobStatusValue(Map<String, dynamic> item) {
    final delivery = _deliveryMap(item);

    return _firstRawNonEmpty([
      item['deliveryStatus'],
      item['DeliveryStatus'],
      item['status'],
      item['Status'],
      delivery?['deliveryStatus'],
      delivery?['DeliveryStatus'],
      delivery?['status'],
      delivery?['Status'],
    ]);
  }

  String _formatStatus(dynamic value) {
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

  Color _statusColor(String status) {
    final lower = status.toLowerCase();

    if (lower.contains('delivered')) return const Color(0xFF00A76F);
    if (lower.contains('transit')) return _kPink;
    if (lower.contains('assigned')) return _kPrimaryBlue;
    if (lower.contains('picked')) return _kAccentBlue;
    if (lower.contains('cancel') || lower.contains('failed')) {
      return const Color(0xFFD92D20);
    }

    return _kYellow;
  }

  String _jobText(
    Map<String, dynamic> item,
    List<String> keys, {
    bool checkDelivery = true,
  }) {
    final delivery = checkDelivery ? _deliveryMap(item) : null;

    final values = <dynamic>[];

    for (final key in keys) {
      values.add(item[key]);
      values.add(item[_upperFirst(key)]);
    }

    if (delivery != null) {
      for (final key in keys) {
        values.add(delivery[key]);
        values.add(delivery[_upperFirst(key)]);
      }
    }

    return _firstNonEmpty(values);
  }

  double? _jobDouble(
    Map<String, dynamic> item,
    List<String> keys, {
    bool checkDelivery = true,
  }) {
    final delivery = checkDelivery ? _deliveryMap(item) : null;

    final values = <dynamic>[];

    for (final key in keys) {
      values.add(item[key]);
      values.add(item[_upperFirst(key)]);
    }

    if (delivery != null) {
      for (final key in keys) {
        values.add(delivery[key]);
        values.add(delivery[_upperFirst(key)]);
      }
    }

    for (final value in values) {
      if (value == null) continue;

      if (value is num) return value.toDouble();

      final parsed = double.tryParse(value.toString().trim());
      if (parsed != null) return parsed;
    }

    return null;
  }

  String _upperFirst(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      _showSnack(
        'Location service is disabled. Please turn on GPS.',
        Colors.red,
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showSnack('Location permission denied.', Colors.red);
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnack(
        'Location permission permanently denied. Enable it from app settings.',
        Colors.red,
      );
      return false;
    }

    return true;
  }

  Future<void> _updateDeliveryStatus({
    required String deliveryRequestId,
    required int newStatus,
    required String note,
  }) async {
    await _apiService.updateDeliveryStatus(
      deliveryRequestId: deliveryRequestId,
      newStatus: newStatus,
      note: note,
      riderId: widget.riderId,
    );
  }

  String _formatDistanceMeters(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }

    return '${meters.round()} m';
  }

  Future<_LocationCheckResult?> _ensureRiderIsNearTarget({
    required Map<String, dynamic> item,
    required List<String> latitudeKeys,
    required List<String> longitudeKeys,
    required String targetName,
    required double allowedRadiusMeters,
  }) async {
    final targetLatLng = _jobLatLng(item, latitudeKeys, longitudeKeys);

    if (targetLatLng == null) {
      _showSnack('$targetName coordinate is missing.', Colors.red);
      return null;
    }

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _liveRiderLocationSettings(),
      );

      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        targetLatLng.latitude,
        targetLatLng.longitude,
      );

      if (distanceMeters > allowedRadiusMeters) {
        _showSnack(
          'You are ${_formatDistanceMeters(distanceMeters)} from the $targetName. '
          'Move within ${_formatDistanceMeters(allowedRadiusMeters)} before continuing.',
          Colors.orange,
        );
        return null;
      }

      return _LocationCheckResult(
        position: position,
        targetLatLng: targetLatLng,
        distanceMeters: distanceMeters,
        targetName: targetName,
      );
    } catch (e) {
      debugPrint('[RiderFraudCheck] Could not verify $targetName distance: $e');
      _showTrackingErrorOnce(
        'Could not verify your distance to the $targetName. Please check GPS/network.',
      );
      return null;
    }
  }

  String _gpsAuditText(_LocationCheckResult check) {
    return '${check.targetName} distance ${_formatDistanceMeters(check.distanceMeters)} '
        'GPS ${check.position.latitude.toStringAsFixed(6)},'
        '${check.position.longitude.toStringAsFixed(6)}';
  }

  Widget _proofTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimaryBlue, width: 1.4),
        ),
      ),
    );
  }

  void _disposeTextControllersAfterDialog(
    List<TextEditingController> controllers,
  ) {
    // Do not dispose dialog controllers immediately after Navigator.pop().
    // Flutter may still read them for a few frames while the dialog/keyboard
    // route is closing. Immediate dispose causes:
    // "A TextEditingController was used after being disposed."
    Future<void>.delayed(const Duration(seconds: 2), () {
      for (final controller in controllers) {
        try {
          controller.dispose();
        } catch (_) {
          // The controller may already be gone during hot restart; ignore.
        }
      }
    });
  }

  Future<_PickupProofData?> _showPickupProofDialog(
    Map<String, dynamic> item,
  ) async {
    final pickupContactController = TextEditingController(
      text: _jobText(item, ['senderName', 'customerName']),
    );
    final conditionController = TextEditingController(
      text: 'Package received in good condition',
    );

    try {
      return await showDialog<_PickupProofData>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          String? errorText;

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Confirm pickup proof'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Confirm who handed over the package. This is saved in the delivery audit note until the backend proof-upload endpoint is added.',
                      style: TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _proofTextField(
                      controller: pickupContactController,
                      label: 'Pickup contact name',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 10),
                    _proofTextField(
                      controller: conditionController,
                      label: 'Package condition / proof note',
                      icon: Icons.inventory_2_outlined,
                      maxLines: 2,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFD92D20),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final contact = pickupContactController.text.trim();
                    final condition = conditionController.text.trim();

                    if (contact.isEmpty) {
                      setDialogState(() {
                        errorText = 'Enter the pickup contact name.';
                      });
                      return;
                    }

                    if (condition.isEmpty) {
                      setDialogState(() {
                        errorText = 'Enter a pickup proof note.';
                      });
                      return;
                    }

                    Navigator.pop(
                      context,
                      _PickupProofData(
                        pickupContactName: contact,
                        packageCondition: condition,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Confirm Pickup'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _disposeTextControllersAfterDialog([
        pickupContactController,
        conditionController,
      ]);
    }
  }

  Future<_DeliveryProofData?> _showDeliveryProofDialog(
    Map<String, dynamic> item,
  ) async {
    final receiverController = TextEditingController(
      text: _jobText(item, ['receiverName']),
    );
    final otpController = TextEditingController();
    final noteController = TextEditingController(
      text: 'Package handed over to receiver',
    );

    try {
      return await showDialog<_DeliveryProofData>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          String? errorText;

          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Enter delivery OTP'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ask the customer/receiver for the 6-digit delivery confirmation code shown in their TellMe app. Enter it only after handing over the package.',
                      style: TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _proofTextField(
                      controller: receiverController,
                      label: 'Receiver name',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 10),
                    _proofTextField(
                      controller: otpController,
                      label: '6-digit delivery OTP',
                      icon: Icons.lock_outline,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _proofTextField(
                      controller: noteController,
                      label: 'Delivery proof note',
                      icon: Icons.fact_check_outlined,
                      maxLines: 2,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFD92D20),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext, rootNavigator: true).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final receiver = receiverController.text.trim();
                    final otp = otpController.text.replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );
                    final note = noteController.text.trim();

                    if (receiver.isEmpty) {
                      setDialogState(() {
                        errorText = 'Enter the receiver name.';
                      });
                      return;
                    }

                    if (otp.length != 6) {
                      setDialogState(() {
                        errorText = 'Enter the 6-digit delivery OTP.';
                      });
                      return;
                    }

                    if (note.isEmpty) {
                      setDialogState(() {
                        errorText = 'Enter a delivery proof note.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext, rootNavigator: true).pop(
                      _DeliveryProofData(
                        receiverName: receiver,
                        deliveryOtp: otp,
                        deliveryNote: note,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A76F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Verify OTP & Deliver'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _disposeTextControllersAfterDialog([
        receiverController,
        otpController,
        noteController,
      ]);
    }
  }

  Future<void> _onMyWay(Map<String, dynamic> item) async {
    final deliveryRequestId = _deliveryRequestId(item);

    if (deliveryRequestId.isEmpty) {
      _showSnack('Delivery ID not found.', Colors.red);
      return;
    }

    final statusNumber = _statusNumber(_jobStatusValue(item));

    if (statusNumber == DeliveryStatusCode.delivered) {
      _showSnack('This delivery has already been completed.', Colors.orange);
      return;
    }

    // Only the job that was clicked should show the loading spinner.
    if (_startingTrackingDeliveryId != null) return;

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    setState(() => _startingTrackingDeliveryId = deliveryRequestId);

    try {
      await _startRiderLiveTracking(
        deliveryRequestId: deliveryRequestId,
        item: item,
      );

      await _loadRiderJobs();

      if (!mounted) return;
      _showSnack(
        'Tracking started for Delivery #${_shortId(deliveryRequestId)}.',
        Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not start trip: $e', Colors.red);
    } finally {
      if (mounted && _startingTrackingDeliveryId == deliveryRequestId) {
        setState(() => _startingTrackingDeliveryId = null);
      }
    }
  }

  Future<void> _confirmMarkDelivered(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Complete delivery?'),
        content: const Text(
          'Confirm only when you are at the drop-off point and the package has been handed over. You will enter the customer delivery OTP next.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A76F),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    // Important: the OTP dialog is opened after the confirmation dialog closes.
    // This avoids disposing dialog-dependent widgets while async verification is running.
    await _markDelivered(item);
  }

  Future<void> _markPickedUp(Map<String, dynamic> item) async {
    final deliveryRequestId = _deliveryRequestId(item);

    if (deliveryRequestId.isEmpty) {
      _showSnack('Delivery ID not found.', Colors.red);
      return;
    }

    final statusNumber = _statusNumber(_jobStatusValue(item));

    if (statusNumber == DeliveryStatusCode.delivered) {
      _showSnack('This delivery has already been completed.', Colors.orange);
      return;
    }

    if (statusNumber == DeliveryStatusCode.pickedUp ||
        statusNumber == DeliveryStatusCode.inTransit) {
      _showSnack('Package is already picked up.', Colors.orange);
      return;
    }

    if (!_isLiveTracking || _activeTrackingDeliveryId != deliveryRequestId) {
      _showSnack(
        'Start live tracking first before marking package as picked up.',
        Colors.orange,
      );
      return;
    }

    if (_markingPickedUpDeliveryId != null ||
        _markingDeliveredDeliveryId != null) {
      return;
    }

    setState(() => _markingPickedUpDeliveryId = deliveryRequestId);

    try {
      final pickupCheck = await _ensureRiderIsNearTarget(
        item: item,
        latitudeKeys: ['pickupLatitude'],
        longitudeKeys: ['pickupLongitude'],
        targetName: 'pickup point',
        allowedRadiusMeters: _pickupArrivalRadiusMeters,
      );

      if (pickupCheck == null) return;

      final proof = await _showPickupProofDialog(item);
      if (proof == null) return;

      await _sendRiderLocationNow(
        deliveryRequestId: deliveryRequestId,
        item: item,
      );

      await _updateDeliveryStatus(
        deliveryRequestId: deliveryRequestId,
        newStatus: DeliveryStatusCode.pickedUp,
        note:
            'Package picked up by rider | '
            '${_gpsAuditText(pickupCheck)} | '
            'Pickup contact: ${proof.pickupContactName} | '
            'Pickup proof: ${proof.packageCondition}',
      );

      await _loadRiderJobs();

      if (!mounted) return;
      _showSnack(
        'Package picked up. Route switched to drop-off.',
        Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not mark picked up: $e', Colors.red);
    } finally {
      if (mounted && _markingPickedUpDeliveryId == deliveryRequestId) {
        setState(() => _markingPickedUpDeliveryId = null);
      }
    }
  }

  Future<void> _markDelivered(Map<String, dynamic> item) async {
    final deliveryRequestId = _deliveryRequestId(item);

    if (deliveryRequestId.isEmpty) {
      _showSnack('Delivery ID not found.', Colors.red);
      return;
    }

    final statusNumber = _statusNumber(_jobStatusValue(item));

    if (statusNumber == DeliveryStatusCode.delivered) {
      _showSnack(
        'This delivery is already marked as delivered.',
        Colors.orange,
      );
      return;
    }

    if (statusNumber != DeliveryStatusCode.pickedUp &&
        statusNumber != DeliveryStatusCode.inTransit) {
      _showSnack('Mark package as picked up first.', Colors.orange);
      return;
    }

    if (!_isLiveTracking || _activeTrackingDeliveryId != deliveryRequestId) {
      _showSnack(
        'Resume live tracking before marking this delivery as delivered.',
        Colors.orange,
      );
      return;
    }

    if (_markingPickedUpDeliveryId != null ||
        _markingDeliveredDeliveryId != null) {
      return;
    }

    final dropoffCheck = await _ensureRiderIsNearTarget(
      item: item,
      latitudeKeys: ['dropoffLatitude'],
      longitudeKeys: ['dropoffLongitude'],
      targetName: 'drop-off point',
      allowedRadiusMeters: _dropoffArrivalRadiusMeters,
    );

    if (!mounted || dropoffCheck == null) return;

    final proof = await _showDeliveryProofDialog(item);
    if (!mounted || proof == null) return;

    setState(() => _markingDeliveredDeliveryId = deliveryRequestId);

    try {
      await _sendRiderLocationNow(
        deliveryRequestId: deliveryRequestId,
        item: item,
      );

      await _verifyDeliveryOtpAndComplete(
        deliveryRequestId: deliveryRequestId,
        proof: proof,
        dropoffCheck: dropoffCheck,
      );

      if (!mounted) return;

      if (_activeTrackingDeliveryId == deliveryRequestId) {
        await _stopRiderLiveTracking(showMessage: false);
      }

      if (!mounted) return;

      await _loadRiderJobs();

      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnack('OTP verified. Delivery completed.', Colors.green);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        Colors.red,
      );
    } finally {
      if (mounted && _markingDeliveredDeliveryId == deliveryRequestId) {
        setState(() => _markingDeliveredDeliveryId = null);
      }
    }
  }

  Future<void> _verifyDeliveryOtpAndComplete({
    required String deliveryRequestId,
    required _DeliveryProofData proof,
    required _LocationCheckResult dropoffCheck,
  }) async {
    final uri = Uri.parse(
      ApiConfig.riderVerifyDeliveryOtpUrl(deliveryRequestId),
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if ((widget.authToken ?? '').trim().isNotEmpty)
        'Authorization': 'Bearer ${widget.authToken!.trim()}',
    };

    final body = <String, dynamic>{
      'riderId': widget.riderId,
      'otp': proof.deliveryOtp,
      'deliveryOtp': proof.deliveryOtp,
      'receiverName': proof.receiverName,
      'deliveryNote':
          '${proof.deliveryNote} | ${_gpsAuditText(dropoffCheck)}',
      'latitude': dropoffCheck.position.latitude,
      'longitude': dropoffCheck.position.longitude,
    };

    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));

    Map<String, dynamic> decoded = <String, dynamic>{};

    if (response.body.trim().isNotEmpty) {
      final rawDecoded = jsonDecode(response.body);
      if (rawDecoded is Map) {
        decoded = Map<String, dynamic>.from(rawDecoded);
      }
    }

    final success = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded['success'] == true;

    if (!success) {
      final message =
          decoded['message'] ??
          decoded['error'] ??
          decoded['title'] ??
          'OTP verification failed. Please check the code and try again.';

      throw Exception(message.toString());
    }
  }

  Future<void> _startRiderLiveTracking({
    required String deliveryRequestId,
    required Map<String, dynamic> item,
  }) async {
    if (_isLiveTracking && _activeTrackingDeliveryId == deliveryRequestId) {
      await _sendRiderLocationNow(
        deliveryRequestId: deliveryRequestId,
        item: item,
      );
      return;
    }

    if (_activeTrackingDeliveryId != null &&
        _activeTrackingDeliveryId != deliveryRequestId) {
      await _stopRiderLiveTracking(showMessage: false);
    }

    // Activate the selected job immediately. This prevents all job cards from
    // showing loading and makes only this delivery become the active tracking job.
    if (mounted) {
      setState(() {
        _isLiveTracking = true;
        _activeTrackingDeliveryId = deliveryRequestId;
        _currentRiderLatLng = null;
        _animatedRiderLatLng = null;
        _activePickupLatLng = null;
        _activeDropoffLatLng = null;
        _riderMapMarkers = {};
        _riderMapPolylines = {};
        _riderMovementPath = [];
        _riderBearing = 0;
        _lastLocationSentAt = null;
        _currentRiderStreetText = null;
        _activeRoadEtaText = null;
        _lastReverseGeocodeAt = null;
        _lastRiderCameraMoveAt = null;
        _lastRouteFetchOrigin = null;
        _lastRouteFetchDestination = null;
        _lastRouteFetchAt = null;
        _lastTrackingErrorShownAt = null;
        _lastAcceptedPositionAt = null;
        _lastPositionStreamEventAt = null;
        _lastApiLocationPersistedAt = null;
        _lastPublishedRiderLatLng = null;
        _isPublishingRiderPosition = false;
        _isRiderMapReady = false;
      });
    }

    // Send the first location through the REST API immediately. This keeps
    // tracking useful even if SignalR/WebSocket negotiation is slow or blocked.
    await _sendRiderLocationNow(
      deliveryRequestId: deliveryRequestId,
      item: item,
    );

    // Try SignalR, but do not block the trip forever if the hub connection times out.
    try {
      await LogisticsTrackingSignalRService.instance
          .connect(hubBaseUrl: _hubBaseUrl)
          .timeout(const Duration(seconds: 8));

      await LogisticsTrackingSignalRService.instance.joinDeliveryTrackingGroup(
        deliveryRequestId,
      );

      debugPrint('[RiderSignalR] SignalR live tracking connected.');
    } catch (e) {
      debugPrint(
        '[RiderSignalR] SignalR unavailable, continuing with API location updates: $e',
      );

      try {
        await LogisticsTrackingSignalRService.instance.disconnect();
      } catch (_) {}

      if (mounted) {
        _showSnack(
          'Tracking started, but live push connection is slow. The app will keep sending location updates.',
          Colors.orange,
        );
      }
    }

    await _startRiderPositionStream(
      deliveryRequestId: deliveryRequestId,
      item: item,
    );

    // The stream is the primary source. This watchdog only requests a fresh
    // position when a device stops producing stream events.
    _riderTrackingTimer?.cancel();
    _riderTrackingTimer = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) async {
      if (_activeTrackingDeliveryId != deliveryRequestId) return;

      final lastEvent = _lastPositionStreamEventAt;
      if (lastEvent != null &&
          DateTime.now().difference(lastEvent).inSeconds < 15) {
        return;
      }

      await _sendRiderLocationNow(
        deliveryRequestId: deliveryRequestId,
        item: item,
      );
    });
  }

  LocationSettings _liveRiderLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: _enableAndroidForegroundServiceTracking
            ? const ForegroundNotificationConfig(
                notificationTitle: 'TellMe Logistics tracking active',
                notificationText:
                    'Your delivery location is being shared while this trip is active.',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  Future<void> _startRiderPositionStream({
    required String deliveryRequestId,
    required Map<String, dynamic> item,
  }) async {
    await _riderPositionSubscription?.cancel();
    _riderPositionSubscription = null;

    try {
      _riderPositionSubscription =
          Geolocator.getPositionStream(
            locationSettings: _liveRiderLocationSettings(),
          ).listen(
            (position) {
              _lastPositionStreamEventAt = DateTime.now();
              _handleRiderPosition(
                deliveryRequestId: deliveryRequestId,
                item: item,
                position: position,
              );
            },
            onError: (Object error) {
              debugPrint('[RiderTracking] Position stream error: $error');
              if (!mounted) return;

              final errorText = error.toString();
              if (errorText.contains('FOREGROUND_SERVICE')) {
                _showTrackingErrorOnce(
                  'Live GPS foreground service permission is missing. Tracking will continue with periodic GPS updates while the app is open.',
                );
                return;
              }

              _showTrackingErrorOnce(
                'Live GPS paused. TellMe will keep retrying your location.',
              );
            },
          );
    } on PlatformException catch (e) {
      debugPrint('[RiderTracking] Could not open position stream: $e');
      if (!mounted) return;

      if ((e.message ?? '').contains('FOREGROUND_SERVICE') ||
          e.toString().contains('FOREGROUND_SERVICE')) {
        _showTrackingErrorOnce(
          'Android foreground service permission is missing. Tracking will continue with periodic GPS updates while the app is open.',
        );
      } else {
        _showTrackingErrorOnce(
          'Could not start continuous GPS stream. Tracking will continue with periodic GPS updates.',
        );
      }
    } catch (e) {
      debugPrint('[RiderTracking] Could not open position stream: $e');
      if (mounted) {
        _showTrackingErrorOnce(
          'Could not start continuous GPS stream. Tracking will continue with periodic GPS updates.',
        );
      }
    }
  }

  Future<void> _handleRiderPosition({
    required String deliveryRequestId,
    required Map<String, dynamic> item,
    required Position position,
  }) async {
    if (_activeTrackingDeliveryId != deliveryRequestId ||
        _isPublishingRiderPosition) {
      return;
    }

    final now = DateTime.now();
    final currentLatLng = LatLng(position.latitude, position.longitude);
    final lastLatLng = _lastPublishedRiderLatLng;
    final millisecondsSinceLastAccepted = _lastAcceptedPositionAt == null
        ? 999999
        : now.difference(_lastAcceptedPositionAt!).inMilliseconds;
    final metersMoved = lastLatLng == null
        ? double.infinity
        : Geolocator.distanceBetween(
            lastLatLng.latitude,
            lastLatLng.longitude,
            currentLatLng.latitude,
            currentLatLng.longitude,
          );

    if (millisecondsSinceLastAccepted < 1000) return;
    if (millisecondsSinceLastAccepted < 5000 && metersMoved < 5) return;

    _lastAcceptedPositionAt = now;
    _lastPublishedRiderLatLng = currentLatLng;
    _isPublishingRiderPosition = true;

    try {
      await _publishRiderPosition(
        deliveryRequestId: deliveryRequestId,
        item: item,
        position: position,
      );
    } finally {
      _isPublishingRiderPosition = false;
    }
  }

  Future<void> _publishRiderPosition({
    required String deliveryRequestId,
    required Map<String, dynamic> item,
    required Position position,
    bool forceApiPersistence = false,
  }) async {
    _updateRiderMap(
      item: item,
      latitude: position.latitude,
      longitude: position.longitude,
    );

    Future<bool> pushThroughSignalR() async {
      if (!LogisticsTrackingSignalRService.instance.isConnected) return false;

      try {
        await LogisticsTrackingSignalRService.instance.sendRiderLocation(
          deliveryRequestId: deliveryRequestId,
          riderId: widget.riderId,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
        );
        return true;
      } catch (e) {
        debugPrint('[RiderSignalR] Immediate location push failed: $e');
        return false;
      }
    }

    final now = DateTime.now();
    final signalRConnected =
        LogisticsTrackingSignalRService.instance.isConnected;
    final shouldPersistToApi =
        forceApiPersistence ||
        !signalRConnected ||
        _lastApiLocationPersistedAt == null ||
        now.difference(_lastApiLocationPersistedAt!).inSeconds >= 20;
    var usedSignalR = false;
    var usedApi = false;

    if (shouldPersistToApi) {
      try {
        await _sendRiderLocationToApi(
          deliveryRequestId: deliveryRequestId,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
        );
        _lastApiLocationPersistedAt = DateTime.now();
        usedApi = true;
      } catch (e) {
        debugPrint('[RiderTracking] API persistence failed: $e');
        usedSignalR = await pushThroughSignalR();
        if (!usedSignalR) rethrow;
      }
    } else {
      usedSignalR = await pushThroughSignalR();

      if (!usedSignalR) {
        await _sendRiderLocationToApi(
          deliveryRequestId: deliveryRequestId,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
        );
        _lastApiLocationPersistedAt = DateTime.now();
        usedApi = true;
      }
    }

    debugPrint(
      '[RiderTracking] Published location delivery=$deliveryRequestId '
      'rider=${widget.riderId} lat=${position.latitude} '
      'lng=${position.longitude} signalR=$usedSignalR api=$usedApi',
    );
  }

  Future<void> _sendRiderLocationNow({
    required String deliveryRequestId,
    required Map<String, dynamic> item,
  }) async {
    if (_isPublishingRiderPosition) return;
    _isPublishingRiderPosition = true;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _liveRiderLocationSettings(),
      );

      _lastAcceptedPositionAt = DateTime.now();
      _lastPublishedRiderLatLng = LatLng(position.latitude, position.longitude);

      await _publishRiderPosition(
        deliveryRequestId: deliveryRequestId,
        item: item,
        position: position,
        forceApiPersistence: true,
      );
    } catch (e) {
      debugPrint('[RiderTracking] Failed to send rider location: $e');
      if (!mounted) return;
      _showTrackingErrorOnce(
        'Could not send rider location. Please check GPS/network.',
      );
    } finally {
      _isPublishingRiderPosition = false;
    }
  }

  Future<void> _sendRiderLocationToApi({
    required String deliveryRequestId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
  }) async {
    await _apiService.sendRiderLocation(
      deliveryRequestId: deliveryRequestId,
      riderId: widget.riderId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
    );
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

  LatLng? _jobLatLng(
    Map<String, dynamic> item,
    List<String> latitudeKeys,
    List<String> longitudeKeys,
  ) {
    // IMPORTANT:
    // Coordinates must come from the delivery request object first.
    // The rider job/assignment object can contain different IDs/status fields,
    // so reading coordinates from it first can place pickup/drop-off wrongly.
    final delivery = _deliveryMap(item);

    double? readDoubleFromMap(Map? map, List<String> keys) {
      if (map == null) return null;

      for (final key in keys) {
        final value = map[key] ?? map[_upperFirst(key)];
        if (value == null) continue;

        if (value is num) return value.toDouble();

        final parsed = double.tryParse(value.toString().trim());
        if (parsed != null) return parsed;
      }

      return null;
    }

    final lat =
        readDoubleFromMap(delivery, latitudeKeys) ??
        readDoubleFromMap(item, latitudeKeys);
    final lng =
        readDoubleFromMap(delivery, longitudeKeys) ??
        readDoubleFromMap(item, longitudeKeys);

    if (lat == null || lng == null || lat == 0 || lng == 0) return null;

    debugPrint(
      '[RiderMap] Coordinate resolved lat=$lat lng=$lng '
      'latKeys=$latitudeKeys lngKeys=$longitudeKeys',
    );

    return LatLng(lat, lng);
  }

  Future<_DirectionsRouteResult> _fetchDirectionsPolyline({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (_googleApiKey.trim().isEmpty) {
      debugPrint(
        '[RiderMap] GOOGLE_MAPS_API_KEY is missing. Skipping route fetch.',
      );
      return const _DirectionsRouteResult(points: <LatLng>[]);
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'alternatives': 'false',
      'units': 'metric',
      'language': 'en',
      'region': 'ng',
      'departure_time': 'now',
      'key': _googleApiKey,
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      debugPrint(
        '[RiderMap] Directions API HTTP ${response.statusCode}: ${response.body}',
      );
      return const _DirectionsRouteResult(points: <LatLng>[]);
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map || decoded['status'] != 'OK') {
      debugPrint(
        '[RiderMap] Directions API failed: '
        '${decoded is Map ? decoded['status'] : decoded} '
        '${decoded is Map ? decoded['error_message'] ?? '' : ''}',
      );
      return const _DirectionsRouteResult(points: <LatLng>[]);
    }

    final routes = decoded['routes'];

    if (routes is! List || routes.isEmpty) {
      return const _DirectionsRouteResult(points: <LatLng>[]);
    }

    final route = routes.first;

    if (route is! Map) {
      return const _DirectionsRouteResult(points: <LatLng>[]);
    }

    String? etaText;
    final legs = route['legs'];

    if (legs is List && legs.isNotEmpty && legs.first is Map) {
      final firstLeg = legs.first as Map;
      final durationInTraffic = firstLeg['duration_in_traffic'];
      final duration = firstLeg['duration'];

      if (durationInTraffic is Map &&
          durationInTraffic['text']?.toString().trim().isNotEmpty == true) {
        etaText = durationInTraffic['text'].toString().trim();
      } else if (duration is Map &&
          duration['text']?.toString().trim().isNotEmpty == true) {
        etaText = duration['text'].toString().trim();
      }
    }

    final detailedPoints = <LatLng>[];

    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map || leg['steps'] is! List) continue;

        for (final step in leg['steps'] as List) {
          if (step is! Map || step['polyline'] is! Map) continue;

          final encoded = (step['polyline'] as Map)['points']?.toString() ?? '';
          if (encoded.isEmpty) continue;

          for (final point in _decodePolyline(encoded)) {
            if (detailedPoints.isEmpty ||
                !_isSameLatLng(detailedPoints.last, point)) {
              detailedPoints.add(point);
            }
          }
        }
      }
    }

    if (detailedPoints.length >= 2) {
      debugPrint(
        '[RiderMap] Using ${detailedPoints.length} detailed route points. ETA=$etaText',
      );
      return _DirectionsRouteResult(
        points: detailedPoints,
        etaText: etaText,
      );
    }

    final overview = route['overview_polyline'];

    if (overview is! Map) {
      return _DirectionsRouteResult(points: detailedPoints, etaText: etaText);
    }

    final encoded = overview['points']?.toString() ?? '';

    if (encoded.isEmpty) {
      return _DirectionsRouteResult(points: detailedPoints, etaText: etaText);
    }

    debugPrint('[RiderMap] Detailed steps unavailable; using overview route.');
    return _DirectionsRouteResult(
      points: _decodePolyline(encoded),
      etaText: etaText,
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
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

  Polyline _fallbackRoutePolyline({
    required LatLng riderLatLng,
    required LatLng destinationLatLng,
  }) {
    return Polyline(
      polylineId: const PolylineId('road_route_to_destination'),
      points: [riderLatLng, destinationLatLng],
      width: 4,
      color: _kAccentBlue.withOpacity(0.55),
      patterns: [PatternItem.dash(18.0), PatternItem.gap(10.0)],
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );
  }

  Set<Polyline> _withoutRoutePolylines(Set<Polyline> polylines) {
    return Set<Polyline>.from(polylines)..removeWhere(
      (p) =>
          p.polylineId.value == 'road_route_to_destination' ||
          p.polylineId.value == 'road_route_to_destination_border' ||
          p.polylineId.value == 'rider_movement_path' ||
          p.polylineId.value == 'pickup_to_dropoff' ||
          p.polylineId.value == 'pickup_to_dropoff_preview',
    );
  }

  Future<void> _refreshRoadRoutePolyline({
    required LatLng riderLatLng,
    required LatLng? destinationLatLng,
  }) async {
    if (destinationLatLng == null) {
      if (!mounted) return;

      setState(() {
        _activeRoadEtaText = null;
        _riderMapPolylines = _withoutRoutePolylines(_riderMapPolylines);
      });
      return;
    }

    try {
      final routeResult = await _fetchDirectionsPolyline(
        origin: riderLatLng,
        destination: destinationLatLng,
      );
      final routePoints = routeResult.points;

      if (!mounted) return;

      setState(() {
        final existing = _withoutRoutePolylines(_riderMapPolylines);

        if (routePoints.length < 2) {
          // Directions API can fail in emulators or if the API key is restricted.
          // Keep a visible lightweight guide so the rider still understands the target.
          _activeRoadEtaText = null;
          _riderMapPolylines = {
            ...existing,
            _fallbackRoutePolyline(
              riderLatLng: riderLatLng,
              destinationLatLng: destinationLatLng,
            ),
          };
          return;
        }

        _activeRoadEtaText = routeResult.etaText;

        // This is the remaining road route from the rider's current GPS to the
        // destination. Since it is recalculated on each GPS update, it reduces
        // naturally as the rider approaches.
        _riderMapPolylines = {
          ...existing,
          Polyline(
            polylineId: const PolylineId('road_route_to_destination_border'),
            points: routePoints,
            width: 11,
            color: Colors.white,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 10,
          ),
          Polyline(
            polylineId: const PolylineId('road_route_to_destination'),
            points: routePoints,
            width: 7,
            color: _kPrimaryBlue,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 11,
          ),
        };
      });

      _focusRouteCamera(
        riderLatLng: riderLatLng,
        pickupLatLng: _activePickupLatLng,
        dropoffLatLng: _activeDropoffLatLng,
        activeDestinationLatLng: destinationLatLng,
      );
    } catch (e) {
      debugPrint('[RiderMap] Road route fetch failed: $e');

      if (!mounted) return;

      setState(() {
        _activeRoadEtaText = null;
        _riderMapPolylines = {
          ..._withoutRoutePolylines(_riderMapPolylines),
          _fallbackRoutePolyline(
            riderLatLng: riderLatLng,
            destinationLatLng: destinationLatLng,
          ),
        };
      });
    }
  }

  void _applyRiderMapState({
    required LatLng displayRiderLatLng,
    required LatLng actualRiderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
    required DateTime updatedAt,
  }) {
    _animatedRiderLatLng = displayRiderLatLng;
    _currentRiderLatLng = actualRiderLatLng;
    _activePickupLatLng = pickupLatLng;
    _activeDropoffLatLng = dropoffLatLng;
    _lastLocationSentAt = updatedAt;

    _riderMapMarkers = {
      Marker(
        markerId: const MarkerId('rider_current_location'),
        position: displayRiderLatLng,
        infoWindow: const InfoWindow(title: 'You are here'),
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

    // Keep the existing route line while the bike marker animates. The route is
    // refreshed separately by _refreshRoadRoutePolyline().
  }

  Future<void> _animateRiderMarkerTo({
    required LatLng targetLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
    required DateTime updatedAt,
  }) async {
    final startLatLng =
        _animatedRiderLatLng ?? _currentRiderLatLng ?? targetLatLng;

    _bikeAnimationController?.stop();
    _bikeAnimationController?.dispose();
    _bikeAnimationController = null;

    if (_isSameLatLng(startLatLng, targetLatLng)) {
      if (!mounted) return;

      setState(() {
        _applyRiderMapState(
          displayRiderLatLng: targetLatLng,
          actualRiderLatLng: targetLatLng,
          pickupLatLng: pickupLatLng,
          dropoffLatLng: dropoffLatLng,
          updatedAt: updatedAt,
        );
      });

      _focusRouteCamera(
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
        _applyRiderMapState(
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
          _applyRiderMapState(
            displayRiderLatLng: targetLatLng,
            actualRiderLatLng: targetLatLng,
            pickupLatLng: pickupLatLng,
            dropoffLatLng: dropoffLatLng,
            updatedAt: updatedAt,
          );
        });

        _focusRouteCamera(
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

  void _moveRiderCameraSafely(LatLng riderLatLng) {
    if (!_isRiderMapReady || _riderMapController == null) return;

    _lastRiderCameraMoveAt = DateTime.now();

    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || !_isRiderMapReady || _riderMapController == null) {
        return;
      }

      // Keep the rider bike centered so movement is easy to follow,
      // similar to Uber/Bolt live trip maps.
      _riderMapController!.animateCamera(
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

  String _shortAddressFromGoogleResult(Map item) {
    final components = item['address_components'];

    String route = '';
    String area = '';
    String locality = '';

    if (components is List) {
      for (final component in components) {
        if (component is! Map) continue;

        final types = component['types'];
        final longName = component['long_name']?.toString() ?? '';

        if (types is! List || longName.trim().isEmpty) continue;

        if (types.contains('route') && route.isEmpty) {
          route = longName;
        } else if ((types.contains('sublocality') ||
                types.contains('sublocality_level_1') ||
                types.contains('neighborhood')) &&
            area.isEmpty) {
          area = longName;
        } else if (types.contains('locality') && locality.isEmpty) {
          locality = longName;
        }
      }
    }

    final parts = <String>[
      if (route.isNotEmpty) route,
      if (area.isNotEmpty) area,
      if (locality.isNotEmpty && locality != area) locality,
    ];

    if (parts.isNotEmpty) return parts.join(', ');

    final formatted = item['formatted_address']?.toString() ?? '';

    if (formatted.trim().isNotEmpty) {
      return formatted.split(',').take(3).join(',').trim();
    }

    return '';
  }

  Future<void> _updateRiderStreetName(LatLng riderLatLng) async {
    if (_googleApiKey.trim().isEmpty) {
      return;
    }

    final now = DateTime.now();

    // Do not reverse-geocode every GPS tick. This avoids unnecessary Google calls.
    if (_lastReverseGeocodeAt != null &&
        now.difference(_lastReverseGeocodeAt!).inSeconds < 12) {
      return;
    }

    _lastReverseGeocodeAt = now;

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${riderLatLng.latitude},${riderLatLng.longitude}'
        '&key=$_googleApiKey',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);

      if (decoded is! Map || decoded['status'] != 'OK') {
        debugPrint(
          '[RiderMap] Reverse geocode failed: ${decoded is Map ? decoded['status'] : decoded}',
        );
        return;
      }

      final results = decoded['results'];

      if (results is! List || results.isEmpty) return;

      String address = '';

      for (final result in results) {
        if (result is! Map) continue;

        address = _shortAddressFromGoogleResult(result);

        if (address.isNotEmpty) break;
      }

      if (address.isEmpty) return;

      if (!mounted) return;

      setState(() {
        _currentRiderStreetText = address;
      });

      debugPrint('[RiderMap] Current street: $address');
    } catch (e) {
      debugPrint('[RiderMap] Reverse geocode error: $e');
    }
  }

  void _updateRiderMap({
    required Map<String, dynamic> item,
    required double latitude,
    required double longitude,
  }) {
    final riderLatLng = LatLng(latitude, longitude);

    final pickupLatLng = _jobLatLng(
      item,
      ['pickupLatitude'],
      ['pickupLongitude'],
    );

    final dropoffLatLng = _jobLatLng(
      item,
      ['dropoffLatitude'],
      ['dropoffLongitude'],
    );

    if (_riderMovementPath.isEmpty ||
        !_isSameLatLng(_riderMovementPath.last, riderLatLng)) {
      _riderMovementPath.add(riderLatLng);
    }

    if (_riderMovementPath.length > 120) {
      _riderMovementPath.removeAt(0);
    }

    _animateRiderMarkerTo(
      targetLatLng: riderLatLng,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
      updatedAt: DateTime.now(),
    );

    // Use Google Directions so the route follows roads instead of drawing
    // a misleading straight line.
    final routeDestination = _nextNavigationDestination(
      item: item,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );
    if (_shouldRefreshRoute(
      current: riderLatLng,
      destination: routeDestination,
    )) {
      _refreshRoadRoutePolyline(
        riderLatLng: riderLatLng,
        destinationLatLng: routeDestination,
      );
    }

    _updateRiderStreetName(riderLatLng);
  }

  Future<void> _stopRiderLiveTracking({bool showMessage = true}) async {
    final deliveryId = _activeTrackingDeliveryId;

    _riderTrackingTimer?.cancel();
    _riderTrackingTimer = null;
    await _riderPositionSubscription?.cancel();
    _riderPositionSubscription = null;

    if (deliveryId != null) {
      await LogisticsTrackingSignalRService.instance.leaveDeliveryTrackingGroup(
        deliveryId,
      );
    }

    if (!mounted) return;

    setState(() {
      _isLiveTracking = false;
      _activeTrackingDeliveryId = null;
      _currentRiderLatLng = null;
      _animatedRiderLatLng = null;
      _activePickupLatLng = null;
      _activeDropoffLatLng = null;
      _riderMapMarkers = {};
      _riderMapPolylines = {};
      _riderMovementPath = [];
      _riderBearing = 0;
      _lastLocationSentAt = null;
      _currentRiderStreetText = null;
      _activeRoadEtaText = null;
      _lastReverseGeocodeAt = null;
      _lastRiderCameraMoveAt = null;
      _lastRouteFetchOrigin = null;
      _lastRouteFetchDestination = null;
      _lastRouteFetchAt = null;
      _lastAcceptedPositionAt = null;
      _lastPositionStreamEventAt = null;
      _lastApiLocationPersistedAt = null;
      _lastPublishedRiderLatLng = null;
      _isPublishingRiderPosition = false;
      _isRiderMapReady = false;
    });

    if (showMessage) {
      _showSnack('Live tracking stopped.', Colors.orange);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoLine({
    required IconData icon,
    required String text,
    int maxLines = 1,
  }) {
    if (text.trim().isEmpty || text.trim().toLowerCase() == 'null') {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kSoftPanel,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: _kPrimaryBlue),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _completedBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00A76F).withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00A76F).withOpacity(0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF00A76F), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This delivery has been completed.',
              style: TextStyle(
                color: Color(0xFF00A76F),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _lastSentText() {
    if (_lastLocationSentAt == null) return '';

    final t = _lastLocationSentAt!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');

    return 'Last sent $hh:$mm:$ss';
  }

  String _etaText({
    required LatLng riderLatLng,
    required LatLng? destinationLatLng,
  }) {
    if (destinationLatLng == null) return 'ETA calculating';

    final googleEta = _activeRoadEtaText?.trim();
    if (googleEta != null && googleEta.isNotEmpty) {
      return googleEta;
    }

    final meters = Geolocator.distanceBetween(
      riderLatLng.latitude,
      riderLatLng.longitude,
      destinationLatLng.latitude,
      destinationLatLng.longitude,
    );

    // Fallback ETA only. The preferred ETA now comes from Google Directions
    // duration/duration_in_traffic when the road route is available.
    const assumedBikeSpeedKmh = 25.0;
    final minutes = (meters / 1000) / assumedBikeSpeedKmh * 60;
    final rounded = minutes.clamp(1, 180).ceil();

    return '$rounded min';
  }

  LatLng? _nextNavigationDestination({
    required Map<String, dynamic> item,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
  }) {
    final statusNumber = _statusNumber(_jobStatusValue(item));

    if ((statusNumber == DeliveryStatusCode.pickedUp ||
            statusNumber == DeliveryStatusCode.inTransit) &&
        dropoffLatLng != null) {
      return dropoffLatLng;
    }

    return pickupLatLng ?? dropoffLatLng;
  }

  String _nextNavigationLabel({
    required Map<String, dynamic> item,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
  }) {
    final destination = _nextNavigationDestination(
      item: item,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );

    if (destination == null) return 'Navigate';

    final statusNumber = _statusNumber(_jobStatusValue(item));
    if ((statusNumber == DeliveryStatusCode.pickedUp ||
            statusNumber == DeliveryStatusCode.inTransit) &&
        dropoffLatLng != null) {
      return 'Navigate to drop-off';
    }

    return pickupLatLng != null ? 'Navigate to pickup' : 'Navigate to drop-off';
  }

  Future<void> _openGoogleMapsNavigation({
    required LatLng destination,
    LatLng? origin,
  }) async {
    final navigationUri = Uri.parse(
      'google.navigation:q=${destination.latitude},${destination.longitude}&mode=d',
    );

    if (await launchUrl(navigationUri, mode: LaunchMode.externalApplication)) {
      return;
    }

    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (origin != null) 'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'travelmode': 'driving',
    });

    if (await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
      return;
    }

    _showSnack('Could not open Google Maps.', Colors.red);
  }

  void _focusRouteCamera({
    required LatLng riderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
    LatLng? activeDestinationLatLng,
  }) {
    if (!_isRiderMapReady || _riderMapController == null) return;

    if (_isFullScreenRiderMap && _isFollowingRider) {
      _moveRiderCameraSafely(riderLatLng);
      return;
    }

    final roadRoutePoints = _riderMapPolylines
        .where(
          (polyline) =>
              polyline.polylineId.value == 'road_route_to_destination',
        )
        .expand((polyline) => polyline.points)
        .toList();

    final destination =
        activeDestinationLatLng ??
        (roadRoutePoints.isNotEmpty
            ? roadRoutePoints.last
            : pickupLatLng ?? dropoffLatLng);

    if (destination == null) {
      _moveRiderCameraSafely(riderLatLng);
      return;
    }

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
      _moveRiderCameraSafely(riderLatLng);
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || !_isRiderMapReady || _riderMapController == null) return;

      _riderMapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    });
  }

  Widget _buildRiderLiveMap({
    required Map<String, dynamic> item,
    required bool isThisLive,
  }) {
    if (!isThisLive) return const SizedBox.shrink();

    final pickupLatLng =
        _activePickupLatLng ??
        _jobLatLng(item, ['pickupLatitude'], ['pickupLongitude']);

    final dropoffLatLng =
        _activeDropoffLatLng ??
        _jobLatLng(item, ['dropoffLatitude'], ['dropoffLongitude']);

    final displayRiderLatLng = _animatedRiderLatLng ?? _currentRiderLatLng;

    // Lagos fallback prevents a blank map before the first GPS fix.
    // The bike marker is shown only after the rider GPS is available.
    final mapTarget =
        displayRiderLatLng ??
        pickupLatLng ??
        dropoffLatLng ??
        const LatLng(6.5244, 3.3792);

    final navigationDestination = _nextNavigationDestination(
      item: item,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );
    final navigationLabel = _nextNavigationLabel(
      item: item,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );
    final hasRiderGps = displayRiderLatLng != null;
    final lastSentText = _lastSentText();
    final etaText = hasRiderGps
        ? _etaText(
            riderLatLng: displayRiderLatLng,
            destinationLatLng: navigationDestination,
          )
        : 'ETA --';

    final riderStreetText = _currentRiderStreetText?.trim().isNotEmpty == true
        ? _currentRiderStreetText!.trim()
        : 'Locating current street...';

    final mapMarkers = hasRiderGps
        ? _riderMapMarkers
        : <Marker>{
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

    final mapPolylines = hasRiderGps ? _riderMapPolylines : <Polyline>{};

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kCardBorder),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryBlue.withOpacity(0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 360,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: mapTarget,
                      zoom: hasRiderGps ? 16 : 12,
                    ),
                    onMapCreated: (controller) {
                      _riderMapController = controller;
                      _isRiderMapReady = true;

                      controller.setMapStyle(_focusedMapStyle);

                      if (displayRiderLatLng != null) {
                        _focusRouteCamera(
                          riderLatLng: displayRiderLatLng,
                          pickupLatLng: pickupLatLng,
                          dropoffLatLng: dropoffLatLng,
                          activeDestinationLatLng: navigationDestination,
                        );
                      }
                    },
                    markers: mapMarkers,
                    polylines: mapPolylines,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    trafficEnabled: false,
                    buildingsEnabled: false,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
                ),

                // Top route status, kept compact so the map remains visible.
                Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kCardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: _kPrimaryBlue.withOpacity(0.10),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_kAccentBlue, _kPrimaryBlue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.two_wheeler,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasRiderGps
                                    ? '$navigationLabel - ETA $etaText'
                                    : 'Waiting for GPS fix',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _kTextPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hasRiderGps
                                    ? '$riderStreetText${lastSentText.isNotEmpty ? ' - $lastSentText' : ''}'
                                    : 'Tap "I\'m on my way" and allow location access.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _kTextSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: hasRiderGps
                                ? _kCyan.withOpacity(0.16)
                                : _kYellow.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hasRiderGps
                                  ? _kCyan.withOpacity(0.4)
                                  : _kYellow.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            hasRiderGps ? 'LIVE' : 'GPS',
                            style: TextStyle(
                              color: hasRiderGps ? _kPrimaryBlue : _kNavyDot,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Recenter control.
                Positioned(
                  right: 14,
                  bottom: 68,
                  child: _mapFloatingButton(
                    icon: Icons.fullscreen_rounded,
                    tooltip: 'Open full-screen map',
                    onTap: () => _openFullScreenRiderMap(item),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 16,
                  child: _mapFloatingButton(
                    icon: Icons.my_location,
                    tooltip: 'Show complete route',
                    onTap: displayRiderLatLng == null
                        ? null
                        : () => _focusRouteCamera(
                            riderLatLng: displayRiderLatLng,
                            pickupLatLng: pickupLatLng,
                            dropoffLatLng: dropoffLatLng,
                            activeDestinationLatLng: navigationDestination,
                          ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _navigationActionPanel(
              label: navigationLabel,
              destination: navigationDestination,
              origin: displayRiderLatLng,
              etaText: etaText,
              streetText: riderStreetText,
              hasRiderGps: hasRiderGps,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: _mapLegendItem(
                    color: _kPrimaryBlue,
                    text: 'Your bike',
                  ),
                ),
                Expanded(
                  child: _mapLegendItem(color: _kCyan, text: 'Pickup'),
                ),
                Expanded(
                  child: _mapLegendItem(color: _kPink, text: 'Drop-off'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapFloatingButton({
    required IconData icon,
    required VoidCallback? onTap,
    String? tooltip,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: _kPrimaryBlue.withOpacity(0.22),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: tooltip == null
              ? Icon(
                  icon,
                  color: onTap == null ? Colors.grey : _kPrimaryBlue,
                  size: 21,
                )
              : Tooltip(
                  message: tooltip,
                  child: Icon(
                    icon,
                    color: onTap == null ? Colors.grey : _kPrimaryBlue,
                    size: 21,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _navigationActionPanel({
    required String label,
    required LatLng? destination,
    required LatLng? origin,
    required String etaText,
    required String streetText,
    required bool hasRiderGps,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kSoftPanel,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.alt_route_rounded,
              color: _kPrimaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasRiderGps ? etaText : 'Waiting for GPS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasRiderGps ? streetText : 'Start tracking to enable route',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: ElevatedButton.icon(
              onPressed: destination == null
                  ? null
                  : () => _openGoogleMapsNavigation(
                      destination: destination,
                      origin: origin,
                    ),
              icon: const Icon(Icons.map_outlined, size: 17),
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _kCardBorder,
                disabledForegroundColor: _kTextSecondary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapLegendItem({required Color color, required String text}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _deliverySafetyGatePanel({
    required bool isThisLive,
    required bool isHeadingToDropoff,
    required bool isDelivered,
    required double? distanceMeters,
    required double allowedRadiusMeters,
  }) {
    if (isDelivered) return const SizedBox.shrink();

    final targetLabel = isHeadingToDropoff ? 'drop-off point' : 'pickup point';
    final actionLabel = isHeadingToDropoff ? 'Mark Delivered' : 'Package Picked Up';

    late final IconData icon;
    late final Color color;
    late final String title;
    late final String message;

    if (!isThisLive) {
      icon = Icons.lock_outline_rounded;
      color = _kYellow;
      title = '$actionLabel locked';
      message = 'Start live tracking first. Rider must be within ${_formatDistanceMeters(allowedRadiusMeters)} of the $targetLabel before this action can be submitted.';
    } else if (distanceMeters == null) {
      icon = Icons.gps_not_fixed_rounded;
      color = _kYellow;
      title = 'Waiting for GPS check';
      message = 'Live tracking is active. Waiting for rider GPS to calculate distance to the $targetLabel.';
    } else if (distanceMeters > allowedRadiusMeters) {
      icon = Icons.wrong_location_outlined;
      color = _kPink;
      title = '$actionLabel blocked';
      message = 'You are ${_formatDistanceMeters(distanceMeters)} from the $targetLabel. Move within ${_formatDistanceMeters(allowedRadiusMeters)} to continue.';
    } else {
      icon = Icons.verified_user_outlined;
      color = const Color(0xFF00A76F);
      title = '$actionLabel unlocked';
      message = 'GPS verified: you are ${_formatDistanceMeters(distanceMeters)} from the $targetLabel, within the allowed ${_formatDistanceMeters(allowedRadiusMeters)} radius.';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> item) {
    final deliveryRequestId = _deliveryRequestId(item);
    final assignmentId = _assignmentId(item);
    final shortId = _shortId(deliveryRequestId);

    final statusNumber = _statusNumber(_jobStatusValue(item));
    final status = _formatStatus(_jobStatusValue(item));

    final pickup = _jobText(item, ['pickupAddress']);
    final dropoff = _jobText(item, ['dropoffAddress']);

    final senderName = _jobText(item, ['senderName', 'customerName']);
    final senderPhone = _jobText(item, ['senderPhone', 'customerPhone']);

    final receiverName = _jobText(item, ['receiverName']);
    final receiverPhone = _jobText(item, ['receiverPhone']);

    final packageDescription = _jobText(item, [
      'packageDescription',
      'packageCategory',
    ]);

    final isDelivered = statusNumber == DeliveryStatusCode.delivered;
    final isPickedUp = statusNumber == DeliveryStatusCode.pickedUp;
    final isInTransit = statusNumber == DeliveryStatusCode.inTransit;
    final isHeadingToDropoff = isPickedUp || isInTransit;
    final isThisLive = _activeTrackingDeliveryId == deliveryRequestId;
    final isStartingThisJob = _startingTrackingDeliveryId == deliveryRequestId;
    final isMarkingPickedUpJob =
        _markingPickedUpDeliveryId == deliveryRequestId;
    final isMarkingThisJob = _markingDeliveredDeliveryId == deliveryRequestId;
    final isAnyStartInProgress = _startingTrackingDeliveryId != null;
    final isAnyDeliveryUpdateInProgress =
        _markingPickedUpDeliveryId != null ||
        _markingDeliveredDeliveryId != null;

    final pickupLatLng = _jobLatLng(
      item,
      ['pickupLatitude'],
      ['pickupLongitude'],
    );
    final dropoffLatLng = _jobLatLng(
      item,
      ['dropoffLatitude'],
      ['dropoffLongitude'],
    );
    final riderLatLng = _currentRiderLatLng ?? _animatedRiderLatLng;
    final targetLatLng = isHeadingToDropoff ? dropoffLatLng : pickupLatLng;
    final allowedActionRadiusMeters = isHeadingToDropoff
        ? _dropoffArrivalRadiusMeters
        : _pickupArrivalRadiusMeters;
    final distanceToActionTargetMeters =
        isThisLive && riderLatLng != null && targetLatLng != null
            ? Geolocator.distanceBetween(
                riderLatLng.latitude,
                riderLatLng.longitude,
                targetLatLng.latitude,
                targetLatLng.longitude,
              )
            : null;
    final isWithinActionRadius = distanceToActionTargetMeters != null &&
        distanceToActionTargetMeters <= allowedActionRadiusMeters;
    final canSubmitStatusAction = !isAnyDeliveryUpdateInProgress &&
        isThisLive &&
        isWithinActionRadius;
    final statusActionLockedLabel = !isThisLive
        ? 'Start Tracking First'
        : (distanceToActionTargetMeters == null
              ? 'Waiting for GPS'
              : 'Move Closer');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kCardBorder),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryBlue.withOpacity(0.055),
            blurRadius: 18,
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isThisLive
                        ? const [_kPink, _kPrimaryBlue]
                        : const [_kAccentBlue, _kPrimaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isThisLive
                      ? Icons.navigation_outlined
                      : Icons.local_shipping_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortId.isNotEmpty
                          ? 'Delivery #$shortId'
                          : 'Delivery Job',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: _kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isThisLive
                          ? 'Live route active'
                          : 'Assigned delivery task',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _kTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(status),
            ],
          ),
          if (assignmentId.isNotEmpty && assignmentId != deliveryRequestId) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _kSoftPanel,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Assignment ID: ${_shortId(assignmentId)}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: _kTextSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isThisLive)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _kCyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kCyan.withOpacity(0.28)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.gps_fixed, color: _kPrimaryBlue, size: 17),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Live tracking active. Client can see your movement.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _kTextPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _infoLine(
            icon: Icons.location_on_outlined,
            text: 'Pickup: $pickup',
            maxLines: 2,
          ),
          _infoLine(
            icon: Icons.flag_outlined,
            text: 'Drop-off: $dropoff',
            maxLines: 2,
          ),
          if (senderName.isNotEmpty || senderPhone.isNotEmpty)
            _infoLine(
              icon: Icons.person_pin_circle_outlined,
              text:
                  'Sender: $senderName${senderPhone.isNotEmpty ? ' • $senderPhone' : ''}',
            ),
          if (receiverName.isNotEmpty || receiverPhone.isNotEmpty)
            _infoLine(
              icon: Icons.person_outline,
              text:
                  'Receiver: $receiverName${receiverPhone.isNotEmpty ? ' • $receiverPhone' : ''}',
            ),
          _infoLine(
            icon: Icons.inventory_2_outlined,
            text: 'Package: $packageDescription',
            maxLines: 2,
          ),
          _deliverySafetyGatePanel(
            isThisLive: isThisLive,
            isHeadingToDropoff: isHeadingToDropoff,
            isDelivered: isDelivered,
            distanceMeters: distanceToActionTargetMeters,
            allowedRadiusMeters: allowedActionRadiusMeters,
          ),
          _buildRiderLiveMap(item: item, isThisLive: isThisLive),
          const SizedBox(height: 8),
          if (isDelivered)
            _completedBox()
          else
            Row(
              children: [
                if (!isThisLive) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (isStartingThisJob || isAnyStartInProgress)
                          ? null
                          : () => _onMyWay(item),
                      icon: isStartingThisJob
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.navigation_outlined, size: 18),
                      label: Text(
                        isStartingThisJob
                            ? 'Starting...'
                            : (isHeadingToDropoff
                                  ? 'Resume Delivery'
                                  : "I'm on my way"),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _stopRiderLiveTracking(),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text(
                        'Stop Tracking',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPink,
                        side: const BorderSide(color: _kPink),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canSubmitStatusAction
                        ? (isHeadingToDropoff
                              ? () => _confirmMarkDelivered(item)
                              : () => _markPickedUp(item))
                        : null,
                    icon: isMarkingPickedUpJob || isMarkingThisJob
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isHeadingToDropoff
                                ? Icons.check_circle_outline
                                : Icons.inventory_2_outlined,
                            size: 18,
                          ),
                    label: Text(
                      isMarkingPickedUpJob || isMarkingThisJob
                          ? 'Updating...'
                          : (canSubmitStatusAction
                                ? (isHeadingToDropoff
                                      ? 'Mark Delivered'
                                      : 'Package Picked Up')
                                : statusActionLockedLabel),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isHeadingToDropoff
                          ? const Color(0xFF00A76F)
                          : _kAccentBlue,
                      disabledForegroundColor: _kTextSecondary,
                      side: BorderSide(
                        color: canSubmitStatusAction
                            ? (isHeadingToDropoff
                                  ? const Color(0xFF00A76F)
                                  : _kAccentBlue)
                            : _kCardBorder,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _topMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD7E8FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kCardBorder),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryBlue.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: _kSoftPanel,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.assignment_outlined,
              size: 34,
              color: _kPrimaryBlue.withOpacity(0.72),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No assigned jobs',
            style: TextStyle(
              color: _kTextPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Jobs assigned to this rider will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadRiderJobs,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kPrimaryBlue,
              side: const BorderSide(color: _kCardBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreenRiderMap(Map<String, dynamic> item) {
    setState(() {
      _riderMapController = null;
      _isRiderMapReady = false;
      _isFollowingRider = true;
      _fullScreenMapJob = Map<String, dynamic>.from(item);
      _isFullScreenRiderMap = true;
    });
  }

  void _closeFullScreenRiderMap() {
    setState(() {
      _riderMapController = null;
      _isRiderMapReady = false;
      _isFollowingRider = false;
      _isFullScreenRiderMap = false;
      _fullScreenMapJob = null;
    });
  }

  void _toggleFullScreenRiderFollow({
    required LatLng? riderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
    required LatLng? destinationLatLng,
  }) {
    if (riderLatLng == null) return;

    setState(() => _isFollowingRider = !_isFollowingRider);

    if (_isFollowingRider) {
      _moveRiderCameraSafely(riderLatLng);
    } else {
      _focusRouteCamera(
        riderLatLng: riderLatLng,
        pickupLatLng: pickupLatLng,
        dropoffLatLng: dropoffLatLng,
        activeDestinationLatLng: destinationLatLng,
      );
    }
  }

  void _showFullScreenRiderRoute({
    required LatLng? riderLatLng,
    required LatLng? pickupLatLng,
    required LatLng? dropoffLatLng,
    required LatLng? destinationLatLng,
  }) {
    if (riderLatLng == null) return;

    setState(() => _isFollowingRider = false);
    _focusRouteCamera(
      riderLatLng: riderLatLng,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
      activeDestinationLatLng: destinationLatLng,
    );
  }

  Widget _fullScreenRiderMapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return Material(
      color: selected ? _kPrimaryBlue : Colors.white,
      elevation: 5,
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: selected ? Colors.white : _kPrimaryBlue,
        disabledColor: Colors.grey,
      ),
    );
  }

  Widget _buildFullScreenRiderMap() {
    final item = _fullScreenMapJob;
    if (item == null) return const SizedBox.shrink();

    final pickupLatLng =
        _activePickupLatLng ??
        _jobLatLng(item, ['pickupLatitude'], ['pickupLongitude']);
    final dropoffLatLng =
        _activeDropoffLatLng ??
        _jobLatLng(item, ['dropoffLatitude'], ['dropoffLongitude']);
    final riderLatLng = _animatedRiderLatLng ?? _currentRiderLatLng;
    final destinationLatLng = _nextNavigationDestination(
      item: item,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );
    final navigationLabel = _nextNavigationLabel(
      item: item,
      pickupLatLng: pickupLatLng,
      dropoffLatLng: dropoffLatLng,
    );
    final routeLabel = navigationLabel.replaceFirst('Navigate', 'Heading');
    final mapTarget =
        riderLatLng ??
        destinationLatLng ??
        pickupLatLng ??
        dropoffLatLng ??
        const LatLng(6.5244, 3.3792);
    final etaText = riderLatLng == null
        ? 'ETA --'
        : _etaText(
            riderLatLng: riderLatLng,
            destinationLatLng: destinationLatLng,
          );
    final streetText = _currentRiderStreetText?.trim().isNotEmpty == true
        ? _currentRiderStreetText!.trim()
        : 'Locating current street...';

    final markers = riderLatLng == null
        ? <Marker>{
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
          }
        : _riderMapMarkers;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeFullScreenRiderMap();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: _kPageBackground,
          body: Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: mapTarget,
                    zoom: riderLatLng == null ? 13 : 16,
                  ),
                  onMapCreated: (controller) {
                    _riderMapController = controller;
                    _isRiderMapReady = true;
                    controller.setMapStyle(_focusedMapStyle);

                    if (riderLatLng != null) {
                      _focusRouteCamera(
                        riderLatLng: riderLatLng,
                        pickupLatLng: pickupLatLng,
                        dropoffLatLng: dropoffLatLng,
                        activeDestinationLatLng: destinationLatLng,
                      );
                    }
                  },
                  markers: markers,
                  polylines: riderLatLng == null
                      ? <Polyline>{}
                      : _riderMapPolylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: true,
                  trafficEnabled: false,
                  buildingsEnabled: false,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  minMaxZoomPreference: const MinMaxZoomPreference(11, 20),
                  padding: const EdgeInsets.fromLTRB(12, 92, 12, 170),
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _fullScreenRiderMapButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Close full-screen map',
                          onPressed: _closeFullScreenRiderMap,
                        ),
                      ),
                      Positioned(
                        left: 68,
                        top: 15,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.10),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: _kCyan,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              const Text(
                                'LIVE ROUTE',
                                style: TextStyle(
                                  color: _kPrimaryBlue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Column(
                          children: [
                            _fullScreenRiderMapButton(
                              icon: Icons.route_rounded,
                              tooltip: 'Show complete route',
                              onPressed: riderLatLng == null
                                  ? null
                                  : () => _showFullScreenRiderRoute(
                                      riderLatLng: riderLatLng,
                                      pickupLatLng: pickupLatLng,
                                      dropoffLatLng: dropoffLatLng,
                                      destinationLatLng: destinationLatLng,
                                    ),
                              selected: !_isFollowingRider,
                            ),
                            const SizedBox(height: 10),
                            _fullScreenRiderMapButton(
                              icon: Icons.navigation_rounded,
                              tooltip: 'Follow rider',
                              onPressed: riderLatLng == null
                                  ? null
                                  : () => _toggleFullScreenRiderFollow(
                                      riderLatLng: riderLatLng,
                                      pickupLatLng: pickupLatLng,
                                      dropoffLatLng: dropoffLatLng,
                                      destinationLatLng: destinationLatLng,
                                    ),
                              selected: _isFollowingRider,
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kCardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _kSoftPanel,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.two_wheeler_rounded,
                                  color: _kPrimaryBlue,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      routeLabel,
                                      style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$streetText${_lastSentText().isNotEmpty ? ' - ${_lastSentText()}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _kTextSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                etaText,
                                style: const TextStyle(
                                  color: _kPrimaryBlue,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreenRiderMap && _fullScreenMapJob != null) {
      return _buildFullScreenRiderMap();
    }

    final riderTitle = widget.riderName?.trim().isNotEmpty == true
        ? widget.riderName!.trim()
        : 'Rider Jobs';
    final canGoBack = Navigator.canPop(context);
    final activeJobs = _jobs.where((job) {
      if (job is! Map) return false;
      final status = _statusNumber(
        _jobStatusValue(Map<String, dynamic>.from(job)),
      );
      return status != DeliveryStatusCode.delivered &&
          status != 6 &&
          status != 7;
    }).length;
    final liveLabel = _isLiveTracking ? 'Live route on' : 'Ready to ride';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _kPageBackground,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: _kPrimaryBlue,
            onRefresh: _loadRiderJobs,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kAccentBlue, _kPrimaryBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _kPrimaryBlue.withOpacity(0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Material(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: canGoBack
                                  ? () => Navigator.maybePop(context)
                                  : null,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.22),
                                  ),
                                ),
                                child: Icon(
                                  canGoBack
                                      ? Icons.arrow_back_ios_new_rounded
                                      : Icons.two_wheeler_outlined,
                                  color: Colors.white,
                                  size: canGoBack ? 20 : 24,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  riderTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.riderName?.trim().isNotEmpty == true
                                      ? 'TellMe rider console'
                                      : 'Rider ID ${_shortId(widget.riderId)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFEFF8FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Material(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: _isLoading ? null : _loadRiderJobs,
                              borderRadius: BorderRadius.circular(12),
                              child: const SizedBox(
                                width: 42,
                                height: 42,
                                child: Icon(Icons.refresh, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _topMetric(
                              icon: Icons.assignment_turned_in_outlined,
                              label: 'Assigned',
                              value: '${_jobs.length}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _topMetric(
                              icon: Icons.route_outlined,
                              label: 'Active',
                              value: '$activeJobs',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _topMetric(
                              icon: Icons.sensors_outlined,
                              label: 'Status',
                              value: liveLabel,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator(color: _kPrimaryBlue),
                    ),
                  )
                else if (_jobs.isEmpty)
                  _emptyState()
                else
                  ..._jobs.map((job) {
                    if (job is! Map) return const SizedBox.shrink();
                    return _jobCard(Map<String, dynamic>.from(job));
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
