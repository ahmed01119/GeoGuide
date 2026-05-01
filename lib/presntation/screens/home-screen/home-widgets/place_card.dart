import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/place-info/place-info.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/place_repository.dart';
import 'package:geoguide/presntation/widgets/place_weather_chip.dart';

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

  String get _imageUrl {
    final source = _cache.get(widget.place.id) ?? widget.place;

    final urls = <String>[];
    final seen = <String>{};

    void add(String url) {
      final clean = url.trim();
      if (_validDisplayImage(clean) && seen.add(clean)) {
        urls.add(clean);
      }
    }

    add(source.imageUrl);
    for (final u in source.mediaUrls) add(u);

    add(widget.place.imageUrl);
    for (final u in widget.place.mediaUrls) add(u);

    if (urls.isNotEmpty) return urls.first;

    // No real image is safer than showing a wrong generic photo.
    return '';
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

    // Preload one safe image only. This avoids repeated API/rate-limit pressure.
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

  Future<void> _openPlace(BuildContext context) async {
    Landmark latest = _cache.get(widget.place.id) ?? widget.place;

    if (!_cache.has(widget.place.id)) {
      _cache.put(widget.place);
    }

    if (_cache.getFresh(widget.place.id) == null) {
      AppInjector.firebase
          .getLandmarkById(widget.place.id)
          .then((fresh) {
        if (fresh != null) _cache.merge(fresh);
      }).catchError((_) {});
    }

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

  // Smart image widget: only displays safe real URLs from Firestore/API.
  Widget _buildImage() {
    final url = _imageUrl.trim();

    if (url.isEmpty) {
      return Container(
        color: Colors.grey.shade300,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      );
    }

    return Image.network(
      url,
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: () => _openPlace(context),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
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
                    tag: widget.place.id,
                    child: _buildImage(), // 🔥 هنا التعديل
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
                    stream: _repo.favoriteStream(widget.place.id),
                    builder: (context, snapshot) {
                      final isFav = snapshot.data ?? false;
                      return GestureDetector(
                        onTap: () async {
                          await _repo.toggleFavorite(widget.place);
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

                if (widget.place.rating > 0)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star,
                              color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            widget.place.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
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
                        widget.place.name,
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
                        widget.place.address.isNotEmpty
                            ? widget.place.address
                            : widget.place.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      PlaceWeatherChip(
                        lat: widget.place.lat,
                        lng: widget.place.lng,
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
        ),
      ),
    );
  }
}