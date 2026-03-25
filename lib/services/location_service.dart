import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  Future<Position?> getCurrentLocation() async {
    try {
      // Check if location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: Servicio de ubicación deshabilitado');
        return null;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('LocationService: Permiso actual = $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('LocationService: Permiso después de solicitar = $permission');
        if (permission == LocationPermission.denied) {
          debugPrint('LocationService: Permiso denegado');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('LocationService: Permiso denegado permanentemente');
        return null;
      }

      // Try getting current position
      try {
        debugPrint('LocationService: Obteniendo posición actual...');
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
        debugPrint('LocationService: Posición obtenida: lat=${position.latitude}, lon=${position.longitude}, alt=${position.altitude}');
        return position;
      } catch (e) {
        debugPrint('LocationService: Error getCurrentPosition: $e');
        
        // Fallback: try last known position
        debugPrint('LocationService: Intentando última posición conocida...');
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          debugPrint('LocationService: Última posición: lat=${lastPosition.latitude}, lon=${lastPosition.longitude}, alt=${lastPosition.altitude}');
          return lastPosition;
        }
        debugPrint('LocationService: No hay última posición conocida');
        return null;
      }
    } catch (e) {
      debugPrint('LocationService: Error general: $e');
      return null;
    }
  }

  /// Reverse-geocode [latitude]/[longitude] to a human-readable address
  /// using the free Nominatim (OpenStreetMap) API.
  Future<String?> getAddress(double latitude, double longitude) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$latitude'
        '&lon=$longitude'
        '&format=json'
        '&addressdetails=1'
        '&accept-language=es',
      );

      final response = await http
          .get(url, headers: {'User-Agent': 'FreeCameraApp/1.0'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final addr = data['address'];
        if (addr != null) {
          final parts = <String>[];
          // Road / street
          final road = addr['road'] ?? addr['pedestrian'] ?? addr['highway'];
          if (road != null) parts.add(road as String);
          // Suburb / neighbourhood
          final suburb = addr['suburb'] ?? addr['neighbourhood'];
          if (suburb != null) parts.add(suburb as String);

          // Already have 2 parts → return immediately (short address)
          if (parts.length >= 2) return parts.join(', ');

          // Fallback: fill up to 2 parts with city/town
          final city = addr['city'] ??
              addr['town'] ??
              addr['village'] ??
              addr['municipality'];
          if (city != null && parts.length < 2) parts.add(city as String);

          if (parts.isNotEmpty) return parts.join(', ');
        }
        // Fallback to display_name
        final displayName = data['display_name'];
        return displayName is String ? displayName : null;
      }
      return null;
    } catch (e) {
      debugPrint('LocationService: Error reverse geocoding: $e');
      return null;
    }
  }
}
