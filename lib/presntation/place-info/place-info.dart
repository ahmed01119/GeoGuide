// ============================================================
//  presntation/place-info/place-info.dart  (REBUILT LOGIC)
//
//  UI is preserved exactly.
//  Logic changes:
//  - Single stream from PlaceRepository (no competing sources)
//  - Enrichment calls go through repository (proper TTL, no re-fetch)
//  - Image gallery is stable (committed atomically)
//  - No unnecessary rebuilds
// ============================================================

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:ui';

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/place_repository.dart';
import 'package:geoguide/services/weather_service.dart';
import 'package:geoguide/presntation/widgets/place_weather_chip.dart';

// ── Theme ────────────────────────────────────────────────────
const _kBrown = Color(0xFF5C4033);
const _kBrownMed = Color(0xFF8D6E63);
const _kBrownLight = Color(0xFFF4ECE5);
const _kBg = Color(0xFFF7F1EB);
const _kCard = Color(0xFFF9F5F1);
const _kBorder = Color(0xFFEEE2D8);
const _kText = Color(0xFF2E251F);
const _kTextMid = Color(0xFF5E544D);
const _kTextLight = Color(0xFF8B817A);

// ── URL launcher ─────────────────────────────────────────────
Future<void> _launchSafely(
  Uri uri, {
  BuildContext? context,
  String? errorMessage,
}) async {
  try {
    bool launched = false;

    if (kIsWeb) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    }

    if (!launched && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? 'Could not open the link.'),
          backgroundColor: _kBrownMed,
        ),
      );
    }
  } catch (_) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? 'Could not open the link.'),
          backgroundColor: _kBrownMed,
        ),
      );
    }
  }
}

// ────────────────────────────────────────────────────────────────
//  PLACE INFO SCREEN
// ────────────────────────────────────────────────────────────────
class PlaceInfoScreen extends StatefulWidget {
  final Landmark place;

  const PlaceInfoScreen({
    super.key,
    required this.place,
  });

  @override
  State<PlaceInfoScreen> createState() => _PlaceInfoScreenState();
}

class _PlaceInfoScreenState extends State<PlaceInfoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final PlaceRepository _repo = AppInjector.repository;
  final FirebaseService _firebase = AppInjector.firebase;

  StreamSubscription<Landmark>? _sub;

  late Landmark _place;
  List<String> _gallery = [];

  // Loading state flags (for UI indicators only)
  bool _loadingWiki = false;
  bool _loadingImages = false;
  static final Set<String> _preloadedGalleryUrls = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Seed from widget (may be stale snapshot — that's OK)
    _place = _repo.get(widget.place.id) ?? widget.place;
    _buildGallery();

    // Subscribe to live updates from repository
    _subscribeToRepo();

    // Trigger background enrichment (TTL-gated inside repository)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerEnrichment();
    });
  }

  @override
  void didUpdateWidget(covariant PlaceInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.place.id != widget.place.id) {
      // Navigation to a different place
      _sub?.cancel();
      _place = _repo.get(widget.place.id) ?? widget.place;
      _buildGallery();
      _subscribeToRepo();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerEnrichment();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _subscribeToRepo() {
    _sub?.cancel();
    if (widget.place.id.trim().isEmpty) return;

    _sub = _repo.streamLandmark(widget.place.id).listen((updated) {
      if (!mounted) return;
      final oldGallery = _gallery.join('|');
      setState(() {
        _place = updated;
        _buildGallery();
      });
      final newGallery = _gallery.join('|');
      if (oldGallery != newGallery) _precacheGallery();
    });
  }

  void _buildGallery() {
    final seen = <String>{};
    final urls = <String>[];

    void add(String u) {
      final clean = u.trim();
      if (clean.isNotEmpty &&
          clean.startsWith('http') &&
          !AppInjector.images.isBadImageUrl(clean) &&
          seen.add(clean)) {
        urls.add(clean);
      }
    }

    add(_place.imageUrl);
    for (final u in _place.mediaUrls) add(u);

    // Do NOT add generic fallback photos here. If there are no real images,
    // _PremiumImageCarousel will show the neutral placeholder.
    _gallery = urls.take(6).toList();
  }

  Future<void> _precacheGallery() async {
    if (!mounted) return;

    for (final url in _gallery.take(2)) {
      if (AppInjector.images.isBadImageUrl(url)) continue;
      if (!_preloadedGalleryUrls.add(url)) continue;

      try {
        await precacheImage(
          NetworkImage(
            url,
            headers: const {'User-Agent': 'GeoGuide-App'},
          ),
          context,
        );
      } catch (_) {}
    }
  }

  /// Trigger enrichment — all TTL checks happen inside the repository.
  Future<void> _triggerEnrichment() async {
    if (!mounted) return;

    final id = widget.place.id;

    final shouldRefreshImages = _repo.needsImageRefresh(id);
    final shouldRefreshWiki = _repo.needsWikiRefresh(id);
    final shouldRefreshNearby = _repo.needsNearbyRefresh(id);

    if (shouldRefreshImages && _gallery.length < 3) {
      setState(() => _loadingImages = true);
    }
    if (shouldRefreshImages) {
      await _repo.enrichImages(_place);
    }
    if (mounted) setState(() => _loadingImages = false);

    if (!mounted) return;

    if (shouldRefreshWiki && _place.shortDescription.trim().length < 60) {
      setState(() => _loadingWiki = true);
    }
    if (shouldRefreshWiki) {
      await _repo.enrichWikipedia(_place);
    }
    if (mounted) setState(() => _loadingWiki = false);

    if (shouldRefreshNearby) {
      await _repo.enrichNearby(_place);
    }
  }

  Future<void> _toggleWishlist() async {
    try {
      await _repo.toggleFavorite(_place);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update wishlist')),
      );
    }
  }

  Future<void> _toggleVisited() async {
    try {
      await _repo.toggleVisited(_place);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update visited status')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final shortest = media.size.shortestSide;
    final isTablet = shortest >= 600;

    final expandedHeight =
        isTablet ? 430.0 : (screenHeight < 700 ? 320.0 : 360.0);
    final tabHeight = isTablet
        ? media.size.height * 0.74
        : (screenHeight < 700 ? screenHeight * 0.72 : screenHeight * 0.82);

    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: expandedHeight,
            pinned: true,
            stretch: true,
            backgroundColor: _kBrown,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: _GlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: StreamBuilder<bool>(
                  stream: _repo.favoriteStream(_place.id),
                  builder: (context, snap) {
                    final isFav = snap.data ?? false;
                    return _GlassIconButton(
                      icon: isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isFav ? Colors.redAccent : Colors.white,
                      onTap: _toggleWishlist,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: StreamBuilder<bool>(
                  stream: _repo.visitedStream(_place.id),
                  builder: (context, snap) {
                    final isVisited = snap.data ?? false;
                    return _GlassIconButton(
                      icon: isVisited
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline_rounded,
                      color:
                          isVisited ? const Color(0xFF4CAF50) : Colors.white,
                      onTap: _toggleVisited,
                    );
                  },
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _PremiumImageCarousel(
                    urls: _gallery,
                    heroTag: 'place_info_${_place.id}',
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.18),
                              Colors.black.withOpacity(0.04),
                              Colors.black.withOpacity(0.62),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: isTablet ? 120 : 86,
                    bottom: 16,
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: EdgeInsets.all(isTablet ? 18 : 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.20),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (_place.category.isNotEmpty)
                                      _HeroPill(
                                        icon: Icons.category_rounded,
                                        label:
                                            _place.category.toUpperCase(),
                                      ),
                                    if (_place.city.isNotEmpty)
                                      _HeroPill(
                                        icon: Icons.location_on_rounded,
                                        label: _place.city,
                                      ),
                                    StreamBuilder<double>(
                                      stream: _repo.averageRatingStream(
                                          _place.id),
                                      builder: (ctx, snap) {
                                        final avg =
                                            snap.data ?? _place.rating;
                                        if (avg <= 0) {
                                          return const SizedBox.shrink();
                                        }
                                        return _HeroPill(
                                          icon: Icons.star_rounded,
                                          label:
                                              avg.toStringAsFixed(1),
                                        );
                                      },
                                    ),
                                    if (_place.lat != 0 && _place.lng != 0)
                                      PlaceWeatherChip(
                                        lat: _place.lat,
                                        lng: _place.lng,
                                        textColor: Colors.white,
                                        backgroundColor:
                                            Colors.white.withOpacity(0.14),
                                        iconSize: 13,
                                        fontSize: 11.5,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _place.name,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isTablet ? 28 : 24,
                                    height: 1.15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (_place.shortDescription.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _place.shortDescription,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.92),
                                      fontSize: isTablet ? 14 : 13,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
                  color: _kBg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 24 : 16,
                    12,
                    isTablet ? 24 : 16,
                    40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_loadingWiki)
                        _buildStatusCard(
                          'Loading details from Wikipedia…'),
                      if (_loadingImages)
                        _buildStatusCard('Loading more images…'),
                      _buildOverviewCard(isTablet),
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
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
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _kBrownLight,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: TabBar(
                                  controller: _tabController,
                                  isScrollable: true,
                                  indicator: BoxDecoration(
                                    color: _kBrown,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  indicatorPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  labelColor: Colors.white,
                                  unselectedLabelColor: _kTextMid,
                                  dividerColor: Colors.transparent,
                                  labelStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                  unselectedLabelStyle: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  tabs: const [
                                    Tab(text: 'Details'),
                                    Tab(text: 'History'),
                                    Tab(text: 'Reviews'),
                                    Tab(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.place_rounded,
                                              size: 13),
                                          SizedBox(width: 4),
                                          Text('Nearby'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              height: tabHeight,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _DetailsTab(
                                    place: _place,
                                    firebase: _firebase,
                                    repo: _repo,
                                  ),
                                  _HistoryTab(
                                    place: _place,
                                    isLoading: _loadingWiki,
                                  ),
                                  _ReviewsTab(
                                    place: _place,
                                    repo: _repo,
                                  ),
                                  _NearbyTab(
                                    place: _place,
                                    firebase: _firebase,
                                  ),
                                ],
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildStatusCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _kBrownMed,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: _kTextMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(bool isTablet) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 20 : 18),
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
          const Text(
            'About this place',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _kText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _place.shortDescription.isNotEmpty
                ? _place.shortDescription
                : 'No description available yet.',
            style: TextStyle(
              fontSize: isTablet ? 15 : 14,
              height: 1.65,
              color: _kTextMid,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  DETAILS TAB
// ════════════════════════════════════════════════════════════════
class _DetailsTab extends StatelessWidget {
  final Landmark place;
  final FirebaseService firebase;
  final PlaceRepository repo;

  const _DetailsTab({
    required this.place,
    required this.firebase,
    required this.repo,
  });

  String get _locationLabel {
    if (place.name.trim().isNotEmpty && place.city.trim().isNotEmpty) {
      return '${place.name}, ${place.city}, Egypt';
    }
    if (place.address.trim().isNotEmpty) return place.address;
    if (place.city.trim().isNotEmpty) return '${place.city}, Egypt';
    return 'Egypt';
  }

  Future<void> _openMaps(BuildContext context) async {
    final Uri uri;
    if (place.lat != 0 && place.lng != 0) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lng}',
      );
    } else {
      final q = Uri.encodeComponent(_locationLabel);
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$q');
    }
    await _launchSafely(uri, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 18 : 14,
        14,
        isTablet ? 18 : 14,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(
              label: 'Location', icon: Icons.pin_drop_rounded),
          const SizedBox(height: 8),
          _LocationCard(
            label: _locationLabel,
            onTap: () => _openMaps(context),
          ),
          const SizedBox(height: 16),
          if (place.lat != 0 && place.lng != 0) ...[
            const _SectionLabel(
              label: 'Current Weather',
              icon: Icons.wb_sunny_rounded,
            ),
            const SizedBox(height: 8),
            FutureBuilder<WeatherInfo?>(
              future: WeatherService.instance.getCurrentWeather(
                lat: place.lat,
                lng: place.lng,
              ),
              builder: (context, snapshot) {
                final weather = snapshot.data;
                if (weather == null) {
                  return _InfoTile(
                    icon: Icons.cloud_off_rounded,
                    value: 'Weather data is currently unavailable.',
                    accentColor: _kBrownMed,
                  );
                }
                return _InfoTile(
                  icon: Icons.thermostat_rounded,
                  value:
                      '${weather.temperatureC.round()}°C - ${weather.description}',
                  accentColor: const Color(0xFF1565C0),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          if (place.openingHours.isNotEmpty) ...[
            const _SectionLabel(
                label: 'Opening Hours',
                icon: Icons.access_time_rounded),
            const SizedBox(height: 8),
            _InfoTile(
              icon: Icons.schedule_rounded,
              value: place.openingHours,
              accentColor: const Color(0xFF43A047),
            ),
            const SizedBox(height: 16),
          ],
          StreamBuilder<double>(
            stream: repo.averageRatingStream(place.id),
            builder: (context, snap) {
              final avg = snap.data ?? place.rating;
              if (avg <= 0) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel(
                      label: 'Visitor Rating',
                      icon: Icons.star_rounded),
                  const SizedBox(height: 8),
                  _RatingTile(rating: avg),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          if (place.ticketPrice != null &&
              place.ticketPrice!.isNotEmpty) ...[
            const _SectionLabel(
                label: 'Ticket Price',
                icon: Icons.local_activity_rounded),
            const SizedBox(height: 8),
            _InfoTile(
              icon: Icons.confirmation_number_rounded,
              value: place.ticketPrice!,
              accentColor: _kBrownMed,
            ),
            const SizedBox(height: 16),
          ],
          const _SectionLabel(
              label: 'Book & Reserve',
              icon: Icons.local_activity_rounded),
          const SizedBox(height: 12),
          _PremiumBookingSection(place: place),
          if ((place.wikipediaUrl ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionLabel(
                label: 'Wikipedia', icon: Icons.menu_book_rounded),
            const SizedBox(height: 8),
            _InfoTile(
              icon: Icons.open_in_new_rounded,
              value: 'Open article',
              accentColor: _kBrownMed,
              isLink: true,
              onTap: () => _launchSafely(
                  Uri.parse(place.wikipediaUrl!),
                  context: context),
            ),
          ],
          StreamBuilder<Map<String, String>>(
            stream: firebase.bookingLinksStream(place.id),
            builder: (context, snap) {
              final links = snap.data ?? {};
              if (links.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const _SectionLabel(
                      label: 'More Links',
                      icon: Icons.open_in_new_rounded),
                  const SizedBox(height: 8),
                  ...links.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InfoTile(
                        icon: Icons.link_rounded,
                        value: e.key,
                        accentColor: _kBrownMed,
                        isLink: true,
                        onTap: () => _launchSafely(
                            Uri.parse(e.value),
                            context: context),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  HISTORY TAB
// ════════════════════════════════════════════════════════════════
class _HistoryTab extends StatelessWidget {
  final Landmark place;
  final bool isLoading;

  const _HistoryTab({required this.place, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _kBrownMed),
            SizedBox(height: 12),
            Text(
              'Fetching Wikipedia information…',
              style: TextStyle(color: _kTextMid),
            ),
          ],
        ),
      );
    }

    final text =
        place.history.isNotEmpty ? place.history : place.fullDescription;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Text(
          text.isNotEmpty
              ? text
              : 'No historical information available yet.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.75,
            color: _kTextMid,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  REVIEWS TAB
// ════════════════════════════════════════════════════════════════
class _ReviewsTab extends StatefulWidget {
  final Landmark place;
  final PlaceRepository repo;

  const _ReviewsTab({required this.place, required this.repo});

  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  final _ctrl = TextEditingController();
  double _rating = 4;
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.repo.addReview(
        placeId: widget.place.id,
        rating: _rating,
        comment: _ctrl.text.trim(),
      );
      _ctrl.clear();
      if (mounted) setState(() => _rating = 4);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete(String uid) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Review'),
            content: const Text('Delete your review?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (ok) {
      await widget.repo.deleteReview(
          placeId: widget.place.id, userId: uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AppInjector.firebase.currentUserId;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          padding: EdgeInsets.all(isTablet ? 16 : 14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Leave a review',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                children: List.generate(
                  5,
                  (i) => IconButton(
                    onPressed: () =>
                        setState(() => _rating = (i + 1).toDouble()),
                    icon: Icon(
                      i + 1 <= _rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: _ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Write your comment…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrown,
                    foregroundColor: Colors.white,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: widget.repo.reviewsStream(widget.place.id),
            builder: (context, snap) {
              final reviews = snap.data ?? [];
              if (reviews.isEmpty) {
                return const Center(
                  child: Text('No reviews yet.',
                      style: TextStyle(color: _kTextLight)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                itemCount: reviews.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final r = reviews[i];
                  final rating = (r['rating'] ?? 0).toDouble();
                  final comment = r['comment']?.toString() ?? '';
                  final uName = r['userName']?.toString() ?? 'User';
                  final uid = r['userId']?.toString() ?? '';
                  final isMe = me != null && uid == me;

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                uName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _kText,
                                ),
                              ),
                            ),
                            if (isMe)
                              GestureDetector(
                                onTap: () => _delete(uid),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.red.withOpacity(0.08),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          children: List.generate(
                            5,
                            (j) => Icon(
                              j < rating.round()
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: Colors.amber,
                              size: 18,
                            ),
                          ),
                        ),
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            comment,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: _kTextMid,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  NEARBY TAB  (same as before but uses FirebaseService directly)
// ════════════════════════════════════════════════════════════════
// [Keeping the existing _NearbyTab implementation from the original file
//  since it already uses Overpass + Firebase and the logic is stable.
//  The key improvement is that enrichNearby() is called from the repo
//  at the PlaceInfoScreen level with TTL-gating.]

enum _NearbyFilter { all, attractions, hotels, dining }

class _NearbyItem {
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final double rating;
  final bool isLive;

  const _NearbyItem({
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.rating,
    this.isLive = false,
  });
}

class _NearbyTab extends StatefulWidget {
  final Landmark place;
  final FirebaseService firebase;

  const _NearbyTab({required this.place, required this.firebase});

  @override
  State<_NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<_NearbyTab> {
  _NearbyFilter _filter = _NearbyFilter.all;
  List<_NearbyItem> _items = [];
  bool _loading = true;

  double get _lat => widget.place.lat;
  double get _lng => widget.place.lng;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // First: load from nearbyPlaces cached in landmark
    _loadFromLandmark();
    // Then: load from Firebase for same-city places
    await _loadFromFirebase();
    // Finally: fetch live from Overpass if coords available
    if (_lat != 0 && _lng != 0) _fetchLive();
  }

  void _loadFromLandmark() {
    final cached = widget.place.nearbyPlaces;
    if (cached.isEmpty) return;

    final items = <_NearbyItem>[];
    for (final item in cached) {
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      items.add(_NearbyItem(
        name: name,
        category: _mapCat((item['category'] ?? 'tourist').toString()),
        address: (item['address'] ?? widget.place.city).toString(),
        lat: ((item['lat'] ?? 0) as num).toDouble(),
        lng: ((item['lng'] ?? 0) as num).toDouble(),
        rating: ((item['rating'] ?? 0) as num).toDouble(),
      ));
    }

    if (mounted && items.isNotEmpty) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _loadFromFirebase() async {
    try {
      final snapshot = await widget.firebase
          .nearbySuggestionsStream(
            city: widget.place.city,
            excludePlaceId: widget.place.id,
            sourceLat: _lat,
            sourceLng: _lng,
          )
          .first
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      final items = snapshot
          .map((lm) => _NearbyItem(
                name: lm.name,
                category: _mapCat(lm.category),
                address: lm.address.isNotEmpty ? lm.address : lm.city,
                lat: lm.lat,
                lng: lm.lng,
                rating: lm.rating,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchLive() async {
    if (_lat == 0 || _lng == 0) return;

    try {
      final query = '''
[out:json][timeout:25];
(
  node["amenity"~"restaurant|cafe|fast_food"](around:2500,$_lat,$_lng);
  node["tourism"~"hotel|guest_house|hostel|motel"](around:3000,$_lat,$_lng);
  node["tourism"~"attraction|museum|viewpoint|gallery"](around:3500,$_lat,$_lng);
  node["historic"](around:3500,$_lat,$_lng);
);
out center tags;
''';

      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      ).timeout(const Duration(seconds: 28));

      if (response.statusCode != 200) return;

      final data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      final seen = <String>{};
      final liveItems = <_NearbyItem>[];

      for (final el in elements) {
        final tags =
            (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
        final name = (tags['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final itemLat =
            ((el['lat'] ?? el['center']?['lat'] ?? 0) as num)
                .toDouble();
        final itemLng =
            ((el['lon'] ?? el['center']?['lon'] ?? 0) as num)
                .toDouble();
        if (itemLat == 0 || itemLng == 0) continue;

        final amenity =
            (tags['amenity'] ?? '').toString().toLowerCase();
        final tourism =
            (tags['tourism'] ?? '').toString().toLowerCase();
        final historic =
            (tags['historic'] ?? '').toString().toLowerCase();

        String category = 'tourist';
        if (amenity == 'restaurant' || amenity == 'fast_food') {
          category = 'restaurant';
        } else if (amenity == 'cafe') {
          category = 'cafe';
        } else if (tourism == 'hotel' ||
            tourism == 'guest_house' ||
            tourism == 'hostel' ||
            tourism == 'motel') {
          category = 'hotel';
        } else if (tourism.isNotEmpty || historic.isNotEmpty) {
          category = 'tourist';
        }

        final addr = _composeAddress(tags);
        final key = '${name.toLowerCase()}|$category';
        if (!seen.add(key)) continue;

        liveItems.add(_NearbyItem(
          name: name,
          category: category,
          address: addr,
          lat: itemLat,
          lng: itemLng,
          rating: 0,
          isLive: true,
        ));
      }

      if (!mounted) return;

      final existingKeys = _items.map((e) => e.name.toLowerCase()).toSet();
      final newLive = liveItems
          .where((e) => !existingKeys.contains(e.name.toLowerCase()))
          .toList();

      final merged = [..._items, ...newLive];
      merged.sort((a, b) {
        final da = _dist(a.lat, a.lng);
        final db = _dist(b.lat, b.lng);
        return da.compareTo(db);
      });

      setState(() => _items = merged.take(80).toList());
    } catch (_) {}
  }

  String _composeAddress(Map<String, dynamic> tags) {
    final parts = [
      (tags['addr:street'] ?? '').toString().trim(),
      (tags['addr:city'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(', ') : widget.place.city;
  }

  String _mapCat(String raw) {
    final cat = raw.toLowerCase();
    if (cat.contains('hotel') || cat.contains('resort')) return 'hotel';
    if (cat.contains('restaurant') || cat.contains('food')) {
      return 'restaurant';
    }
    if (cat.contains('cafe') || cat.contains('coffee')) return 'cafe';
    if (cat.contains('park') || cat.contains('outing')) return 'outing';
    return 'tourist';
  }

  double _dist(double lat, double lng) {
    if (_lat == 0 || _lng == 0 || lat == 0 || lng == 0) return 9999;
    return (lat - _lat).abs() + (lng - _lng).abs();
  }

  List<_NearbyItem> get _filtered {
    switch (_filter) {
      case _NearbyFilter.hotels:
        return _items.where((e) => e.category == 'hotel').toList();
      case _NearbyFilter.dining:
        return _items
            .where((e) =>
                e.category == 'restaurant' || e.category == 'cafe')
            .toList();
      case _NearbyFilter.attractions:
        return _items
            .where((e) =>
                e.category == 'tourist' || e.category == 'outing')
            .toList();
      case _NearbyFilter.all:
        return _items;
    }
  }

  Color _catColor(String cat) {
    switch (cat) {
      case 'hotel':
        return const Color(0xFF5C6BC0);
      case 'restaurant':
        return const Color(0xFFEF6C00);
      case 'cafe':
        return const Color(0xFF795548);
      case 'outing':
        return const Color(0xFF2E7D32);
      default:
        return _kBrownMed;
    }
  }

  Color _catBg(String cat) {
    switch (cat) {
      case 'hotel':
        return const Color(0xFFEDE7F6);
      case 'restaurant':
        return const Color(0xFFFFF3E0);
      case 'cafe':
        return const Color(0xFFEFEBE9);
      case 'outing':
        return const Color(0xFFE8F5E9);
      default:
        return _kBrownLight;
    }
  }

  IconData _catIcon(String cat) {
    switch (cat) {
      case 'hotel':
        return Icons.hotel_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'cafe':
        return Icons.local_cafe_rounded;
      case 'outing':
        return Icons.park_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  String _catLabel(_NearbyItem item) {
    switch (item.category) {
      case 'hotel':
        return 'HOTEL';
      case 'restaurant':
        return 'RESTAURANT';
      case 'cafe':
        return 'CAFE';
      case 'outing':
        return 'OUTING';
      default:
        return 'ATTRACTION';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      (_NearbyFilter.all, 'All', Icons.grid_view_rounded),
      (_NearbyFilter.attractions, 'Attractions', Icons.photo_camera_rounded),
      (_NearbyFilter.hotels, 'Hotels', Icons.hotel_rounded),
      (_NearbyFilter.dining, 'Dining', Icons.restaurant_rounded),
    ];

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: chips.map((c) {
              final selected = _filter == c.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? _kBrown : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: selected ? _kBrown : _kBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.$3,
                            size: 15,
                            color: selected ? Colors.white : _kTextMid),
                        const SizedBox(width: 6),
                        Text(
                          c.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : _kTextMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _kBrownMed))
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: _kBrownLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.place_rounded,
                                size: 34, color: _kBrownMed),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No nearby places found',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: _kTextMid,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(14, 0, 14, 18),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, idx) {
                        final item = _filtered[idx];
                        return _NearbyItemTile(
                          item: item,
                          catColor: _catColor(item.category),
                          catBg: _catBg(item.category),
                          catIcon: _catIcon(item.category),
                          catLabel: _catLabel(item),
                          placeCity: widget.place.city,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _NearbyItemTile extends StatelessWidget {
  final _NearbyItem item;
  final Color catColor;
  final Color catBg;
  final IconData catIcon;
  final String catLabel;
  final String placeCity;

  const _NearbyItemTile({
    required this.item,
    required this.catColor,
    required this.catBg,
    required this.catIcon,
    required this.catLabel,
    required this.placeCity,
  });

  Future<void> _openMaps(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}',
    );
    await _launchSafely(uri, context: context);
  }

  Future<void> _book(BuildContext context) async {
    final q = Uri.encodeComponent('${item.name} $placeCity Egypt');
    final Uri uri;
    if (item.category == 'hotel') {
      uri = Uri.parse(
        'https://www.booking.com/searchresults.html?ss=${Uri.encodeComponent(item.name)}',
      );
    } else if (item.category == 'restaurant' ||
        item.category == 'cafe') {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}',
      );
    } else {
      uri = Uri.parse(
          'https://www.viator.com/searchResults/all?text=$q');
    }
    await _launchSafely(uri, context: context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: catBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(catIcon, color: catColor, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: _kText,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: catBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              catLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: catColor,
                              ),
                            ),
                          ),
                          if (item.isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          if (item.rating > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 13, color: Colors.amber),
                                const SizedBox(width: 2),
                                Text(
                                  item.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _kTextMid,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (item.address.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: _kTextLight),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                item.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: _kTextLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _kBorder))),
            child: Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.directions_rounded,
                    label: 'Directions',
                    color: const Color(0xFF2E7D32),
                    bg: const Color(0xFFE8F5E9),
                    onTap: () => _openMaps(context),
                    isLeft: true,
                  ),
                ),
                Container(width: 1, height: 46, color: _kBorder),
                Expanded(
                  child: _ActionBtn(
                    icon: item.category == 'hotel'
                        ? Icons.bed_rounded
                        : item.category == 'restaurant' ||
                                item.category == 'cafe'
                            ? Icons.directions_rounded
                            : Icons.confirmation_number_rounded,
                    label: item.category == 'hotel'
                        ? 'Book Room'
                        : item.category == 'restaurant' ||
                                item.category == 'cafe'
                            ? 'Directions'
                            : 'Book Tour',
                    color: _kBrown,
                    bg: _kBrownLight,
                    onTap: () => _book(context),
                    isLeft: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;
  final bool isLeft;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    final radius = isLeft
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(20))
        : const BorderRadius.only(
            bottomRight: Radius.circular(20));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  BOOKING SECTION (unchanged from original)
// ════════════════════════════════════════════════════════════════
class _PremiumBookingSection extends StatelessWidget {
  final Landmark place;
  const _PremiumBookingSection({required this.place});

  String get _encodedName => Uri.encodeComponent(place.name);
  String get _encodedCity =>
      Uri.encodeComponent(place.city.isNotEmpty ? place.city : 'Egypt');
  String get _encodedQuery =>
      Uri.encodeComponent('${place.name} ${place.city} Egypt');

  bool get _isHotel {
    final cat = place.category.toLowerCase();
    return cat.contains('hotel') || cat.contains('resort');
  }

  bool get _isDining {
    final cat = place.category.toLowerCase();
    return cat.contains('restaurant') || cat.contains('cafe');
  }

  @override
  Widget build(BuildContext context) {
    if (_isHotel) return _buildHotelBooking(context);
    if (_isDining) return _buildDiningBooking(context);
    return _buildAttractionBooking(context);
  }

  Widget _buildHotelBooking(BuildContext context) {
    return Column(
      children: [
        _BookingProviderCard(
          providerName: 'Booking.com',
          tagline: 'Best price guarantee · Free cancellation',
          badge: 'POPULAR',
          badgeColor: const Color(0xFF1565C0),
          icon: Icons.hotel_rounded,
          iconBg: const Color(0xFFE3F2FD),
          iconColor: const Color(0xFF1565C0),
          priceHint: 'From \$45/night',
          features: const [
            'Free cancellation',
            'No prepayment needed',
            'Instant confirmation',
          ],
          onTap: () => _launchSafely(
            Uri.parse(
                'https://www.booking.com/searchresults.html?ss=$_encodedName'),
            context: context,
          ),
        ),
        const SizedBox(height: 10),
        _BookingProviderCard(
          providerName: 'Agoda',
          tagline: 'Exclusive deals for Egypt hotels',
          badge: 'DEALS',
          badgeColor: const Color(0xFFE65100),
          icon: Icons.local_offer_rounded,
          iconBg: const Color(0xFFFFF3E0),
          iconColor: const Color(0xFFE65100),
          priceHint: 'Special discounts',
          features: const [
            'Secret deals',
            'Last minute offers',
            'Member prices',
          ],
          onTap: () => _launchSafely(
            Uri.parse(
                'https://www.agoda.com/search?q=$_encodedQuery'),
            context: context,
          ),
        ),
      ],
    );
  }

  Widget _buildDiningBooking(BuildContext context) {
    return Column(
      children: [
        _BookingProviderCard(
          providerName: 'Google Maps',
          tagline: 'Get directions & view reviews',
          badge: 'DIRECTIONS',
          badgeColor: const Color(0xFF1565C0),
          icon: Icons.directions_rounded,
          iconBg: const Color(0xFFE3F2FD),
          iconColor: const Color(0xFF1565C0),
          priceHint: 'Free navigation',
          features: const [
            'Turn-by-turn directions',
            'View photos',
            'Read reviews',
          ],
          onTap: () {
            final Uri uri = place.lat != 0 && place.lng != 0
                ? Uri.parse(
                    'https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lng}')
                : Uri.parse(
                    'https://www.google.com/maps/search/?api=1&query=$_encodedQuery');
            _launchSafely(uri, context: context);
          },
        ),
        const SizedBox(height: 10),
        _BookingProviderCard(
          providerName: 'TripAdvisor',
          tagline: 'Read reviews from real travelers',
          badge: 'REVIEWS',
          badgeColor: const Color(0xFF2E7D32),
          icon: Icons.rate_review_rounded,
          iconBg: const Color(0xFFE8F5E9),
          iconColor: const Color(0xFF2E7D32),
          priceHint: 'See all reviews',
          features: const ['Traveler reviews', 'Photos', 'Menu info'],
          onTap: () => _launchSafely(
            Uri.parse(
                'https://www.tripadvisor.com/Search?q=$_encodedQuery'),
            context: context,
          ),
        ),
      ],
    );
  }

  Widget _buildAttractionBooking(BuildContext context) {
    return Column(
      children: [
        _BookingProviderCard(
          providerName: 'Viator',
          tagline: 'Skip-the-line tickets & guided tours',
          badge: 'POPULAR',
          badgeColor: const Color(0xFF2E7D32),
          icon: Icons.confirmation_number_outlined,
          iconBg: const Color(0xFFE8F5E9),
          iconColor: const Color(0xFF2E7D32),
          priceHint: 'From \$15',
          features: const [
            'Skip the line',
            'Expert guides',
            'Free cancellation',
          ],
          onTap: () => _launchSafely(
            Uri.parse(
                'https://www.viator.com/searchResults/all?text=$_encodedName+$_encodedCity'),
            context: context,
          ),
        ),
        const SizedBox(height: 10),
        _BookingProviderCard(
          providerName: 'GetYourGuide',
          tagline: 'Instant booking · Best experiences',
          badge: 'INSTANT',
          badgeColor: const Color(0xFFE65100),
          icon: Icons.tour_outlined,
          iconBg: const Color(0xFFFFF3E0),
          iconColor: const Color(0xFFE65100),
          priceHint: 'Compare tours',
          features: const [
            'Instant confirmation',
            'Mobile ticket',
            'Best guides',
          ],
          onTap: () => _launchSafely(
            Uri.parse(
                'https://www.getyourguide.com/s/?q=$_encodedName'),
            context: context,
          ),
        ),
      ],
    );
  }
}

class _BookingProviderCard extends StatelessWidget {
  final String providerName;
  final String tagline;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String priceHint;
  final List<String> features;
  final VoidCallback onTap;

  const _BookingProviderCard({
    required this.providerName,
    required this.tagline,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.priceHint,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              providerName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _kText,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: badgeColor.withOpacity(0.25)),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tagline,
                          style: const TextStyle(
                              fontSize: 12.5, color: _kTextLight),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: features
                    .map((f) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F4EF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  size: 11, color: _kBrownMed),
                              const SizedBox(width: 4),
                              Text(f,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: _kTextMid,
                                  )),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _kBrown,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Book Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.white, size: 12),
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

// ════════════════════════════════════════════════════════════════
//  SHARED UI HELPERS (all unchanged from original)
// ════════════════════════════════════════════════════════════════

class _PremiumImageCarousel extends StatefulWidget {
  final List<String> urls;
  final String heroTag;

  const _PremiumImageCarousel(
      {required this.urls, required this.heroTag});

  @override
  State<_PremiumImageCarousel> createState() =>
      _PremiumImageCarouselState();
}

class _PremiumImageCarouselState extends State<_PremiumImageCarousel> {
  late final PageController _pc;
  int _cur = 0;

  List<String> get _valid {
    final seen = <String>{};
    return widget.urls
        .map((u) => u.trim())
        .where((u) =>
            u.isNotEmpty &&
            u.startsWith('http') &&
            !AppInjector.images.isBadImageUrl(u) &&
            seen.add(u))
        .take(6)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _pc = PageController();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _openFullscreen(int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _FullscreenGallery(
          urls: _valid,
          initialIndex: initialIndex,
          heroTag: widget.heroTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_valid.isEmpty) return const _PlaceholderImage();

    return Stack(
      children: [
        PageView.builder(
          controller: _pc,
          itemCount: _valid.length,
          onPageChanged: (i) => setState(() => _cur = i),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _openFullscreen(i),
            child: Hero(
              tag: '${widget.heroTag}_img_$i',
              child: _NetImage(url: _valid[i]),
            ),
          ),
        ),
        if (_cur > 0)
          Positioned(
            left: 10,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrow(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => _pc.previousPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut),
              ),
            ),
          ),
        if (_cur < _valid.length - 1)
          Positioned(
            right: 10,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrow(
                icon: Icons.arrow_forward_ios_rounded,
                onTap: () => _pc.nextPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut),
              ),
            ),
          ),
        Positioned(
          right: 14,
          bottom: 28,
          child: GestureDetector(
            onTap: () => _openFullscreen(_cur),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.20)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        '${_cur + 1} / ${_valid.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_valid.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _valid.length.clamp(0, 7),
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _cur == i ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color:
                        _cur == i ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String heroTag;

  const _FullscreenGallery({
    required this.urls,
    required this.initialIndex,
    required this.heroTag,
  });

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _pc;
  late int _cur;

  @override
  void initState() {
    super.initState();
    _cur = widget.initialIndex;
    _pc = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _cur = i),
            itemBuilder: (_, i) => Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Hero(
                  tag: '${widget.heroTag}_img_$i',
                  child: _NetImage(
                      url: widget.urls[i], fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 28),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_cur + 1} of ${widget.urls.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.urls.length.clamp(0, 7),
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _cur == i ? 20 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _cur == i ? Colors.white : Colors.white54,
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

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _GlassIconButton(
      {required this.icon, required this.onTap, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CarouselArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.28),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child:
            SizedBox(width: 38, height: 38, child: Icon(icon, color: Colors.white, size: 18)),
      ),
    );
  }
}

class _NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const _NetImage({required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final clean = url.trim();
    if (clean.isEmpty || AppInjector.images.isBadImageUrl(clean)) {
      return const _PlaceholderImage();
    }

    return Image.network(
      clean,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      headers: const {'User-Agent': 'GeoGuide-App'},
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _PlaceholderImage();
      },
      errorBuilder: (_, __, ___) => const _PlaceholderImage(),
    );
  }
}


class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFE6DF),
      child: const Center(
        child: Icon(Icons.image_outlined, color: _kBrownMed, size: 42),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _kBrownMed),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF6A5344),
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LocationCard({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kCard,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: _kBrownMed),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: _kTextMid,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.open_in_new_rounded,
                  color: _kBrownMed, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color accentColor;
  final bool isLink;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.icon,
    required this.value,
    required this.accentColor,
    this.isLink = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                color: _kTextMid,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
          if (isLink)
            const Icon(Icons.open_in_new_rounded,
                color: _kBrownMed, size: 18),
        ],
      ),
    );

    if (!isLink || onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}

class _RatingTile extends StatelessWidget {
  final double rating;
  const _RatingTile({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
          const SizedBox(width: 10),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _kText,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 2,
              children: List.generate(
                5,
                (i) => Icon(
                  i < rating.round()
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: Colors.amber,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 