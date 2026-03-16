import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/photo_metadata.dart';

class PhotoProcessor {
  /// Process a photo and add the metadata overlay
  static Future<File> addMetadataToPhoto(
    File imageFile,
    PhotoMetadata metadata, {
    File? logoFile,
    String logoPosition = 'topLeft',
    String? customNote,
  }) async {
    // Read the original image
    final bytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      throw Exception('No se pudo decodificar la imagen');
    }

    // Get image dimensions
    final imgWidth = originalImage.width;
    final imgHeight = originalImage.height;

    // Create a copy to draw on
    final image = img.Image.from(originalImage);

    // Scale factor based on image width (relative to a 1080px baseline)
    final scale = imgWidth / 1080.0;

    // --- Determine overlay height (35% of image from bottom) ---
    final overlayHeight = (imgHeight * 0.38).toInt();
    final overlayStartY = imgHeight - overlayHeight;

    // Draw gradient overlay from transparent to very dark at bottom
    for (int y = overlayStartY; y < imgHeight; y++) {
      final progress = (y - overlayStartY) / overlayHeight;
      final alpha = (progress * 240).toInt().clamp(0, 240);
      for (int x = 0; x < imgWidth; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        // Blend with black
        final newR = (r * (255 - alpha) / 255).toInt();
        final newG = (g * (255 - alpha) / 255).toInt();
        final newB = (b * (255 - alpha) / 255).toInt();
        image.setPixelRgba(x, y, newR, newG, newB, 255);
      }
    }

    // --- Draw logo if provided ---
    int logoBottomY = 0;
    if (logoFile != null) {
      try {
        final logoBytes = await logoFile.readAsBytes();
        final logoImage = img.decodeImage(logoBytes);
        if (logoImage != null) {
          // Resize logo — bigger
          final logoMaxHeight = (90 * scale).toInt();
          final logoMaxWidth = (200 * scale).toInt();
          final resizedLogo = img.copyResize(
            logoImage,
            width: logoMaxWidth,
            height: logoMaxHeight,
            maintainAspect: true,
          );

          // Position logo at bottom-left area
          final logoX = (25 * scale).toInt();
          final logoY = overlayStartY + (30 * scale).toInt();
          logoBottomY = logoY + resizedLogo.height;

          img.compositeImage(image, resizedLogo, dstX: logoX, dstY: logoY);
        }
      } catch (e) {
        print('Error al procesar logo: $e');
      }
    }

    // --- Draw text overlays ---
    final white = img.ColorRgba8(255, 255, 255, 255);
    final lightGray = img.ColorRgba8(200, 200, 200, 255);

    // Use the largest built-in font for all text (arial48)
    final bigFont = img.arial48;
    final medFont = img.arial24;
    final smallFont = img.arial14;

    // Calculate base Y position for text — starts after logo or from overlay area
    final textBaseX = (30 * scale).toInt();
    int currentY;
    if (logoFile != null && logoBottomY > 0) {
      currentY = logoBottomY + (15 * scale).toInt();
    } else {
      currentY = overlayStartY + (25 * scale).toInt();
    }

    // ============ TIME (very large) ============
    img.drawString(
      image,
      metadata.formattedTime,
      font: bigFont,
      x: textBaseX,
      y: currentY,
      color: white,
    );

    // Calculate time text width to position date next to it
    // arial48 chars are ~28px wide each
    final timeCharWidth = 28;
    final timeTextWidth = metadata.formattedTime.length * timeCharWidth;
    final separatorX = textBaseX + timeTextWidth + (15 * scale).toInt();

    // Draw vertical separator line (thicker)
    final separatorTopY = currentY + 4;
    final separatorBottomY = currentY + 44;
    for (int y = separatorTopY; y < separatorBottomY; y++) {
      for (int dx = 0; dx < 3; dx++) {
        final sx = separatorX + dx;
        if (sx < imgWidth) {
          image.setPixelRgba(sx, y, 255, 255, 255, 180);
        }
      }
    }

    // ============ DATE + DAY OF WEEK (next to time) ============
    final dateX = separatorX + (15 * scale).toInt();
    img.drawString(
      image,
      metadata.formattedDate,
      font: medFont,
      x: dateX,
      y: currentY + 2,
      color: white,
    );
    img.drawString(
      image,
      metadata.formattedDayOfWeek,
      font: medFont,
      x: dateX,
      y: currentY + 28,
      color: lightGray,
    );

    // Move Y down past the time row
    currentY += 60;

    // ============ INFO BOX ============
    // Build info lines
    final infoLines = <String>[
      'Coordenadas: ${metadata.formattedCoordinates}',
      'Clima: ${metadata.formattedWeather}',
      'Altitud: ${metadata.formattedAltitude}',
      'Brujula: ${metadata.formattedCompass}',
    ];

    if (customNote != null && customNote.isNotEmpty) {
      infoLines.add('NOTA: ${customNote.toUpperCase()}');
    } else if (metadata.note.isNotEmpty) {
      infoLines.add('NOTA: ${metadata.note.toUpperCase()}');
    }

    // Line height for medium font
    final lineHeight = 30;
    final boxPadding = (12 * scale).toInt();
    final infoBoxHeight = (infoLines.length * lineHeight) + (boxPadding * 2);
    final infoBoxWidth = (imgWidth * 0.75).toInt();

    // Draw info box semi-transparent background
    final boxStartX = textBaseX - boxPadding;
    final boxStartY = currentY - boxPadding;
    for (int y = boxStartY; y < boxStartY + infoBoxHeight && y < imgHeight; y++) {
      for (int x = boxStartX; x < boxStartX + infoBoxWidth && x < imgWidth; x++) {
        if (x >= 0 && y >= 0) {
          final pixel = image.getPixel(x, y);
          final r = (pixel.r.toInt() * 0.25).toInt();
          final g = (pixel.g.toInt() * 0.25).toInt();
          final b = (pixel.b.toInt() * 0.25).toInt();
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    }

    // Draw left accent border (green line)
    final borderWidth = (4 * scale).toInt().clamp(2, 8);
    for (int y = boxStartY; y < boxStartY + infoBoxHeight && y < imgHeight; y++) {
      for (int bx = boxStartX; bx < boxStartX + borderWidth && bx < imgWidth; bx++) {
        if (bx >= 0 && y >= 0) {
          image.setPixelRgba(bx, y, 100, 220, 100, 255);
        }
      }
    }

    // Draw each info line with medium font
    for (int i = 0; i < infoLines.length; i++) {
      final lineY = currentY + (i * lineHeight);
      if (lineY < imgHeight - 20) {
        img.drawString(
          image,
          infoLines[i],
          font: medFont,
          x: textBaseX + (8 * scale).toInt(),
          y: lineY,
          color: white,
        );
      }
    }

    // --- Save the processed image ---
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}/processed_photo_$timestamp.jpg';

    final encodedBytes = img.encodeJpg(image, quality: 95);
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(encodedBytes);

    // Save to gallery
    await Gal.putImage(outputPath, album: 'Free Camera');

    return outputFile;
  }
}
