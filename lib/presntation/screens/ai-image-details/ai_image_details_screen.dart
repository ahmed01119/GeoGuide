import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/landmark_image_ai_service.dart';

const _kBrown = Color(0xFF5C4033);
const _kBrownMed = Color(0xFF8D6E63);
const _kBrownLight = Color(0xFFF4ECE5);
const _kBg = Color(0xFFF7F1EB);
const _kCard = Color(0xFFF9F5F1);
const _kBorder = Color(0xFFEEE2D8);
const _kText = Color(0xFF2E251F);
const _kTextMid = Color(0xFF5E544D);

class AiImageDetailsScreen extends StatefulWidget {
  final XFile? imageFile;
  final Uint8List? imageBytes;
  final String? heroTag;
  final AiImageDetails details;

  const AiImageDetailsScreen({
    super.key,
    this.imageFile,
    this.imageBytes,
    this.heroTag,
    required this.details,
  }) : assert(
          imageFile != null || imageBytes != null,
          'AiImageDetailsScreen needs imageFile or imageBytes',
        );

  @override
  State<AiImageDetailsScreen> createState() => _AiImageDetailsScreenState();
}

class _AiImageDetailsScreenState extends State<AiImageDetailsScreen> {
  final FirebaseService _firebase = FirebaseService();

  late final Future<Uint8List?> _imageBytesFuture;

  @override
  void initState() {
    super.initState();
    _imageBytesFuture = _getImageBytes();
  }

  Future<Uint8List?> _getImageBytes() async {
    if (widget.imageBytes != null) return widget.imageBytes;
    if (widget.imageFile != null) return widget.imageFile!.readAsBytes();
    return null;
  }

  Future<String> _getImageBase64() async {
    final bytes = await _imageBytesFuture;
    if (bytes == null) return '';
    return base64Encode(bytes);
  }

  Future<void> _toggleSave(BuildContext context, bool isSaved) async {
    try {
      final imageBase64 = await _getImageBase64();
      if (imageBase64.isEmpty) return;

      final saveKey = _firebase.buildSavedAiImageKey(
        imageBase64: imageBase64,
        details: widget.details,
      );

      if (isSaved) {
        await _firebase.removeSavedAiImage(saveKey);
      } else {
        await _firebase.saveAiImage(
          saveKey: saveKey,
          imageBase64: imageBase64,
          details: widget.details,
        );
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _kBrownMed,
          content: Text(
            isSaved ? 'Removed from saved images' : 'Saved successfully',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _kBrownMed,
          content: Text('Could not update saved images'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isTablet = media.size.shortestSide >= 600;

    return FutureBuilder<Uint8List?>(
      future: _imageBytesFuture,
      builder: (context, imageSnapshot) {
        final bytes = imageSnapshot.data;

        return FutureBuilder<String>(
          future: bytes == null ? Future.value('') : Future.value(base64Encode(bytes)),
          builder: (context, base64Snapshot) {
            final imageBase64 = base64Snapshot.data ?? '';
            final saveKey = imageBase64.isEmpty
                ? ''
                : _firebase.buildSavedAiImageKey(
                    imageBase64: imageBase64,
                    details: widget.details,
                  );

            return Scaffold(
              backgroundColor: _kBg,
              body: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    expandedHeight: isTablet ? 430 : 360,
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
                        padding: const EdgeInsets.only(right: 8),
                        child: StreamBuilder<bool>(
                          stream: _firebase.savedAiImageStream(saveKey),
                          builder: (context, snapshot) {
                            final isSaved = snapshot.data ?? false;
                            return _GlassIconButton(
                              icon: isSaved
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              color: isSaved ? Colors.amber : Colors.white,
                              onTap: imageBase64.isEmpty
                                  ? null
                                  : () => _toggleSave(context, isSaved),
                            );
                          },
                        ),
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (bytes == null)
                            Container(color: _kBrownLight)
                          else if (widget.heroTag != null)
                            Hero(
                              tag: widget.heroTag!,
                              child: Material(
                                color: Colors.transparent,
                                child: Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _imageError(),
                                ),
                              ),
                            )
                          else
                            Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _imageError(),
                            ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.16),
                                      Colors.black.withOpacity(0.04),
                                      Colors.black.withOpacity(0.68),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 20,
                            right: 20,
                            bottom: 16,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.92, end: 1),
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutBack,
                              builder: (context, value, child) {
                                return Transform.scale(
                                  scale: value,
                                  alignment: Alignment.bottomCenter,
                                  child: child,
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                  child: Container(
                                    padding: EdgeInsets.all(isTablet ? 18 : 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.22),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.14),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (widget.details.category.isNotEmpty)
                                              _HeroPill(
                                                icon: Icons.category_rounded,
                                                label: widget.details.category.toUpperCase(),
                                              ),
                                            if (widget.details.location.isNotEmpty)
                                              _HeroPill(
                                                icon: Icons.location_on_rounded,
                                                label: widget.details.location,
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          widget.details.title.isNotEmpty
                                              ? widget.details.title
                                              : 'AI Image Details',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: isTablet ? 28 : 24,
                                            height: 1.15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Generated by Egypt AI Guide',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.92),
                                            fontSize: isTablet ? 14 : 13,
                                            height: 1.45,
                                          ),
                                        ),
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
                            18,
                            isTablet ? 24 : 16,
                            40,
                          ),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 18, end: 0),
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, value),
                                child: Opacity(
                                  opacity: (1 - value / 18).clamp(0.0, 1.0),
                                  child: child,
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _MainInfoCard(details: widget.details),
                                const SizedBox(height: 18),
                                if (widget.details.historicalFacts.isNotEmpty) ...[
                                  _SectionCard(
                                    title: 'Historical Facts',
                                    icon: Icons.history_edu_rounded,
                                    children: widget.details.historicalFacts
                                        .map((e) => _BulletText(text: e))
                                        .toList(),
                                  ),
                                  const SizedBox(height: 18),
                                ],
                                if (widget.details.travelTips.isNotEmpty) ...[
                                  _SectionCard(
                                    title: 'Travel Tips',
                                    icon: Icons.tips_and_updates_rounded,
                                    children: widget.details.travelTips
                                        .map((e) => _BulletText(text: e))
                                        .toList(),
                                  ),
                                  const SizedBox(height: 18),
                                ],
                                if (widget.details.tags.isNotEmpty)
                                  _TagsCard(tags: widget.details.tags),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _imageError() {
    return Container(
      color: _kBrownLight,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_rounded,
        color: _kBrownMed,
        size: 42,
      ),
    );
  }
}

class _MainInfoCard extends StatelessWidget {
  final AiImageDetails details;

  const _MainInfoCard({required this.details});

  @override
  Widget build(BuildContext context) {
    return _AnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About this image',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _kText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            details.content.isNotEmpty
                ? details.content
                : 'No description available.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.65,
              color: _kTextMid,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedCard extends StatelessWidget {
  final Widget child;

  const _AnimatedCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.97, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, scale, _) {
        return Transform.scale(
          scale: scale,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
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
            child: child,
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: title, icon: icon),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _TagsCard extends StatelessWidget {
  final List<String> tags;

  const _TagsCard({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(label: 'Tags', icon: Icons.sell_rounded),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: _kBrownLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kBrown,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionLabel({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _kBrownMed, size: 19),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _kText,
          ),
        ),
      ],
    );
  }
}

class _BulletText extends StatelessWidget {
  final String text;

  const _BulletText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 6, color: _kBrownMed),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: _kTextMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroPill({
    required this.icon,
    required this.label,
  });

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
          Icon(icon, color: Colors.white, size: 13),
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

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _GlassIconButton({
    required this.icon,
    this.color = Colors.white,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}
