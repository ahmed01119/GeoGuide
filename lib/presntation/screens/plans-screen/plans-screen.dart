import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/screens/home-screen/planner-screen.dart';
import 'package:geoguide/services/firebase_service.dart';

// This screen shows the user's saved visit plans and allows them to open or delete them.

class SavedPlansPage extends StatelessWidget {
  static const routeName = '/savedPlans';

  const SavedPlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.chestnutBrown,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: _GlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.chestnutBrown,
                                AppColors.deepChestnut,

                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.16),
                            Colors.black.withOpacity(0.05),
                            Colors.black.withOpacity(0.42),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.22),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Trip Plans',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Your saved\nvisit plans',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Open, review, and manage your saved itineraries.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 13.5,
                                  height: 1.45,
                                ),
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
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -10),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F1EB),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: firebase.userPlansStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingCard();
                      }

                      if (snapshot.hasError) {
                        return _buildErrorCard(
                          snapshot.error.toString(),
                        );
                      }

                      final plans = snapshot.data ?? [];

                      if (plans.isEmpty) {
                        return _buildEmptyState();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionHeader(
                            title: 'Saved Plans',
                            subtitle:
                                'Each saved plan keeps your trip days and selected places.',
                          ),
                          const SizedBox(height: 16),
                          ...plans.map(
                            (plan) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _SavedPlanCard(
                                key: ValueKey(
                                  (plan['id'] ?? '').toString(),
                                ),
                                plan: plan,
                                onOpen: () {
                                  final parsedPlan = _parsePlan(plan);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PlannerScreen(plan: parsedPlan),
                                    ),
                                  );
                                },
                                onDelete: () async {
                                  final planId =
                                      (plan['id'] ?? '').toString().trim();
                                  if (planId.isEmpty) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not delete this plan.',
                                          ),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  await firebase.deletePlan(planId);

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Plan deleted'),
                                        backgroundColor: Color(0xFF8D6E63),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<List<Landmark>> _parsePlan(Map<String, dynamic> planDoc) {
    final rawDays = (planDoc['days'] as List? ?? []);

    return rawDays.map<List<Landmark>>((day) {
      final dayMap = Map<String, dynamic>.from(day as Map);
      final places = (dayMap['places'] as List? ?? []);

      return places.map<Landmark>((p) {
        final map = Map<String, dynamic>.from(p as Map);

        return Landmark(
          id: (map['id'] ?? '').toString(),
          name: (map['name'] ?? '').toString(),
          cityId: (map['cityId'] ?? '').toString(),
          city: (map['city'] ?? '').toString(),
          category: (map['category'] ?? '').toString(),
          description: (map['shortDescription'] ?? '').toString(),
          shortDescription: (map['shortDescription'] ?? '').toString(),
          fullDescription: (map['fullDescription'] ?? '').toString(),
          history: (map['history'] ?? '').toString(),
          imageUrl: (map['imageUrl'] ?? '').toString(),
          mediaUrls: (map['mediaUrls'] as List?)
                  ?.map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .toList() ??
              [],
          lat: ((map['lat'] ?? 0) as num).toDouble(),
          lng: ((map['lng'] ?? 0) as num).toDouble(),
          address: (map['address'] ?? map['city'] ?? '').toString(),
          rating: ((map['rating'] ?? 0) as num).toDouble(),
          openingHours: (map['openingHours'] ?? '').toString(),
          location: (map['location'] ?? '').toString(),
          wikipediaUrl: map['wikipediaUrl']?.toString(),
        );
      }).toList();
    }).toList();
  }

  Widget _buildLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Loading saved plans...',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 34,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFF4ECE5),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Icon(
                Icons.event_note_rounded,
                size: 34,
                color: Color(0xFF8D6E63),
              ),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'No saved plans yet',
            style: TextStyle(
              color: Color(0xFF2E251F),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Generate a visit plan from Home and save it to find it here later.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF81756C),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedPlanCard extends StatefulWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onOpen;
  final Future<void> Function() onDelete;

  const _SavedPlanCard({
    super.key,
    required this.plan,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<_SavedPlanCard> createState() => _SavedPlanCardState();
}

class _SavedPlanCardState extends State<_SavedPlanCard> {
  bool _isDeleting = false;

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Plan'),
            content: const Text(
              'Are you sure you want to delete this plan?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || _isDeleting) return;

    setState(() => _isDeleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.plan['title'] ?? 'Trip Plan').toString();
    final city = (widget.plan['city'] ?? 'Unknown city').toString();
    final daysCount = (widget.plan['daysCount'] ?? 0).toString();
    final placesCount = (widget.plan['placesCount'] ?? 0).toString();

    return Dismissible(
      key: ValueKey((widget.plan['id'] ?? '').toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _handleDelete();
        return false;
      },
      background: Container(
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _isDeleting ? null : widget.onOpen,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4ECE5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: Color(0xFF8D6E63),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E251F),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        city,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8D6E63),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MiniPill(
                            icon: Icons.calendar_today_rounded,
                            label:
                                '$daysCount day${daysCount == '1' ? '' : 's'}',
                          ),
                          _MiniPill(
                            icon: Icons.place_rounded,
                            label: '$placesCount places',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    IconButton(
                      onPressed: _isDeleting ? null : _handleDelete,
                      splashRadius: 22,
                      icon: _isDeleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.redAccent,
                              ),
                            )
                          : const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Color(0xFF8D6E63),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1E7DE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF8D6E63)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8D6E63),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2E251F),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF81756C),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
