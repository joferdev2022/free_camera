import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
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
    final double w = size * 0.85; // slightly wider
    final double h = size;
    final double cx = x + w / 2; // center x

    // --- Shield outline path (Classic straight-edged security shield) ---
    final shieldPath = ui.Path();
    final double topY = y + h * 0.08; // slight dip in the top center
    shieldPath.moveTo(cx, topY);
    // Line to top-right corner
    shieldPath.lineTo(cx + w * 0.5, y);
    // Line down right side
    shieldPath.lineTo(cx + w * 0.5, y + h * 0.5);
    // Curve to bottom point
    shieldPath.quadraticBezierTo(cx + w * 0.5, y + h * 0.85, cx, y + h);
    // Curve up left side
    shieldPath.quadraticBezierTo(
      cx - w * 0.5,
      y + h * 0.85,
      cx - w * 0.5,
      y + h * 0.5,
    );
    // Line up left side
    shieldPath.lineTo(cx - w * 0.5, y);
    // Back to top-center
    shieldPath.close();

    // Draw shield border (outline only)
    final borderPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = size * 0.08
      ..strokeJoin = ui.StrokeJoin.round;
    canvas.drawPath(shieldPath, borderPaint);

    // --- Checkmark inside the shield ---
    final checkPath = ui.Path();
    final double checkStartX = cx - w * 0.25;
    final double checkStartY = y + h * 0.50;
    final double checkMidX = cx - w * 0.05;
    final double checkMidY = y + h * 0.70;
    final double checkEndX = cx + w * 0.30;
    final double checkEndY = y + h * 0.35;

    checkPath.moveTo(checkStartX, checkStartY);
    checkPath.lineTo(checkMidX, checkMidY);
    checkPath.lineTo(checkEndX, checkEndY);

    final checkPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = size * 0.08
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

    final completer = Future<ui.Image>.value(await _decodeRgba(pixels, w, h));
    return completer;
  }

  static Future<ui.Image> _decodeRgba(Uint8List pixels, int w, int h) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      pixels,
    );
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
    // 3. Prepare logo for Canvas drawing (decode + resize + round corners)
    //    The logo will be drawn on the Canvas in step 6 so it participates
    //    in the dynamic layout and never overlaps with text.
    // ------------------------------------------------------------------
    img.Image? preparedLogo;
    int preparedLogoWidth = 0;
    int preparedLogoHeight = 0;
    if (logoFile != null) {
      try {
        final logoBytes = await logoFile.readAsBytes();
        final logoImage = img.decodeImage(logoBytes);
        if (logoImage != null) {
          final logoMaxHeight = (160 * scale).toInt();
          final logoMaxWidth = (360 * scale).toInt();

          // Only constrain by ONE dimension to avoid black padding bars.
          // When both width AND height are given with maintainAspect,
          // the image package pads the rest with black — that's the
          // "black rectangle" the user sees.
          final double logoAspect = logoImage.width / logoImage.height;
          int targetW, targetH;
          if (logoAspect >= (logoMaxWidth / logoMaxHeight)) {
            // Logo is wider than the bounding box — constrain by width
            targetW = logoMaxWidth;
            targetH = (logoMaxWidth / logoAspect).round();
          } else {
            // Logo is taller — constrain by height
            targetH = logoMaxHeight;
            targetW = (logoMaxHeight * logoAspect).round();
          }
          final resizedLogo = img.copyResize(
            logoImage,
            width: targetW,
            height: targetH,
          );

          final int lw = resizedLogo.width;
          final int lh = resizedLogo.height;

          preparedLogo = resizedLogo;
          preparedLogoWidth = lw;
          preparedLogoHeight = lh;
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
    final double timemarkX =
        imgWidth - totalTimemarkWidth - timemarkMarginRight;
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
    //
    // STRATEGY: Measure everything FIRST, compute the ideal startY so that
    // all content fits between the logo (or overlay top) and the photo-code
    // line at the bottom, with a minimum 35px (scaled) gap before the code.
    // ------------------------------------------------------------------
    final double textBaseX = 50 * scale;
    final double minGap = 35 * scale;

    // --- Pre-measure all elements ---
    final double timeFontSize = 122 * scale;
    final timeTextPainter = _buildTextPainter(
      metadata.formattedTime,
      fontSize: timeFontSize,
      color: whiteColor,
      fontWeight: FontWeight.w300,
    );

    final double dateFontSize = 52 * scale;
    final double addrFontSize = 34 * scale;

    double addressHeight = 0;
    if (metadata.formattedAddress.isNotEmpty) {
      final addrPainter = _buildTextPainter(
        metadata.formattedAddress,
        fontSize: addrFontSize,
        color: whiteColor,
        fontWeight: FontWeight.bold,
      );
      addressHeight = addrPainter.height + (12 * scale); // height + bottom gap
    }

    // Info box measurements
    final double infoFontSize = 42 * scale;
    final double boxPadding = 14 * scale;
    final double textInset = 10 * scale;
    final double infoBoxWidth = imgWidth * 0.78;
    final double boxStartX = textBaseX - boxPadding;

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

    final double maxLineWidth =
        infoBoxWidth - (2 * boxPadding) - (2 * textInset);
    final double lineSpacing = 12 * scale;
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

    // Photo code measurements (needed to know the bottom boundary)
    final double codeFontSize = 24 * scale;
    final String photoCodeFullText = 'Código de Foto: ${metadata.photoCode}';
    final codeTextPainter = _buildTextPainter(
      photoCodeFullText,
      fontSize: codeFontSize,
      color: lightGrayColor,
    );
    final double codeBarHeight = codeTextPainter.height + (16 * scale);
    final double codeBarY = imgHeight.toDouble() - codeBarHeight;
    final double codeContentY =
        codeBarY + (codeBarHeight - codeTextPainter.height) / 2;
    final double codeLineAboveY = codeContentY - (20 * scale);

    // --- Compute total height of all stacked elements (including logo) ---
    final double logoGap = 20 * scale; // gap between logo and time
    final double logoTotalHeight = (preparedLogo != null)
        ? preparedLogoHeight.toDouble() + logoGap
        : 0;
    final double timeRowHeight =
        timeTextPainter.height + (16 * scale); // time row + gap
    final double totalContentHeight =
        logoTotalHeight + timeRowHeight + addressHeight + infoBoxHeight;

    // The bottom boundary: the info box must end at least 35px above the code line
    final double maxBottomY = codeLineAboveY - minGap;

    // The ideal top position: where we'd like to start drawing
    final double idealStartY = overlayStartY + (40 * scale);

    // Check if the content fits between idealStartY and maxBottomY
    final double contentEndY = idealStartY + totalContentHeight;
    double startY;
    if (contentEndY <= maxBottomY) {
      // Fits normally — use the ideal start position
      startY = idealStartY;
    } else {
      // Doesn't fit — push startY upward so the bottom of
      // the content aligns with maxBottomY
      startY = maxBottomY - totalContentHeight;
      // But don't go above a reasonable minimum (e.g. 10% of the image)
      final double absoluteMinY = imgHeight * 0.10;
      if (startY < absoluteMinY) {
        startY = absoluteMinY;
      }
    }

    // --- Now DRAW everything from startY downward ---
    double currentY = startY;

    // ============ LOGO (if available) ============
    if (preparedLogo != null) {
      final ui.Image logoUiImage = await _imgToUiImage(preparedLogo);
      final double logoDrawX = textBaseX;
      final double logoDrawY = currentY;

      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(logoDrawX, logoDrawY, preparedLogoWidth.toDouble(), preparedLogoHeight.toDouble()),
        Radius.circular(18 * scale),
      ));
      canvas.drawImage(logoUiImage, Offset(logoDrawX, logoDrawY), ui.Paint());
      canvas.restore();
      
      logoUiImage.dispose();
      currentY += preparedLogoHeight.toDouble() + logoGap;
    }

    // ============ TIME (large, light weight, no heavy shadow) ============
    final timePainterFinal = _buildTextPainter(
      metadata.formattedTime,
      fontSize: timeFontSize,
      color: whiteColor,
      fontWeight: FontWeight.w300,
      shadows: [
        const Shadow(
          offset: Offset(1, 1),
          blurRadius: 2,
          color: Color.fromARGB(100, 0, 0, 0),
        ),
      ],
    );
    timePainterFinal.paint(canvas, Offset(textBaseX, currentY));

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
    final double dateBlockHeight = (dateFontSize * 2) + (4 * scale);
    final double dateStartY = currentY + (timeTextPainter.height - dateBlockHeight) / 2;

    _drawTextWithShadow(
      canvas,
      metadata.formattedDate,
      x: dateX,
      y: dateStartY,
      fontSize: dateFontSize,
      color: whiteColor,
    );
    _drawTextWithShadow(
      canvas,
      metadata.formattedDayOfWeek,
      x: dateX,
      y: dateStartY + dateFontSize + (4 * scale),
      fontSize: dateFontSize,
      color: whiteColor,
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
        fontSize: addrFontSize,
        color: whiteColor,
        fontWeight: FontWeight.bold,
      );
      final addrPainter = _buildTextPainter(
        metadata.formattedAddress,
        fontSize: addrFontSize,
        color: whiteColor,
        fontWeight: FontWeight.bold,
      );
      currentY += addrPainter.height + (12 * scale);
    }

    // ============ INFO BOX ============
    final double boxStartY = currentY - boxPadding;

    // Draw info box semi-transparent background
    final boxPaint = ui.Paint()..color = const Color.fromARGB(30, 90, 90, 90);
    final boxRect = ui.RRect.fromRectAndRadius(
      Rect.fromLTWH(boxStartX, boxStartY, infoBoxWidth, infoBoxHeight),
      Radius.circular(8 * scale),
    );
    canvas.drawRRect(boxRect, boxPaint);

    // Draw each info line
    double lineY = currentY;
    for (int i = 0; i < infoPainters.length; i++) {
      infoPainters[i].paint(canvas, Offset(textBaseX + textInset, lineY));
      lineY += infoPainters[i].height + lineSpacing;
    }

    // --- Load and draw security.png icon from assets ---
    final double iconHeight = codeTextPainter.height * 1.3;
    double codeTextX = textBaseX; // default if icon fails
    try {
      final ByteData securityData = await rootBundle.load(
        'assets/images/security.png',
      );
      final Uint8List securityBytes = securityData.buffer.asUint8List();
      final ui.Codec securityCodec = await ui.instantiateImageCodec(
        securityBytes,
      );
      final ui.FrameInfo securityFrame = await securityCodec.getNextFrame();
      final ui.Image securityImage = securityFrame.image;

      // Scale the icon to match the desired height, preserving aspect ratio
      final double aspectRatio = securityImage.width / securityImage.height;
      final double iconWidth = iconHeight * aspectRatio;

      final double iconX = textBaseX;
      final double iconY = codeBarY + (codeBarHeight - iconHeight) / 2;

      // Draw the security icon scaled to the target size
      final ui.Paint iconPaint = ui.Paint()
        ..filterQuality = ui.FilterQuality.high;
      final Rect srcRect = Rect.fromLTWH(
        0,
        0,
        securityImage.width.toDouble(),
        securityImage.height.toDouble(),
      );
      final Rect dstRect = Rect.fromLTWH(iconX, iconY, iconWidth, iconHeight);
      canvas.drawImageRect(securityImage, srcRect, dstRect, iconPaint);

      codeTextX = iconX + iconWidth + (10 * scale);

      securityImage.dispose();
    } catch (_) {
      // Fallback: draw the shield-check icon if asset loading fails
      final double shieldSize = iconHeight;
      final double shieldX = textBaseX;
      final double shieldY = codeBarY + (codeBarHeight - shieldSize) / 2;
      _drawShieldCheck(
        canvas,
        x: shieldX,
        y: shieldY,
        size: shieldSize,
        color: lightGrayColor,
      );
      codeTextX = shieldX + shieldSize * 0.85 + (10 * scale);
    }

    // --- Draw thin line 20px above the text, spanning the full content width ---
    final double totalBottomContentWidth =
        (codeTextX - textBaseX) + codeTextPainter.width;
    final double lineAboveGap = 20 * scale;
    final double lineAboveY = codeContentY - lineAboveGap;
    final codeLinePaint = ui.Paint()
      ..color = const Color.fromARGB(100, 180, 180, 180)
      ..strokeWidth = 1.5 * scale;
    canvas.drawLine(
      Offset(textBaseX, lineAboveY),
      Offset(textBaseX + totalBottomContentWidth, lineAboveY),
      codeLinePaint,
    );

    // Draw photo code text after the icon
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
    final double rightEdgeCodeFontSize = 28 * scale; // larger font for the code
    final double rightEdgeLabelFontSize =
        28 * scale; // font for "Timemark Verified"
    final double rightEdgeMargin = 15 * scale;
    const Color rightEdgeTextColor = ui.Color.fromARGB(234, 253, 251, 251);

    // --- Pre-load security.png icon for right edge (before canvas rotation) ---
    ui.Image? rightEdgeSecurityIcon;
    try {
      final ByteData reSecData = await rootBundle.load(
        'assets/images/security.png',
      );
      final Uint8List reSecBytes = reSecData.buffer.asUint8List();
      final ui.Codec reSecCodec = await ui.instantiateImageCodec(reSecBytes);
      final ui.FrameInfo reSecFrame = await reSecCodec.getNextFrame();
      rightEdgeSecurityIcon = reSecFrame.image;
    } catch (_) {
      // Icon will be null, we draw the fallback shield instead
    }

    // Rotation is -90° (counter-clockwise) = -π/2 radians.
    // This makes text read from bottom to top.
    // After rotating -90°:
    //   To place text at screen position (screenX, screenY),
    //   draw at canvas coords (-screenY, screenX).

    canvas.save();
    canvas.rotate(-3.14159265 / 2); // -90° = bottom-to-top

    // --- Icon, Photo code and "Timemark Verified" (vertical, right edge) ---
    final double vertScreenX =
        imgWidth.toDouble() - rightEdgeMargin - rightEdgeCodeFontSize;

    // Measure code text to center it vertically on the edge
    final String codeLabel = metadata.photoCode;
    final codeVertPainter = _buildTextPainter(
      codeLabel,
      fontSize: rightEdgeCodeFontSize,
      color: rightEdgeTextColor,
    );
    final verifiedVertPainter = _buildTextPainter(
      'Timemark Verified',
      fontSize: rightEdgeLabelFontSize,
      color: rightEdgeTextColor,
    );

    // Icon dimensions in the rotated space
    final double reIconSize = rightEdgeCodeFontSize * 1.2;
    final double reIconGap = 8 * scale;

    // Total width of all elements (in rotated space = vertical span on screen)
    final double vertGap = 20 * scale;
    final double totalVertWidth =
        reIconSize +
        reIconGap +
        codeVertPainter.width +
        vertGap +
        verifiedVertPainter.width;

    // Center the entire group along the image height
    // In rotated coords, the image height maps to the negative X axis
    double currentRotatedX = -(imgHeight / 2.0) - (totalVertWidth / 2.0);

    // 0. Draw security icon (in rotated space)
    if (rightEdgeSecurityIcon != null) {
      final double iconAspect =
          rightEdgeSecurityIcon.width / rightEdgeSecurityIcon.height;
      final double reIconW = reIconSize * iconAspect;
      final double reIconH = reIconSize;
      final double reIconY =
          vertScreenX + (rightEdgeCodeFontSize - reIconH) / 2;

      final ui.Paint reIconPaint = ui.Paint()
        ..filterQuality = ui.FilterQuality.high;
      final Rect reSrcRect = Rect.fromLTWH(
        0,
        0,
        rightEdgeSecurityIcon.width.toDouble(),
        rightEdgeSecurityIcon.height.toDouble(),
      );
      final Rect reDstRect = Rect.fromLTWH(
        currentRotatedX,
        reIconY,
        reIconW,
        reIconH,
      );
      canvas.drawImageRect(
        rightEdgeSecurityIcon,
        reSrcRect,
        reDstRect,
        reIconPaint,
      );
      currentRotatedX += reIconW + reIconGap;
      rightEdgeSecurityIcon.dispose();
    } else {
      // Fallback: draw the vector shield icon
      final double shieldY =
          vertScreenX + (rightEdgeCodeFontSize - reIconSize) / 2;
      _drawShieldCheck(
        canvas,
        x: currentRotatedX,
        y: shieldY,
        size: reIconSize,
        color: rightEdgeTextColor,
      );
      currentRotatedX += reIconSize * 0.85 + reIconGap;
    }

    // 1. Draw Photo Code (larger font)
    _drawTextWithShadow(
      canvas,
      codeLabel,
      x: currentRotatedX,
      y: vertScreenX,
      fontSize: rightEdgeCodeFontSize,
      color: rightEdgeTextColor,
    );
    currentRotatedX += codeVertPainter.width + vertGap;

    // 2. Draw "Timemark Verified" (after the code)
    // Align baseline: offset vertScreenX to account for font size difference
    final double labelYOffset =
        vertScreenX + (rightEdgeCodeFontSize - rightEdgeLabelFontSize);
    _drawTextWithShadow(
      canvas,
      'Timemark Verified',
      x: currentRotatedX,
      y: labelYOffset,
      fontSize: rightEdgeLabelFontSize,
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
