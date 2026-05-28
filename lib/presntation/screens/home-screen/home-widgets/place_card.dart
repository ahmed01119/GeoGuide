import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/place-info/place-info.dart';
import 'package:geoguide/presntation/widgets/place_weather_chip.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/place_repository.dart';

class PlaceCard extends StatefulWidget {
  final Landmark place;

  const PlaceCard({super.key, required this.place});

  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> {
  static final Set<String> _preloadedUrls = {};

  double _scale = 1.0;

  final PlaceRepository _repo = AppInjector.repository;
  final LandmarkCache _cache = LandmarkCache.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Future.microtask(() {
      if (mounted) _precacheImages(context, widget.place);
    });
  }

  bool _validDisplayImage(String url) {
    final clean = url.trim();
    return clean.startsWith('http') && !AppInjector.images.isBadImageUrl(clean);
  }

  String _firstValidImageUrl(Landmark place) {
    // IMPORTANT:
    // The [place] argument is the live Firestore value emitted by
    // PlaceRepository.streamLandmark(id). Do not let an older cache entry win
    // over it, otherwise admin image edits/refreshes can be saved correctly but
    // the card keeps rendering the old image until a full app restart.
    final cached = _cache.get(place.id);

    final urls = <String>[];
    final seen = <String>{};

    void add(String url) {
      final clean = url.trim();
      if (_validDisplayImage(clean) && seen.add(clean)) {
        urls.add(clean);
      }
    }

    // Live Firestore/admin-edited images must win.
    add(place.imageUrl);
    for (final u in place.mediaUrls) add(u);

    // Cache is only a fallback for older cards that have not received a stream
    // snapshot yet.
    if (cached != null && cached.id == place.id) {
      add(cached.imageUrl);
      for (final u in cached.mediaUrls) add(u);
    }

    return urls.isNotEmpty ? urls.first : '';
  }

  Future<void> _precacheImages(BuildContext context, Landmark place) async {
    final urls = <String>[];
    final seen = <String>{};

    void add(String url) {
      final clean = url.trim();
      if (_validDisplayImage(clean) && seen.add(clean)) {
        urls.add(clean);
      }
    }

    add(place.imageUrl);
    for (final u in place.mediaUrls) add(u);

    for (final url in urls.take(1)) {
      if (!_preloadedUrls.add(url)) continue;
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

  Future<void> _openPlace(BuildContext context, Landmark place) async {
    final id = place.id;
    if (id.trim().isNotEmpty && !_cache.has(id)) {
      _cache.put(place);
    }

    if (id.trim().isNotEmpty && _cache.getFresh(id) == null) {
      AppInjector.firebase
          .getLandmarkById(id)
          .then((fresh) {
        if (fresh != null) _cache.merge(fresh);
      })
          .catchError((_) {});
    }

    // Prefer the live card value over cache when opening details. The cache may
    // still contain an older imageUrl/mediaUrls entry.
    final latest = place;
    if (!context.mounted) return;

    await _precacheImages(context, latest);
    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceInfoScreen(place: latest),
      ),
    );
  }

  Widget _buildCardImage(Landmark place) {
    final url = _firstValidImageUrl(place).trim();

    if (url.isEmpty) {
      return Container(
        color: Colors.grey.shade300,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      );
    }

    final imagesRefreshedAt = place.imagesRefreshedAt;
    final mediaCount = place.mediaUrls.length;

    // Cache-bust the widget when Firestore updates imageUrl/mediaUrls.
    // This forces Image.network to rebuild/recreate its internal pipeline.
    return Image.network(
      url,
      key: ValueKey(
        '${place.id}_${place.imageUrl}_${imagesRefreshedAt}_$mediaCount',
      ),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      headers: const {'User-Agent': 'GeoGuide-App'},
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade300,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      ),
    );
  }

  Widget _buildCardContent(Landmark place) {
    // Keep the original layout/colors; only bind to the live [place] values.
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: Hero(
                tag: place.id.trim(),
                child: _buildCardImage(place),
              ),
            ),

            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              top: 10,
              left: 10,
              child: StreamBuilder<bool>(
                stream: _repo.favoriteStream(place.id),
                builder: (context, snapshot) {
                  final isFav = snapshot.data ?? false;
                  return GestureDetector(
                    onTap: () async {
                      await _repo.toggleFavorite(place);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.red : Colors.white,
                        size: 18,
                      ),
                    ),
                  );
                },
              ),
            ),

            if (place.rating > 0)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        place.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    place.address.isNotEmpty ? place.address : place.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  PlaceWeatherChip(
                    lat: place.lat,
                    lng: place.lng,
                    textColor: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.14),
                    iconSize: 13,
                    fontSize: 11,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.place.id.trim();

    if (id.isEmpty) {
      return GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.96),
        onTapUp: (_) => setState(() => _scale = 1),
        onTapCancel: () => setState(() => _scale = 1),
        onTap: () => _openPlace(context, widget.place),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: _buildCardContent(widget.place),
        ),
      );
    }

    return StreamBuilder<Landmark>(
      stream: _repo.streamLandmark(id),
      builder: (context, snapshot) {
        final place = snapshot.data ?? widget.place;

        return GestureDetector(

          onTapDown: (_) => setState(() => _scale = 0.96),
          onTapUp: (_) => setState(() => _scale = 1),
          onTapCancel: () => setState(() => _scale = 1),
          onTap: () => _openPlace(context, place),
          child: AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: _buildCardContent(place),
          ),
        );
      },
    );
  }
}

