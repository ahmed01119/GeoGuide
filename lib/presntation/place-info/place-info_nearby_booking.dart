part of 'place-info.dart';

// ════════════════════════════════════════════════════════════════
//  NEARBY TAB — Firebase first + free API reload + persistent cache
// ════════════════════════════════════════════════════════════════
//
// Required imports in the parent place-info.dart file:
// import 'package:geoguide/services/nearby-service.dart';
// import 'package:geoguide/services/firebase_nearby_cache_extension.dart';
//
// Behavior:
// - Shows cached nearbyPlaces immediately.
// - Merges Firebase nearby suggestions without replacing old items.
// - Uses NearbyService for free Nominatim + Overpass fallback.
// - Adds Outing places.
// - Saves generated/loaded nearby places back to landmarks/{placeId}.nearbyPlaces.
// - On next screen open, cached places appear immediately without Refresh.
// - Strong dedupe prevents repeated places.

enum _NearbyFilter { all, attractions, hotels, dining, outing }

class _NearbyItem {
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final double rating;
  final bool isLive;
  final String? bookingUrl;
  final String? website;
  final String? mapsUrl;
  final String? wikipediaUrl;

  const _NearbyItem({
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.rating,
    this.isLive = false,
    this.bookingUrl,
    this.website,
    this.mapsUrl,
    this.wikipediaUrl,
  });

  String get dedupeKey {
    return '${_normalize(name)}|${_normalize(category)}';
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _NearbyTab extends StatefulWidget {
  final Landmark place;
  final FirebaseService firebase;

  const _NearbyTab({
    required this.place,
    required this.firebase,
  });

  @override
  State<_NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<_NearbyTab> {
  final NearbyService _nearbyService = NearbyService();

  _NearbyFilter _filter = _NearbyFilter.all;
  List<_NearbyItem> _items = [];

  bool _loading = true;
  bool _checkingLive = false;
  bool _savingCache = false;
  String? _statusMessage;
  String? _lastSavedSignature;

  double get _lat => widget.place.lat;
  double get _lng => widget.place.lng;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    _loadFromLandmarkCache();
    await _loadFromFirebaseSuggestions();

    if (mounted) {
      setState(() => _loading = false);
    }

    if (_lat != 0 && _lng != 0) {
      await _reloadFreeApis(forceRefresh: false);
    }
  }

  void _loadFromLandmarkCache() {
    final cached = widget.place.nearbyPlaces;
    if (cached.isEmpty) return;

    final items = <_NearbyItem>[];

    for (final item in cached) {
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      items.add(
        _NearbyItem(
          name: name,
          category: _mapCat((item['category'] ?? 'tourist').toString()),
          address: (item['address'] ?? widget.place.city).toString(),
          lat: ((item['lat'] ?? 0) as num).toDouble(),
          lng: ((item['lng'] ?? 0) as num).toDouble(),
          rating: ((item['rating'] ?? 0) as num).toDouble(),
          isLive: false,
          bookingUrl: item['bookingUrl']?.toString(),
          website: item['website']?.toString(),
          mapsUrl: item['mapsUrl']?.toString(),
          wikipediaUrl: item['wikipediaUrl']?.toString(),
        ),
      );
    }

    if (items.isNotEmpty) {
      _mergeItems(
        items,
        message: 'Stored nearby places loaded',
      );
      _lastSavedSignature = _itemsSignature(_items);
    }
  }

  Future<void> _loadFromFirebaseSuggestions() async {
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
          .map(
            (lm) => _NearbyItem(
              name: lm.name,
              category: _mapCat(lm.category),
              address: lm.address.isNotEmpty ? lm.address : lm.city,
              lat: lm.lat,
              lng: lm.lng,
              rating: lm.rating,
              isLive: false,
              mapsUrl: lm.lat != 0 && lm.lng != 0
                  ? 'https://www.google.com/maps/search/?api=1&query=${lm.lat},${lm.lng}'
                  : null,
              wikipediaUrl: lm.wikipediaUrl,
            ),
          )
          .where((item) => item.name.trim().isNotEmpty)
          .toList();

      _mergeItems(
        items,
        message: items.isNotEmpty ? 'Firebase nearby places loaded' : null,
      );
    } catch (_) {
      // Keep cached UI. Free API reload will try after this.
    }
  }

  Future<void> _reloadFreeApis({required bool forceRefresh}) async {
    if (_lat == 0 || _lng == 0) return;
    if (_checkingLive) return;

    setState(() {
      _checkingLive = true;
      _statusMessage = 'Checking for new nearby places...';
    });

    try {
      final existing = _items.map(_toNearbyPlace).toList();

      final result = await _nearbyService.getNearbyWithAutoRefresh(
        lat: _lat,
        lng: _lng,
        cityName: widget.place.city,
        existingPlaces: existing,
        categories: _categoriesForFilter(_filter),
        limit: 36,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      final before = _items.length;

      final incoming = result.places
          .map(_fromNearbyPlace)
          .where((item) => item.name.trim().isNotEmpty)
          .toList();

      _mergeItems(
        incoming,
        message: null,
      );

      final added = _items.length - before;

      if (added > 0 || result.didRefresh || forceRefresh) {
        await _persistNearbyCache();
      }

      if (!mounted) return;

      setState(() {
        if (added > 0) {
          _statusMessage =
              '$added new nearby place${added == 1 ? '' : 's'} added and saved';
        } else if (_items.isNotEmpty) {
          _statusMessage = 'Nearby places are up to date';
        } else {
          _statusMessage = 'No nearby places found yet';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = _items.isNotEmpty
            ? 'Showing stored places. Live reload is unavailable now.'
            : 'Live nearby search is unavailable now.';
      });
    } finally {
      if (mounted) {
        setState(() => _checkingLive = false);
      }
    }
  }

  Future<void> _persistNearbyCache() async {
    if (_savingCache) return;
    if (widget.place.id.trim().isEmpty) return;
    if (_items.isEmpty) return;

    final signature = _itemsSignature(_items);
    if (_lastSavedSignature == signature) return;

    _savingCache = true;

    try {
      final places = _items.map(_toNearbyPlace).map((p) => p.toJson()).toList();

      await widget.firebase.saveNearbyPlacesForLandmark(
        placeId: widget.place.id,
        nearbyPlaces: places,
      );

      _lastSavedSignature = signature;

      if (mounted) {
        setState(() => _statusMessage = 'Nearby places saved for next time');
      }

      print('[Nearby] cached ${places.length} nearby places for ${widget.place.name}');
    } catch (e) {
      print('[Nearby] cache save failed: $e');
    } finally {
      _savingCache = false;
    }
  }

  String _itemsSignature(List<_NearbyItem> items) {
    final keys = items.map((e) => e.dedupeKey).toList()..sort();
    return keys.join('|');
  }

  bool _isCurrentPlaceItem(_NearbyItem item) {
    final itemName = _normalizePlaceName(item.name);
    final placeName = _normalizePlaceName(widget.place.name);

    if (itemName.isEmpty || placeName.isEmpty) return false;

    if (itemName == placeName) return true;

    // Handles small variants like "Khan el Khalili Bazaar" vs "Khan el-Khalili".
    if (itemName.contains(placeName) || placeName.contains(itemName)) {
      final diff = (itemName.length - placeName.length).abs();
      return diff <= 12;
    }

    return false;
  }

  String _normalizePlaceName(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .replaceAll(RegExp(r'\b(the|of|el|al|and|egypt|cairo|giza)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  NearbyPlace _toNearbyPlace(_NearbyItem item) {
    return NearbyPlace(
      placeId: 'ui_${item.dedupeKey}',
      name: item.name,
      address: item.address,
      lat: item.lat,
      lng: item.lng,
      distanceKm: _distKm(item.lat, item.lng),
      rating: item.rating,
      userRatingsTotal: 0,
      priceLevel: '',
      isOpenNow: false,
      hasOpeningHours: false,
      imageUrl: '',
      category: item.category,
      types: const [],
      mapsUrl: item.mapsUrl ??
          'https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}',
      bookingUrl: item.bookingUrl,
      wikipediaUrl: item.wikipediaUrl,
      website: item.website,
      fetchedAt: DateTime.now(),
    );
  }

  _NearbyItem _fromNearbyPlace(NearbyPlace place) {
    return _NearbyItem(
      name: place.name,
      category: _mapCat(place.category),
      address: place.address,
      lat: place.lat,
      lng: place.lng,
      rating: place.rating,
      isLive: true,
      bookingUrl: place.bookingUrl,
      website: place.website,
      mapsUrl: place.mapsUrl,
      wikipediaUrl: place.wikipediaUrl,
    );
  }

  void _mergeItems(
    List<_NearbyItem> incoming, {
    String? message,
  }) {
    if (incoming.isEmpty) {
      if (message != null && mounted) {
        setState(() => _statusMessage = message);
      }
      return;
    }

    final merged = <_NearbyItem>[];
    final seen = <String>{};

    for (final item in [..._items, ...incoming]) {
      final name = item.name.trim();
      if (name.isEmpty) continue;

      // Do not show the current opened landmark inside its own Nearby tab.
      // Example: Khan el-Khalili page must not list Khan el-Khalili as nearby.
      if (_isCurrentPlaceItem(item)) continue;

      final key = item.dedupeKey;
      if (!seen.add(key)) continue;

      merged.add(item);
    }

    merged.sort((a, b) {
      final da = _distKm(a.lat, a.lng);
      final db = _distKm(b.lat, b.lng);

      final scoreA = _itemScore(a, da);
      final scoreB = _itemScore(b, db);

      return scoreB.compareTo(scoreA);
    });

    if (!mounted) return;

    setState(() {
      _items = merged.take(90).toList();
      if (message != null) _statusMessage = message;
    });
  }

  double _itemScore(_NearbyItem item, double distanceKm) {
    double score = 0;

    if (distanceKm > 0 && distanceKm < 999) {
      score += 40 - distanceKm.clamp(0, 40);
    }

    if (item.rating > 0) score += item.rating * 5;

    switch (item.category) {
      case 'tourist':
        score += 8;
        break;
      case 'outing':
        score += 7;
        break;
      case 'hotel':
        score += 4;
        break;
      case 'restaurant':
        score += 4;
        break;
      case 'cafe':
        score += 3;
        break;
    }

    final name = item.name.toLowerCase();
    const famous = [
      'museum',
      'tower',
      'opera',
      'palace',
      'citadel',
      'park',
      'garden',
      'mall',
      'zoo',
      'aquarium',
      'cinema',
      'متحف',
      'برج',
      'قصر',
      'حديقة',
      'مول',
      'سينما',
    ];

    if (famous.any(name.contains)) score += 4;

    return score;
  }

  List<String> _categoriesForFilter(_NearbyFilter filter) {
    switch (filter) {
      case _NearbyFilter.hotels:
        return const ['hotel'];
      case _NearbyFilter.dining:
        return const ['restaurant', 'cafe'];
      case _NearbyFilter.attractions:
        return const ['tourist'];
      case _NearbyFilter.outing:
        return const ['outing'];
      case _NearbyFilter.all:
        return const ['hotel', 'restaurant', 'cafe', 'tourist', 'outing'];
    }
  }

  String _mapCat(String raw) {
    final cat = raw.toLowerCase();

    if (cat.contains('hotel') ||
        cat.contains('resort') ||
        cat.contains('hostel') ||
        cat.contains('guest')) {
      return 'hotel';
    }

    if (cat.contains('restaurant') ||
        cat.contains('food') ||
        cat.contains('مطعم')) {
      return 'restaurant';
    }

    if (cat.contains('cafe') ||
        cat.contains('coffee') ||
        cat.contains('bakery') ||
        cat.contains('pastry') ||
        cat.contains('dessert') ||
        cat.contains('مقهى') ||
        cat.contains('كافيه')) {
      return 'cafe';
    }

    if (cat.contains('park') ||
        cat.contains('garden') ||
        cat.contains('outing') ||
        cat.contains('mall') ||
        cat.contains('cinema') ||
        cat.contains('theatre') ||
        cat.contains('zoo') ||
        cat.contains('aquarium') ||
        cat.contains('theme') ||
        cat.contains('leisure') ||
        cat.contains('حديقة') ||
        cat.contains('مول') ||
        cat.contains('سينما') ||
        cat.contains('خروجات')) {
      return 'outing';
    }

    return 'tourist';
  }

  double _distKm(double lat, double lng) {
    if (_lat == 0 || _lng == 0 || lat == 0 || lng == 0) return 9999;

    // Lightweight approximate distance in km.
    // Good enough for sorting nearby UI items.
    final dLat = (lat - _lat).abs() * 111.0;
    final dLng = (lng - _lng).abs() * 111.0;
    return dLat + dLng;
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
        return _items.where((e) => e.category == 'tourist').toList();
      case _NearbyFilter.outing:
        return _items.where((e) => e.category == 'outing').toList();
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

  Future<void> _onFilterChanged(_NearbyFilter filter) async {
    setState(() => _filter = filter);

    final currentFiltered = _filtered;

    if (currentFiltered.isEmpty && _lat != 0 && _lng != 0) {
      await _reloadFreeApis(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      (_NearbyFilter.all, 'All', Icons.grid_view_rounded),
      (_NearbyFilter.attractions, 'Attractions', Icons.photo_camera_rounded),
      (_NearbyFilter.outing, 'Outing', Icons.park_rounded),
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
                  onTap: () => _onFilterChanged(c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                        Icon(
                          c.$3,
                          size: 15,
                          color: selected ? Colors.white : _kTextMid,
                        ),
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
        if (_statusMessage != null || _checkingLive || _savingCache)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F1EB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  if (_checkingLive || _savingCache) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kBrownMed,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    const Icon(
                      Icons.sync_rounded,
                      size: 15,
                      color: _kBrownMed,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _savingCache
                          ? 'Saving nearby places...'
                          : (_statusMessage ?? 'Updating nearby places...'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kTextMid,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _checkingLive || _savingCache
                        ? null
                        : () => _reloadFreeApis(forceRefresh: true),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Reload',
                        style: TextStyle(
                          fontSize: 12,
                          color: _kBrown,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: _kBrownMed,
            onRefresh: () => _reloadFreeApis(forceRefresh: true),
            child: _loading && _items.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: _kBrownMed),
                  )
                : _filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.35,
                            child: Center(
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
                                    child: const Icon(
                                      Icons.place_rounded,
                                      size: 34,
                                      color: _kBrownMed,
                                    ),
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
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: _checkingLive || _savingCache
                                        ? null
                                        : () => _reloadFreeApis(
                                              forceRefresh: true,
                                            ),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Reload nearby places'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
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
    final raw = item.mapsUrl?.trim();
    final Uri uri;

    if (raw != null && raw.isNotEmpty) {
      uri = Uri.parse(raw);
    } else if (item.lat != 0 && item.lng != 0) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}',
      );
    } else {
      final q = Uri.encodeComponent('${item.name} $placeCity Egypt');
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }

    await _launchSafely(uri, context: context);
  }

  Future<void> _book(BuildContext context) async {
    final directBooking = item.bookingUrl?.trim();
    final website = item.website?.trim();

    if (directBooking != null && directBooking.isNotEmpty) {
      await _launchSafely(Uri.parse(directBooking), context: context);
      return;
    }

    if (website != null && website.isNotEmpty) {
      await _launchSafely(Uri.parse(website), context: context);
      return;
    }

    final q = Uri.encodeComponent('${item.name} $placeCity Egypt');
    final Uri uri;

    if (item.category == 'hotel') {
      uri = Uri.parse(
        'https://www.booking.com/searchresults.html?ss=${Uri.encodeComponent(item.name)}',
      );
    } else if (item.category == 'restaurant' || item.category == 'cafe') {
      uri = item.lat != 0 && item.lng != 0
          ? Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}',
            )
          : Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
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
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
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
                  decoration: BoxDecoration(
                    color: catBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: _kText,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: catBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              catLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: catColor,
                              ),
                            ),
                          ),
                          if (item.isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          if (item.rating > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  item.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _kTextMid,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (item.address.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 12,
                              color: _kTextLight,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                item.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: _kTextLight,
                                ),
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
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _kBorder)),
            ),
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
                        : item.category == 'restaurant' ||
                                item.category == 'cafe'
                            ? Icons.directions_rounded
                            : Icons.confirmation_number_rounded,
                    label: item.bookingUrl?.trim().isNotEmpty == true ||
                            item.website?.trim().isNotEmpty == true
                        ? 'Open Link'
                        : item.category == 'hotel'
                            ? 'Book Room'
                            : item.category == 'restaurant' ||
                                    item.category == 'cafe'
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
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
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


// ════════════════════════════════════════════════════════════════
//  BOOKING SECTION — original premium design
// ════════════════════════════════════════════════════════════════
class _PremiumBookingSection extends StatelessWidget {
  final Landmark place;
  const _PremiumBookingSection({required this.place});

  String get _encodedName => Uri.encodeComponent(place.name);
  String get _encodedCity =>
      Uri.encodeComponent(place.city.isNotEmpty ? place.city : 'Egypt');
  String get _encodedQuery =>
      Uri.encodeComponent('${place.name} ${place.city} Egypt');

  bool get _isHotel {
    final cat = place.category.toLowerCase();
    return cat.contains('hotel') ||
        cat.contains('resort') ||
        cat.contains('hostel') ||
        cat.contains('motel');
  }

  bool get _isDining {
    final cat = place.category.toLowerCase();
    return cat.contains('restaurant') ||
        cat.contains('cafe') ||
        cat.contains('coffee') ||
        cat.contains('food');
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
            features: const [
              'Free cancellation',
              'No prepayment needed',
              'Instant confirmation',
            ],
            onTap: () => _launchSafely(
              Uri.parse(
                'https://www.booking.com/searchresults.html?ss=$_encodedName',
              ),
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
            features: const [
              'Secret deals',
              'Last minute offers',
              'Member prices',
            ],
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
            features: const [
              'Open Uber app',
              'Set destination automatically',
              'Order in seconds',
            ],
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
            features: const [
              'Turn-by-turn directions',
              'View photos',
              'Read reviews',
            ],
            onTap: () {
              final Uri uri = place.lat != 0 && place.lng != 0
                  ? Uri.parse(
                      'https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lng}',
                    )
                  : Uri.parse(
                      'https://www.google.com/maps/search/?api=1&query=$_encodedQuery',
                    );
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
            features: const [
              'Traveler reviews',
              'Photos',
              'Menu info',
            ],
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
            features: const [
              'Open Uber app',
              'Set destination automatically',
              'Order in seconds',
            ],
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
            features: const [
              'Skip the line',
              'Expert guides',
              'Free cancellation',
            ],
            onTap: () => _launchSafely(
              Uri.parse(
                'https://www.viator.com/searchResults/all?text=$_encodedName+$_encodedCity',
              ),
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
            features: const [
              'Instant confirmation',
              'Mobile ticket',
              'Best guides',
            ],
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
            features: const [
              'Open Uber app',
              'Set destination automatically',
              'Order in seconds',
            ],
            onTap: () => _launchUberRide(place, context: context),
          ),
        ],
      );
}

class _BookingProviderCard extends StatefulWidget {
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
  State<_BookingProviderCard> createState() => _BookingProviderCardState();
}

class _BookingProviderCardState extends State<_BookingProviderCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _pressed ? _kBrownLight : _kCard;
    final borderColor = _pressed ? _kBrownMed.withOpacity(0.55) : _kBorder;
    final shadowOpacity = _pressed ? 0.08 : 0.025;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: _setPressed,
          splashColor: _kBrownMed.withOpacity(0.16),
          highlightColor: _kBrownMed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(shadowOpacity),
                  blurRadius: _pressed ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _pressed
                        ? widget.iconColor.withOpacity(0.16)
                        : widget.iconBg,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(widget.icon, color: widget.iconColor, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.providerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: _pressed ? _kBrown : _kText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: widget.badgeColor.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              widget.badge,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: widget.badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.tagline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.2,
                          height: 1.35,
                          color: _kTextMid,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: widget.features
                            .map(
                              (f) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _pressed
                                      ? Colors.white.withOpacity(0.75)
                                      : _kBrownLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  f,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: _kTextMid,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.payments_outlined,
                            size: 15,
                            color: _kBrownMed,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              widget.priceHint,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _kBrown,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: _pressed
                                  ? _kBrown.withOpacity(0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.open_in_new_rounded,
                              size: 17,
                              color: _kBrownMed,
                            ),
                          ),
                        ],
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
