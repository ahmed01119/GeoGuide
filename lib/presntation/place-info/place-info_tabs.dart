part of 'place-info.dart';

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
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
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
          const _SectionLabel(label: 'Location', icon: Icons.pin_drop_rounded),
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
                label: 'Opening Hours', icon: Icons.access_time_rounded),
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
                      label: 'Visitor Rating', icon: Icons.star_rounded),
                  const SizedBox(height: 8),
                  _RatingTile(rating: avg),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          if (place.ticketPrice != null && place.ticketPrice!.isNotEmpty) ...[
            const _SectionLabel(
                label: 'Ticket Price', icon: Icons.local_activity_rounded),
            const SizedBox(height: 8),
            _InfoTile(
              icon: Icons.confirmation_number_rounded,
              value: place.ticketPrice!,
              accentColor: _kBrownMed,
            ),
            const SizedBox(height: 16),
          ],
          const _SectionLabel(
              label: 'Book & Reserve', icon: Icons.local_activity_rounded),
          const SizedBox(height: 12),
          _PremiumBookingSection(place: place),
          const SizedBox(height: 16),
          const _SectionLabel(label: 'Wikipedia', icon: Icons.menu_book_rounded),
          const SizedBox(height: 8),
          _InfoTile(
            icon: Icons.open_in_new_rounded,
            value: (place.wikipediaUrl ?? '').trim().isNotEmpty
                ? 'Open article'
                : 'Search article on Wikipedia',
            accentColor: _kBrownMed,
            isLink: true,
            onTap: () {
              final direct = (place.wikipediaUrl ?? '').trim();
              final uri = direct.isNotEmpty
                  ? Uri.parse(direct)
                  : Uri.parse(
                      'https://en.wikipedia.org/w/index.php?search=${Uri.encodeComponent('${place.name} ${place.city} Egypt')}',
                    );
              _launchSafely(uri, context: context);
            },
          ),
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
                      label: 'More Links', icon: Icons.open_in_new_rounded),
                  const SizedBox(height: 8),
                  ...links.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InfoTile(
                        icon: Icons.link_rounded,
                        value: e.key,
                        accentColor: _kBrownMed,
                        isLink: true,
                        onTap: () =>
                            _launchSafely(Uri.parse(e.value), context: context),
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

    final text = place.history.isNotEmpty ? place.history : place.fullDescription;

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
          text.isNotEmpty ? text : 'No historical information available yet.',
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
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (ok) {
      await widget.repo.deleteReview(placeId: widget.place.id, userId: uid);
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
                    onPressed: () => setState(() => _rating = (i + 1).toDouble()),
                    icon: Icon(
                      i + 1 <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
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
                  child: Text('No reviews yet.', style: TextStyle(color: _kTextLight)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                itemCount: reviews.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                                    color: Colors.red.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
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
