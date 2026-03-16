import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherData {
  final String description;
  final double temperature; // in Fahrenheit

  WeatherData({required this.description, required this.temperature});
}

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();

  factory WeatherService() => _instance;

  WeatherService._internal();

  /// Get weather using Open-Meteo API (free, no API key needed)
  Future<WeatherData?> getWeather(double latitude, double longitude) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&current_weather=true'
        '&temperature_unit=fahrenheit',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final currentWeather = data['current_weather'];
        final temp = (currentWeather['temperature'] as num).toDouble();
        final weatherCode = currentWeather['weathercode'] as int;

        return WeatherData(
          description: _weatherCodeToDescription(weatherCode),
          temperature: temp,
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
      case 53:
      case 55:
        return 'Llovizna';
      case 56:
      case 57:
        return 'Llovizna helada';
      case 61:
      case 63:
      case 65:
        return 'Lluvia';
      case 66:
      case 67:
        return 'Lluvia helada';
      case 71:
      case 73:
      case 75:
        return 'Nieve';
      case 77:
        return 'Granizo';
      case 80:
      case 81:
      case 82:
        return 'Chubascos';
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
