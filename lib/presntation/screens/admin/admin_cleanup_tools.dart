import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/presntation/screens/admin/admin_guard.dart';

class AdminCleanupTools extends StatefulWidget {
  const AdminCleanupTools({super.key});

  @override
  State<AdminCleanupTools> createState() => _AdminCleanupToolsState();
}

class _AdminCleanupToolsState extends State<AdminCleanupTools> {
  List<City> _cities = [];
  String _cityId = '';
  bool _loading = true;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cities = await AppInjector.firebase.getCities();
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _loading = false;
    });
  }

  Future<void> _runCityCleanup() async {
    if (_cityId.trim().isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Run City Cleanup'),
        content: const Text('Are you sure you want to run cleanup for this city?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Run')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final res = await AppInjector.firebase.adminRunCleanupCity(_cityId);
      if (!mounted) return;
      setState(() {
        _summary = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cleanup failed: $e')));
    }
  }

  Future<void> _runAllCleanup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Run Cleanup For All Cities'),
        content: const Text('This runs in batches. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Run')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    final res = await AppInjector.firebase.adminRunCleanupAllCities();
    if (!mounted) return;
    setState(() {
      _summary = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      child: Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      appBar: AppBar(
        title: const Text('Admin Cleanup Tools'),
        backgroundColor: AppColors.chestnutBrown,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.chestnutBrown))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cleanup Current City',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _cityId.isEmpty ? null : _cityId,
                        hint: const Text('Select city'),
                        items: _cities
                            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _cityId = v ?? ''),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _runCityCleanup,
                        icon: const Icon(Icons.cleaning_services_rounded),
                        label: const Text('Run City Cleanup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.chestnutBrown,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (_cityId.isEmpty) return;
                          await AppInjector.firebase.cleanupDuplicatesForCity(_cityId);
                          await AppInjector.firebase.addAdminLog(
                            actionType: 'duplicate_merged',
                            targetCollection: 'cities',
                            targetId: _cityId,
                            reason: 'manual duplicate cleanup',
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Duplicate cleanup completed')),
                          );
                        },
                        icon: const Icon(Icons.merge_type_rounded),
                        label: const Text('Cleanup Duplicates For City'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (_cityId.isEmpty) return;
                          await AppInjector.firebase.cleanupWrongCityAssignments(_cityId);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('City assignment validation completed')),
                          );
                        },
                        icon: const Icon(Icons.location_searching_rounded),
                        label: const Text('Validate Wrong City Assignments'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Global Cleanup', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _runAllCleanup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.chestnutBrown,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Run Cleanup All Cities (Manual)'),
                      ),
                    ],
                  ),
                ),
                if (_summary != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Summary:\n${_summary.toString()}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF5E544D),
                      ),
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }
}
