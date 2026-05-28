import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/screens/admin/admin_place_editor.dart';

import '../../../constants/app_injector.dart';
import '../../../core/place_category_normalizer.dart';
import '../../../core/place_search_pipeline.dart';
import '../../../services/landmark_cache.dart';

class AdminApiAddPlaceScreen extends StatefulWidget {
  const AdminApiAddPlaceScreen({super.key});

  @override
  State<AdminApiAddPlaceScreen> createState() => _AdminApiAddPlaceScreenState();
}

class _AdminApiAddPlaceScreenState extends State<AdminApiAddPlaceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _q = TextEditingController();
  final _city = TextEditingController();
  final _category = TextEditingController();

  bool _loading = false;
  String _message = '';

  @override
  void dispose() {
    _q.dispose();
    _city.dispose();
    _category.dispose();
    super.dispose();
  }

  bool _isWeakAfterEnrichment(Landmark place) {
    final short = place.shortDescription.trim();
    final full = place.fullDescription.trim();
    final history = place.history.trim();
    final hasImage = place.imageUrl.trim().startsWith('http') ||
        place.mediaUrls.any((u) => u.trim().startsWith('http'));

    return short.length < 40 &&
        full.length < 80 &&
        history.length < 80 &&
        !hasImage;
  }

  Future<City> _resolveCity(String cityName) async {
    final cleanCity = cityName.trim();
    final cities = await AppInjector.firebase.getCities();

    for (final c in cities) {
      if (c.name.trim().toLowerCase() == cleanCity.toLowerCase()) {
        return c;
      }
    }

    // If the city is not found in Firestore, create/use it through the existing
    // repository/Firebase helper so the editor does not receive an empty cityId.
    return AppInjector.firebase.findOrCreateCityByName(cleanCity);
  }

  Landmark _buildDraft({
    required String query,
    required City city,
    required String normalizedCategory,
  }) {
    final now = DateTime.now();
    final lat = city.lat;
    final lng = city.lng;

    return Landmark(
      id: '',
      name: query,
      displayName: query,
      normalizedName: PlaceSearchPipeline.normalizeSearchQuery(query),
      aliases: [query],
      cityId: city.id,
      city: city.name,
      category: normalizedCategory,
      description: '',
      shortDescription: '',
      fullDescription: '',
      history: '',
      imageUrl: '',
      mediaUrls: const [],
      lat: lat,
      lng: lng,
      address: city.name,
      rating: 0,
      openingHours: '',
      location: lat != 0 && lng != 0 ? '$lat, $lng' : '',
      createdAt: now,
      updatedAt: now,
      generatedBySearch: true,
      hidden: false,
      needsReview: true,
      invalidPlace: false,
      invalidReason: '',
      sources: {
        'provider': 'api_prefill_conservative',
        'origin': 'api_prefill',
        'query': query,
        'apiPrefillCreatedAt': now.toIso8601String(),
      },
      nearbyPlaces: const [],
    );
  }

  /// Fetch from APIs means: create a temporary admin draft, enrich it, then open
  /// the editor with the enriched Firestore document. This makes the Add Place
  /// editor show description/images before the admin presses Save.
  Future<Landmark?> _fetchPrefilledPlace() async {
    final query = _q.text.trim();
    final cityName = _city.text.trim();
    final category = _category.text.trim().toLowerCase();

    if (query.isEmpty || cityName.isEmpty || category.isEmpty) return null;

    final normalizedCategory = PlaceCategoryNormalizer.normalize(
      category,
      contextText: query,
    );

    final city = await _resolveCity(cityName);
    final draft = _buildDraft(
      query: query,
      city: city,
      normalizedCategory: normalizedCategory,
    );

    final savedId = await AppInjector.firebase.adminUpsertPlace(
      draft,
      createdByAdmin: true,
      markVerified: false,
    );

    if (kDebugMode) {
      debugPrint('[AdminApiAddEnrichStart] id=$savedId name=$query');
    }

    var fresh = await AppInjector.firebase.getLandmarkById(savedId);
    if (fresh == null) return null;

    await AppInjector.repository.enrichWikipedia(fresh, force: true);
    if (kDebugMode) {
      debugPrint('[AdminApiAddWikiDone] id=$savedId');
    }

    fresh = await AppInjector.firebase.getLandmarkById(savedId);
    if (fresh != null) {
      await AppInjector.repository.enrichImages(
        fresh,
        force: true,
        imageUpdateSource: 'admin_image_refresh',
        allowAdminImageOverwrite: true,
      );
    }

    fresh = await AppInjector.firebase.getLandmarkById(savedId);
    if (fresh != null) {
      LandmarkCache.instance.put(fresh);
      if (kDebugMode) {
        debugPrint(
          '[AdminApiAddImagesDone] id=$savedId image=${fresh.imageUrl} mediaCount=${fresh.mediaUrls.length}',
        );
      }

      if (_isWeakAfterEnrichment(fresh)) {
        await AppInjector.firebase.adminUpsertPlace(
          fresh.copyWith(needsReview: true),
          createdByAdmin: true,
          markVerified: false,
        );
        fresh = await AppInjector.firebase.getLandmarkById(savedId) ?? fresh;
      }

      if (kDebugMode) {
        debugPrint(
          '[AdminApiAddFresh] id=${fresh.id} shortEmpty=${fresh.shortDescription.trim().isEmpty} image=${fresh.imageUrl}',
        );
      }
    }

    return fresh;
  }

  Future<void> _fetchAndOpenEditor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _message = 'Fetching place details and images...';
    });

    try {
      final draft = await _fetchPrefilledPlace();
      if (!mounted) return;

      if (draft == null) {
        setState(() {
          _message =
              'API prefill failed. No data was saved. You can complete the form manually.';
        });
        return;
      }

      final res = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => AdminPlaceEditor(
            place: draft,
            origin: 'api_prefill',
            query: _q.text.trim(),
          ),
        ),
      );

      if (!mounted) return;
      if (res?['changed'] == true) {
        Navigator.pop(context, res);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'API prefill failed: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      appBar: AppBar(
        title: const Text('Add using APIs'),
        backgroundColor: AppColors.chestnutBrown,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _q,
              decoration: const InputDecoration(
                labelText: 'Place name / query',
                filled: true,
                fillColor: Color(0xFFF9F5F1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              decoration: const InputDecoration(
                labelText: 'City',
                filled: true,
                fillColor: Color(0xFFF9F5F1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category.text.isEmpty ? null : _category.text.trim(),
              items: const ['tourist', 'hotel', 'restaurant', 'cafe', 'outing']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => _category.text = v ?? '',
              decoration: const InputDecoration(
                labelText: 'Category',
                filled: true,
                fillColor: Color(0xFFF9F5F1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            if (_message.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _message,
                  style: const TextStyle(color: Color(0xFF8B817A)),
                ),
              ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _loading ? null : _fetchAndOpenEditor,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_download_rounded),
              label: Text(_loading ? 'Fetching details...' : 'Fetch from APIs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.chestnutBrown,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                final q = _q.text.trim();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminPlaceEditor(
                      place: null,
                      origin: 'manual',
                      query: q,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Continue manually'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
