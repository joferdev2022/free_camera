import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherData {
  final String description;
  final double temperature; // in Celsius (real)
  final double? apparentTemperature; // feels like, in Celsius
  final int? humidity; // relative humidity %
  final double? windSpeed; // km/h

  WeatherData({
    required this.description,
    required this.temperature,
    this.apparentTemperature,
    this.humidity,
    this.windSpeed,
  });
}

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();

  factory WeatherService() => _instance;

  WeatherService._internal();

  /// Get weather using Open-Meteo API (free, no API key needed)
  /// Uses the modern 'current' parameter for real-time accurate data
  Future<WeatherData?> getWeather(double latitude, double longitude) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m'
        '&temperature_unit=celsius'
        '&wind_speed_unit=kmh',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current'];
        final temp = (current['temperature_2m'] as num).toDouble();
        final weatherCode = current['weather_code'] as int;
        final apparentTemp =
            (current['apparent_temperature'] as num?)?.toDouble();
        final humidity = (current['relative_humidity_2m'] as num?)?.toInt();
        final windSpeed = (current['wind_speed_10m'] as num?)?.toDouble();

        return WeatherData(
          description: _weatherCodeToDescription(weatherCode),
          temperature: temp,
          apparentTemperature: apparentTemp,
          humidity: humidity,
          windSpeed: windSpeed,
        );
      }
      return null;
    } catch (e) {
      print('Error obteniendo clima: $e');
      return null;
    }
  }

  String _weatherCodeToDescription(int code) {
    switch (code) {
      case 0:
        return 'Despejado';
      case 1:
        return 'Mayormente despejado';
      case 2:
        return 'Parcialmente nublado';
      case 3:
        return 'Nublado';
      case 45:
      case 48:
        return 'Niebla';
      case 51:
        return 'Llovizna ligera';
      case 53:
        return 'Llovizna moderada';
      case 55:
        return 'Llovizna intensa';
      case 56:
      case 57:
        return 'Llovizna helada';
      case 61:
        return 'Lluvia ligera';
      case 63:
        return 'Lluvia moderada';
      case 65:
        return 'Lluvia intensa';
      case 66:
      case 67:
        return 'Lluvia helada';
      case 71:
        return 'Nevada ligera';
      case 73:
        return 'Nevada moderada';
      case 75:
        return 'Nevada intensa';
      case 77:
        return 'Granizo';
      case 80:
        return 'Chubascos ligeros';
      case 81:
        return 'Chubascos moderados';
      case 82:
        return 'Chubascos intensos';
      case 85:
      case 86:
        return 'Chubascos de nieve';
      case 95:
        return 'Tormenta';
      case 96:
      case 99:
        return 'Tormenta con granizo';
      default:
        return 'Desconocido';
    }
  }
}
