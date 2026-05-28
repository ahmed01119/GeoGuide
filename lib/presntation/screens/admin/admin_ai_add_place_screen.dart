import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/screens/admin/admin_place_editor.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:http/http.dart' as http;

import '../../../constants/app_injector.dart';
import '../../../core/config/app_config.dart';
import '../../../core/place_category_normalizer.dart';

class AdminAiAddPlaceScreen extends StatefulWidget {
  const AdminAiAddPlaceScreen({super.key});

  @override
  State<AdminAiAddPlaceScreen> createState() => _AdminAiAddPlaceScreenState();
}

class _AdminAiAddPlaceScreenState extends State<AdminAiAddPlaceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _q = TextEditingController();
  final _city = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();

  bool _loading = false;
  String _message = '';

  @override
  void dispose() {
    _q.dispose();
    _city.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<Landmark?> _generate() async {
    // Do not final-save from here; generate a draft, then enrich it from APIs
    // before opening AdminPlaceEditor for admin review/save.

    final query = _q.text.trim();
    final cityName = _city.text.trim();
    final categoryIn = _category.text.trim().toLowerCase();
    if (query.isEmpty || cityName.isEmpty || categoryIn.isEmpty) return null;

    final normalizedCategory = PlaceCategoryNormalizer.normalize(
      categoryIn,
      contextText: query,
    );

    if (!AppConfig.hasValidGeminiKey) {
      return null;
    }

    final prompt = '''
Generate structured place data (JSON only) for an admin to review before saving.

User query: "$query"
City: "$cityName"
Category: "$normalizedCategory"
Optional notes: "${_notes.text.trim()}"

Rules:
- Return JSON with these keys:
  name, displayName, normalizedName, aliases, address, shortDescription, fullDescription, history, openingHours, lat, lng, suggestedImageSearchTerms
- If you are not confident about exact coordinates, return lat=0 and lng=0.
- Aliases can be an empty list.
- openingHours can be "" if unknown.
- suggestedImageSearchTerms can be a list of short phrases.

JSON example:
{
  "name":"...",
  "displayName":"...",
  "normalizedName":"...",
  "aliases":["..."],
  "address":"...",
  "shortDescription":"...",
  "fullDescription":"...",
  "history":"...",
  "openingHours":"...",
  "lat":0,
  "lng":0,
  "suggestedImageSearchTerms":["..."]
}
''';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/${AppConfig.geminiModel}:generateContent?key=${AppConfig.geminiApiKey}',
    );

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.55,
        'topP': 0.9,
        'topK': 35,
        'maxOutputTokens': 1200,
        'responseMimeType': 'application/json',
      },
    };

    final resp = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      return null;
    }

    final decoded = jsonDecode(resp.body) as Object;

    String text = '';

    // Safe extraction: Gemini responses are not always consistent.
    // We traverse defensively and never assume the exact response shape.
    if (decoded is Map) {
      final candidates = decoded['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final firstCandidate = candidates.first;
        if (firstCandidate is Map) {
          final content = firstCandidate['content'];
          if (content is Map) {
            final parts = content['parts'];
            if (parts is List && parts.isNotEmpty) {
              final firstPart = parts.first;
              if (firstPart is Map) {
                final t = firstPart['text'];
                if (t != null) text = t.toString();
              }
            }
          }
        }
      }

      // Some variants return plain text under other keys.
      if (text.isEmpty) {
        final altText = decoded['text'];
        if (altText != null) text = altText.toString();
      }
      if (text.isEmpty) {
        final altCandidates = decoded['output'];
        if (altCandidates != null) text = altCandidates.toString();
      }
    }

    String rawJson = text.trim();

    // If the AI returns only JSON, decoding text is enough.
    // If it returns extra text, try extracting the first JSON object block.
    if (rawJson.isEmpty) {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(resp.body);
      if (match != null) rawJson = (match.group(0) ?? '').trim();
    }

    if (rawJson.isEmpty) return null;

    Map<String, dynamic>? data;

    // 1) Try direct decode.
    try {
      final decodedJson = jsonDecode(rawJson);
      if (decodedJson is Map<String, dynamic>) {
        data = decodedJson;
      }
    } catch (_) {}

    // 2) If direct decode failed, try extracting JSON block.
    if (data == null) {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(rawJson);
      final block = (match?.group(0) ?? '').trim();
      if (block.isNotEmpty) {
        try {
          final decodedBlock = jsonDecode(block);
          if (decodedBlock is Map<String, dynamic>) {
            data = decodedBlock;
          }
        } catch (_) {}
      }
    }

    if (data == null) return null;

    // Extracted JSON is valid. If it doesn't contain required minimal fields,
    // treat it as invalid and do NOT prefill/save.
    final nameCandidate = (data['name'] ?? query).toString().trim();
    if (nameCandidate.isEmpty) return null;

    double lat = 0;
    double lng = 0;

    final latRaw = data['lat'];
    final lngRaw = data['lng'];
    if (latRaw is num) lat = latRaw.toDouble();
    if (lngRaw is num) lng = lngRaw.toDouble();

    final name = (data['name'] ?? query).toString().trim();
    if (name.isEmpty) return null;

    final now = DateTime.now();

    return Landmark(
      id: '',
      name: name,
      displayName: (data['displayName'] ?? name).toString().trim(),
      normalizedName: (data['normalizedName'] ?? name).toString().trim(),
      aliases: (data['aliases'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      cityId: '',
      city: cityName,
      category: normalizedCategory,
      description: (data['shortDescription'] ?? '').toString().trim(),
      shortDescription: (data['shortDescription'] ?? '').toString().trim(),
      fullDescription: (data['fullDescription'] ?? '').toString().trim(),
      history: (data['history'] ?? '').toString().trim(),
      imageUrl: '',
      mediaUrls: const [],
      lat: lat,
      lng: lng,
      address: (data['address'] ?? '').toString().trim(),
      rating: 0,
      openingHours: (data['openingHours'] ?? '').toString().trim(),
      location: lat != 0 && lng != 0 ? '$lat, $lng' : '',
      createdAt: now,
      updatedAt: now,
      generatedBySearch: false,
      hidden: false,
      needsReview: true,
      invalidPlace: false,
      invalidReason: '',
      sources: {
        'provider': 'admin_ai_prefill',
        'query': query,
        'adminAiGeneratedAt': now.toIso8601String(),
      },
      nearbyPlaces: const [],
    );
  }

  bool _isWeakAfterEnrichment(Landmark lm) {
    final short = lm.shortDescription.trim();
    final full = lm.fullDescription.trim();
    final history = lm.history.trim();
    final hasImage = lm.imageUrl.trim().startsWith('http') || lm.mediaUrls.isNotEmpty;
    final usefulText = short.length >= 40 || full.length >= 80 || history.length >= 80;
    return !hasImage && !usefulText;
  }

  Future<Landmark?> _saveAndEnrichAiDraft(Landmark draft) async {
    var normalized = draft;

    // Make sure AI-created drafts get a real cityId before opening the editor.
    try {
      final city = await AppInjector.firebase.findOrCreateCityByName(
        draft.city,
        lat: draft.lat != 0 ? draft.lat : null,
        lng: draft.lng != 0 ? draft.lng : null,
      );
      normalized = normalized.copyWith(
        cityId: city.id,
        city: city.name,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AdminAiAddCityResolveError] name=${draft.city} error=$e');
      }
    }

    final nowIso = DateTime.now().toIso8601String();
    normalized = normalized.copyWith(
      needsReview: true,
      sources: {
        ...?normalized.sources,
        'provider': 'admin_ai_prefill',
        'adminAiAutoApiEnriched': true,
        'adminAiAutoApiEnrichedAt': nowIso,
        'adminOrigin': 'ai_prefill',
        'adminQuery': _q.text.trim(),
      },
    );

    final savedId = await AppInjector.firebase.adminUpsertPlace(
      normalized,
      createdByAdmin: true,
      markVerified: true,
    );

    var fresh = await AppInjector.firebase.getLandmarkById(savedId);
    if (fresh == null) return normalized.copyWith(id: savedId);

    if (kDebugMode) {
      debugPrint('[AdminAiAddEnrichStart] id=$savedId name=${fresh.name}');
    }

    await AppInjector.repository.enrichWikipedia(fresh, force: true);

    fresh = await AppInjector.firebase.getLandmarkById(savedId) ?? fresh;
    if (kDebugMode) {
      debugPrint('[AdminAiAddWikiDone] id=$savedId');
    }

    await AppInjector.repository.enrichImages(
      fresh,
      force: true,
      imageUpdateSource: 'admin_image_refresh',
      allowAdminImageOverwrite: true,
    );

    fresh = await AppInjector.firebase.getLandmarkById(savedId) ?? fresh;
    if (kDebugMode) {
      debugPrint(
        '[AdminAiAddImagesDone] id=$savedId image=${fresh.imageUrl} mediaCount=${fresh.mediaUrls.length}',
      );
    }

    if (_isWeakAfterEnrichment(fresh)) {
      await AppInjector.firebase.partialUpdate(savedId, {
        'needsReview': true,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      fresh = await AppInjector.firebase.getLandmarkById(savedId) ?? fresh;
    }

    LandmarkCache.instance.put(fresh);

    if (kDebugMode) {
      debugPrint(
        '[AdminAiAddFresh] id=${fresh.id} shortEmpty=${fresh.shortDescription.trim().isEmpty} image=${fresh.imageUrl}',
      );
    }

    return fresh;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      appBar: AppBar(
        title: const Text('Add using AI'),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Optional notes',
                filled: true,
                fillColor: Color(0xFFF9F5F1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
              ),
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
              onPressed: _loading
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() {
                        _loading = true;
                        _message = 'Generating with AI...';
                      });
                      try {
                        final draft = await _generate();
                        if (!mounted) return;
                        if (draft == null) {
                          setState(() {
                            _message = 'AI returned invalid/insufficient JSON. Nothing was saved. Complete the form manually.';
                          });
                          return;
                        }

                        setState(() {
                          _message = 'Fetching details and images from APIs...';
                        });

                        final enrichedDraft = await _saveAndEnrichAiDraft(draft);
                        if (!mounted) return;
                        if (enrichedDraft == null) {
                          setState(() {
                            _message = 'Could not enrich AI place. Complete the form manually.';
                          });
                          return;
                        }

                        final res = await Navigator.push<Map<String, dynamic>>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminPlaceEditor(
                              origin: 'ai_prefill',
                              query: _q.text.trim(),
                              place: enrichedDraft,
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
                          _message = 'AI/API add failed: $e';
                        });
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_loading ? 'Generating and fetching...' : 'Generate with AI'),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminPlaceEditor(
                      place: null,
                      origin: 'manual',
                      query: _q.text.trim(),
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
