import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/models.dart/saved_ai_image_model.dart';
import 'package:geoguide/presntation/screens/ai-image-details/ai_image_details_screen.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/landmark_image_ai_service.dart';

const _kBrown = AppColors.chestnutBrown;
const _kBrownMed = Color(0xFF8D6E63);
const _kBrownLight = Color(0xFFF4ECE5);
const _kBg = Color(0xFFF7F1EB);
const _kBorder = Color(0xFFEEE2D8);
const _kTextMid = Color(0xFF5E544D);

class SavedAiImagesPage extends StatelessWidget {
  static const String routeName = '/saved-ai-images';

  const SavedAiImagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            /// HEADER
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                decoration: const BoxDecoration(
                  color: _kBrown,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(34),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _GlassIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.bookmark_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Saved AI Images',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'All images you saved from Egypt AI Guide will appear here.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            /// LIST
            StreamBuilder<List<SavedAiImage>>(
              stream: firebase.savedAiImagesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: _kBrownMed),
                    ),
                  );
                }

                final images = snapshot.data ?? [];

                if (images.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'No saved images yet',
                        style: TextStyle(
                          color: _kTextMid,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                  sliver: SliverList.separated(
                    itemCount: images.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final item = images[index];
                      return _SavedAiImageCard(item: item);
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedAiImageCard extends StatelessWidget {
  final SavedAiImage item;

  const _SavedAiImageCard({required this.item});

  Uint8List? _decodeImage(String imageBase64) {
    try {
      var cleanBase64 = imageBase64.trim();

      if (cleanBase64.isEmpty) return null;

      /// Handles data URL format:
      /// data:image/png;base64,xxxx
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }

      /// Remove spaces, new lines, tabs
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');

      final bytes = base64Decode(cleanBase64);

      if (bytes.isEmpty) return null;

      return bytes;
    } catch (e) {
      debugPrint('Saved image decode error: $e');
      debugPrint('Saved image base64 length: ${imageBase64.length}');
      debugPrint(
        'Saved image base64 start: ${imageBase64.length > 40 ? imageBase64.substring(0, 40) : imageBase64}',
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodeImage(item.imageBase64);
    final hasValidImage = imageBytes != null && imageBytes.isNotEmpty;

    debugPrint('================ SAVED AI IMAGE ================');
    debugPrint('Saved AI Image ID: ${item.id}');
    debugPrint('Saved AI Image Title: ${item.title}');
    debugPrint('Saved AI Image base64 length: ${item.imageBase64.length}');
    debugPrint('Has valid image: $hasValidImage');
    debugPrint('================================================');

    final details = AiImageDetails(
      title: item.title,
      location: item.location,
      content: item.content,
      historicalFacts: item.historicalFacts,
      travelTips: item.travelTips,
      category: item.category,
      tags: item.tags,
    );

    return GestureDetector(
      onTap: !hasValidImage
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AiImageDetailsScreen(
                    heroTag: 'saved_${item.id}',
                    imageBytes: imageBytes,
                    details: details,
                  ),
                ),
              );
            },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kBorder),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ivoryCream,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// IMAGE
              SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!hasValidImage)
                      Container(
                        color: _kBrownLight,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_rounded,
                          color: _kBrownMed,
                          size: 42,
                        ),
                      )
                    else ...[
                      Hero(
                        tag: 'saved_${item.id}',
                        child: Image.memory(
                          imageBytes,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          gaplessPlayback: true,
                          errorBuilder: (_, error, ___) {
                            debugPrint('Image.memory render error: $error');

                            return Container(
                              color: _kBrownLight,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.image_not_supported_rounded,
                                color: _kBrownMed,
                                size: 42,
                              ),
                            );
                          },
                        ),
                      ),

                      /// GRADIENT
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.58),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    /// TEXT OVER IMAGE
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.category.isNotEmpty ||
                              item.location.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (item.category.isNotEmpty)
                                  _SmallPill(
                                    icon: Icons.category,
                                    label: item.category,
                                    hasValidImage: hasValidImage,
                                  ),
                                if (item.location.isNotEmpty)
                                  _SmallPill(
                                    icon: Icons.location_on,
                                    label: item.location,
                                    hasValidImage: hasValidImage,
                                  ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          Text(
                            item.title.isNotEmpty
                                ? item.title
                                : 'AI Image Details',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasValidImage ? Colors.white : _kBrownMed,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              /// DESCRIPTION
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  item.content.isNotEmpty
                      ? item.content
                      : 'No description available.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextMid,
                    fontSize: 13.5,
                    height: 1.45,
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

class _SmallPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool hasValidImage;

  const _SmallPill({
    required this.icon,
    required this.label,
    required this.hasValidImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasValidImage
            ? Colors.black.withOpacity(0.25)
            : Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasValidImage
              ? Colors.white.withOpacity(0.25)
              : _kBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: hasValidImage ? Colors.white : _kBrownMed,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasValidImage ? Colors.white : _kBrownMed,
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
    final width = MediaQuery.of(context).size.width;
    final buttonSize = (width * 0.112).clamp(42.0, 50.0).toDouble();

    return Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.10),
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Icon(
          icon,
          color: Colors.white,
          size: (buttonSize * 0.43).clamp(18.0, 22.0).toDouble(),
        ),
      ),
    );
  }
}