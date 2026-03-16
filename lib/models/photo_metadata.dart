import 'dart:math';

class PhotoMetadata {
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? accuracy;
  final double? altitude;
  final double? compassHeading;
  final String? weatherDescription;
  final double? temperature;
  final String note;
  final String photoCode;

  PhotoMetadata({
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.compassHeading,
    this.weatherDescription,
    this.temperature,
    this.note = '',
    String? photoCode,
  }) : photoCode = photoCode ?? _generatePhotoCode();

  static String _generatePhotoCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(15, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Formatted time as HH:mm
  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  /// Formatted time with seconds HH:mm:ss
  String get formattedTimeFull {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  /// Formatted date in Spanish: "13 de mar 2026"
  String get formattedDate {
    final months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    return '${timestamp.day} de ${months[timestamp.month - 1]} ${timestamp.year}';
  }

  /// Day of week abbreviation in Spanish
  String get formattedDayOfWeek {
    final days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return days[timestamp.weekday - 1];
  }

  /// Formatted coordinates with S/N and W/E labels
  String get formattedCoordinates {
    if (latitude == null || longitude == null) {
      return 'Sin coordenadas';
    }
    final latDir = latitude! >= 0 ? 'N' : 'S';
    final lonDir = longitude! >= 0 ? 'E' : 'W';
    return '${latitude!.abs().toStringAsFixed(6)}°$latDir, ${longitude!.abs().toStringAsFixed(6)}°$lonDir';
  }

  String get formattedLocation {
    if (latitude == null || longitude == null) {
      return 'No ubicación disponible';
    }
    return 'Lat: ${latitude!.toStringAsFixed(6)}\nLon: ${longitude!.toStringAsFixed(6)}';
  }

  String get formattedLocationInline {
    if (latitude == null || longitude == null) {
      return 'No ubicación';
    }
    return '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
  }

  /// Formatted altitude string
  String get formattedAltitude {
    if (altitude == null) return 'N/A';
    return '${altitude!.toStringAsFixed(1)} m';
  }

  /// Formatted compass heading with cardinal direction
  String get formattedCompass {
    if (compassHeading == null) return 'N/A';
    final heading = compassHeading!;
    String direction;
    if (heading >= 337.5 || heading < 22.5) {
      direction = 'N';
    } else if (heading >= 22.5 && heading < 67.5) {
      direction = 'NE';
    } else if (heading >= 67.5 && heading < 112.5) {
      direction = 'E';
    } else if (heading >= 112.5 && heading < 157.5) {
      direction = 'SE';
    } else if (heading >= 157.5 && heading < 202.5) {
      direction = 'S';
    } else if (heading >= 202.5 && heading < 247.5) {
      direction = 'SO';
    } else if (heading >= 247.5 && heading < 292.5) {
      direction = 'O';
    } else {
      direction = 'NO';
    }
    return '${heading.toStringAsFixed(0)}° $direction';
  }

  /// Formatted weather string
  String get formattedWeather {
    if (weatherDescription == null) return 'N/A';
    final tempStr = temperature != null ? ' ${temperature!.toStringAsFixed(0)}°F' : '';
    // Capitalize first letter
    final desc = weatherDescription!.isNotEmpty
        ? weatherDescription![0].toUpperCase() + weatherDescription!.substring(1)
        : '';
    return '$desc$tempStr';
  }
}
