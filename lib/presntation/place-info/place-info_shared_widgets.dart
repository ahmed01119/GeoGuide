part of 'place-info.dart';

// ════════════════════════════════════════════════════════════════
//  SHARED UI HELPERS (all unchanged from original)
// ════════════════════════════════════════════════════════════════

class _PremiumImageCarousel extends StatefulWidget {
  final List<String> urls;
  final String heroTag;

  const _PremiumImageCarousel({required this.urls, required this.heroTag});

  @override
  State<_PremiumImageCarousel> createState() => _PremiumImageCarouselState();
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.20)),
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
                    color: _cur == i ? Colors.white : Colors.white54,
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
                  child: _NetImage(url: widget.urls[i], fit: BoxFit.contain),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                border: Border.all(color: Colors.white.withOpacity(0.18)),
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
        child: SizedBox(
            width: 38, height: 38, child: Icon(icon, color: Colors.white, size: 18)),
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
            const Icon(Icons.open_in_new_rounded, color: _kBrownMed, size: 18),
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
