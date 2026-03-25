import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/metadata_preloader.dart';
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

  // Preloader — starts fetching ALL metadata as soon as the screen opens.
  late MetadataPreloader _preloader;

  @override
  void initState() {
    super.initState();
    _preloader = MetadataPreloader();
    _initializeCamera();
    _preloader.start(); // ← kick off location/compass/weather/address NOW
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

      // 1. Capture photo FIRST — this is instant, no waiting.
      final image = await _controller.takePicture();
      final captureTime = DateTime.now();

      // 2. If data is still loading, show a brief snackbar and wait.
      if (!_preloader.isComplete) {
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
                  Text('Finalizando captura de datos...'),
                ],
              ),
              duration: Duration(seconds: 10),
            ),
          );
        }
        await _preloader.waitForCompletion(
          timeout: const Duration(seconds: 6),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      }

      // 3. Build metadata from the preloaded data.
      final p = _preloader;
      final metadata = PhotoMetadata(
        timestamp: captureTime,
        latitude: p.position?.latitude,
        longitude: p.position?.longitude,
        accuracy: p.position?.accuracy.toString(),
        altitude: p.position?.altitude,
        compassHeading: p.compassHeading,
        weatherDescription: p.weatherData?.description,
        temperature: p.weatherData?.temperature,
        apparentTemperature: p.weatherData?.apparentTemperature,
        humidity: p.weatherData?.humidity,
        windSpeed: p.weatherData?.windSpeed,
        address: p.address ?? '',
      );

      debugPrint(
        '>>> Metadata creada: '
        'coords=${metadata.formattedCoordinates}, '
        'clima=${metadata.formattedWeather}, '
        'alt=${metadata.formattedAltitude}, '
        'dir=${metadata.formattedAddress}',
      );

      if (!mounted) return;

      // 4. Navigate to editor.
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
    _preloader.dispose();
    super.dispose();
  }

  // =====================================================================
  // UI
  // =====================================================================

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
                    'Los datos se capturan automáticamente en segundo plano:\n\n'
                    '• Fecha y hora\n'
                    '• Coordenadas GPS\n'
                    '• Altitud\n'
                    '• Dirección de la brújula\n'
                    '• Clima actual\n'
                    '• Dirección / ubicación\n\n'
                    'Puedes ver el estado en tiempo real en la vista previa.\n'
                    'En la siguiente pantalla podrás agregar un logo y una nota.',
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
          // Camera preview — fills the screen
          CameraPreview(_controller),

          // Live metadata overlay — bottom, above the shutter bar
          Positioned(
            bottom: 84,
            left: 0,
            right: 0,
            child: ListenableBuilder(
              listenable: _preloader,
              builder: (context, _) => _buildMetadataOverlay(),
            ),
          ),

          // Shutter button bar
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

  // -------------------------------------------------------------------
  // Translucent overlay showing live preloaded data
  // -------------------------------------------------------------------
  Widget _buildMetadataOverlay() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _overlayRow(
            icon: Icons.location_on,
            label: 'GPS',
            state: _preloader.locationState,
            value: _preloader.position != null
                ? _formatCoords(
                    _preloader.position!.latitude,
                    _preloader.position!.longitude,
                  )
                : null,
          ),
          const SizedBox(height: 4),
          _overlayRow(
            icon: Icons.terrain,
            label: 'Altitud',
            state: _preloader.locationState,
            value: _preloader.position != null
                ? '${_preloader.position!.altitude.toStringAsFixed(1)} m'
                : null,
          ),
          const SizedBox(height: 4),
          _overlayRow(
            icon: Icons.explore,
            label: 'Brújula',
            state: _preloader.compassState,
            value: _preloader.compassHeading != null
                ? _formatCompass(_preloader.compassHeading!)
                : null,
          ),
          const SizedBox(height: 4),
          _overlayRow(
            icon: Icons.cloud,
            label: 'Clima',
            state: _preloader.weatherState,
            value: _preloader.weatherData != null
                ? '${_preloader.weatherData!.description} | '
                    '${_preloader.weatherData!.temperature.toStringAsFixed(1)}°C'
                : null,
          ),
          const SizedBox(height: 4),
          _overlayRow(
            icon: Icons.place,
            label: 'Dirección',
            state: _preloader.addressState,
            value: _preloader.address,
          ),
        ],
      ),
    );
  }

  Widget _overlayRow({
    required IconData icon,
    required String label,
    required LoadState state,
    String? value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.greenAccent),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(child: _stateWidget(state, value)),
      ],
    );
  }

  Widget _stateWidget(LoadState state, String? value) {
    switch (state) {
      case LoadState.loading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.amber.shade300,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Cargando...',
              style: TextStyle(
                color: Colors.amber.shade300,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      case LoadState.loaded:
        return Text(
          value ?? 'N/A',
          style: const TextStyle(color: Colors.white, fontSize: 12),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        );
      case LoadState.error:
        return Text(
          'No disponible',
          style: TextStyle(color: Colors.red.shade300, fontSize: 12),
        );
    }
  }

  // -------------------------------------------------------------------
  // Formatting helpers
  // -------------------------------------------------------------------
  String _formatCoords(double lat, double lon) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(6)}°$latDir, '
        '${lon.abs().toStringAsFixed(6)}°$lonDir';
  }

  String _formatCompass(double heading) {
    double h = heading % 360;
    if (h < 0) h += 360;
    String direction;
    if (h >= 337.5 || h < 22.5) {
      direction = 'N';
    } else if (h >= 22.5 && h < 67.5) {
      direction = 'NE';
    } else if (h >= 67.5 && h < 112.5) {
      direction = 'E';
    } else if (h >= 112.5 && h < 157.5) {
      direction = 'SE';
    } else if (h >= 157.5 && h < 202.5) {
      direction = 'S';
    } else if (h >= 202.5 && h < 247.5) {
      direction = 'SO';
    } else if (h >= 247.5 && h < 292.5) {
      direction = 'O';
    } else {
      direction = 'NO';
    }
    return '${h.toStringAsFixed(1)}° $direction';
  }
}
