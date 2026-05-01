import 'package:flutter/material.dart';
import 'package:geoguide/services/weather_service.dart';

class PlaceWeatherChip extends StatelessWidget {
  final double lat;
  final double lng;
  final Color? textColor;
  final Color? backgroundColor;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const PlaceWeatherChip({
    super.key,
    required this.lat,
    required this.lng,
    this.textColor,
    this.backgroundColor,
    this.iconSize = 14,
    this.fontSize = 11.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    if (lat == 0 || lng == 0) return const SizedBox.shrink();

    final fg = textColor ?? const Color(0xFF5E544D);
    final bg = backgroundColor ?? const Color(0xFFF4ECE5);

    return FutureBuilder<WeatherInfo?>(
      future: WeatherService.instance.getCurrentWeather(lat: lat, lng: lng),
      builder: (context, snapshot) {
        final weather = snapshot.data;
        if (weather == null) return const SizedBox.shrink();

        return Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wb_sunny_outlined, size: iconSize, color: fg),
              const SizedBox(width: 4),
              Text(
                '${weather.temperatureC.round()}°C',
                style: TextStyle(
                  color: fg,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
