import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/services/pipe_service.dart';

class CreateCity extends StatefulWidget {
  static String routeName = '/createCity';
  const CreateCity({super.key});

  @override
  State<CreateCity> createState() => _CreateCityState();
}

class _CreateCityState extends State<CreateCity> {
  final TextEditingController cityNameController = TextEditingController();

  final DataPipelineService _pipeline = DataPipelineService();

  bool _isLoading = false;
  String _status = '';

  @override
  void dispose() {
    cityNameController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // FREE GEOCODING (OpenStreetMap)
  // ─────────────────────────────────────────────────────────
  Future<Map<String, double>> _geocodeFree(String cityName) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&limit=1&countrycodes=eg&q=${Uri.encodeComponent(cityName)}',
      );

      final response = await http.get(
        url,
        headers: const {
          'User-Agent': 'GeoGuide/1.0 (educational-app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return {'lat': 0, 'lng': 0};
      }

      final data = jsonDecode(response.body) as List? ?? [];

      if (data.isEmpty) return {'lat': 0, 'lng': 0};

      final first = data.first as Map<String, dynamic>;

      return {
        'lat': double.tryParse(first['lat'].toString()) ?? 0,
        'lng': double.tryParse(first['lon'].toString()) ?? 0,
      };
    } catch (e) {
      debugPrint('[Geocode Error] $e');
      return {'lat': 0, 'lng': 0};
    }
  }

  // ─────────────────────────────────────────────────────────
  // CHECK CITY EXISTENCE
  // ─────────────────────────────────────────────────────────
  Future<DocumentSnapshot?> _findExistingCity(String cityName) async {
    final query = await FirebaseFirestore.instance
        .collection('cities')
        .where('name', isEqualTo: cityName)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first;
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────
  // CREATE CITY + RUN PIPELINE
  // ─────────────────────────────────────────────────────────
  Future<void> _submitCity() async {
    final cityName = cityNameController.text.trim();

    if (cityName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a city name')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '🔄 Checking city...';
    });

    try {
      // ── check if city exists
      final existing = await _findExistingCity(cityName);

      String cityId;
      double lat;
      double lng;

      if (existing != null) {
        // already exists
        cityId = existing.id;
        final data = existing.data() as Map<String, dynamic>;

        lat = (data['lat'] ?? 0).toDouble();
        lng = (data['lng'] ?? 0).toDouble();

        setState(() => _status = '📍 City already exists, updating...');
      } else {
        // create new city
        setState(() => _status = '🌍 Geocoding city...');

        final geo = await _geocodeFree(cityName);

        lat = geo['lat'] ?? 0;
        lng = geo['lng'] ?? 0;

        final docRef =
            await FirebaseFirestore.instance.collection('cities').add({
          'name': cityName,
          'lat': lat,
          'lng': lng,
        });

        cityId = docRef.id;

        setState(() => _status = '🏙️ City created...');
      }

      final city = City(
        id: cityId,
        name: cityName,
        lat: lat,
        lng: lng,
        image: '',
      );

      // ── RUN PIPELINE
      setState(() => _status = '⚙️ Running smart pipeline...');

      final landmarks = await _pipeline.fetchOrLoadLandmarks(
        city,
        forceRefresh: true,
        onProgress: (msg) {
          if (mounted) {
            setState(() => _status = msg);
          }
        },
      );

      setState(() {
        _isLoading = false;
        _status =
            '✅ Done! ${landmarks.length} places ready in ${city.name}';
      });

      cityNameController.clear();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = '❌ Error: $e';
      });

      debugPrint('[CreateCity ERROR] $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // UI (NO DESIGN CHANGE)
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New City')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter City Name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: cityNameController,
              decoration: const InputDecoration(
                hintText: 'City name...',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitCity,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isLoading
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 8),
                        ],
                      )
                    : const Text('Create City & Fetch Places'),
              ),
            ),

            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 14,
                  color: _status.startsWith('✅')
                      ? Colors.green
                      : _status.startsWith('❌')
                          ? Colors.red
                          : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}