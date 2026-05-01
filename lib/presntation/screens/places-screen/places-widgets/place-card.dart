import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/place-info/place-info.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/place_repository.dart';

class PlaceCard extends StatefulWidget {
  final Landmark place;

  const PlaceCard({super.key, required this.place});

  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> {
  double _scale = 1.0;

  final PlaceRepository _repo = AppInjector.repository;
  final LandmarkCache _cache = LandmarkCache.instance;

  /// Returns the freshest available image — prefers cache (may have been
  /// enriched since the list was built), falls back to widget snapshot.
  String get _imageUrl {
    final source = _cache.get(widget.place.id) ?? widget.place;

    if (source.imageUrl.trim().isNotEmpty &&
        source.imageUrl.trim().startsWith('http')) {
      return source.imageUrl.trim();
    }

    final list = source.mediaUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && u.startsWith('http'))
        .toList();

    if (list.isNotEmpty) return list.first;

    // hard fallback to widget data
    if (widget.place.imageUrl.trim().isNotEmpty) {
      return widget.place.imageUrl.trim();
    }
    final fb = widget.place.mediaUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && u.startsWith('http'))
        .toList();
    return fb.isNotEmpty ? fb.first : '';
  }

  Future<void> _precacheImages(BuildContext context, Landmark place) async {
    final urls = <String>[];
    final seen = <String>{};

    void add(String url) {
      final clean = url.trim();
      if (clean.isNotEmpty && clean.startsWith('http') && seen.add(clean)) {
        urls.add(clean);
      }
    }

    add(place.imageUrl);
    for (final u in place.mediaUrls) add(u);

    for (final url in urls.take(3)) {
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {}
    }
  }

  Future<void> _openPlace(BuildContext context) async {
    // Use the freshest available data from cache
    Landmark latest = _cache.get(widget.place.id) ?? widget.place;

    // Seed cache if missing
    if (!_cache.has(widget.place.id)) {
      _cache.put(widget.place);
    }

    // Kick off a background fetch if cache is stale (non-blocking)
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
                // Image
                Positioned.fill(
                  child: Hero(
                    tag: widget.place.id,
                    child: _imageUrl.isEmpty
                        ? Container(
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.image_not_supported),
                          )
                        : Image.network(
                            _imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.image_not_supported,
                                  color: Colors.grey),
                            ),
                          ),
                  ),
                ),

                // Overlay gradient
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

                // Favorite icon (live stream from repository)
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

                // Rating badge
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
                          const Icon(Icons.star, color: Colors.amber, size: 14),
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

                // Place name and address
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