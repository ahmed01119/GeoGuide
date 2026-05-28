import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/place-info/place-info.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:share_plus/share_plus.dart';

class PlannerScreen extends StatelessWidget {
  final List<List<Landmark>> plan;

  PlannerScreen({
    super.key,
    required this.plan,
  });

  final FirebaseService firebase = FirebaseService();

  String get _cityName {
    for (final day in plan) {
      if (day.isNotEmpty) {
        final city = day.first.city.trim();
        if (city.isNotEmpty) return city;
      }
    }
    return 'Egypt';
  }

  int get _totalPlaces {
    return plan.fold<int>(0, (sum, day) => sum + day.length);
  }

  String get _defaultTitle {
    return '$_cityName ${plan.length}-day trip';
  }

  Future<void> _savePlan(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in first to save your plan.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await firebase.savePlan(
      plan: plan,
      title: _defaultTitle,
      userId: user.uid,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Plan saved successfully'),
        backgroundColor: Color(0xFF8D6E63),
      ),
    );
  }

  void _sharePlan() {
    final buffer = StringBuffer();
    buffer.writeln('Trip Plan - $_cityName');
    buffer.writeln('${plan.length} day(s) • $_totalPlaces place(s)');
    buffer.writeln();

    for (int i = 0; i < plan.length; i++) {
      final day = plan[i];
      buffer.writeln('Day ${i + 1}:');

      if (day.isEmpty) {
        buffer.writeln('- Free day');
      } else {
        for (final place in day) {
          buffer.writeln('- ${place.name}');
        }
      }

      buffer.writeln();
    }

    Share.share(buffer.toString().trim());
  }

  String _getImageUrl(Landmark place) {
    if (place.imageUrl.trim().isNotEmpty) {
      return place.imageUrl.trim();
    }

    final cleaned = place.mediaUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();

    if (cleaned.isNotEmpty) return cleaned.first;
    return '';
  }

  List<String> _getImages(Landmark place) {
    final urls = <String>[];

    if (place.imageUrl.trim().isNotEmpty) {
      urls.add(place.imageUrl.trim());
    }

    for (final url in place.mediaUrls) {
      final clean = url.trim();
      if (clean.isNotEmpty && !urls.contains(clean)) {
        urls.add(clean);
      }
    }

    return urls.take(7).toList();
  }

  String _getDescription(Landmark place) {
    if (place.shortDescription.trim().isNotEmpty) {
      return place.shortDescription.trim();
    }
    if (place.address.trim().isNotEmpty) {
      return place.address.trim();
    }
    return 'A great place to include in your visit plan.';
  }

  List<Landmark> _morningPlaces(List<Landmark> day) {
    if (day.isEmpty) return [];
    if (day.length <= 2) return day;
    return day.take(2).toList();
  }

  List<Landmark> _afternoonPlaces(List<Landmark> day) {
    if (day.length <= 2) return [];
    if (day.length <= 4) return day.skip(2).toList();
    return day.skip(2).take(2).toList();
  }

  List<Landmark> _eveningPlaces(List<Landmark> day) {
    if (day.length <= 4) return [];
    return day.skip(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isTablet = media.size.shortestSide >= 600;
    final expandedHeight = isTablet ? 260.0 : 220.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
         SliverAppBar(
  expandedHeight: 280,
  toolbarHeight: 72,
  pinned: true,
  backgroundColor: AppColors.chestnutBrown,
  surfaceTintColor: Colors.transparent,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      bottom: Radius.circular(30),
    ),
  ),

  clipBehavior: Clip.antiAlias,
  leading: Padding(
    padding: const EdgeInsets.only(left: 12, top: 8, bottom: 28),
    child: _GlassIconButton(
      icon: Icons.arrow_back_ios_new_rounded,
      onTap: () => Navigator.pop(context),
    ),
  ),
            actions: [
              IconButton(
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: () => _savePlan(context),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: _sharePlan,
              ),
            ],
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
                    bottom: 10,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: EdgeInsets.all(isTablet ? 20 : 16),
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
                                  'AI Trip Plan',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _cityName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isTablet ? 30 : 26,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${plan.length} day plan • $_totalPlaces selected places',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: isTablet ? 14.5 : 13.5,
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
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 24 : 16,
                    12,
                    isTablet ? 24 : 16,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                        title: 'Your itinerary',
                        subtitle:
                            'A realistic day-by-day plan arranged from the selected places in $_cityName.',
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(plan.length, (index) {
                        final day = plan[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _DayPlanCard(
                            dayIndex: index,
                            dayPlaces: day,
                            getImages: _getImages,
                            getImageUrl: _getImageUrl,
                            getDescription: _getDescription,
                            morningPlaces: _morningPlaces(day),
                            afternoonPlaces: _afternoonPlaces(day),
                            eveningPlaces: _eveningPlaces(day),
                          ),
                        );
                      }),
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

class _DayPlanCard extends StatelessWidget {
  final int dayIndex;
  final List<Landmark> dayPlaces;
  final List<String> Function(Landmark) getImages;
  final String Function(Landmark) getImageUrl;
  final String Function(Landmark) getDescription;
  final List<Landmark> morningPlaces;
  final List<Landmark> afternoonPlaces;
  final List<Landmark> eveningPlaces;

  const _DayPlanCard({
    required this.dayIndex,
    required this.dayPlaces,
    required this.getImages,
    required this.getImageUrl,
    required this.getDescription,
    required this.morningPlaces,
    required this.afternoonPlaces,
    required this.eveningPlaces,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return Container(
      padding: EdgeInsets.all(isTablet ? 20 : 16),
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
          Row(
            children: [
              Container(
                width: isTablet ? 54 : 48,
                height: isTablet ? 54 : 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4ECE5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Color(0xFF8D6E63),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Day ${dayIndex + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isTablet ? 20 : 18,
                        color: const Color(0xFF2E251F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dayPlaces.isEmpty
                          ? 'Free day'
                          : '${dayPlaces.length} place${dayPlaces.length > 1 ? 's' : ''} planned',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF81756C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (dayPlaces.isEmpty)
            const _EmptyDayCard()
          else ...[
            if (morningPlaces.isNotEmpty)
              _TimeSection(
                title: 'Morning',
                icon: Icons.wb_sunny_outlined,
                places: morningPlaces,
                getImages: getImages,
                getImageUrl: getImageUrl,
                getDescription: getDescription,
              ),
            if (afternoonPlaces.isNotEmpty) ...[
              const SizedBox(height: 10),
              _TimeSection(
                title: 'Afternoon',
                icon: Icons.wb_cloudy_outlined,
                places: afternoonPlaces,
                getImages: getImages,
                getImageUrl: getImageUrl,
                getDescription: getDescription,
              ),
            ],
            if (eveningPlaces.isNotEmpty) ...[
              const SizedBox(height: 10),
              _TimeSection(
                title: 'Evening',
                icon: Icons.nightlight_round,
                places: eveningPlaces,
                getImages: getImages,
                getImageUrl: getImageUrl,
                getDescription: getDescription,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TimeSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Landmark> places;
  final List<String> Function(Landmark) getImages;
  final String Function(Landmark) getImageUrl;
  final String Function(Landmark) getDescription;

  const _TimeSection({
    required this.title,
    required this.icon,
    required this.places,
    required this.getImages,
    required this.getImageUrl,
    required this.getDescription,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF8D6E63)),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: isTablet ? 15 : 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF6A5344),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...places.map(
          (place) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PlanPlaceCard(
              place: place,
              images: getImages(place),
              imageUrl: getImageUrl(place),
              description: getDescription(place),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanPlaceCard extends StatelessWidget {
  final Landmark place;
  final List<String> images;
  final String imageUrl;
  final String description;

  const _PlanPlaceCard({
    required this.place,
    required this.images,
    required this.imageUrl,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isTablet = media.size.shortestSide >= 600;
    final stacked = media.size.width < 380;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaceInfoScreen(place: place),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9F5F1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFEDE2D8),
                ),
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PlaceImageGallery(
                          imageUrl: imageUrl,
                          images: images,
                          isFullWidth: true,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: _PlaceCardContent(
                            place: place,
                            description: description,
                            isTablet: isTablet,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PlaceImageGallery(
                          imageUrl: imageUrl,
                          images: images,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _PlaceCardContent(
                              place: place,
                              description: description,
                              isTablet: isTablet,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceCardContent extends StatelessWidget {
  final Landmark place;
  final String description;
  final bool isTablet;

  const _PlaceCardContent({
    required this.place,
    required this.description,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          place.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isTablet ? 16.5 : 15.5,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E251F),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (place.city.trim().isNotEmpty)
              _MiniPill(
                icon: Icons.location_on_rounded,
                label: place.city,
              ),
            if (place.category.trim().isNotEmpty)
              _MiniPill(
                icon: Icons.category_rounded,
                label: place.category,
              ),
            if (place.rating > 0)
              _MiniPill(
                icon: Icons.star_rounded,
                label: place.rating.toStringAsFixed(1),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF6C625B),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Color(0xFF8D6E63),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaceImageGallery extends StatefulWidget {
  final String imageUrl;
  final List<String> images;
  final bool isFullWidth;

  const _PlaceImageGallery({
    required this.imageUrl,
    required this.images,
    this.isFullWidth = false,
  });

  @override
  State<_PlaceImageGallery> createState() => _PlaceImageGalleryState();
}

class _PlaceImageGalleryState extends State<_PlaceImageGallery> {
  late final PageController _pageController;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images.where((e) => e.trim().isNotEmpty).toList();

    final width = widget.isFullWidth ? double.infinity : 105.0;
    final height = widget.isFullWidth ? 170.0 : 120.0;

    return ClipRRect(
      borderRadius: widget.isFullWidth
          ? const BorderRadius.vertical(top: Radius.circular(20))
          : const BorderRadius.horizontal(left: Radius.circular(20)),
      child: SizedBox(
        width: width,
        height: height,
        child: images.isEmpty
            ? Container(
                color: const Color(0xFFE9E1D9),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_not_supported_outlined,
                      size: 28,
                      color: Color(0xFF9A918B),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'No image',
                      style: TextStyle(
                        color: Color(0xFF9A918B),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: images.length,
                      onPageChanged: (index) {
                        setState(() => _current = index);
                      },
                      itemBuilder: (_, index) {
                        return Image.network(
                          images[index],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFE9E1D9),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 28,
                                  color: Color(0xFF9A918B),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'No image',
                                  style: TextStyle(
                                    color: Color(0xFF9A918B),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_current + 1}/${images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
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

class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDE2D8)),
      ),
      child: const Text(
        'This day is left light so the trip stays realistic and not exhausting.',
        style: TextStyle(
          fontSize: 12.5,
          color: Color(0xFF6C625B),
          height: 1.45,
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
          Icon(
            icon,
            size: 12,
            color: const Color(0xFF8D6E63),
          ),
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