import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/screens/admin/admin_place_preview_card.dart';
import 'package:geoguide/presntation/place-info/place-info.dart';
import 'package:geoguide/core/place_search_pipeline.dart';
import 'package:geoguide/services/landmark_cache.dart';

class AdminPlaceEditor extends StatefulWidget {
  final Landmark? place;
  final String origin;
  final String? query;

  const AdminPlaceEditor({
    super.key,
    this.place,
    this.origin = 'edit_existing',
    this.query,
  });

  @override
  State<AdminPlaceEditor> createState() => _AdminPlaceEditorState();
}

class _AdminPlaceEditorState extends State<AdminPlaceEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _displayName = TextEditingController();
  final _category = TextEditingController();
  final _city = TextEditingController();
  final _cityId = TextEditingController();
  final _address = TextEditingController();
  final _shortDescription = TextEditingController();
  final _fullDescription = TextEditingController();
  final _history = TextEditingController();
  final _imageUrl = TextEditingController();
  final _mediaUrls = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _rating = TextEditingController();
  final _opening = TextEditingController();
  bool _hidden = false;
  bool _needsReview = false;

  bool _saving = false;
  Landmark? _savedPreview;
  String _savedPlaceId = '';

  @override
  void initState() {
    super.initState();
    final p = widget.place;
    if (p != null) {
      _name.text = p.name;
      _displayName.text = p.displayName;
      _category.text = p.category;
      _city.text = p.city;
      _cityId.text = p.cityId;
      _address.text = p.address;
      _shortDescription.text = p.shortDescription;
      _fullDescription.text = p.fullDescription;
      _history.text = p.history;
      _imageUrl.text = p.imageUrl;
      _mediaUrls.text = p.mediaUrls.join(', ');
      _lat.text = p.lat.toString();
      _lng.text = p.lng.toString();
      _rating.text = p.rating.toString();
      _opening.text = p.openingHours;
      _hidden = p.hidden;
      _needsReview = p.needsReview;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _displayName,
      _category,
      _city,
      _cityId,
      _address,
      _shortDescription,
      _fullDescription,
      _history,
      _imageUrl,
      _mediaUrls,
      _lat,
      _lng,
      _rating,
      _opening,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _hasUsefulContent(Landmark place) {
    final hasText = place.shortDescription.trim().length >= 40 ||
        place.fullDescription.trim().length >= 80 ||
        place.history.trim().length >= 80;
    final hasImage = place.imageUrl.trim().startsWith('http') ||
        place.mediaUrls.any((u) => u.trim().startsWith('http'));
    return hasText || hasImage;
  }

  bool _imageFieldsWereChangedByAdmin({
    required Landmark? base,
    required String image,
    required List<String> media,
  }) {
    if (base == null) return image.isNotEmpty || media.isNotEmpty;
    final oldImage = base.imageUrl.trim();
    final oldMedia = base.mediaUrls.map((e) => e.trim()).where((e) => e.isNotEmpty).join('|');
    final newMedia = media.map((e) => e.trim()).where((e) => e.isNotEmpty).join('|');
    return image.trim() != oldImage || newMedia != oldMedia;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final allowed = {'tourist', 'hotel', 'restaurant', 'cafe', 'outing'};
      final category = _category.text.trim().toLowerCase();
      if (!allowed.contains(category)) {
        throw Exception('Category must be one of: ${allowed.join(', ')}');
      }

      final mediaFromController = _mediaUrls.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.startsWith('http'))
          .toList();

      var image = _imageUrl.text.trim();
      var media = mediaFromController;

      final base = widget.place;
      final originalId = base?.id.trim() ?? '';
      final isExistingEdit = widget.origin == 'edit_existing' && originalId.isNotEmpty;
      final isCreateFlow = !isExistingEdit;

      if (kDebugMode) {
        if (isExistingEdit) {
          debugPrint('[AdminEditMode] id=$originalId origin=${widget.origin}');
        } else {
          debugPrint('[AdminCreateMode] id=$originalId origin=${widget.origin}');
        }
      }

      final imageTouched = _imageFieldsWereChangedByAdmin(
        base: base,
        image: image,
        media: media,
      );

      // Only create/API/AI draft flows may preserve a newer image from Firebase.
      // Existing edit mode must save exactly the controller values typed by admin.
      if (isCreateFlow && originalId.isNotEmpty && !imageTouched) {
        final latest = await AppInjector.firebase.getLandmarkById(originalId);
        if (latest != null &&
            (latest.imageUrl.trim() != image || latest.mediaUrls.length != media.length)) {
          image = latest.imageUrl.trim();
          media = latest.mediaUrls;
          if (kDebugMode) {
            debugPrint(
              '[AdminEditorPreserveFreshImages] id=$originalId image=$image mediaCount=${media.length}',
            );
          }
        }
      }

      final parsedLat = double.tryParse(_lat.text.trim()) ?? 0;
      final parsedLng = double.tryParse(_lng.text.trim()) ?? 0;
      final parsedRating = double.tryParse(_rating.text.trim()) ?? 0;
      final nowIso = DateTime.now().toIso8601String();

      final place = Landmark(
        id: isExistingEdit ? originalId : (base?.id ?? ''),
        name: _name.text.trim(),
        cityId: _cityId.text.trim(),
        city: _city.text.trim(),
        category: category,
        description: _shortDescription.text.trim(),
        shortDescription: _shortDescription.text.trim(),
        fullDescription: _fullDescription.text.trim(),
        history: _history.text.trim(),
        imageUrl: image,
        mediaUrls: media,
        lat: parsedLat,
        lng: parsedLng,
        address: _address.text.trim(),
        rating: parsedRating,
        openingHours: _opening.text.trim(),
        location: '${parsedLat}, ${parsedLng}',
        displayName: _displayName.text.trim().isNotEmpty
            ? _displayName.text.trim()
            : _name.text.trim(),
        normalizedName: PlaceSearchPipeline.normalizeSearchQuery(_name.text.trim()),
        aliases: base?.aliases ?? const [],
        generatedBySearch: base?.generatedBySearch ??
            (widget.origin == 'api_prefill' || widget.origin == 'ai_prefill'),
        hidden: _hidden,
        needsReview: _needsReview,
        invalidPlace: base?.invalidPlace ?? false,
        invalidReason: base?.invalidReason ?? '',
        isDuplicate: base?.isDuplicate ?? false,
        duplicateOf: base?.duplicateOf ?? '',
        sources: {
          ...(base?.sources ?? const <String, dynamic>{}),
          'adminOrigin': widget.origin,
          if ((widget.query ?? '').trim().isNotEmpty) 'adminQuery': widget.query!.trim(),
          'lastAdminEditAt': nowIso,
        },
        nearbyPlaces: base?.nearbyPlaces ?? const [],
      );

      if (kDebugMode) {
        debugPrint(
          '[AdminEditorPayload] id=${place.id} name=${place.name} '
          'address=${place.address} short=${place.shortDescription} '
          'full=${place.fullDescription} history=${place.history} '
          'image=${place.imageUrl}',
        );
      }

      final savedId = await AppInjector.firebase.adminUpsertPlace(
        place,
        createdByAdmin: isCreateFlow,
        markVerified: true,
      );

      var fresh = await AppInjector.firebase.getLandmarkById(isExistingEdit ? originalId : savedId);

      // Safety fallback: if API/AI draft reached this editor without being
      // enriched first, enrich after save as well. Never run this for existing edits.
      if (isCreateFlow &&
          (widget.origin == 'api_prefill' || widget.origin == 'ai_prefill') &&
          fresh != null &&
          !_hasUsefulContent(fresh)) {
        if (kDebugMode) {
          debugPrint('[AdminApiAddEnrichStart] id=$savedId name=${fresh.name} origin=${widget.origin}');
        }

        await AppInjector.repository.enrichWikipedia(fresh, force: true);
        if (kDebugMode) debugPrint('[AdminApiAddWikiDone] id=$savedId');

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
          if (kDebugMode) {
            debugPrint(
              '[AdminApiAddImagesDone] id=$savedId image=${fresh.imageUrl} mediaCount=${fresh.mediaUrls.length}',
            );
            debugPrint(
              '[AdminApiAddFresh] id=${fresh.id} shortEmpty=${fresh.shortDescription.trim().isEmpty} image=${fresh.imageUrl}',
            );
          }
        }
      }

      if (fresh != null) {
        LandmarkCache.instance.put(fresh);
      }

      if (kDebugMode) {
        debugPrint(
          '[AdminFreshAfterSave] id=${fresh?.id ?? savedId} name=${fresh?.name ?? place.name} '
          'address=${fresh?.address ?? place.address} short=${fresh?.shortDescription ?? place.shortDescription} '
          'full=${fresh?.fullDescription ?? place.fullDescription} history=${fresh?.history ?? place.history} '
          'image=${fresh?.imageUrl ?? place.imageUrl}',
        );
      }

      final originalEditId = isExistingEdit ? originalId : savedId;

      if (kDebugMode && isExistingEdit) {
        debugPrint(
          '[AdminEditSavedFresh] id=${fresh?.id ?? originalEditId} '
          'name=${fresh?.name ?? place.name} image=${fresh?.imageUrl ?? place.imageUrl}',
        );
      }

      if (kDebugMode) {
        final vis = await AppInjector.firebase.verifyLandmarkVisibleInCity(originalEditId);
        debugPrint(
          '[AdminSaveVerify] place=$originalEditId cityId=${fresh?.cityId ?? ''} '
          'visible=${vis.visible} reason=${vis.reason}',
        );
      }

      if (!mounted) return;

      Navigator.pop(context, {
        'changed': true,
        'placeId': originalEditId,
        if (fresh != null) 'place': fresh.toJson(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF9F5F1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      appBar: AppBar(
        title: Text(widget.place == null ? 'Add Place' : 'Edit Place'),
        backgroundColor: AppColors.chestnutBrown,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? 'Saving...' : 'Save',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_savedPreview != null) ...[
              AdminPlacePreviewCard(
                place: _savedPreview!,
                title: 'Saved place preview',
                subtitle: 'Tap to open normal place details',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaceInfoScreen(place: _savedPreview!),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open place'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.chestnutBrown,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context, {
                          'changed': true,
                          'placeId': _savedPlaceId,
                        });
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back to admin list'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _name,
              decoration: deco('Name'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(controller: _displayName, decoration: deco('Display Name')),
            const SizedBox(height: 10),
            TextFormField(controller: _category, decoration: deco('Category')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _city, decoration: deco('City'))),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _cityId, decoration: deco('City ID'))),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(controller: _address, decoration: deco('Address')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    decoration: deco('Lat'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    decoration: deco('Lng'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(controller: _shortDescription, decoration: deco('Short Description')),
            const SizedBox(height: 10),
            TextFormField(controller: _fullDescription, decoration: deco('Full Description'), maxLines: 3),
            const SizedBox(height: 10),
            TextFormField(controller: _history, decoration: deco('History'), maxLines: 3),
            const SizedBox(height: 10),
            TextFormField(controller: _imageUrl, decoration: deco('Image URL')),
            const SizedBox(height: 10),
            TextFormField(controller: _mediaUrls, decoration: deco('Media URLs (comma separated)')),
            const SizedBox(height: 10),
            TextFormField(
              controller: _rating,
              decoration: deco('Rating'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextFormField(controller: _opening, decoration: deco('Opening Hours')),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
              title: const Text('Hidden'),
            ),
            SwitchListTile.adaptive(
              value: _needsReview,
              onChanged: (v) => setState(() => _needsReview = v),
              title: const Text('Needs Review'),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
