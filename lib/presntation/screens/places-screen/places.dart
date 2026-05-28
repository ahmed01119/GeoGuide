// ignore_for_file: sort_child_properties_last, file_names

import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/place-info/place-info.dart';
import 'package:geoguide/constants/app_injector.dart';




class Places extends StatelessWidget {
  final List<Landmark> places;
  final bool isAdmin;

  const Places({
    super.key,
    required this.places,
    this.isAdmin = false,
  });

  static double _r(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    const themeBg = Color(0xFFF7F1EB);

    final media = MediaQuery.of(context);
    final size = media.size;
    final width = size.width;
    final height = size.height;
    final shortest = size.shortestSide;
    final isTablet = shortest >= 600;

    final horizontalPadding = _r(width * 0.043, 14, 24);
    final headerHeight =
        isTablet ? _r(height * 0.22, 300, 380) : _r(height * 0.20, 270, 330);

    final glassPadding = _r(width * 0.043, 14, 20);
    final glassTop = media.padding.top + 72;
    final glassBottom = _r(height * 0.022, 18, 26);

    final sectionTopPadding = _r(height * 0.015, 10, 16);
    final sectionBottomPadding = _r(height * 0.030, 22, 32);
    final listGap = _r(height * 0.017, 14, 20);

    return Scaffold(
      backgroundColor: themeBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: headerHeight,
            toolbarHeight: 72,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.chestnutBrown,
            systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: AppColors.chestnutBrown,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            leadingWidth: 72,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, bottom: 22),
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
                          AppColors.chestnutBrown,
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.04),
                              Colors.white.withOpacity(0.02),
                              Colors.black.withOpacity(0.06),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: horizontalPadding,
                    right: horizontalPadding,
                    bottom: glassBottom,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: glassPadding,
                            vertical: glassPadding * 0.6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.22),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 360;
                              final titleSize = compact
                                  ? _r(width * 0.060, 22, 25)
                                  : _r(width * 0.064, 24, 28);
                              final subtitleSize = _r(width * 0.034, 12.5, 14);
                              final badgeSize = _r(width * 0.030, 11.5, 12.5);

                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: _r(width * 0.032, 11, 13),
                                          vertical: _r(height * 0.008, 6, 8),
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.16),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          'Explore Egypt',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: badgeSize,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: .4,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: _r(height * 0.014, 10, 14)),
                                      Text(
                                        'All places\nin one screen',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: titleSize,
                                          height: 1.12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: _r(height * 0.010, 7, 10)),
                                      Text(
                                        places.isEmpty
                                            ? 'No places available right now.'
                                            : 'Browse ${places.length} place${places.length > 1 ? 's' : ''} and open any card for full details.',
                                        maxLines: compact ? 3 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.92),
                                          fontSize: subtitleSize,
                                          height: 1.45,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
              offset: const Offset(0, -8),
              child: Container(
                decoration: const BoxDecoration(
                  color: themeBg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    sectionTopPadding,
                    horizontalPadding,
                    sectionBottomPadding,
                  ),
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
                            SizedBox(height: listGap),

                            /// مهم: ListView جوه Column لازم shrinkWrap + never scroll
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: places.length,
                              separatorBuilder: (_, __) =>
                                  SizedBox(height: listGap),
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

  @override
  Widget build(BuildContext context) {
    final placeId = place.id.trim();

    if (placeId.isEmpty) {
      return _PlaceListCardBody(place: place, onTap: onTap);
    }

    return StreamBuilder<Landmark>(
      stream: AppInjector.repository.streamLandmark(placeId),
      builder: (context, snapshot) {
        final livePlace = snapshot.data ?? place;

        return _PlaceListCardBody(
          place: livePlace,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlaceInfoScreen(place: livePlace),
              ),
            );
          },
        );
      },
    );

  }
}

class _PlaceListCardBody extends StatelessWidget {
  final Landmark place;
  final VoidCallback onTap;

  const _PlaceListCardBody({
    super.key,
    required this.place,
    required this.onTap,
  });

  static double _r(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

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
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;


    final imageHeight = _r(height * 0.215, 170, 230);
    final cardPadding = _r(width * 0.038, 14, 20);
    final titleSize = _r(width * 0.046, 17, 20);
    final descriptionSize = _r(width * 0.033, 12.5, 14);
    final addressSize = _r(width * 0.032, 12, 13.5);

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
                  height: imageHeight,
                  width: double.infinity,
                      child: _imageUrl.isEmpty
                      ? const _Placeholder()
                      : Builder(
                          builder: (context) {
                            final imagesRefreshedAt = place.imagesRefreshedAt;
                            final mediaCount = place.mediaUrls.length;

                            final key = ValueKey(
                              '${place.id}_${place.imageUrl}_${imagesRefreshedAt}_$mediaCount',
                            );

                            return Image.network(
                              key: key,
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
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(cardPadding),
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
                    SizedBox(height: _r(height * 0.014, 10, 14)),
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleSize,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF2E251F),
                      ),
                    ),
                    SizedBox(height: _r(height * 0.010, 7, 10)),
                    Text(
                      _description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: descriptionSize,
                        color: const Color(0xFF6C625B),
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: _r(height * 0.014, 10, 14)),
                    Row(
                      children: [
                        if (place.address.trim().isNotEmpty) ...[
                          Icon(
                            Icons.place_outlined,
                            size: _r(width * 0.041, 15, 18),
                            color: const Color(0xFF8D6E63),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              place.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: addressSize,
                                color: const Color(0xFF8D6E63),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: _r(width * 0.041, 15, 18),
                          color: const Color(0xFF8D6E63),
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

  static double _r(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _r(width * 0.026, 9, 11),
        vertical: _r(width * 0.015, 5, 7),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4ECE5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: _r(width * 0.033, 12, 14),
            color: const Color(0xFF8D6E63),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: _r(width * 0.028, 10.5, 12),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8D6E63),
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

  static double _r(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _r(width * 0.052, 19, 22),
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E251F),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: _r(width * 0.033, 12.5, 14),
            color: const Color(0xFF81756C),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  static double _r(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Container(
      color: const Color(0xFFE9E1D9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: _r(width * 0.086, 30, 38),
            color: const Color(0xFF9A918B),
          ),
          const SizedBox(height: 6),
          Text(
            'No image available',
            style: TextStyle(
              color: const Color(0xFF9A918B),
              fontSize: _r(width * 0.028, 10.5, 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  static double _r(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: _r(height * 0.044, 32, 42),
        horizontal: _r(width * 0.053, 18, 24),
      ),
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
        children: [
          SizedBox(
            width: _r(width * 0.18, 68, 82),
            height: _r(width * 0.18, 68, 82),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFFF4ECE5),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Icon(
                Icons.travel_explore_rounded,
                size: _r(width * 0.086, 32, 38),
                color: const Color(0xFF8D6E63),
              ),
            ),
          ),
          SizedBox(height: _r(height * 0.017, 12, 16)),
          Text(
            'No places found',
            style: TextStyle(
              color: const Color(0xFF2E251F),
              fontSize: _r(width * 0.046, 17, 20),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: _r(height * 0.010, 7, 10)),
          Text(
            'There are no places to show right now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF81756C),
              fontSize: _r(width * 0.033, 12.5, 14),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
