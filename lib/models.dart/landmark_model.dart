class Landmark {
  static const int currentImagePipelineVersion = 21;

  static bool _isBadImageUrl(String url) {
    final lower = url.trim().toLowerCase();
    const genericFallbackIds = [
      'photo-1539650116574-75c0c6d73f6e',
      'photo-1503177119275-0aa32b3a9368',
      'photo-1553913861-c0fddf2619ee',
      'photo-1572252009286-268acec5ca0a',
      'photo-1518548419970-58e3b4079ab2',
      'photo-1578922746465-3a80a228f223',
      'photo-1501785888041-af3ef285b470',
      'photo-1526772662000-3f88f10405ff',
      'photo-1500530855697-b586d89ba3ee',
      'photo-1505761671935-60b3a7427bad',
      'photo-1491553895911-0055eca6402d',
      'photo-1476514525535-07fb3b4ae5f1',
    ];

    if (genericFallbackIds.any(lower.contains)) return true;

    return lower.contains('source.unsplash.com') ||
        lower.contains('.pdf') ||
        lower.contains('.svg') ||
        lower.contains('.gif') ||
        lower.contains('.tif') ||
        lower.contains('.tiff') ||
        lower.contains('/wiki/file:') ||
        lower.contains('special:') ||
        lower.endsWith('.html');
  }

  static bool _isSafeImageUrl(String url) {
    final clean = url.trim();
    final lower = clean.toLowerCase();
    return clean.isNotEmpty &&
        (lower.startsWith('http://') || lower.startsWith('https://')) &&
        !_isBadImageUrl(clean);
  }

  final String id;
  final String name;
  final String cityId;
  final String city;
  final String category;
  final String description;
  final String shortDescription;
  final String fullDescription;
  final String history;
  final String imageUrl;
  final List<String> mediaUrls;
  final int imagePipelineVersion;
  final bool imagesAreFallback;
  final double lat;
  final double lng;
  final String address;
  final double rating;
  final String openingHours;
  final String location;
  final String? ticketPrice;
  final String? wikipediaUrl;
  final DateTime? createdAt;

  // tracking
  final DateTime? wikiEnrichedAt;
  final DateTime? imagesRefreshedAt;
  final DateTime? nearbyUpdatedAt;

  final List<Map<String, dynamic>> nearbyPlaces;
  final Map<String, dynamic>? sources;

  const Landmark({
    required this.id,
    required this.name,
    required this.cityId,
    required this.city,
    required this.category,
    required this.description,
    required this.shortDescription,
    required this.fullDescription,
    required this.history,
    required this.imageUrl,
    required this.mediaUrls,
    this.imagePipelineVersion = currentImagePipelineVersion,
    this.imagesAreFallback = false,
    required this.lat,
    required this.lng,
    required this.address,
    required this.rating,
    required this.openingHours,
    required this.location,
    this.ticketPrice,
    this.wikipediaUrl,
    this.createdAt,
    this.wikiEnrichedAt,
    this.imagesRefreshedAt,
    this.nearbyUpdatedAt,
    this.sources,
    this.nearbyPlaces = const [],
  });

  factory Landmark.fromJson(Map<String, dynamic> json, String id) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    int parseInt(dynamic value, [int fallback = currentImagePipelineVersion]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? fallback;
    }

    final storedImageVersion = parseInt(
      json['imagePipelineVersion'],
      currentImagePipelineVersion,
    );
    final storedImagesAreFallback =
        (json['imagesAreFallback'] ?? false).toString().toLowerCase() == 'true';
    final allowStoredImages =
        storedImageVersion == currentImagePipelineVersion;

    final rawImage = allowStoredImages
        ? (json['imageUrl'] ?? '').toString().trim()
        : '';
    final image = _isSafeImageUrl(rawImage) ? rawImage : '';

    final media = allowStoredImages
        ? List<String>.from(json['mediaUrls'] ?? const [])
            .map((e) => e.toString().trim())
            .where(_isSafeImageUrl)
            .toList()
        : <String>[];

    if (image.isNotEmpty && !media.contains(image)) {
      media.insert(0, image);
    }

    final description = (json['description'] ?? '').toString().trim();
    final shortDescription = (json['shortDescription'] ?? '').toString().trim();
    final fullDescription = (json['fullDescription'] ?? '').toString().trim();

    final normalizedShort = shortDescription.isNotEmpty
        ? shortDescription
        : (description.isNotEmpty ? description : fullDescription);

    final normalizedDescription = description.isNotEmpty
        ? description
        : normalizedShort;

    final nearbyRaw = List<Map<String, dynamic>>.from(
      json['nearbyPlaces'] ?? const [],
    );

    final nearbyNormalized = nearbyRaw
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final rawSources = json['sources'];
    final normalizedSources = rawSources is Map
        ? Map<String, dynamic>.from(rawSources)
        : null;

    return Landmark(
      id: id,
      name: (json['name'] ?? '').toString().trim(),
      cityId: (json['cityId'] ?? '').toString().trim(),
      city: (json['city'] ?? '').toString().trim(),
      category: (json['category'] ?? 'tourist').toString().trim(),
      description: normalizedDescription,
      shortDescription: normalizedShort,
      fullDescription: fullDescription,
      history: (json['history'] ?? '').toString().trim(),
      imageUrl: image,
      mediaUrls: media.take(6).toList(),
      imagePipelineVersion: storedImageVersion,
      imagesAreFallback: storedImagesAreFallback,
      lat: ((json['lat'] ?? 0) as num).toDouble(),
      lng: ((json['lng'] ?? 0) as num).toDouble(),
      address: (json['address'] ?? '').toString().trim(),
      rating: ((json['rating'] ?? 0) as num).toDouble(),
      openingHours: (json['openingHours'] ?? '').toString().trim(),
      location: (json['location'] ?? '').toString().trim(),
      ticketPrice: json['ticketPrice']?.toString(),
      wikipediaUrl: json['wikipediaUrl']?.toString().trim(),
      createdAt: parseDate(json['createdAt']),
      wikiEnrichedAt: parseDate(json['wikiEnrichedAt']),
      imagesRefreshedAt: parseDate(json['imagesRefreshedAt']),
      nearbyUpdatedAt: parseDate(json['nearbyUpdatedAt']),
      nearbyPlaces: nearbyNormalized,
      sources: normalizedSources,
    );
  }

  Map<String, dynamic> toJson() {
    final media = <String>[];
    final seen = <String>{};

    void add(String url) {
      final clean = url.trim();
      if (_isSafeImageUrl(clean) && seen.add(clean)) {
        media.add(clean);
      }
    }

    add(imageUrl);
    for (final url in mediaUrls) {
      add(url);
    }

    return {
      'name': name.trim(),
      'cityId': cityId.trim(),
      'city': city.trim(),
      'category': category.trim().isNotEmpty ? category.trim() : 'tourist',
      'description': description.trim(),
      'shortDescription': shortDescription.trim(),
      'fullDescription': fullDescription.trim(),
      'history': history.trim(),
      'imageUrl': media.isNotEmpty ? media.first : '',
      'mediaUrls': media.take(6).toList(),
      'imagePipelineVersion': imagePipelineVersion,
      'imagesAreFallback': imagesAreFallback,
      'lat': lat,
      'lng': lng,
      'address': address.trim(),
      'rating': rating,
      'openingHours': openingHours.trim(),
      'location': location.trim(),
      'ticketPrice': ticketPrice,
      'wikipediaUrl': wikipediaUrl?.trim(),
      'createdAt': createdAt?.toIso8601String(),
      'wikiEnrichedAt': wikiEnrichedAt?.toIso8601String(),
      'imagesRefreshedAt': imagesRefreshedAt?.toIso8601String(),
      'nearbyUpdatedAt': nearbyUpdatedAt?.toIso8601String(),
      'nearbyPlaces': nearbyPlaces
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      'sources': sources ?? <String, dynamic>{},
    };
  }

  Landmark copyWith({
    String? id,
    String? name,
    String? cityId,
    String? city,
    String? category,
    String? description,
    String? shortDescription,
    String? fullDescription,
    String? history,
    String? imageUrl,
    List<String>? mediaUrls,
    int? imagePipelineVersion,
    bool? imagesAreFallback,
    double? lat,
    double? lng,
    String? address,
    double? rating,
    String? openingHours,
    String? location,
    String? ticketPrice,
    String? wikipediaUrl,
    DateTime? createdAt,
    DateTime? wikiEnrichedAt,
    DateTime? imagesRefreshedAt,
    DateTime? nearbyUpdatedAt,
    List<Map<String, dynamic>>? nearbyPlaces,
    Map<String, dynamic>? sources,
  }) {
    final nextDescription = description ?? this.description;
    final nextShort = shortDescription ?? this.shortDescription;

    return Landmark(
      id: id ?? this.id,
      name: name ?? this.name,
      cityId: cityId ?? this.cityId,
      city: city ?? this.city,
      category: category ?? this.category,
      description: nextDescription,
      shortDescription: nextShort,
      fullDescription: fullDescription ?? this.fullDescription,
      history: history ?? this.history,
      imageUrl: imageUrl ?? this.imageUrl,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      imagePipelineVersion: imagePipelineVersion ?? this.imagePipelineVersion,
      imagesAreFallback: imagesAreFallback ?? this.imagesAreFallback,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      address: address ?? this.address,
      rating: rating ?? this.rating,
      openingHours: openingHours ?? this.openingHours,
      location: location ?? this.location,
      ticketPrice: ticketPrice ?? this.ticketPrice,
      wikipediaUrl: wikipediaUrl ?? this.wikipediaUrl,
      createdAt: createdAt ?? this.createdAt,
      wikiEnrichedAt: wikiEnrichedAt ?? this.wikiEnrichedAt,
      imagesRefreshedAt: imagesRefreshedAt ?? this.imagesRefreshedAt,
      nearbyUpdatedAt: nearbyUpdatedAt ?? this.nearbyUpdatedAt,
      nearbyPlaces: nearbyPlaces ?? this.nearbyPlaces,
      sources: sources ?? this.sources,
    );
  }

  bool get hasImages =>
      _isSafeImageUrl(imageUrl) || mediaUrls.any(_isSafeImageUrl);

  bool get hasWikipedia =>
      wikipediaUrl != null && wikipediaUrl!.trim().isNotEmpty;

  bool get hasValidCoordinates => lat != 0 && lng != 0;
}