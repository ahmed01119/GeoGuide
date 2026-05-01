import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherInfo {
  final double temperatureC;
  final String description;
  final int weatherCode;

  const WeatherInfo({
    required this.temperatureC,
    required this.description,
    required this.weatherCode,
  });
}

class _CachedWeather {
  final WeatherInfo info;
  final DateTime fetchedAt;

  const _CachedWeather({
    required this.info,
    required this.fetchedAt,
  });
}

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  static const Duration _cacheDuration = Duration(minutes: 30);
  final Map<String, _CachedWeather> _cache = {};

  Future<WeatherInfo?> getCurrentWeather({
    required double lat,
    required double lng,
  }) async {
    if (lat == 0 || lng == 0) return null;

    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    final now = DateTime.now();
    final cached = _cache[key];

    if (cached != null && now.difference(cached.fetchedAt) < _cacheDuration) {
      return cached.info;
    }

    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat'
      '&longitude=$lng'
      '&current=temperature_2m,weather_code'
      '&timezone=auto',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      final temp = (current['temperature_2m'] as num?)?.toDouble();
      final code = (current['weather_code'] as num?)?.toInt();
      if (temp == null || code == null) return null;

      final info = WeatherInfo(
        temperatureC: temp,
        description: _describeCode(code),
        weatherCode: code,
      );

      _cache[key] = _CachedWeather(info: info, fetchedAt: now);
      return info;
    } catch (_) {
      return null;
    }
  }

  String _describeCode(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
      case 2:
      case 3:
        return 'Cloudy';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
        return 'Rain';
      case 71:
      case 73:
      case 75:
      case 77:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Weather update';
    }
  }
}
