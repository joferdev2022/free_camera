import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

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
}
