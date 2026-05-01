import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geoguide/models.dart/saved_ai_image_model.dart';
import 'package:geoguide/presntation/screens/ai-image-details/ai_image_details_screen.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/landmark_image_ai_service.dart';

const _kBrown = Color(0xFF5C4033);
const _kBrownMed = Color(0xFF8D6E63);
const _kBrownLight = Color(0xFFF4ECE5);
const _kBg = Color(0xFFF7F1EB);
const _kBorder = Color(0xFFEEE2D8);
const _kText = Color(0xFF2E251F);
const _kTextMid = Color(0xFF5E544D);
const _kTextLight = Color(0xFF8B817A);

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
                        InkWell(
                          borderRadius: BorderRadius.circular(50),
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.16),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.18),
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
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

  @override
  Widget build(BuildContext context) {
    final imageBytes = base64Decode(item.imageBase64);

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
      onTap: () {
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
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
                    Hero(
                      tag: 'saved_${item.id}',
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.cover,
                      ),
                    ),

                    /// GRADIENT
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.6),
                            ],
                          ),
                        ),
                      ),
                    ),

                    /// CLEAN TEXT (بدون glass)
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
                              children: [
                                if (item.category.isNotEmpty)
                                  _SmallPill(
                                    icon: Icons.category,
                                    label: item.category,
                                  ),
                                if (item.location.isNotEmpty)
                                  _SmallPill(
                                    icon: Icons.location_on,
                                    label: item.location,
                                  ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
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
                  item.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextMid,
                    fontSize: 13.5,
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

  const _SmallPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}