import 'dart:math';

class PhotoMetadata {
  DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? accuracy;
  final double? altitude;
  final double? compassHeading;
  final String? weatherDescription;
  final double? temperature;
  final double? apparentTemperature;
  final int? humidity;
  final double? windSpeed;
  final String note;
  final String photoCode;
  final String address;

  PhotoMetadata({
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.compassHeading,
    this.weatherDescription,
    this.temperature,
    this.apparentTemperature,
    this.humidity,
    this.windSpeed,
    this.note = '',
    this.address = '',
    String? photoCode,
  }) : photoCode = photoCode ?? _generatePhotoCode();

  /// Creates a copy of this metadata with the given fields replaced.
  PhotoMetadata copyWith({
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    String? accuracy,
    double? altitude,
    double? compassHeading,
    String? weatherDescription,
    double? temperature,
    double? apparentTemperature,
    int? humidity,
    double? windSpeed,
    String? note,
    String? address,
    String? photoCode,
  }) {
    return PhotoMetadata(
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      compassHeading: compassHeading ?? this.compassHeading,
      weatherDescription: weatherDescription ?? this.weatherDescription,
      temperature: temperature ?? this.temperature,
      apparentTemperature: apparentTemperature ?? this.apparentTemperature,
      humidity: humidity ?? this.humidity,
      windSpeed: windSpeed ?? this.windSpeed,
      note: note ?? this.note,
      address: address ?? this.address,
      photoCode: photoCode ?? this.photoCode,
    );
  }

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

  /// Formatted address string
  String get formattedAddress => address;

  /// Formatted altitude string
  String get formattedAltitude {
    if (altitude == null) return 'N/A';
    return '${altitude!.toStringAsFixed(1)} m';
  }

  /// Formatted compass heading with cardinal direction
  String get formattedCompass {
    if (compassHeading == null) return 'N/A';
    // Normalize to 0-360 range (sensor can return negative values)
    double heading = compassHeading! % 360;
    if (heading < 0) heading += 360;
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
    return '${heading.toStringAsFixed(1)}° $direction';
  }

  /// Formatted weather string with temperature and details
  String get formattedWeather {
    if (weatherDescription == null) return 'N/A';
    // Capitalize first letter of description
    final desc = weatherDescription!.isNotEmpty
        ? weatherDescription![0].toUpperCase() + weatherDescription!.substring(1)
        : '';
    final parts = <String>[desc];
    if (temperature != null) {
      parts.add('${temperature!.toStringAsFixed(1)}°C');
    }
    return parts.join(' | ');
  }
}
