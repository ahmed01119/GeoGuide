import 'dart:async';
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

import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:geoguide/services/firebase_nearby_cache_extension.dart';
import 'package:geoguide/services/nearby-service.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/place_repository.dart';
import 'package:geoguide/services/weather_service.dart';
import 'package:geoguide/presntation/widgets/place_weather_chip.dart';
part 'place-info_tabs.dart';
part 'place-info_nearby_booking.dart';
part 'place-info_shared_widgets.dart';

// ── Theme ────────────────────────────────────────────────────
const _kBrown = AppColors.chestnutBrown;
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

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched && !kIsWeb) {
        launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }

      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } else {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (!launched && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? 'Could not open the link.'),
          backgroundColor: _kBrownMed,
        ),
      );
    }
  } catch (e) {
    print('[PlaceInfo] launch failed: $uri error=$e');

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

Future<void> _launchUberRide(
  Landmark place, {
  BuildContext? context,
}) async {
  final destinationName =
      place.name.trim().isNotEmpty ? place.name : 'Destination';
  final destinationAddress = place.address.trim().isNotEmpty
      ? place.address
      : '${place.name} ${place.city} Egypt'.trim();

  final hasCoords = place.lat != 0 && place.lng != 0;

  final webUri = Uri.parse(
    hasCoords
        ? 'https://m.uber.com/ul/?action=setPickup'
            '&dropoff[latitude]=${place.lat}'
            '&dropoff[longitude]=${place.lng}'
            '&dropoff[nickname]=${Uri.encodeComponent(destinationName)}'
        : 'https://m.uber.com/ul/?action=setPickup'
            '&dropoff[formatted_address]=${Uri.encodeComponent(destinationAddress)}'
            '&dropoff[nickname]=${Uri.encodeComponent(destinationName)}',
  );

  // Use web Uber directly. This avoids ACTIVITY_NOT_FOUND when Uber app
  // is not installed on Android.
  await _launchSafely(
    webUri,
    context: context,
    errorMessage: 'Could not open Uber.',
  );
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

    String keyOf(String url) {
      final clean = url.trim();
      final lower = clean.toLowerCase();

      final unsplashMatch = RegExp(r'photo-[a-z0-9\-]+').firstMatch(lower);
      if (unsplashMatch != null) return 'unsplash:${unsplashMatch.group(0)}';

      final uri = Uri.tryParse(clean);
      if (uri == null) return lower;

      final pexelsMatch = RegExp(r'/(?:photos|photo)/(\d+)/?')
          .firstMatch(uri.path.toLowerCase());
      if (pexelsMatch != null) return 'pexels:${pexelsMatch.group(1)}';

      return uri.replace(query: '', fragment: '').toString().toLowerCase();
    }

    void add(String u) {
      final clean = u.trim();
      if (clean.isEmpty ||
          !clean.startsWith('http') ||
          AppInjector.images.isBadImageUrl(clean)) {
        return;
      }

      if (seen.add(keyOf(clean))) {
        urls.add(clean);
      }
    }

    add(_place.imageUrl);
    for (final u in _place.mediaUrls) add(u);

    // Do NOT add generic fallback photos here. If there are no real images,
    // The responsive header carousel will show the neutral placeholder.
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
            toolbarHeight: 72,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.chestnutBrown,
            surfaceTintColor: AppColors.chestnutBrown,
            elevation: 0,
            shadowColor: Colors.transparent,
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: AppColors.chestnutBrown,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: _kBg,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
              child: _GlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4, top: 8, bottom: 8),
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
                padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
                child: StreamBuilder<bool>(
                  stream: _repo.visitedStream(_place.id),
                  builder: (context, snap) {
                    final isVisited = snap.data ?? false;
                    return _GlassIconButton(
                      icon: isVisited
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline_rounded,
                      color: isVisited ? const Color(0xFF4CAF50) : Colors.white,
                      onTap: _toggleVisited,
                    );
                  },
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: LayoutBuilder(
                builder: (context, headerConstraints) {
                  final headerWidth = headerConstraints.maxWidth;
                  final cardHorizontalPadding = isTablet ? 32.0 : 20.0;
                  final cardRightSafeSpace = isTablet ? 132.0 : 112.0;
                  final maxCardWidth = headerWidth >= 900
                      ? 980.0
                      : headerWidth - cardHorizontalPadding - cardRightSafeSpace;
                  final cardWidth = maxCardWidth.clamp(260.0, headerWidth).toDouble();

                  return Stack(
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
                      _PlaceInfoHeaderCarousel(
                        urls: _gallery,
                        heroTag: 'place_info_${_place.id}',
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.50, 0.78, 1.0],
                                colors: [
                                  Colors.black.withOpacity(0.02),
                                  Colors.black.withOpacity(0.04),
                                  AppColors.chestnutBrown.withOpacity(0.18),
                                  AppColors.chestnutBrown.withOpacity(0.46),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: cardHorizontalPadding,
                        bottom: isTablet ? 28 : 22,
                        width: cardWidth,
                        child: IgnorePointer(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: EdgeInsets.all(isTablet ? 18 : 14),
                                decoration: BoxDecoration(
                                  color: AppColors.chestnutBrown.withOpacity(0.42),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.20),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.10),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (_place.category.isNotEmpty)
                                          _HeroPill(
                                            icon: Icons.category_rounded,
                                            label: _place.category.toUpperCase(),
                                          ),
                                        if (_place.city.isNotEmpty)
                                          _HeroPill(
                                            icon: Icons.location_on_rounded,
                                            label: _place.city,
                                          ),
                                        StreamBuilder<double>(
                                          stream:
                                              _repo.averageRatingStream(_place.id),
                                          builder: (ctx, snap) {
                                            final avg = snap.data ?? _place.rating;
                                            if (avg <= 0) {
                                              return const SizedBox.shrink();
                                            }
                                            return _HeroPill(
                                              icon: Icons.star_rounded,
                                              label: avg.toStringAsFixed(1),
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
                                      maxLines: isTablet ? 2 : 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isTablet ? 30 : 24,
                                        height: 1.15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (_place.shortDescription.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        _place.shortDescription,
                                        maxLines: isTablet ? 2 : 2,
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
                  );
                },
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
                        _buildStatusCard('Loading details from Wikipedia…'),
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
                                  isScrollable: false,
                                  indicator: BoxDecoration(
                                    color: _kBrown,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  indicatorPadding: const EdgeInsets.symmetric(
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
                                          Icon(Icons.place_rounded, size: 13),
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

  List<String> _effectiveMediaUrls(Landmark place) {
    final urls = <String>[];
    for (final u in place.mediaUrls) {
      final t = u.trim();
      if (t.isNotEmpty && !urls.contains(t)) urls.add(t);
    }
    final main = place.imageUrl.trim();
    if (main.isNotEmpty && !urls.contains(main)) urls.insert(0, main);
    return urls;
  }
}


class _PlaceInfoHeaderCarousel extends StatefulWidget {
  final List<String> urls;
  final String heroTag;

  const _PlaceInfoHeaderCarousel({
    required this.urls,
    required this.heroTag,
  });

  @override
  State<_PlaceInfoHeaderCarousel> createState() => _PlaceInfoHeaderCarouselState();
}

class _PlaceInfoHeaderCarouselState extends State<_PlaceInfoHeaderCarousel> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void didUpdateWidget(covariant _PlaceInfoHeaderCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.urls.length != oldWidget.urls.length && _index >= widget.urls.length) {
      _index = widget.urls.isEmpty ? 0 : widget.urls.length - 1;
      if (_controller.hasClients && widget.urls.isNotEmpty) {
        _controller.jumpToPage(_index);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    if (widget.urls.length <= 1) return;
    final target = next.clamp(0, widget.urls.length - 1).toInt();
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _openViewer() {
    if (widget.urls.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.88),
        pageBuilder: (_, __, ___) => _PlaceInfoImageViewer(
          urls: widget.urls,
          initialIndex: _index,
          heroTag: widget.heroTag,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return Container(
        color: AppColors.chestnutBrown,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 44,
          color: Colors.white.withOpacity(0.32),
        ),
      );
    }

    final showControls = widget.urls.length > 1;

    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: widget.heroTag,
          child: Material(
            color: Colors.transparent,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final url = widget.urls[index];
                    return GestureDetector(
                  onTap: _openViewer,
                  child: Image.network(
                    url,
                    key: ValueKey(
                      '${widget.heroTag}_$url',
                    ),
                    fit: BoxFit.cover,
                    headers: const {'User-Agent': 'GeoGuide-App'},
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.chestnutBrown,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 42,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (showControls) ...[
          Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _HeaderArrowButton(
                icon: Icons.chevron_left_rounded,
                enabled: _index > 0,
                onTap: () => _goTo(_index - 1),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _HeaderArrowButton(
                icon: Icons.chevron_right_rounded,
                enabled: _index < widget.urls.length - 1,
                onTap: () => _goTo(_index + 1),
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Text(
                '${_index + 1}/${widget.urls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlaceInfoImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String heroTag;

  const _PlaceInfoImageViewer({
    required this.urls,
    required this.initialIndex,
    required this.heroTag,
  });

  @override
  State<_PlaceInfoImageViewer> createState() => _PlaceInfoImageViewerState();
}

class _PlaceInfoImageViewerState extends State<_PlaceInfoImageViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1).toInt();
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    if (widget.urls.length <= 1) return;
    final target = next.clamp(0, widget.urls.length - 1).toInt();
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showControls = widget.urls.length > 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.96),
        body: SafeArea(
          child: Stack(
            children: [
              Hero(
                tag: widget.heroTag,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.urls.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) {
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          widget.urls[index],
                          fit: BoxFit.contain,
                          headers: const {'User-Agent': 'GeoGuide-App'},
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 54,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _HeaderArrowButton(
                  icon: Icons.close_rounded,
                  enabled: true,
                  onTap: () => Navigator.pop(context),
                ),
              ),
              if (showControls) ...[
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeaderArrowButton(
                      icon: Icons.chevron_left_rounded,
                      enabled: _index > 0,
                      onTap: () => _goTo(_index - 1),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeaderArrowButton(
                      icon: Icons.chevron_right_rounded,
                      enabled: _index < widget.urls.length - 1,
                      onTap: () => _goTo(_index + 1),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Text(
                        '${_index + 1}/${widget.urls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _HeaderArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.white.withOpacity(0.16),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Tabs moved to place-info_tabs.dart

// Nearby and booking blocks moved to place-info_nearby_booking.dart

// Shared helpers moved to place-info_shared_widgets.dart
