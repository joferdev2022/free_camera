import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../models/photo_metadata.dart';
import 'photo_editor_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _initializeControllerFuture = _controller.initialize();
      await _initializeControllerFuture;

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Error inicializando cámara: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPhoto) return;

    setState(() {
      _isTakingPhoto = true;
    });

    try {
      await _initializeControllerFuture;

      // Capture photo FIRST (fast)
      final image = await _controller.takePicture();
      final captureTime = DateTime.now();

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Obteniendo ubicación y datos...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }

      // Get location (includes altitude)
      debugPrint('>>> Obteniendo ubicación...');
      final location = await LocationService().getCurrentLocation();
      debugPrint('>>> Ubicación: lat=${location?.latitude}, lon=${location?.longitude}, alt=${location?.altitude}');

      // Get compass heading
      double? compassHeading;
      try {
        final stream = FlutterCompass.events;
        if (stream != null) {
          debugPrint('>>> Obteniendo brújula...');
          final compassEvent = await stream.first.timeout(
            const Duration(seconds: 5),
          );
          compassHeading = compassEvent.heading;
          debugPrint('>>> Brújula: $compassHeading');
        } else {
          debugPrint('>>> Brújula: stream es null, sensor no disponible');
        }
      } catch (e) {
        debugPrint('>>> Brújula error: $e');
      }

      // Get weather data
      WeatherData? weatherData;
      if (location != null) {
        try {
          debugPrint('>>> Obteniendo clima para ${location.latitude}, ${location.longitude}...');
          weatherData = await WeatherService().getWeather(
            location.latitude,
            location.longitude,
          );
          debugPrint('>>> Clima: ${weatherData?.description} ${weatherData?.temperature}°F');
        } catch (e) {
          debugPrint('>>> Error clima: $e');
        }
      } else {
        debugPrint('>>> No hay ubicación, no se puede obtener clima');
      }

      // Create metadata with all the data
      final metadata = PhotoMetadata(
        timestamp: captureTime,
        latitude: location?.latitude,
        longitude: location?.longitude,
        accuracy: location?.accuracy.toString(),
        altitude: location?.altitude,
        compassHeading: compassHeading,
        weatherDescription: weatherData?.description,
        temperature: weatherData?.temperature,
      );

      debugPrint('>>> Metadata creada: coords=${metadata.formattedCoordinates}, clima=${metadata.formattedWeather}, alt=${metadata.formattedAltitude}');

      if (!mounted) return;

      // Hide snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Navigate to editor
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PhotoEditorScreen(
            imageFile: File(image.path),
            metadata: metadata,
          ),
        ),
      );
    } catch (e) {
      debugPrint('>>> Error capturando foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cámara')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tomar Foto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Información'),
                  content: const Text(
                    'Al tomar la foto se capturarán automáticamente:\n\n'
                    '• Fecha y hora\n'
                    '• Coordenadas GPS\n'
                    '• Altitud\n'
                    '• Dirección de la brújula\n'
                    '• Clima actual\n\n'
                    'En la siguiente pantalla podrás agregar un logo y una nota personalizada.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_controller),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    onPressed: _isTakingPhoto ? null : _takePicture,
                    backgroundColor: _isTakingPhoto ? Colors.grey : Colors.red,
                    child: _isTakingPhoto
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.camera_alt, color: Colors.white),
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
