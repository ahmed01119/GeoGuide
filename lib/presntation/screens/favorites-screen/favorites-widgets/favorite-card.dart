import 'package:flutter/material.dart';
import 'package:geoguide/models.dart/landmark_model.dart';

class FavoriteCard extends StatelessWidget {
  final Landmark place;
  const FavoriteCard({super.key, required this.place, required void Function() onRemove, required void Function() onTap});

  String get _imageUrl {
    if (place.imageUrl.trim().isNotEmpty) return place.imageUrl.trim();
    final first = place.mediaUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .firstOrNull;
    return first ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // ── Image ────────────────────────────────────────
          SizedBox(
            width: 100,
            height: 100,
            child: _imageUrl.isEmpty
                ? _Placeholder()
                : Image.network(
                    _imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    },
                    errorBuilder: (_, __, ___) => _Placeholder(),
                  ),
          ),
          // ── Info ─────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8C5E3C),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    place.shortDescription.isNotEmpty
                        ? place.shortDescription
                        : place.address.isNotEmpty
                            ? place.address
                            : 'No description available.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  if (place.rating > 0) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(place.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported, size: 28, color: Colors.grey),
          SizedBox(height: 4),
          Text('No image', style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}