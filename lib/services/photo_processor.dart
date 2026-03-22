import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/photo_metadata.dart';

class PhotoProcessor {
  // ---------------------------------------------------------------------------
  // Helper: build a TextPainter with the given parameters.
  // ---------------------------------------------------------------------------
  static TextPainter _buildTextPainter(
    String text, {
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.normal,
    double? maxWidth,
    List<Shadow>? shadows,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          fontFamily: 'Roboto', // default Flutter font, fully unicode-capable
          shadows: shadows,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxWidth != null ? 100 : 1,
    );
    painter.layout(maxWidth: maxWidth ?? double.infinity);
    return painter;
  }

  // ---------------------------------------------------------------------------
  // Helper: paint a text string on the canvas with a drop-shadow for
  // readability, using TextPainter.
  // ---------------------------------------------------------------------------
  static void _drawTextWithShadow(
    ui.Canvas canvas,
    String text, {
    required double x,
    required double y,
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.normal,
    double? maxWidth,
  }) {
    final shadows = [
      const Shadow(
        offset: Offset(2, 2),
        blurRadius: 4,
        color: Color.fromARGB(180, 0, 0, 0),
      ),
    ];

    final painter = _buildTextPainter(
      text,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      maxWidth: maxWidth,
      shadows: shadows,
    );

    painter.paint(canvas, Offset(x, y));
  }

  // ---------------------------------------------------------------------------
  // Helper: draw a shield icon with a checkmark at the given position.
  // The shield is drawn using Canvas paths; `size` controls the overall
  // height of the icon.
  // ---------------------------------------------------------------------------
  static void _drawShieldCheck(
    ui.Canvas canvas, {
    required double x,
    required double y,
    required double size,
    required Color color,
  }) {
    final double w = size * 0.8; // width is 80% of height
    final double h = size;
    final double cx = x + w / 2; // center x

    // --- Shield outline path ---
    final shieldPath = ui.Path();
    // Start at top-center
    shieldPath.moveTo(cx, y);
    // Top-right curve
    shieldPath.quadraticBezierTo(cx + w * 0.5, y, cx + w * 0.5, y + h * 0.15);
    // Right side going down
    shieldPath.lineTo(cx + w * 0.5, y + h * 0.55);
    // Bottom-right curve to bottom point
    shieldPath.quadraticBezierTo(cx + w * 0.5, y + h * 0.78, cx, y + h);
    // Bottom-left curve
    shieldPath.quadraticBezierTo(cx - w * 0.5, y + h * 0.78, cx - w * 0.5, y + h * 0.55);
    // Left side going up
    shieldPath.lineTo(cx - w * 0.5, y + h * 0.15);
    // Top-left curve back to top-center
    shieldPath.quadraticBezierTo(cx - w * 0.5, y, cx, y);
    shieldPath.close();

    // Draw shield fill (slightly transparent)
    final fillPaint = ui.Paint()
      ..color = color.withAlpha(60)
      ..style = ui.PaintingStyle.fill;
    canvas.drawPath(shieldPath, fillPaint);

    // Draw shield border
    final borderPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = size * 0.06;
    canvas.drawPath(shieldPath, borderPaint);

    // --- Checkmark inside the shield ---
    final checkPath = ui.Path();
    // Checkmark proportions relative to shield center
    final double checkStartX = cx - w * 0.22;
    final double checkStartY = y + h * 0.48;
    final double checkMidX = cx - w * 0.02;
    final double checkMidY = y + h * 0.65;
    final double checkEndX = cx + w * 0.28;
    final double checkEndY = y + h * 0.32;

    checkPath.moveTo(checkStartX, checkStartY);
    checkPath.lineTo(checkMidX, checkMidY);
    checkPath.lineTo(checkEndX, checkEndY);

    final checkPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = size * 0.09
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;
    canvas.drawPath(checkPath, checkPaint);
  }

  // ---------------------------------------------------------------------------
  // Helper: convert an img.Image (from the `image` package) into a dart:ui
  // Image. This is necessary so we can draw the photo onto a Canvas.
  // ---------------------------------------------------------------------------
  static Future<ui.Image> _imgToUiImage(img.Image src) async {
    // Ensure RGBA8 format for dart:ui compatibility
    final rgba = src.convert(numChannels: 4);
    final int w = rgba.width;
    final int h = rgba.height;

    // Build an RGBA byte buffer row-by-row
    final Uint8List pixels = Uint8List(w * h * 4);
    int offset = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = rgba.getPixel(x, y);
        pixels[offset++] = p.r.toInt();
        pixels[offset++] = p.g.toInt();
        pixels[offset++] = p.b.toInt();
        pixels[offset++] = p.a.toInt();
      }
    }

    final completer = Future<ui.Image>.value(
      await _decodeRgba(pixels, w, h),
    );
    return completer;
  }

  static Future<ui.Image> _decodeRgba(Uint8List pixels, int w, int h) async {
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(pixels);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    descriptor.dispose();
    buffer.dispose();
    return image;
  }

  // ---------------------------------------------------------------------------
  // Main entry point – process a photo and add the metadata overlay.
  // ---------------------------------------------------------------------------
  static Future<File> addMetadataToPhoto(
    File imageFile,
    PhotoMetadata metadata, {
    File? logoFile,
    String? customNote,
  }) async {
    // ------------------------------------------------------------------
    // 1. Decode the original photo with the `image` package
    // ------------------------------------------------------------------
    final bytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      throw Exception('No se pudo decodificar la imagen');
    }

    final int imgWidth = originalImage.width;
    final int imgHeight = originalImage.height;

    // Scale factor based on image width (relative to a 1080px baseline)
    final double scale = imgWidth / 1080.0;

    // Create a mutable copy of the decoded image
    final image = img.Image.from(originalImage);

    // ------------------------------------------------------------------
    // 2. Draw gradient overlay at the bottom 38% (pixel-level, image pkg)
    // ------------------------------------------------------------------
    final overlayHeight = (imgHeight * 0.38).toInt();
    final overlayStartY = imgHeight - overlayHeight;

    for (int y = overlayStartY; y < imgHeight; y++) {
      final progress = (y - overlayStartY) / overlayHeight;
      final alpha = (progress * 100).toInt().clamp(0, 100);
      for (int x = 0; x < imgWidth; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        const tintR = 80;
        const tintG = 80;
        const tintB = 80;
        final newR = (r + ((tintR - r) * alpha / 255)).toInt().clamp(0, 255);
        final newG = (g + ((tintG - g) * alpha / 255)).toInt().clamp(0, 255);
        final newB = (b + ((tintB - b) * alpha / 255)).toInt().clamp(0, 255);
        image.setPixelRgba(x, y, newR, newG, newB, 255);
      }
    }

    // ------------------------------------------------------------------
    // 3. Composite logo (pixel-level, image pkg)
    // ------------------------------------------------------------------
    int logoBottomY = 0;
    if (logoFile != null) {
      try {
        final logoBytes = await logoFile.readAsBytes();
        final logoImage = img.decodeImage(logoBytes);
        if (logoImage != null) {
          final logoMaxHeight = (120 * scale).toInt();
          final logoMaxWidth = (280 * scale).toInt();
          final resizedLogo = img.copyResize(
            logoImage,
            width: logoMaxWidth,
            height: logoMaxHeight,
            maintainAspect: true,
          );
          final logoX = (45 * scale).toInt();
          final logoY = overlayStartY + (45 * scale).toInt();
          logoBottomY = logoY + resizedLogo.height;

          img.compositeImage(image, resizedLogo, dstX: logoX, dstY: logoY);
        }
      } catch (e) {
        // ignore logo errors gracefully
      }
    }

    // ------------------------------------------------------------------
    // 4. Convert to dart:ui Image so we can use Canvas for text
    // ------------------------------------------------------------------
    final ui.Image baseUiImage = await _imgToUiImage(image);

    // Set up PictureRecorder + Canvas
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, imgWidth.toDouble(), imgHeight.toDouble()),
    );

    // Draw the base image (with gradient + logo already baked in)
    canvas.drawImage(baseUiImage, Offset.zero, ui.Paint());

    // ------------------------------------------------------------------
    // 5. Draw "Timemark" + "Foto 100% Real" — top-right corner
    // ------------------------------------------------------------------
    const Color yellowColor = Color.fromRGBO(255, 195, 47, 1.0);
    const Color whiteColor = Color.fromRGBO(255, 255, 255, 1.0);
    const Color lightGrayColor = Color.fromRGBO(200, 200, 200, 1.0);

    final double timemarkFontSize = 52 * scale;
    final double fotoRealFontSize = 36 * scale;

    // Measure "Time" and "mark" to position them
    final timePainter = _buildTextPainter(
      'Time',
      fontSize: timemarkFontSize,
      color: yellowColor,
      fontWeight: FontWeight.bold,
      shadows: [
        const Shadow(
          offset: Offset(2, 2),
          blurRadius: 4,
          color: Color.fromARGB(180, 0, 0, 0),
        ),
      ],
    );
    final markPainter = _buildTextPainter(
      'mark',
      fontSize: timemarkFontSize,
      color: whiteColor,
      fontWeight: FontWeight.bold,
      shadows: [
        const Shadow(
          offset: Offset(2, 2),
          blurRadius: 4,
          color: Color.fromARGB(180, 0, 0, 0),
        ),
      ],
    );

    final double totalTimemarkWidth = timePainter.width + markPainter.width;
    final double timemarkMarginRight = 30 * scale;
    final double timemarkMarginTop = 30 * scale;
    final double timemarkX = imgWidth - totalTimemarkWidth - timemarkMarginRight;
    final double timemarkY = timemarkMarginTop;

    timePainter.paint(canvas, Offset(timemarkX, timemarkY));
    markPainter.paint(canvas, Offset(timemarkX + timePainter.width, timemarkY));

    // "Foto 100% Real" — centered below "Timemark"
    final fotoRealPainter = _buildTextPainter(
      'Foto 100% Real',
      fontSize: fotoRealFontSize,
      color: lightGrayColor,
      fontWeight: FontWeight.normal,
      shadows: [
        const Shadow(
          offset: Offset(1, 1),
          blurRadius: 3,
          color: Color.fromARGB(150, 0, 0, 0),
        ),
      ],
    );
    final double fotoRealX =
        timemarkX + (totalTimemarkWidth - fotoRealPainter.width) / 2;
    final double fotoRealY = timemarkY + timePainter.height + (4 * scale);
    fotoRealPainter.paint(canvas, Offset(fotoRealX, fotoRealY));

    // ------------------------------------------------------------------
    // 6. Draw bottom-left text overlays (time, date, info box, photo code)
    // ------------------------------------------------------------------
    final double textBaseX = 50 * scale;
    double currentY;
    if (logoFile != null && logoBottomY > 0) {
      currentY = logoBottomY + (20 * scale);
    } else {
      currentY = overlayStartY + (40 * scale);
    }

    // ============ TIME (large) ============
    final double timeFontSize = 48 * scale;
    _drawTextWithShadow(
      canvas,
      metadata.formattedTime,
      x: textBaseX,
      y: currentY,
      fontSize: timeFontSize,
      color: whiteColor,
      fontWeight: FontWeight.bold,
    );

    // Measure the time text to position separator + date
    final timeTextPainter = _buildTextPainter(
      metadata.formattedTime,
      fontSize: timeFontSize,
      color: whiteColor,
      fontWeight: FontWeight.bold,
    );

    final double separatorX = textBaseX + timeTextPainter.width + (15 * scale);

    // Vertical separator line
    final separatorPaint = ui.Paint()
      ..color = const Color.fromARGB(180, 255, 255, 255)
      ..strokeWidth = 3 * scale;
    canvas.drawLine(
      Offset(separatorX, currentY + 6 * scale),
      Offset(separatorX, currentY + timeTextPainter.height - 6 * scale),
      separatorPaint,
    );

    // ============ DATE + DAY OF WEEK (next to time) ============
    final double dateX = separatorX + (15 * scale);
    final double dateFontSize = 24 * scale;

    _drawTextWithShadow(
      canvas,
      metadata.formattedDate,
      x: dateX,
      y: currentY + (2 * scale),
      fontSize: dateFontSize,
      color: whiteColor,
    );
    _drawTextWithShadow(
      canvas,
      metadata.formattedDayOfWeek,
      x: dateX,
      y: currentY + (2 * scale) + dateFontSize + (4 * scale),
      fontSize: dateFontSize,
      color: lightGrayColor,
    );

    // Move Y past the time row
    currentY += timeTextPainter.height + (16 * scale);

    // ============ ADDRESS (if available) ============
    if (metadata.formattedAddress.isNotEmpty) {
      _drawTextWithShadow(
        canvas,
        metadata.formattedAddress,
        x: textBaseX,
        y: currentY,
        fontSize: 28 * scale,
        color: whiteColor,
        fontWeight: FontWeight.bold,
      );
      final addrPainter = _buildTextPainter(
        metadata.formattedAddress,
        fontSize: 28 * scale,
        color: whiteColor,
        fontWeight: FontWeight.bold,
      );
      currentY += addrPainter.height + (12 * scale);
    }

    // ============ INFO BOX ============
    final double infoFontSize = 36 * scale;
    final double boxPadding = 14 * scale;
    final double textInset = 10 * scale;
    final double infoBoxWidth = imgWidth * 0.78;
    final double boxStartX = textBaseX - boxPadding;

    // Build info lines
    final infoLines = <String>[
      'Coordenadas: ${metadata.formattedCoordinates}',
      'Clima: ${metadata.formattedWeather}',
      'Altitud: ${metadata.formattedAltitude}',
      'Brújula: ${metadata.formattedCompass}',
    ];

    if (customNote != null && customNote.isNotEmpty) {
      infoLines.add('NOTA: ${customNote.toUpperCase()}');
    } else if (metadata.note.isNotEmpty) {
      infoLines.add('NOTA: ${metadata.note.toUpperCase()}');
    }

    // Use ParagraphBuilder for each line so Canvas handles word-wrap
    // First pass: measure total height needed for the info box
    final double maxLineWidth = infoBoxWidth - (2 * boxPadding) - (2 * textInset);
    final double lineSpacing = 12 * scale; // extra gap between info lines
    final List<TextPainter> infoPainters = [];

    for (final line in infoLines) {
      final painter = _buildTextPainter(
        line,
        fontSize: infoFontSize,
        color: whiteColor,
        maxWidth: maxLineWidth,
        shadows: [
          const Shadow(
            offset: Offset(1, 1),
            blurRadius: 3,
            color: Color.fromARGB(150, 0, 0, 0),
          ),
        ],
      );
      infoPainters.add(painter);
    }

    double totalInfoHeight = 0;
    for (int i = 0; i < infoPainters.length; i++) {
      totalInfoHeight += infoPainters[i].height;
      if (i < infoPainters.length - 1) {
        totalInfoHeight += lineSpacing;
      }
    }

    final double infoBoxHeight = totalInfoHeight + (2 * boxPadding);
    final double boxStartY = currentY - boxPadding;

    // Draw info box semi-transparent background
    final boxPaint = ui.Paint()
      ..color = const Color.fromARGB(90, 90, 90, 90);
    final boxRect = ui.RRect.fromRectAndRadius(
      Rect.fromLTWH(boxStartX, boxStartY, infoBoxWidth, infoBoxHeight),
      Radius.circular(8 * scale),
    );
    canvas.drawRRect(boxRect, boxPaint);

    // Draw each info line (TextPainter handles wrapping automatically)
    double lineY = currentY;
    for (int i = 0; i < infoPainters.length; i++) {
      infoPainters[i].paint(canvas, Offset(textBaseX + textInset, lineY));
      lineY += infoPainters[i].height + lineSpacing;
    }

    // ============ PHOTO CODE — bottom-left with gray bar + shield icon ============
    final double codeFontSize = 24 * scale;
    final String photoCodeFullText = 'Código de Foto: ${metadata.photoCode}';

    // Measure the text first to size the bar correctly
    final codeTextPainter = _buildTextPainter(
      photoCodeFullText,
      fontSize: codeFontSize,
      color: lightGrayColor,
    );

    final double shieldSize = codeTextPainter.height * 1.3;
    final double codeBarHeight = codeTextPainter.height + (16 * scale);
    final double codeBarY = imgHeight.toDouble() - codeBarHeight;

    // Draw semi-transparent gray bar spanning the full image width
    final codeBarPaint = ui.Paint()
      ..color = const Color.fromARGB(120, 100, 100, 100);
    canvas.drawRect(
      Rect.fromLTWH(0, codeBarY, imgWidth.toDouble(), codeBarHeight),
      codeBarPaint,
    );

    // Draw thin line ~10px above the text, spanning only the text+shield width
    final double lineAboveGap = 10 * scale;
    final double totalContentWidth =
        (shieldSize * 0.8) + (10 * scale) + codeTextPainter.width;
    final double lineStartX = textBaseX;
    final double lineEndX = textBaseX + totalContentWidth;
    final double lineAboveY = codeBarY + (codeBarHeight - codeTextPainter.height) / 2 - lineAboveGap;
    final codeBarLinePaint = ui.Paint()
      ..color = const Color.fromARGB(100, 180, 180, 180)
      ..strokeWidth = 1.5 * scale;
    canvas.drawLine(
      Offset(lineStartX, lineAboveY),
      Offset(lineEndX, lineAboveY),
      codeBarLinePaint,
    );

    // Vertical center of the bar
    final double codeContentY = codeBarY + (codeBarHeight - codeTextPainter.height) / 2;

    // Draw shield-check icon
    final double shieldX = textBaseX;
    final double shieldY = codeBarY + (codeBarHeight - shieldSize) / 2;
    _drawShieldCheck(
      canvas,
      x: shieldX,
      y: shieldY,
      size: shieldSize,
      color: lightGrayColor,
    );

    // Draw photo code text after the shield icon
    final double codeTextX = shieldX + shieldSize * 0.8 + (10 * scale);
    _drawTextWithShadow(
      canvas,
      photoCodeFullText,
      x: codeTextX,
      y: codeContentY,
      fontSize: codeFontSize,
      color: lightGrayColor,
    );

    // ============ RIGHT EDGE — vertical photo code + "Timemark Verified" ============
    // Drawn vertically along the right edge, reading bottom-to-top.
    // No gray bar behind these — just text with shadows.
    final double rightEdgeFontSize = 18 * scale;
    final double rightEdgeMargin = 15 * scale;
    const Color rightEdgeTextColor = Color.fromARGB(160, 200, 200, 200);

    // Rotation is -90° (counter-clockwise) = -π/2 radians.
    // This makes text read from bottom to top.
    // After rotating -90°:
    //   To place text at screen position (screenX, screenY),
    //   draw at canvas coords (-screenY, screenX).

    canvas.save();
    canvas.rotate(-3.14159265 / 2); // -90° = bottom-to-top

    // --- Photo code (vertical, right edge, bottom-to-top) ---
    // screenX = imgWidth - margin - fontHeight (near the right edge)
    // screenY = we want text to appear roughly in the middle-to-lower area
    final double vertScreenX = imgWidth.toDouble() - rightEdgeMargin - rightEdgeFontSize;

    // Place the photo code ending around 65% down the image
    final double codeEndScreenY = imgHeight * 0.65;
    // In -90° rotated coords: drawX = -screenY, drawY = screenX
    _drawTextWithShadow(
      canvas,
      metadata.photoCode,
      x: -codeEndScreenY,
      y: vertScreenX,
      fontSize: rightEdgeFontSize,
      color: rightEdgeTextColor,
    );

    // --- "Timemark Verified" (vertical, right edge, above the code) ---
    // "Above" in bottom-to-top direction means further down screen-Y
    final double verifiedGap = 20 * scale;

    // Measure "Timemark Verified" to position it
    final verifiedPainter = _buildTextPainter(
      'Timemark Verified',
      fontSize: rightEdgeFontSize,
      color: rightEdgeTextColor,
      shadows: [
        const Shadow(
          offset: Offset(1, 1),
          blurRadius: 3,
          color: Color.fromARGB(150, 0, 0, 0),
        ),
      ],
    );

    // Place it right after (below on screen) the photo code
    final double verifiedStartScreenY = codeEndScreenY + verifiedGap;
    _drawTextWithShadow(
      canvas,
      'Timemark Verified',
      x: -verifiedStartScreenY - verifiedPainter.width,
      y: vertScreenX,
      fontSize: rightEdgeFontSize,
      color: rightEdgeTextColor,
    );

    canvas.restore();

    // ------------------------------------------------------------------
    // 7. Encode the Canvas result back to JPEG bytes
    // ------------------------------------------------------------------
    final picture = recorder.endRecording();
    final ui.Image finalImage = await picture.toImage(imgWidth, imgHeight);
    final ByteData? byteData = await finalImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    if (byteData == null) {
      throw Exception('Error al renderizar la imagen procesada');
    }

    // Convert raw RGBA back to img.Image for JPEG encoding
    final Uint8List rawPixels = byteData.buffer.asUint8List();
    final outputImg = img.Image(width: imgWidth, height: imgHeight);
    int pixelOffset = 0;
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final r = rawPixels[pixelOffset];
        final g = rawPixels[pixelOffset + 1];
        final b = rawPixels[pixelOffset + 2];
        final a = rawPixels[pixelOffset + 3];
        outputImg.setPixelRgba(x, y, r, g, b, a);
        pixelOffset += 4;
      }
    }

    // Clean up dart:ui resources
    baseUiImage.dispose();
    finalImage.dispose();

    // ------------------------------------------------------------------
    // 8. Save to file + gallery
    // ------------------------------------------------------------------
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}/processed_photo_$timestamp.jpg';

    final encodedBytes = img.encodeJpg(outputImg, quality: 95);
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(encodedBytes);

    // Save to gallery
    await Gal.putImage(outputPath, album: 'Free Camera');

    return outputFile;
  }
}
