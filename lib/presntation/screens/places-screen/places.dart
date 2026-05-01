// ignore_for_file: sort_child_properties_last, file_names

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/place-info/place-info.dart';

class Places extends StatelessWidget {
  final List<Landmark> places;
  final bool isAdmin;

  const Places({
    super.key,
    required this.places,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    const themeBg = Color(0xFFF7F1EB);

    return Scaffold(
      backgroundColor: themeBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 235,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF8D6E63),
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
                          Color(0xFFA67C52),
                          Color(0xFF8D6E63),
                          Color(0xFF5D4037),
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
                    bottom: 22,
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
                                  'Explore Egypt',
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
                                'All places\nin one screen',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                places.isEmpty
                                    ? 'No places available right now.'
                                    : 'Browse ${places.length} place${places.length > 1 ? 's' : ''} and open any card for full details.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w400,
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
                  color: themeBg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: places.isEmpty
                      ? const _EmptyState()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionHeader(
                              title: 'Discover Places',
                              subtitle:
                                  'Tap any place to open photos, history, details, and more.',
                            ),
                            const SizedBox(height: 16),

                            /// مهم: ListView جوه Column لازم shrinkWrap + never scroll
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: places.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final place = places[index];
                                return _PlaceListCard(
                                  key: ValueKey(place.id),
                                  place: place,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            PlaceInfoScreen(place: place),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceListCard extends StatelessWidget {
  final Landmark place;
  final VoidCallback onTap;

  const _PlaceListCard({
    super.key,
    required this.place,
    required this.onTap,
  });

  String get _imageUrl {
    if (place.imageUrl.trim().isNotEmpty) return place.imageUrl.trim();

    final cleaned = place.mediaUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();

    if (cleaned.isNotEmpty) return cleaned.first;
    return '';
  }

  String get _description {
    if (place.shortDescription.trim().isNotEmpty) {
      return place.shortDescription.trim();
    }
    if (place.description.trim().isNotEmpty) {
      return place.description.trim();
    }
    if (place.address.trim().isNotEmpty) {
      return place.address.trim();
    }
    return 'No description available.';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: _imageUrl.isEmpty
                      ? const _Placeholder()
                      : Image.network(
                          _imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: const Color(0xFFE9E1D9),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => const _Placeholder(),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (place.category.trim().isNotEmpty)
                            _MiniPill(
                              icon: Icons.category_rounded,
                              label: place.category.toUpperCase(),
                            ),
                          if (place.category.trim().isNotEmpty &&
                              place.city.trim().isNotEmpty)
                            const SizedBox(width: 6),
                          if (place.city.trim().isNotEmpty)
                            _MiniPill(
                              icon: Icons.location_on_rounded,
                              label: place.city,
                            ),
                          if ((place.category.trim().isNotEmpty ||
                                  place.city.trim().isNotEmpty) &&
                              place.rating > 0)
                            const SizedBox(width: 6),
                          if (place.rating > 0)
                            _MiniPill(
                              icon: Icons.star_rounded,
                              label: place.rating.toStringAsFixed(1),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E251F),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6C625B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (place.address.trim().isNotEmpty) ...[
                          const Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: Color(0xFF8D6E63),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              place.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF8D6E63),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
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
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4ECE5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF8D6E63)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.8,
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

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE9E1D9),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 34,
            color: Color(0xFF9A918B),
          ),
          SizedBox(height: 6),
          Text(
            'No image available',
            style: TextStyle(
              color: Color(0xFF9A918B),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
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
                Icons.travel_explore_rounded,
                size: 34,
                color: Color(0xFF8D6E63),
              ),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'No places found',
            style: TextStyle(
              color: Color(0xFF2E251F),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'There are no places to show right now.',
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