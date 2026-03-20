import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/photo_metadata.dart';

class PhotoProcessor {
  /// Transliterate special characters to ASCII equivalents
  /// so they render correctly with the built-in bitmap fonts.
  static String _sanitizeText(String text) {
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'ñ': 'n',
      'Ñ': 'N',
      'ü': 'u',
      'Ü': 'U',
      '°': ' ',
      '¡': '!',
      '¿': '?',
      'à': 'a',
      'è': 'e',
      'ì': 'i',
      'ò': 'o',
      'ù': 'u',
      'À': 'A',
      'È': 'E',
      'Ì': 'I',
      'Ò': 'O',
      'Ù': 'U',
      'â': 'a',
      'ê': 'e',
      'î': 'i',
      'ô': 'o',
      'û': 'u',
      'Â': 'A',
      'Ê': 'E',
      'Î': 'I',
      'Ô': 'O',
      'Û': 'U',
      'ä': 'a',
      'ë': 'e',
      'ï': 'i',
      'ö': 'o',
      'Ä': 'A',
      'Ë': 'E',
      'Ï': 'I',
      'Ö': 'O',
      'ç': 'c',
      'Ç': 'C',
    };
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString();
  }

  /// Process a photo and add the metadata overlay
  static Future<File> addMetadataToPhoto(
    File imageFile,
    PhotoMetadata metadata, {
    File? logoFile,
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

    // Draw gradient overlay — soft, translucent gray (barely noticeable)
    for (int y = overlayStartY; y < imgHeight; y++) {
      final progress = (y - overlayStartY) / overlayHeight;
      // Max alpha ~100 for a very subtle overlay
      final alpha = (progress * 100).toInt().clamp(0, 100);
      for (int x = 0; x < imgWidth; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        // Blend towards a soft gray (80, 80, 80) instead of pure black
        const tintR = 80;
        const tintG = 80;
        const tintB = 80;
        final newR = (r + ((tintR - r) * alpha / 255)).toInt().clamp(0, 255);
        final newG = (g + ((tintG - g) * alpha / 255)).toInt().clamp(0, 255);
        final newB = (b + ((tintB - b) * alpha / 255)).toInt().clamp(0, 255);
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
          final logoMaxHeight = (120 * scale).toInt();
          final logoMaxWidth = (280 * scale).toInt();
          final resizedLogo = img.copyResize(
            logoImage,
            width: logoMaxWidth,
            height: logoMaxHeight,
            maintainAspect: true,
          );

          // Position logo — shifted right and down
          final logoX = (45 * scale).toInt();
          final logoY = overlayStartY + (45 * scale).toInt();
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
    final yellow = img.ColorRgba8(255, 195, 47, 255);

    // --- Draw "Timemark" + "Foto 100% Real" in top-right corner ---
    final timemarkFont = img.arial48; // closest to arial52
    final fotoRealFont = img.arial24; // closest to arial36

    // "Time" in yellow, "mark" in white — drawn separately
    // Approximate char width for arial48: ~28px, for arial24: ~14px
    final timemarkCharWidth = 28;
    final timeText = 'Time';
    final markText = 'mark';
    final timeWidth = timeText.length * timemarkCharWidth;
    final markWidth = markText.length * timemarkCharWidth;
    final totalTimemarkWidth = timeWidth + markWidth;

    // Position in top-right corner with margin
    final timemarkMarginRight = (30 * scale).toInt();
    final timemarkMarginTop = (30 * scale).toInt();
    final timemarkX = imgWidth - totalTimemarkWidth - timemarkMarginRight;
    final timemarkY = timemarkMarginTop;

    // Draw shadow for "Time"
    img.drawString(
      image,
      timeText,
      font: timemarkFont,
      x: timemarkX + 2,
      y: timemarkY + 2,
      color: img.ColorRgba8(0, 0, 0, 150),
    );
    // Draw "Time" in yellow
    img.drawString(
      image,
      timeText,
      font: timemarkFont,
      x: timemarkX,
      y: timemarkY,
      color: yellow,
    );

    // Draw shadow for "mark"
    final markX = timemarkX + timeWidth;
    img.drawString(
      image,
      markText,
      font: timemarkFont,
      x: markX + 2,
      y: timemarkY + 2,
      color: img.ColorRgba8(0, 0, 0, 150),
    );
    // Draw "mark" in white
    img.drawString(
      image,
      markText,
      font: timemarkFont,
      x: markX,
      y: timemarkY,
      color: white,
    );

    // Draw "Foto 100% Real" below "Timemark"
    final fotoRealText = 'Foto 100% Real';
    final fotoRealCharWidth = 14; // approximate char width for arial24
    final fotoRealWidth = fotoRealText.length * fotoRealCharWidth;
    // Center "Foto 100% Real" relative to "Timemark"
    final fotoRealX = timemarkX + ((totalTimemarkWidth - fotoRealWidth) ~/ 2);
    final fotoRealY = timemarkY + 52; // below Timemark text

    // Draw shadow for readability
    img.drawString(
      image,
      fotoRealText,
      font: fotoRealFont,
      x: fotoRealX + 1,
      y: fotoRealY + 1,
      color: img.ColorRgba8(0, 0, 0, 150),
    );
    // Draw "Foto 100% Real" in lightGray (same as photo code color)
    img.drawString(
      image,
      fotoRealText,
      font: fotoRealFont,
      x: fotoRealX,
      y: fotoRealY,
      color: lightGray,
    );

    // Use the largest built-in font for all text (arial48)
    final bigFont = img.arial48;
    final medFont = img.arial24;

    // Calculate base Y position for text — shifted right and down
    final textBaseX = (50 * scale).toInt();
    int currentY;
    if (logoFile != null && logoBottomY > 0) {
      currentY = logoBottomY + (20 * scale).toInt();
    } else {
      currentY = overlayStartY + (40 * scale).toInt();
    }

    // ============ TIME (very large) ============
    img.drawString(
      image,
      _sanitizeText(metadata.formattedTime),
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
      _sanitizeText(metadata.formattedDate),
      font: medFont,
      x: dateX,
      y: currentY + 2,
      color: white,
    );
    img.drawString(
      image,
      _sanitizeText(metadata.formattedDayOfWeek),
      font: medFont,
      x: dateX,
      y: currentY + 28,
      color: lightGray,
    );

    // Move Y down past the time row
    currentY += 60;

    // ============ INFO BOX ============
    // Font for info box: arial24 is the closest built-in to arial36
    // (the image package only provides arial14, arial24, arial48).
    final infoFont = img.arial24;
    // Approximate character width for arial24 bitmap font
    const infoCharWidth = 13;

    // Build raw info lines (before wrapping)
    final rawInfoLines = <String>[
      _sanitizeText('Coordenadas: ${metadata.formattedCoordinates}'),
      _sanitizeText('Clima: ${metadata.formattedWeather}'),
      _sanitizeText('Altitud: ${metadata.formattedAltitude}'),
      _sanitizeText('Brujula: ${metadata.formattedCompass}'),
    ];

    if (customNote != null && customNote.isNotEmpty) {
      rawInfoLines.add(_sanitizeText('NOTA: ${customNote.toUpperCase()}'));
    } else if (metadata.note.isNotEmpty) {
      rawInfoLines.add(_sanitizeText('NOTA: ${metadata.note.toUpperCase()}'));
    }

    // --- Word-wrap logic ---
    final boxPadding = (14 * scale).toInt();
    final infoBoxWidth = (imgWidth * 0.78).toInt();
    final textInset = (8 * scale).toInt();
    // Maximum available pixel width for text inside the box
    final maxTextWidth = infoBoxWidth - (2 * boxPadding) - (2 * textInset);
    // Maximum characters that fit in one line
    final maxCharsPerLine = (maxTextWidth / infoCharWidth).floor().clamp(1, 9999);

    // Wrap a single string into multiple lines respecting word boundaries
    List<String> wrapLine(String text, int maxChars) {
      if (text.length <= maxChars) return [text];
      final words = text.split(' ');
      final lines = <String>[];
      var current = '';
      for (final word in words) {
        if (current.isEmpty) {
          // If a single word exceeds maxChars, force-break it
          if (word.length > maxChars) {
            int start = 0;
            while (start < word.length) {
              final end = (start + maxChars).clamp(0, word.length);
              lines.add(word.substring(start, end));
              start = end;
            }
          } else {
            current = word;
          }
        } else if ((current.length + 1 + word.length) <= maxChars) {
          current += ' $word';
        } else {
          lines.add(current);
          // Handle word longer than maxChars after a line break
          if (word.length > maxChars) {
            int start = 0;
            while (start < word.length) {
              final end = (start + maxChars).clamp(0, word.length);
              lines.add(word.substring(start, end));
              start = end;
            }
            current = '';
          } else {
            current = word;
          }
        }
      }
      if (current.isNotEmpty) {
        lines.add(current);
      }
      return lines;
    }

    // Apply wrapping to all info lines
    final wrappedInfoLines = <String>[];
    for (final line in rawInfoLines) {
      wrappedInfoLines.addAll(wrapLine(line, maxCharsPerLine));
    }

    // Line height: increased spacing between rows for readability
    // arial24 glyphs are ~24px tall; using 34px gives ~10px gap between lines
    final lineHeight = 34;
    final infoBoxHeight =
        (wrappedInfoLines.length * lineHeight) + (boxPadding * 2);

    // Draw info box — soft, subtle semi-transparent gray background
    final boxStartX = textBaseX - boxPadding;
    final boxStartY = currentY - boxPadding;
    for (
      int y = boxStartY;
      y < boxStartY + infoBoxHeight && y < imgHeight;
      y++
    ) {
      for (
        int x = boxStartX;
        x < boxStartX + infoBoxWidth && x < imgWidth;
        x++
      ) {
        if (x >= 0 && y >= 0) {
          final pixel = image.getPixel(x, y);
          // Blend with soft gray (90,90,90) at ~35% opacity for a subtle look
          const tintR = 90;
          const tintG = 90;
          const tintB = 90;
          const blendAlpha = 90; // out of 255
          final r = (pixel.r.toInt() +
                  ((tintR - pixel.r.toInt()) * blendAlpha / 255))
              .toInt()
              .clamp(0, 255);
          final g = (pixel.g.toInt() +
                  ((tintG - pixel.g.toInt()) * blendAlpha / 255))
              .toInt()
              .clamp(0, 255);
          final b = (pixel.b.toInt() +
                  ((tintB - pixel.b.toInt()) * blendAlpha / 255))
              .toInt()
              .clamp(0, 255);
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    }

    // Draw each wrapped info line
    for (int i = 0; i < wrappedInfoLines.length; i++) {
      final lineY = currentY + (i * lineHeight);
      if (lineY < imgHeight - 20) {
        img.drawString(
          image,
          wrappedInfoLines[i],
          font: infoFont,
          x: textBaseX + textInset,
          y: lineY,
          color: white,
        );
      }
    }

    // --- Draw photo code at bottom-left ---
    final photoCodeText = _sanitizeText('Codigo de Foto: ${metadata.photoCode}');
    final codeY = imgHeight - (35 * scale).toInt();
    final codeX = textBaseX;
    // Draw shadow for readability
    img.drawString(
      image,
      photoCodeText,
      font: medFont,
      x: codeX + 1,
      y: codeY + 1,
      color: img.ColorRgba8(0, 0, 0, 150),
    );
    img.drawString(
      image,
      photoCodeText,
      font: medFont,
      x: codeX,
      y: codeY,
      color: lightGray,
    );

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
