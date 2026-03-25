import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'weather_service.dart';

/// Loading state for individual metadata fields.
enum LoadState { loading, loaded, error }

/// Preloads all photo metadata (location, compass, weather, address) in
/// parallel.  Extends [ChangeNotifier] so the camera-preview overlay can
/// reactively rebuild as each piece of data arrives.
class MetadataPreloader extends ChangeNotifier {
  // ---- Location ----
  LoadState locationState = LoadState.loading;
  Position? position;

  // ---- Compass ----
  LoadState compassState = LoadState.loading;
  double? compassHeading;

  // ---- Weather ----
  LoadState weatherState = LoadState.loading;
  WeatherData? weatherData;

  // ---- Address (reverse geocoding) ----
  LoadState addressState = LoadState.loading;
  String? address;

  // ---- Internal ----
  final Completer<void> _completer = Completer<void>();
  StreamSubscription? _compassSubscription;
  bool _disposed = false;

  /// True when every field has finished (loaded **or** error).
  bool get isComplete =>
      locationState != LoadState.loading &&
      compassState != LoadState.loading &&
      weatherState != LoadState.loading &&
      addressState != LoadState.loading;

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /// Start preloading.  Call once, right after construction.
  void start() {
    _fetchLocation();
    _fetchCompass();
  }

  /// Waits until all data is loaded, or until [timeout] expires.
  Future<void> waitForCompletion({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (isComplete) return;
    try {
      await _completer.future.timeout(timeout);
    } catch (_) {
      debugPrint(
        '>>> Preloader: Timeout esperando datos, continuando con lo disponible',
      );
    }
  }

  // ------------------------------------------------------------------
  // Internal helpers
  // ------------------------------------------------------------------

  void _checkComplete() {
    if (isComplete && !_completer.isCompleted) {
      _completer.complete();
    }
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
      _checkComplete();
    }
  }

  // ------------------------------------------------------------------
  // Fetchers
  // ------------------------------------------------------------------

  Future<void> _fetchLocation() async {
    try {
      debugPrint('>>> Preloader: Obteniendo ubicación...');
      final pos = await LocationService().getCurrentLocation();
      if (_disposed) return;

      if (pos != null) {
        position = pos;
        locationState = LoadState.loaded;
        _safeNotify();
        debugPrint(
          '>>> Preloader: Ubicación OK: '
          'lat=${pos.latitude}, lon=${pos.longitude}, alt=${pos.altitude}',
        );
        // Launch location-dependent fetches in parallel
        _fetchWeather(pos.latitude, pos.longitude);
        _fetchAddress(pos.latitude, pos.longitude);
      } else {
        locationState = LoadState.error;
        weatherState = LoadState.error;
        addressState = LoadState.error;
        _safeNotify();
        debugPrint('>>> Preloader: Ubicación no disponible');
      }
    } catch (e) {
      if (_disposed) return;
      locationState = LoadState.error;
      weatherState = LoadState.error;
      addressState = LoadState.error;
      _safeNotify();
      debugPrint('>>> Preloader: Error ubicación: $e');
    }
  }

  Future<void> _fetchCompass() async {
    try {
      final stream = FlutterCompass.events;
      if (stream == null) {
        compassState = LoadState.error;
        _safeNotify();
        debugPrint('>>> Preloader: Sensor de brújula no disponible');
        return;
      }

      debugPrint('>>> Preloader: Suscribiéndose a brújula...');
      _compassSubscription = stream.listen((event) {
        if (_disposed) return;
        if (event.heading != null) {
          final newHeading = event.heading!;
          final prevHeading = compassHeading;
          compassHeading = newHeading; // always store the latest

          // Notify UI on first reading or when heading changes ≥ 1°
          final isFirst = compassState != LoadState.loaded;
          final significant = prevHeading == null ||
              (newHeading - prevHeading).abs() >= 1.0;

          if (isFirst || significant) {
            compassState = LoadState.loaded;
            _safeNotify();
          }
        }
      });

      // Safety timeout
      Future.delayed(const Duration(seconds: 5), () {
        if (!_disposed && compassState == LoadState.loading) {
          compassState = LoadState.error;
          _safeNotify();
          debugPrint('>>> Preloader: Brújula timeout');
        }
      });
    } catch (e) {
      if (_disposed) return;
      compassState = LoadState.error;
      _safeNotify();
      debugPrint('>>> Preloader: Error brújula: $e');
    }
  }

  Future<void> _fetchWeather(double lat, double lon) async {
    try {
      debugPrint('>>> Preloader: Obteniendo clima...');
      final weather = await WeatherService().getWeather(lat, lon);
      if (_disposed) return;

      if (weather != null) {
        weatherData = weather;
        weatherState = LoadState.loaded;
        debugPrint(
          '>>> Preloader: Clima OK: '
          '${weather.description} ${weather.temperature}°C',
        );
      } else {
        weatherState = LoadState.error;
        debugPrint('>>> Preloader: Clima no disponible');
      }
      _safeNotify();
    } catch (e) {
      if (_disposed) return;
      weatherState = LoadState.error;
      _safeNotify();
      debugPrint('>>> Preloader: Error clima: $e');
    }
  }

  Future<void> _fetchAddress(double lat, double lon) async {
    try {
      debugPrint('>>> Preloader: Obteniendo dirección...');
      final addr = await LocationService().getAddress(lat, lon);
      if (_disposed) return;

      address = addr;
      addressState =
          (addr != null && addr.isNotEmpty) ? LoadState.loaded : LoadState.error;
      _safeNotify();
      debugPrint('>>> Preloader: Dirección: $addr');
    } catch (e) {
      if (_disposed) return;
      addressState = LoadState.error;
      _safeNotify();
      debugPrint('>>> Preloader: Error dirección: $e');
    }
  }

  // ------------------------------------------------------------------
  @override
  void dispose() {
    _disposed = true;
    _compassSubscription?.cancel();
    if (!_completer.isCompleted) _completer.complete();
    super.dispose();
  }
}
