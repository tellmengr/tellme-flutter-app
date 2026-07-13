// lib/services/google_maps_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class GoogleMapsService {
  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  final Duration timeout = AppConfig.networkTimeout;

  Future<List<Map<String, dynamic>>> searchAddress(String query) async {
    final cleanQuery = query.trim();

    if (cleanQuery.length < 3) return [];
    if (apiKey.isEmpty) {
      debugPrint('Google Maps API key is empty.');
      return _fallbackGeocodeSearch(cleanQuery);
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': cleanQuery,
        'key': apiKey,
        'types': 'address',
        'components': 'country:ng',
      },
    );

    try {
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode != 200) {
        return _fallbackGeocodeSearch(cleanQuery);
      }

      final data = jsonDecode(response.body);

      if (data is! Map) return _fallbackGeocodeSearch(cleanQuery);
      if (data['status'] != 'OK') return _fallbackGeocodeSearch(cleanQuery);
      if (data['predictions'] is! List) {
        return _fallbackGeocodeSearch(cleanQuery);
      }

      final predictions = data['predictions'] as List;

      final results = predictions.map<Map<String, dynamic>>((item) {
        final mapItem = item is Map ? item : <String, dynamic>{};
        final formatting = mapItem['structured_formatting'];

        final formattingMap = formatting is Map
            ? formatting
            : <String, dynamic>{};

        return {
          'place_id': mapItem['place_id']?.toString() ?? '',
          'description': mapItem['description']?.toString() ?? '',
          'main_text':
              formattingMap['main_text']?.toString() ??
              mapItem['description']?.toString() ??
              '',
          'secondary_text': formattingMap['secondary_text']?.toString() ?? '',
        };
      }).toList();

      if (results.isNotEmpty) return results;

      return _fallbackGeocodeSearch(cleanQuery);
    } catch (e) {
      debugPrint('Google Places search error: $e');
      return _fallbackGeocodeSearch(cleanQuery);
    }
  }

  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final cleanPlaceId = placeId.trim();

    if (cleanPlaceId.isEmpty) return null;
    if (cleanPlaceId.startsWith('geocode:')) {
      final coordinates = cleanPlaceId.replaceFirst('geocode:', '').split(',');
      if (coordinates.length != 2) return null;

      final lat = double.tryParse(coordinates[0]);
      final lng = double.tryParse(coordinates[1]);
      if (lat == null || lng == null) return null;

      return {
        'geometry': {
          'location': {'lat': lat, 'lng': lng},
        },
        'formatted_address': '',
      };
    }

    if (apiKey.isEmpty) {
      debugPrint('Google Maps API key is empty.');
      return null;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': cleanPlaceId,
        'fields': 'geometry,formatted_address',
        'key': apiKey,
      },
    );

    try {
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);

      if (data is! Map) return null;
      if (data['status'] != 'OK') return null;
      if (data['result'] is! Map) return null;

      return Map<String, dynamic>.from(data['result'] as Map);
    } catch (e) {
      debugPrint('Google place details error: $e');
      return null;
    }
  }

  Future<List<LatLng>> getDirections({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint('Google Maps API key is empty.');
      return [];
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'alternatives': 'false',
      'units': 'metric',
      'language': 'en',
      'region': 'ng',
      'key': apiKey,
    });

    try {
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[Directions] HTTP ${response.statusCode}: ${response.body}',
        );
        return [];
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        debugPrint('[Directions] Unexpected response format.');
        return [];
      }

      if (decoded['status'] != 'OK') {
        debugPrint(
          '[Directions] ${decoded['status']}: '
          '${decoded['error_message'] ?? 'No route was returned.'}',
        );
        return [];
      }

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) {
        debugPrint('[Directions] The response contained no routes.');
        return [];
      }

      final route = routes.first;
      if (route is! Map) return [];

      final detailedPoints = <LatLng>[];
      final legs = route['legs'];

      if (legs is List) {
        for (final leg in legs) {
          if (leg is! Map || leg['steps'] is! List) continue;

          for (final step in leg['steps'] as List) {
            if (step is! Map || step['polyline'] is! Map) continue;

            final encoded =
                (step['polyline'] as Map)['points']?.toString() ?? '';
            if (encoded.isEmpty) continue;

            for (final point in _decodePolyline(encoded)) {
              if (detailedPoints.isEmpty ||
                  !_sameCoordinate(detailedPoints.last, point)) {
                detailedPoints.add(point);
              }
            }
          }
        }
      }

      if (detailedPoints.length >= 2) {
        debugPrint(
          '[Directions] Using ${detailedPoints.length} detailed route points.',
        );
        return detailedPoints;
      }

      final overview = route['overview_polyline'];
      if (overview is! Map) return [];

      final encoded = overview['points']?.toString() ?? '';
      if (encoded.isEmpty) return [];

      debugPrint('[Directions] Detailed steps unavailable; using overview.');
      return _decodePolyline(encoded);
    } catch (e) {
      debugPrint('Directions API error: $e');
      return [];
    }
  }

  bool _sameCoordinate(LatLng first, LatLng second) {
    return (first.latitude - second.latitude).abs() < 0.000001 &&
        (first.longitude - second.longitude).abs() < 0.000001;
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
      } while (byte >= 0x20 && index < encoded.length);

      final dLat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);

      final dLng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  Future<String> reverseGeocode(LatLng latLng) async {
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );

      if (placemarks.isEmpty) return '';

      final place = placemarks.first;

      final parts = <String>[
        place.street ?? '',
        place.subLocality ?? '',
        place.locality ?? '',
        place.administrativeArea ?? '',
        place.country ?? '',
      ].where((x) => x.trim().isNotEmpty).toList();

      return parts.join(', ');
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
      return '';
    }
  }

  Future<List<Map<String, dynamic>>> _fallbackGeocodeSearch(
    String query,
  ) async {
    try {
      final queryWithCountry =
          query.toLowerCase().contains('nigeria') ? query : '$query, Nigeria';
      final locations = await geocoding.locationFromAddress(queryWithCountry);

      if (locations.isEmpty) return [];

      final limited = locations.take(5).toList();

      return limited.map<Map<String, dynamic>>((location) {
        final lat = location.latitude;
        final lng = location.longitude;

        return {
          'place_id': 'geocode:$lat,$lng',
          'description': queryWithCountry,
          'main_text': query,
          'secondary_text': 'Nigeria',
          'lat': lat,
          'lng': lng,
          'formatted_address': queryWithCountry,
        };
      }).toList();
    } catch (e) {
      debugPrint('Fallback address search error: $e');
      return [];
    }
  }
}
