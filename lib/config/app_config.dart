// lib/config/app_config.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api_config.dart';

class AppConfig {
  // Google Maps
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  // Timeouts
  static const Duration networkTimeout = Duration(seconds: 20);
  static const Duration debounceDelay = Duration(milliseconds: 450);
  static const Duration estimateDebounceDelay = Duration(milliseconds: 450);

  // Tracking
  static const double assumedBikeSpeedKmh = 25.0;
  static const int maxMovementPathLength = 120;
  static const int animationDurationMs = 1400;

  // SignalR
  static String get signalRHubBaseUrl => ApiConfig.baseUrl;

  // Default locations (Lagos, Nigeria)
  static const LatLng defaultLocation = LatLng(6.5244, 3.3792);
}

class MapStyles {
  static const String focusedTrackingMapStyle = r'''
[
  {
    "featureType": "poi",
    "stylers": [
      { "visibility": "off" }
    ]
  },
  {
    "featureType": "transit",
    "stylers": [
      { "visibility": "off" }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "labels",
    "stylers": [
      { "visibility": "off" }
    ]
  },
  {
    "featureType": "landscape",
    "stylers": [
      { "color": "#f4f7fb" }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [
      { "color": "#ffffff" }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      { "color": "#7f8794" }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.icon",
    "stylers": [
      { "visibility": "off" }
    ]
  },
  {
    "featureType": "water",
    "stylers": [
      { "color": "#d9ecff" }
    ]
  }
]
''';
}