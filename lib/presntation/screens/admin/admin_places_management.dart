import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/constants/app_colors.dart';

// NOTE: Admin delete UI wiring only (Firebase call already exists in FirebaseService).

import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/screens/admin/admin_guard.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/presntation/screens/admin/admin_place_editor.dart';
import 'package:geoguide/presntation/screens/admin/admin_place_preview_card.dart';
import 'package:geoguide/presntation/screens/admin/admin_add_place_method_selector.dart';
import 'package:geoguide/presntation/screens/admin/admin_api_add_place_screen.dart';
import 'package:geoguide/presntation/screens/admin/admin_ai_add_place_screen.dart';

class AdminPlacesManagement extends StatefulWidget {
  const AdminPlacesManagement({super.key});

  @override
  State<AdminPlacesManagement> createState() => _AdminPlacesManagementState();
}

class _AdminPlacesManagementState extends State<AdminPlacesManagement> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  Future<String?> _confirmDeletePlaceDialog({
    required String placeName,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete Place'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to permanently delete this place from Firebase?'),
              SizedBox(height: 12),
              Text('This action cannot be undone.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('confirmed'),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    return result;
  }

  List<Landmark> _all = [];
  List<Landmark> _filtered = [];
  List<City> _cities = [];
  String _cityId = '';
  String _category = '';
  bool _onlyReview = false;
  bool _loading = true;
  Landmark? _lastUpdated;
  String _lastAction = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cities = await AppInjector.firebase.getCities();
      final places = await AppInjector.firebase.adminGetPlaces(
        cityId: _cityId,
        category: _category,
        needsReview: _onlyReview ? true : null,
      );
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _all = places;
        _applySearch();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _applySearch() {
    final q = _search.text.trim().toLowerCase();
    _filtered = _all.where((p) {
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.city.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _replaceFreshPlaceInMemory(
    Landmark fresh, {
    required String action,
  }) async {
    LandmarkCache.instance.notifyAdminPlaceChanged(fresh);
    // ignore: avoid_print
    print('[AdminFreshCacheUpdated] id=${fresh.id} image=${fresh.imageUrl} mediaCount=${fresh.mediaUrls.length}');

    if (!mounted) return;
    setState(() {
      final index = _all.indexWhere((e) => e.id == fresh.id);
      if (index >= 0) {
        _all[index] = fresh;
        // ignore: avoid_print
        print('[AdminListItemReplaced] id=${fresh.id} image=${fresh.imageUrl}');
      } else {
        _all.insert(0, fresh);
      }

      _applySearch();
      _lastUpdated = fresh;
      _lastAction = action;
    });

    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showPreviewForPlace(String placeId, String action) async {
    final fresh = await AppInjector.firebase.getLandmarkById(placeId);
    if (!mounted || fresh == null) return;
    await _replaceFreshPlaceInMemory(fresh, action: action);
  }

  Future<void> _onHideToggle(Landmark p) async {
    if (p.hidden) {
      await AppInjector.firebase.adminUnhidePlace(p.id);
      await _showPreviewForPlace(p.id, 'Place unhidden');
    } else {
      await AppInjector.firebase.adminHidePlace(p.id, reason: 'admin quick toggle');
      await _showPreviewForPlace(p.id, 'Place hidden');
    }
    await _load();
  }

  Future<void> _onApprove(Landmark p) async {
    await AppInjector.firebase.adminApprovePlace(p.id);
    await _showPreviewForPlace(p.id, 'Place approved');
    await _load();
  }

  Future<void> _onMarkInvalid(Landmark p) async {
    await AppInjector.firebase.adminMarkInvalid(p.id, 'Marked invalid by admin');
    await _showPreviewForPlace(p.id, 'Place marked invalid');
    await _load();
  }

  Future<void> _openEditor([Landmark? p]) async {
    final isManual = p == null;
    final origin = isManual ? 'manual' : 'edit_existing';

    // Always open editor with the freshest Firestore copy to avoid saving stale
    // imageUrl/mediaUrls after an admin refresh.
    Landmark? editorPlace = p;
    if (p != null && p.id.trim().isNotEmpty) {
      editorPlace = await AppInjector.firebase.getLandmarkById(p.id) ?? p;
      LandmarkCache.instance.put(editorPlace);
    }

    final changed = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPlaceEditor(
          place: editorPlace,
          origin: origin,
        ),
      ),
    );

    if (changed?['changed'] != true) return;

    final placeId = (changed?['placeId'] ?? '').toString().trim();
    if (placeId.isEmpty) return;

    final fresh = await AppInjector.firebase.getLandmarkById(placeId);
    if (!mounted) return;

    if (fresh != null) {
      await _replaceFreshPlaceInMemory(
        fresh,
        action: isManual ? 'New place added' : 'Place updated',
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isManual ? 'Place added successfully' : 'Place updated successfully'),
        backgroundColor: AppColors.chestnutBrown,
      ),
    );

    await _load();
  }

  Future<void> _openApiAdd() async {
    final changed = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AdminApiAddPlaceScreen()),
    );

    if (changed?['changed'] != true) {
      await _load();
      return;
    }

    final placeId = (changed?['placeId'] ?? '').toString().trim();
    if (placeId.isNotEmpty) {
      final fresh = await AppInjector.firebase.getLandmarkById(placeId);
      if (fresh != null) {
        await _replaceFreshPlaceInMemory(fresh, action: 'API place added');
      }
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F1EB),
        appBar: AppBar(
          title: const Text('Admin Places'),
          backgroundColor: AppColors.chestnutBrown,
          actions: [
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AdminAddPlaceMethodSelector(
                    onManual: () async {
                      Navigator.pop(context);
                      await _openEditor(null);
                    },
                    onApi: () async {
                      Navigator.pop(context);
                      await _openApiAdd();
                    },
                    onAi: () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminAiAddPlaceScreen()),
                      );
                      await _load();
                    },
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.chestnutBrown),
              )
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  if (_lastUpdated != null) ...[
                    AdminPlacePreviewCard(
                      place: _lastUpdated!,
                      title: _lastAction.isEmpty ? 'Last updated place' : _lastAction,
                      subtitle: 'Tap to open normal place details',
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(_applySearch),
                          decoration: InputDecoration(
                            hintText: 'Search places...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: const Color(0xFFF9F5F1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _cityId.isEmpty ? null : _cityId,
                                hint: const Text('City'),
                                items: _cities
                                    .map((c) => DropdownMenuItem(
                                          value: c.id,
                                          child: Text(c.name),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  _cityId = v ?? '';
                                  _load();
                                },
                                decoration: const InputDecoration(
                                  filled: true,
                                  fillColor: Color(0xFFF9F5F1),
                                  border: OutlineInputBorder(borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _category.isEmpty ? null : _category,
                                hint: const Text('Category'),
                                items: const ['tourist', 'hotel', 'restaurant', 'cafe', 'outing']
                                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (v) {
                                  _category = v ?? '';
                                  _load();
                                },
                                decoration: const InputDecoration(
                                  filled: true,
                                  fillColor: Color(0xFFF9F5F1),
                                  border: OutlineInputBorder(borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile.adaptive(
                          value: _onlyReview,
                          onChanged: (v) {
                            _onlyReview = v;
                            _load();
                          },
                          title: const Text('Only review queue'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._filtered.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          title: Text(p.name),
                          subtitle: Text('${p.city} • ${p.category}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') await _openEditor(p);
                              if (v == 'hide') await _onHideToggle(p);
                              if (v == 'approve') await _onApprove(p);
                              if (v == 'invalid') await _onMarkInvalid(p);
                              if (v == 'delete') {
                                final confirmed = await _confirmDeletePlaceDialog(placeName: p.name);
                                if (confirmed == null || confirmed.trim().isEmpty) return;

                                final summary = await AppInjector.firebase.adminHardDeletePlaceWithCascade(
                                  placeId: p.id,
                                  typedConfirmation: 'confirmed',
                                );

                                if (!mounted) return;

                                if (!summary.isSuccess) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Delete failed: ${summary.failedSteps.isNotEmpty ? summary.failedSteps.first : 'partial success'}',
                                      ),
                                      backgroundColor: AppColors.red.withOpacity(0.15),
                                    ),
                                  );
                                  return;
                                }

                                setState(() {
                                  _all.removeWhere((x) => x.id == p.id);
                                  _applySearch();
                                  _lastUpdated = null;
                                  _lastAction = 'Place deleted';
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Deleted: ${summary.deletedLandmark}. Favorites: ${summary.favoritesDeleted}, Reviews: ${summary.reviewsDeleted}, Nearby: ${summary.nearbyDeleted}, Duplicates: ${summary.duplicateRefsUpdated}',
                                    ),
                                  ),
                                );
                                await _load();
                                return;
                              }
                              if (v == 'refresh_images') {
                                final freshBefore = await AppInjector.firebase.getLandmarkById(p.id) ?? p;
                                await AppInjector.repository.enrichImages(
                                  freshBefore,
                                  force: true,
                                  imageUpdateSource: 'admin_image_refresh',
                                  allowAdminImageOverwrite: true,
                                );
                                await AppInjector.firebase.addAdminLog(
                                  actionType: 'images_refreshed',
                                  targetCollection: 'landmarks',
                                  targetId: p.id,
                                );
                                await _showPreviewForPlace(p.id, 'Images refreshed');
                                await _load();
                              }
                              if (v == 'refresh_details') {
                                final freshBefore = await AppInjector.firebase.getLandmarkById(p.id) ?? p;
                                await AppInjector.repository.enrichWikipedia(freshBefore, force: true);
                                await AppInjector.firebase.addAdminLog(
                                  actionType: 'details_refreshed',
                                  targetCollection: 'landmarks',
                                  targetId: p.id,
                                );
                                await _showPreviewForPlace(p.id, 'Details refreshed');
                                await _load();
                              }
                              if (v == 'refresh_nearby') {
                                final freshBefore = await AppInjector.firebase.getLandmarkById(p.id) ?? p;
                                await AppInjector.repository.enrichNearby(freshBefore, force: true);
                                await AppInjector.firebase.addAdminLog(
                                  actionType: 'details_refreshed',
                                  targetCollection: 'landmarks',
                                  targetId: p.id,
                                  reason: 'nearby refreshed',
                                );
                                await _showPreviewForPlace(p.id, 'Nearby refreshed');
                                await _load();
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'hide', child: Text(p.hidden ? 'Unhide' : 'Hide')),
                              const PopupMenuItem(value: 'approve', child: Text('Approve')),
                              const PopupMenuItem(value: 'invalid', child: Text('Mark invalid')),
                              const PopupMenuItem(value: 'refresh_images', child: Text('Refresh images')),
                              const PopupMenuItem(value: 'refresh_details', child: Text('Refresh details')),
                              const PopupMenuItem(value: 'refresh_nearby', child: Text('Refresh nearby')),
                              PopupMenuItem(
                                value: 'delete',
                                textStyle: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
