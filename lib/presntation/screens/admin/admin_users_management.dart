import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/presntation/screens/admin/admin_guard.dart';

class AdminUsersManagement extends StatefulWidget {
  const AdminUsersManagement({super.key});

  @override
  State<AdminUsersManagement> createState() => _AdminUsersManagementState();
}

class _AdminUsersManagementState extends State<AdminUsersManagement> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await AppInjector.firebase.adminListUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _apply();
      _loading = false;
    });
  }

  void _apply() {
    final q = _search.text.trim().toLowerCase();
    _filtered = _users.where((u) {
      if (q.isEmpty) return true;
      final n = (u['name'] ?? '').toString().toLowerCase();
      final e = (u['email'] ?? '').toString().toLowerCase();
      return n.contains(q) || e.contains(q);
    }).toList();
  }

  Future<void> _toggleBlock(Map<String, dynamic> u) async {
    await AppInjector.firebase
        .adminSetUserBlocked((u['uid'] ?? '').toString(), !(u['isBlocked'] == true));
    await _load();
  }

  Future<void> _toggleRole(Map<String, dynamic> u) async {
    final current = (u['role'] ?? 'user').toString().toLowerCase();
    final next = current == 'admin' ? 'user' : 'admin';
    await AppInjector.firebase.adminSetUserRole((u['uid'] ?? '').toString(), next);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F1EB),
        appBar: AppBar(
          title: const Text('Admin Users'),
          backgroundColor: AppColors.chestnutBrown,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.chestnutBrown))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(_apply),
                      decoration: InputDecoration(
                        hintText: 'Search users by name/email...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final u = _filtered[i];
                        final blocked = u['isBlocked'] == true;
                        final role = (u['role'] ?? 'user').toString();
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            title: Text((u['name'] ?? '').toString().isEmpty
                                ? '(No name)'
                                : (u['name'] ?? '').toString()),
                            subtitle: Text(
                              '${u['email']}\nrole=$role ${blocked ? '• BLOCKED' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'block') await _toggleBlock(u);
                                if (v == 'role') await _toggleRole(u);
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'block',
                                  child: Text(blocked ? 'Unblock User' : 'Block User'),
                                ),
                                PopupMenuItem(
                                  value: 'role',
                                  child: Text(
                                    role == 'admin' ? 'Set role: user' : 'Set role: admin',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
