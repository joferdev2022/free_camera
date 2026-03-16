import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/photo_metadata.dart';
import '../services/photo_processor.dart';

class PhotoEditorScreen extends StatefulWidget {
  final File imageFile;
  final PhotoMetadata metadata;

  const PhotoEditorScreen({
    super.key,
    required this.imageFile,
    required this.metadata,
  });

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  File? _logoFile;
  final String _logoPosition = 'topLeft';
  bool _isProcessing = false;
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() {
          _logoFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      print('Error seleccionando logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _processAndSavePhoto() async {
    try {
      setState(() {
        _isProcessing = true;
      });

      // Process the photo with overlay
      await PhotoProcessor.addMetadataToPhoto(
        widget.imageFile,
        widget.metadata,
        logoFile: _logoFile,
        logoPosition: _logoPosition,
        customNote: _noteController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('¡Foto guardada en Galería!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Wait a bit then go back
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error guardando foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Foto'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[900],
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    'Procesando foto...',
                    style: TextStyle(color: Colors.grey[300], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Agregando datos a la imagen',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Photo preview
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          Image.file(
                            widget.imageFile,
                            height: 350,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          // Preview overlay simulation
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.8),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_logoFile != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Image.file(
                                        _logoFile!,
                                        height: 30,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        widget.metadata.formattedTime,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Container(
                                        width: 1.5,
                                        height: 30,
                                        color: Colors.white54,
                                        margin: const EdgeInsets.symmetric(horizontal: 10),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.metadata.formattedDate,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            widget.metadata.formattedDayOfWeek,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(4),
                                      border: const Border(
                                        left: BorderSide(
                                          color: Colors.greenAccent,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _overlayInfoLine('Coordenadas', widget.metadata.formattedCoordinates),
                                        _overlayInfoLine('Clima', widget.metadata.formattedWeather),
                                        _overlayInfoLine('Altitud', widget.metadata.formattedAltitude),
                                        _overlayInfoLine('Brújula', widget.metadata.formattedCompass),
                                      ],
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

                  // Metadata details card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: Colors.grey[850],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Datos Capturados',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(Icons.access_time, 'Hora', widget.metadata.formattedTimeFull),
                            _buildInfoRow(Icons.calendar_today, 'Fecha', '${widget.metadata.formattedDate} (${widget.metadata.formattedDayOfWeek})'),
                            _buildInfoRow(Icons.location_on, 'Coordenadas', widget.metadata.formattedCoordinates),
                            _buildInfoRow(Icons.cloud, 'Clima', widget.metadata.formattedWeather),
                            _buildInfoRow(Icons.terrain, 'Altitud', widget.metadata.formattedAltitude),
                            _buildInfoRow(Icons.explore, 'Brújula', widget.metadata.formattedCompass),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Note input
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: Colors.grey[850],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nota Personalizada',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Se mostrará en la foto como "NOTA:"',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _noteController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Ej: Tu nombre o descripción...',
                                hintStyle: TextStyle(color: Colors.grey[600]),
                                filled: true,
                                fillColor: Colors.grey[800],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon: Icon(Icons.note, color: Colors.grey[500]),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Logo section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: Colors.grey[850],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Logo (Opcional)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_logoFile != null)
                              Column(
                                children: [
                                  Container(
                                    height: 80,
                                    width: 80,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey[700]!),
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.grey[800],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        _logoFile!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ElevatedButton.icon(
                              onPressed: _pickLogo,
                              icon: const Icon(Icons.image),
                              label: Text(
                                _logoFile != null
                                    ? 'Cambiar Logo'
                                    : 'Seleccionar Logo',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            if (_logoFile != null) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _logoFile = null;
                                  });
                                },
                                icon: const Icon(Icons.delete, size: 18),
                                label: const Text('Quitar Logo'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _processAndSavePhoto,
                            icon: const Icon(Icons.save_alt),
                            label: const Text('Procesar y Guardar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _overlayInfoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.greenAccent),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
