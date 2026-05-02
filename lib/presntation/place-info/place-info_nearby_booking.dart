part of 'place-info.dart';

// ════════════════════════════════════════════════════════════════
//  NEARBY TAB  (same as before but uses FirebaseService directly)
// ════════════════════════════════════════════════════════════════
enum _NearbyFilter { all, attractions, hotels, dining }

class _NearbyItem {
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final double rating;
  final bool isLive;

  const _NearbyItem({
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.rating,
    this.isLive = false,
  });
}

class _NearbyTab extends StatefulWidget {
  final Landmark place;
  final FirebaseService firebase;

  const _NearbyTab({required this.place, required this.firebase});

  @override
  State<_NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<_NearbyTab> {
  _NearbyFilter _filter = _NearbyFilter.all;
  List<_NearbyItem> _items = [];
  bool _loading = true;

  double get _lat => widget.place.lat;
  double get _lng => widget.place.lng;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loadFromLandmark();
    await _loadFromFirebase();
    if (_lat != 0 && _lng != 0) _fetchLive();
  }

  void _loadFromLandmark() {
    final cached = widget.place.nearbyPlaces;
    if (cached.isEmpty) return;

    final items = <_NearbyItem>[];
    for (final item in cached) {
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      items.add(_NearbyItem(
        name: name,
        category: _mapCat((item['category'] ?? 'tourist').toString()),
        address: (item['address'] ?? widget.place.city).toString(),
        lat: ((item['lat'] ?? 0) as num).toDouble(),
        lng: ((item['lng'] ?? 0) as num).toDouble(),
        rating: ((item['rating'] ?? 0) as num).toDouble(),
      ));
    }

    if (mounted && items.isNotEmpty) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _loadFromFirebase() async {
    try {
      final snapshot = await widget.firebase
          .nearbySuggestionsStream(
            city: widget.place.city,
            excludePlaceId: widget.place.id,
            sourceLat: _lat,
            sourceLng: _lng,
          )
          .first
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      final items = snapshot
          .map((lm) => _NearbyItem(
                name: lm.name,
                category: _mapCat(lm.category),
                address: lm.address.isNotEmpty ? lm.address : lm.city,
                lat: lm.lat,
                lng: lm.lng,
                rating: lm.rating,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchLive() async {
    if (_lat == 0 || _lng == 0) return;
    try {
      final query = '''
[out:json][timeout:25];
(
  node["amenity"~"restaurant|cafe|fast_food"](around:2500,$_lat,$_lng);
  node["tourism"~"hotel|guest_house|hostel|motel"](around:3000,$_lat,$_lng);
  node["tourism"~"attraction|museum|viewpoint|gallery"](around:3500,$_lat,$_lng);
  node["historic"](around:3500,$_lat,$_lng);
);
out center tags;
''';

      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      ).timeout(const Duration(seconds: 28));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List? ?? []).cast<Map<String, dynamic>>();
      final seen = <String>{};
      final liveItems = <_NearbyItem>[];

      for (final el in elements) {
        final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
        final name = (tags['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final itemLat = ((el['lat'] ?? el['center']?['lat'] ?? 0) as num).toDouble();
        final itemLng = ((el['lon'] ?? el['center']?['lon'] ?? 0) as num).toDouble();
        if (itemLat == 0 || itemLng == 0) continue;

        final amenity = (tags['amenity'] ?? '').toString().toLowerCase();
        final tourism = (tags['tourism'] ?? '').toString().toLowerCase();
        final historic = (tags['historic'] ?? '').toString().toLowerCase();

        String category = 'tourist';
        if (amenity == 'restaurant' || amenity == 'fast_food') {
          category = 'restaurant';
        } else if (amenity == 'cafe') {
          category = 'cafe';
        } else if (tourism == 'hotel' ||
            tourism == 'guest_house' ||
            tourism == 'hostel' ||
            tourism == 'motel') {
          category = 'hotel';
        } else if (tourism.isNotEmpty || historic.isNotEmpty) {
          category = 'tourist';
        }

        final addr = _composeAddress(tags);
        final key = '${name.toLowerCase()}|$category';
        if (!seen.add(key)) continue;

        liveItems.add(_NearbyItem(
          name: name,
          category: category,
          address: addr,
          lat: itemLat,
          lng: itemLng,
          rating: 0,
          isLive: true,
        ));
      }

      if (!mounted) return;
      final existingKeys = _items.map((e) => e.name.toLowerCase()).toSet();
      final newLive =
          liveItems.where((e) => !existingKeys.contains(e.name.toLowerCase())).toList();
      final merged = [..._items, ...newLive];
      merged.sort((a, b) => _dist(a.lat, a.lng).compareTo(_dist(b.lat, b.lng)));
      setState(() => _items = merged.take(80).toList());
    } catch (_) {}
  }

  String _composeAddress(Map<String, dynamic> tags) {
    final parts = [
      (tags['addr:street'] ?? '').toString().trim(),
      (tags['addr:city'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(', ') : widget.place.city;
  }

  String _mapCat(String raw) {
    final cat = raw.toLowerCase();
    if (cat.contains('hotel') || cat.contains('resort')) return 'hotel';
    if (cat.contains('restaurant') || cat.contains('food')) return 'restaurant';
    if (cat.contains('cafe') || cat.contains('coffee')) return 'cafe';
    if (cat.contains('park') || cat.contains('outing')) return 'outing';
    return 'tourist';
  }

  double _dist(double lat, double lng) {
    if (_lat == 0 || _lng == 0 || lat == 0 || lng == 0) return 9999;
    return (lat - _lat).abs() + (lng - _lng).abs();
  }

  List<_NearbyItem> get _filtered {
    switch (_filter) {
      case _NearbyFilter.hotels:
        return _items.where((e) => e.category == 'hotel').toList();
      case _NearbyFilter.dining:
        return _items
            .where((e) => e.category == 'restaurant' || e.category == 'cafe')
            .toList();
      case _NearbyFilter.attractions:
        return _items.where((e) => e.category == 'tourist' || e.category == 'outing').toList();
      case _NearbyFilter.all:
        return _items;
    }
  }

  Color _catColor(String cat) {
    switch (cat) {
      case 'hotel':
        return const Color(0xFF5C6BC0);
      case 'restaurant':
        return const Color(0xFFEF6C00);
      case 'cafe':
        return const Color(0xFF795548);
      case 'outing':
        return const Color(0xFF2E7D32);
      default:
        return _kBrownMed;
    }
  }

  Color _catBg(String cat) {
    switch (cat) {
      case 'hotel':
        return const Color(0xFFEDE7F6);
      case 'restaurant':
        return const Color(0xFFFFF3E0);
      case 'cafe':
        return const Color(0xFFEFEBE9);
      case 'outing':
        return const Color(0xFFE8F5E9);
      default:
        return _kBrownLight;
    }
  }

  IconData _catIcon(String cat) {
    switch (cat) {
      case 'hotel':
        return Icons.hotel_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'cafe':
        return Icons.local_cafe_rounded;
      case 'outing':
        return Icons.park_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  String _catLabel(_NearbyItem item) {
    switch (item.category) {
      case 'hotel':
        return 'HOTEL';
      case 'restaurant':
        return 'RESTAURANT';
      case 'cafe':
        return 'CAFE';
      case 'outing':
        return 'OUTING';
      default:
        return 'ATTRACTION';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      (_NearbyFilter.all, 'All', Icons.grid_view_rounded),
      (_NearbyFilter.attractions, 'Attractions', Icons.photo_camera_rounded),
      (_NearbyFilter.hotels, 'Hotels', Icons.hotel_rounded),
      (_NearbyFilter.dining, 'Dining', Icons.restaurant_rounded),
    ];

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: chips.map((c) {
              final selected = _filter == c.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? _kBrown : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: selected ? _kBrown : _kBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.$3, size: 15, color: selected ? Colors.white : _kTextMid),
                        const SizedBox(width: 6),
                        Text(
                          c.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : _kTextMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _kBrownMed))
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: _kBrownLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.place_rounded, size: 34, color: _kBrownMed),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No nearby places found',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: _kTextMid,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, idx) {
                        final item = _filtered[idx];
                        return _NearbyItemTile(
                          item: item,
                          catColor: _catColor(item.category),
                          catBg: _catBg(item.category),
                          catIcon: _catIcon(item.category),
                          catLabel: _catLabel(item),
                          placeCity: widget.place.city,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _NearbyItemTile extends StatelessWidget {
  final _NearbyItem item;
  final Color catColor;
  final Color catBg;
  final IconData catIcon;
  final String catLabel;
  final String placeCity;

  const _NearbyItemTile({
    required this.item,
    required this.catColor,
    required this.catBg,
    required this.catIcon,
    required this.catLabel,
    required this.placeCity,
  });

  Future<void> _openMaps(BuildContext context) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}');
    await _launchSafely(uri, context: context);
  }

  Future<void> _book(BuildContext context) async {
    final q = Uri.encodeComponent('${item.name} $placeCity Egypt');
    final Uri uri;
    if (item.category == 'hotel') {
      uri = Uri.parse('https://www.booking.com/searchresults.html?ss=${Uri.encodeComponent(item.name)}');
    } else if (item.category == 'restaurant' || item.category == 'cafe') {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}');
    } else {
      uri = Uri.parse('https://www.viator.com/searchResults/all?text=$q');
    }
    await _launchSafely(uri, context: context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(14)),
                  child: Icon(catIcon, color: catColor, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _kText),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              catLabel,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: catColor),
                            ),
                          ),
                          if (item.isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32)),
                              ),
                            ),
                          if (item.rating > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                                const SizedBox(width: 2),
                                Text(
                                  item.rating.toStringAsFixed(1),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMid),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (item.address.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 12, color: _kTextLight),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                item.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: _kTextLight),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _kBorder))),
            child: Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.directions_rounded,
                    label: 'Directions',
                    color: const Color(0xFF2E7D32),
                    bg: const Color(0xFFE8F5E9),
                    onTap: () => _openMaps(context),
                    isLeft: true,
                  ),
                ),
                Container(width: 1, height: 46, color: _kBorder),
                Expanded(
                  child: _ActionBtn(
                    icon: item.category == 'hotel'
                        ? Icons.bed_rounded
                        : item.category == 'restaurant' || item.category == 'cafe'
                            ? Icons.directions_rounded
                            : Icons.confirmation_number_rounded,
                    label: item.category == 'hotel'
                        ? 'Book Room'
                        : item.category == 'restaurant' || item.category == 'cafe'
                            ? 'Directions'
                            : 'Book Tour',
                    color: _kBrown,
                    bg: _kBrownLight,
                    onTap: () => _book(context),
                    isLeft: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;
  final bool isLeft;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    final radius = isLeft
        ? const BorderRadius.only(bottomLeft: Radius.circular(20))
        : const BorderRadius.only(bottomRight: Radius.circular(20));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  BOOKING SECTION
// ════════════════════════════════════════════════════════════════
class _PremiumBookingSection extends StatelessWidget {
  final Landmark place;
  const _PremiumBookingSection({required this.place});

  String get _encodedName => Uri.encodeComponent(place.name);
  String get _encodedCity => Uri.encodeComponent(place.city.isNotEmpty ? place.city : 'Egypt');
  String get _encodedQuery => Uri.encodeComponent('${place.name} ${place.city} Egypt');

  bool get _isHotel {
    final cat = place.category.toLowerCase();
    return cat.contains('hotel') || cat.contains('resort');
  }

  bool get _isDining {
    final cat = place.category.toLowerCase();
    return cat.contains('restaurant') || cat.contains('cafe');
  }

  @override
  Widget build(BuildContext context) {
    if (_isHotel) return _buildHotelBooking(context);
    if (_isDining) return _buildDiningBooking(context);
    return _buildAttractionBooking(context);
  }

  Widget _buildHotelBooking(BuildContext context) => Column(
        children: [
          _BookingProviderCard(
            providerName: 'Booking.com',
            tagline: 'Best price guarantee · Free cancellation',
            badge: 'POPULAR',
            badgeColor: const Color(0xFF1565C0),
            icon: Icons.hotel_rounded,
            iconBg: const Color(0xFFE3F2FD),
            iconColor: const Color(0xFF1565C0),
            priceHint: 'From \$45/night',
            features: const ['Free cancellation', 'No prepayment needed', 'Instant confirmation'],
            onTap: () => _launchSafely(
              Uri.parse('https://www.booking.com/searchresults.html?ss=$_encodedName'),
              context: context,
            ),
          ),
          const SizedBox(height: 10),
          _BookingProviderCard(
            providerName: 'Agoda',
            tagline: 'Exclusive deals for Egypt hotels',
            badge: 'DEALS',
            badgeColor: const Color(0xFFE65100),
            icon: Icons.local_offer_rounded,
            iconBg: const Color(0xFFFFF3E0),
            iconColor: const Color(0xFFE65100),
            priceHint: 'Special discounts',
            features: const ['Secret deals', 'Last minute offers', 'Member prices'],
            onTap: () => _launchSafely(
              Uri.parse('https://www.agoda.com/search?q=$_encodedQuery'),
              context: context,
            ),
          ),
          const SizedBox(height: 10),
          _BookingProviderCard(
            providerName: 'Uber',
            tagline: 'Open Uber and book your ride',
            badge: 'RIDE',
            badgeColor: Colors.black,
            icon: Icons.local_taxi_rounded,
            iconBg: const Color(0xFFF3F3F3),
            iconColor: Colors.black87,
            priceHint: 'Live fare estimate',
            features: const ['Open Uber app', 'Set destination automatically', 'Order in seconds'],
            onTap: () => _launchUberRide(place, context: context),
          ),
        ],
      );

  Widget _buildDiningBooking(BuildContext context) => Column(
        children: [
          _BookingProviderCard(
            providerName: 'Google Maps',
            tagline: 'Get directions & view reviews',
            badge: 'DIRECTIONS',
            badgeColor: const Color(0xFF1565C0),
            icon: Icons.directions_rounded,
            iconBg: const Color(0xFFE3F2FD),
            iconColor: const Color(0xFF1565C0),
            priceHint: 'Free navigation',
            features: const ['Turn-by-turn directions', 'View photos', 'Read reviews'],
            onTap: () {
              final Uri uri = place.lat != 0 && place.lng != 0
                  ? Uri.parse('https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lng}')
                  : Uri.parse('https://www.google.com/maps/search/?api=1&query=$_encodedQuery');
              _launchSafely(uri, context: context);
            },
          ),
          const SizedBox(height: 10),
          _BookingProviderCard(
            providerName: 'TripAdvisor',
            tagline: 'Read reviews from real travelers',
            badge: 'REVIEWS',
            badgeColor: const Color(0xFF2E7D32),
            icon: Icons.rate_review_rounded,
            iconBg: const Color(0xFFE8F5E9),
            iconColor: const Color(0xFF2E7D32),
            priceHint: 'See all reviews',
            features: const ['Traveler reviews', 'Photos', 'Menu info'],
            onTap: () => _launchSafely(
              Uri.parse('https://www.tripadvisor.com/Search?q=$_encodedQuery'),
              context: context,
            ),
          ),
          const SizedBox(height: 10),
          _BookingProviderCard(
            providerName: 'Uber',
            tagline: 'Open Uber and book your ride',
            badge: 'RIDE',
            badgeColor: Colors.black,
            icon: Icons.local_taxi_rounded,
            iconBg: const Color(0xFFF3F3F3),
            iconColor: Colors.black87,
            priceHint: 'Live fare estimate',
            features: const ['Open Uber app', 'Set destination automatically', 'Order in seconds'],
            onTap: () => _launchUberRide(place, context: context),
          ),
        ],
      );

  Widget _buildAttractionBooking(BuildContext context) => Column(
        children: [
          _BookingProviderCard(
            providerName: 'Viator',
            tagline: 'Skip-the-line tickets & guided tours',
            badge: 'POPULAR',
            badgeColor: const Color(0xFF2E7D32),
            icon: Icons.confirmation_number_outlined,
            iconBg: const Color(0xFFE8F5E9),
            iconColor: const Color(0xFF2E7D32),
            priceHint: 'From \$15',
            features: const ['Skip the line', 'Expert guides', 'Free cancellation'],
            onTap: () => _launchSafely(
              Uri.parse('https://www.viator.com/searchResults/all?text=$_encodedName+$_encodedCity'),
              context: context,
            ),
          ),
          const SizedBox(height: 10),
          _BookingProviderCard(
            providerName: 'GetYourGuide',
            tagline: 'Instant booking · Best experiences',
            badge: 'INSTANT',
            badgeColor: const Color(0xFFE65100),
            icon: Icons.tour_outlined,
            iconBg: const Color(0xFFFFF3E0),
            iconColor: const Color(0xFFE65100),
            priceHint: 'Compare tours',
            features: const ['Instant confirmation', 'Mobile ticket', 'Best guides'],
            onTap: () => _launchSafely(
              Uri.parse('https://www.getyourguide.com/s/?q=$_encodedName'),
              context: context,
            ),
          ),
          const SizedBox(height: 10),
          _BookingProviderCard(
            providerName: 'Uber',
            tagline: 'Open Uber and book your ride',
            badge: 'RIDE',
            badgeColor: Colors.black,
            icon: Icons.local_taxi_rounded,
            iconBg: const Color(0xFFF3F3F3),
            iconColor: Colors.black87,
            priceHint: 'Live fare estimate',
            features: const ['Open Uber app', 'Set destination automatically', 'Order in seconds'],
            onTap: () => _launchUberRide(place, context: context),
          ),
        ],
      );
}

class _BookingProviderCard extends StatelessWidget {
  final String providerName;
  final String tagline;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String priceHint;
  final List<String> features;
  final VoidCallback onTap;

  const _BookingProviderCard({
    required this.providerName,
    required this.tagline,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.priceHint,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              providerName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kText),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: badgeColor.withOpacity(0.25)),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(tagline, style: const TextStyle(fontSize: 12.5, color: _kTextLight)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: features
                    .map(
                      (f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F4EF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 11, color: _kBrownMed),
                            const SizedBox(width: 4),
                            Text(
                              f,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _kTextMid),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: _kBrown, borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Book Now',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
