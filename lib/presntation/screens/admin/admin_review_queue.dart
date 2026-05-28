import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/screens/admin/admin_guard.dart';
import 'package:geoguide/presntation/screens/admin/admin_place_editor.dart';
import 'package:geoguide/presntation/screens/admin/admin_place_preview_card.dart';

class AdminReviewQueue extends StatefulWidget {
  const AdminReviewQueue({super.key});

  @override
  State<AdminReviewQueue> createState() => _AdminReviewQueueState();
}

class _AdminReviewQueueState extends State<AdminReviewQueue> {
  bool _loading = true;
  List<Landmark> _queue = [];
  Landmark? _lastUpdated;
  String _lastAction = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = await AppInjector.firebase.adminGetReviewQueue();
    if (!mounted) return;
    setState(() {
      _queue = q;
      _loading = false;
    });
  }

  Future<void> _approve(Landmark lm) async {
    await AppInjector.firebase.adminApprovePlace(lm.id);
    final fresh = await AppInjector.firebase.getLandmarkById(lm.id);
    if (fresh != null && mounted) {
      setState(() {
        _lastUpdated = fresh;
        _lastAction = 'Place approved';
      });
    }
    await _load();
  }

  Future<void> _editApprove(Landmark lm) async {
    final changed = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => AdminPlaceEditor(place: lm)),
    );
    final placeId = (changed?['placeId'] ?? '').toString();
    if (placeId.isNotEmpty) {
      final fresh = await AppInjector.firebase.getLandmarkById(placeId);
      if (fresh != null && mounted) {
        setState(() {
          _lastUpdated = fresh;
          _lastAction = 'Place edited';
        });
      }
    }
    if (changed?['changed'] == true) {
      await AppInjector.firebase.adminApprovePlace(lm.id);
      final fresh = await AppInjector.firebase.getLandmarkById(lm.id);
      if (fresh != null && mounted) {
        setState(() {
          _lastUpdated = fresh;
          _lastAction = 'Place edited and approved';
        });
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F1EB),
        appBar: AppBar(
          title: const Text('Admin Review Queue'),
          backgroundColor: AppColors.chestnutBrown,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.chestnutBrown))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_lastUpdated != null) ...[
                    AdminPlacePreviewCard(
                      place: _lastUpdated!,
                      title: _lastAction.isEmpty ? 'Last updated place' : _lastAction,
                      subtitle: 'Tap to open normal place details',
                    ),
                    const SizedBox(height: 12),
                  ],
                  ...List.generate(_queue.length, (i) {
                  final p = _queue[i];
                  final flags = <String>[
                    if (p.needsReview) 'needsReview',
                    if (p.cityNeedsReview) 'cityNeedsReview',
                    if (p.imageNeedsReview) 'imageNeedsReview',
                    if (p.outingNeedsReview) 'outingNeedsReview',
                    if (p.invalidPlace) 'invalid',
                    if (p.isDuplicate) 'duplicate',
                    if (p.hidden) 'hidden',
                  ];
                  return Padding(
                    padding: EdgeInsets.only(bottom: i == _queue.length - 1 ? 0 : 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        title: Text(p.name),
                        subtitle: Text('${p.city} • ${p.category}\n${flags.join(', ')}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'approve') await _approve(p);
                            if (v == 'edit') await _editApprove(p);
                            if (v == 'hide') {
                              await AppInjector.firebase
                                  .adminHidePlace(p.id, reason: 'review queue hide');
                              final fresh = await AppInjector.firebase.getLandmarkById(p.id);
                              if (fresh != null && mounted) {
                                setState(() {
                                  _lastUpdated = fresh;
                                  _lastAction = 'Place hidden';
                                });
                              }
                              await _load();
                            }
                            if (v == 'unhide') {
                              await AppInjector.firebase.adminUnhidePlace(p.id);
                              final fresh = await AppInjector.firebase.getLandmarkById(p.id);
                              if (fresh != null && mounted) {
                                setState(() {
                                  _lastUpdated = fresh;
                                  _lastAction = 'Place unhidden';
                                });
                              }
                              await _load();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'approve', child: Text('Approve')),
                            const PopupMenuItem(value: 'edit', child: Text('Edit & approve')),
                            const PopupMenuItem(value: 'hide', child: Text('Hide')),
                            const PopupMenuItem(value: 'unhide', child: Text('Unhide')),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                ],
              ),
      ),
    );
  }
}
