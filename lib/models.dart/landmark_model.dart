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
  final String displayName;
  final String normalizedName;
  final List<String> aliases;
  final bool generatedBySearch;
  final DateTime? updatedAt;
  final DateTime? nearbyRefreshedAt;
  final DateTime? imagesFailedAt;
  final String imagesFailureReason;
  final DateTime? nearbyFailedAt;
  final String nearbyFailureReason;

  // tracking
  final DateTime? wikiEnrichedAt;
  final DateTime? imagesRefreshedAt;
  final DateTime? nearbyUpdatedAt;

  /// Set when automated validation rejects stored artwork (portrait/unrelated).
  final DateTime? imageRejectedAt;
  final String imageRejectedReason;
  /// When true, [fromJson] omits unsafe hero images until re-enriched.
  final bool imageNeedsReview;

  /// When true, the app should hide this row from city/search lists.
  final bool hidden;

  /// When true, this document is a duplicate of [duplicateOf] and should
  /// not be shown in city/search lists.
  final bool isDuplicate;

  /// Id of the best kept duplicate document (when [isDuplicate] is true).
  final String duplicateOf;

  /// Marks the row as suspicious/random/invalid. Hidden by default.
  final bool invalidPlace;
  final String invalidReason;

  /// Generic review flag (used by invalid/city/outting validation).
  final bool needsReview;

  /// When [category] == `outing`, indicates the entry might not be
  /// visitor-friendly. Hidden by default when set.
  final bool outingNeedsReview;
  final String outingNeedsReviewReason;

  /// When city assignment could not be verified confidently.
  final bool cityNeedsReview;
  final String cityReviewReason;

  /// Timestamp when imageUrls/mediaUrls were validated during cleanup.
  final DateTime? imagesValidatedAt;

  /// Timestamp when Firestore landmark data was validated/cleaned.
  final DateTime? dataValidatedAt;

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
    this.displayName = '',
    this.normalizedName = '',
    this.aliases = const [],
    this.generatedBySearch = false,
    this.updatedAt,
    this.nearbyRefreshedAt,
    this.imagesFailedAt,
    this.imagesFailureReason = '',
    this.nearbyFailedAt,
    this.nearbyFailureReason = '',
    this.wikiEnrichedAt,
    this.imagesRefreshedAt,
    this.nearbyUpdatedAt,
    this.imageRejectedAt,
    this.imageRejectedReason = '',
    this.imageNeedsReview = false,
    this.hidden = false,
    this.isDuplicate = false,
    this.duplicateOf = '',
    this.invalidPlace = false,
    this.invalidReason = '',
    this.needsReview = false,
    this.outingNeedsReview = false,
    this.outingNeedsReviewReason = '',
    this.cityNeedsReview = false,
    this.cityReviewReason = '',
    this.imagesValidatedAt,
    this.dataValidatedAt,
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

    final imageRejectedAtEarly = parseDate(json['imageRejectedAt']);
    final imageNeedsReviewEarly =
        (json['imageNeedsReview'] ?? false).toString().toLowerCase() == 'true';
    final stripImagesForReview = imageNeedsReviewEarly ||
        (imageRejectedAtEarly != null &&
            (json['imageRejectedReason'] ?? '').toString().trim().isNotEmpty);

    final rawImage = allowStoredImages && !stripImagesForReview
        ? (json['imageUrl'] ?? '').toString().trim()
        : '';
    final image = _isSafeImageUrl(rawImage) ? rawImage : '';

    final media = allowStoredImages && !stripImagesForReview
        ? List<String>.from(json['mediaUrls'] ?? const [])
            .map((e) => e.toString().trim())
            .where(_isSafeImageUrl)
            .toList()
        : <String>[];

    if (!stripImagesForReview && image.isNotEmpty && !media.contains(image)) {
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

    final aliasesRaw = json['aliases'];
    final aliasesList = aliasesRaw is List
        ? aliasesRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : const <String>[];

    final genFlag =
        (json['generatedBySearch'] ?? false).toString().toLowerCase() == 'true';

    final imageRejectedAt = imageRejectedAtEarly;
    final imageNeedsReview = imageNeedsReviewEarly;

    final hidden = (json['hidden'] ?? false).toString().toLowerCase() == 'true';
    final isDuplicate =
        (json['isDuplicate'] ?? false).toString().toLowerCase() == 'true';
    final duplicateOf = (json['duplicateOf'] ?? '').toString().trim();
    final invalidPlace =
        (json['invalidPlace'] ?? false).toString().toLowerCase() == 'true';
    final invalidReason = (json['invalidReason'] ?? '').toString().trim();
    final needsReview =
        (json['needsReview'] ?? false).toString().toLowerCase() == 'true';
    final outingNeedsReview = (json['outingNeedsReview'] ?? false).toString().toLowerCase() == 'true';
    final outingNeedsReviewReason =
        (json['outingNeedsReviewReason'] ?? '').toString().trim();
    final cityNeedsReview =
        (json['cityNeedsReview'] ?? false).toString().toLowerCase() == 'true';
    final cityReviewReason =
        (json['cityReviewReason'] ?? '').toString().trim();

    final imagesValidatedAt = parseDate(json['imagesValidatedAt']);
    final dataValidatedAt = parseDate(json['dataValidatedAt']);

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
      displayName: (json['displayName'] ?? '').toString().trim(),
      normalizedName: (json['normalizedName'] ?? '').toString().trim(),
      aliases: aliasesList,
      generatedBySearch: genFlag,
      updatedAt: parseDate(json['updatedAt']),
      nearbyRefreshedAt: parseDate(json['nearbyRefreshedAt']),
      imagesFailedAt: parseDate(json['imagesFailedAt']),
      imagesFailureReason: (json['imagesFailureReason'] ?? '').toString(),
      nearbyFailedAt: parseDate(json['nearbyFailedAt']),
      nearbyFailureReason: (json['nearbyFailureReason'] ?? '').toString(),
      wikiEnrichedAt: parseDate(json['wikiEnrichedAt']),
      imagesRefreshedAt: parseDate(json['imagesRefreshedAt']),
      nearbyUpdatedAt: parseDate(json['nearbyUpdatedAt']),
      imageRejectedAt: imageRejectedAt,
      imageRejectedReason: (json['imageRejectedReason'] ?? '').toString().trim(),
      imageNeedsReview: imageNeedsReview,
      hidden: hidden,
      isDuplicate: isDuplicate,
      duplicateOf: duplicateOf,
      invalidPlace: invalidPlace,
      invalidReason: invalidReason,
      needsReview: needsReview,
      outingNeedsReview: outingNeedsReview,
      outingNeedsReviewReason: outingNeedsReviewReason,
      cityNeedsReview: cityNeedsReview,
      cityReviewReason: cityReviewReason,
      imagesValidatedAt: imagesValidatedAt,
      dataValidatedAt: dataValidatedAt,
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
      'displayName': displayName.trim(),
      'normalizedName': normalizedName.trim(),
      'aliases': aliases,
      'generatedBySearch': generatedBySearch,
      'updatedAt': updatedAt?.toIso8601String(),
      'nearbyRefreshedAt': nearbyRefreshedAt?.toIso8601String(),
      'imagesFailedAt': imagesFailedAt?.toIso8601String(),
      'imagesFailureReason': imagesFailureReason.trim(),
      'nearbyFailedAt': nearbyFailedAt?.toIso8601String(),
      'nearbyFailureReason': nearbyFailureReason.trim(),
      'wikiEnrichedAt': wikiEnrichedAt?.toIso8601String(),
      'imagesRefreshedAt': imagesRefreshedAt?.toIso8601String(),
      'nearbyUpdatedAt': nearbyUpdatedAt?.toIso8601String(),
      'imageRejectedAt': imageRejectedAt?.toIso8601String(),
      'imageRejectedReason': imageRejectedReason.trim(),
      'imageNeedsReview': imageNeedsReview,
      'hidden': hidden,
      'isDuplicate': isDuplicate,
      'duplicateOf': duplicateOf.trim(),
      'invalidPlace': invalidPlace,
      'invalidReason': invalidReason.trim(),
      'needsReview': needsReview,
      'outingNeedsReview': outingNeedsReview,
      'outingNeedsReviewReason': outingNeedsReviewReason.trim(),
      'cityNeedsReview': cityNeedsReview,
      'cityReviewReason': cityReviewReason.trim(),
      'imagesValidatedAt': imagesValidatedAt?.toIso8601String(),
      'dataValidatedAt': dataValidatedAt?.toIso8601String(),
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
    String? displayName,
    String? normalizedName,
    List<String>? aliases,
    bool? generatedBySearch,
    DateTime? updatedAt,
    DateTime? nearbyRefreshedAt,
    DateTime? imagesFailedAt,
    String? imagesFailureReason,
    DateTime? nearbyFailedAt,
    String? nearbyFailureReason,
    DateTime? wikiEnrichedAt,
    DateTime? imagesRefreshedAt,
    DateTime? nearbyUpdatedAt,
    DateTime? imageRejectedAt,
    String? imageRejectedReason,
    bool? imageNeedsReview,
    bool? hidden,
    bool? isDuplicate,
    String? duplicateOf,
    bool? invalidPlace,
    String? invalidReason,
    bool? needsReview,
    bool? outingNeedsReview,
    String? outingNeedsReviewReason,
    bool? cityNeedsReview,
    String? cityReviewReason,
    DateTime? imagesValidatedAt,
    DateTime? dataValidatedAt,
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
      displayName: displayName ?? this.displayName,
      normalizedName: normalizedName ?? this.normalizedName,
      aliases: aliases ?? this.aliases,
      generatedBySearch: generatedBySearch ?? this.generatedBySearch,
      updatedAt: updatedAt ?? this.updatedAt,
      nearbyRefreshedAt: nearbyRefreshedAt ?? this.nearbyRefreshedAt,
      imagesFailedAt: imagesFailedAt ?? this.imagesFailedAt,
      imagesFailureReason: imagesFailureReason ?? this.imagesFailureReason,
      nearbyFailedAt: nearbyFailedAt ?? this.nearbyFailedAt,
      nearbyFailureReason: nearbyFailureReason ?? this.nearbyFailureReason,
      wikiEnrichedAt: wikiEnrichedAt ?? this.wikiEnrichedAt,
      imagesRefreshedAt: imagesRefreshedAt ?? this.imagesRefreshedAt,
      nearbyUpdatedAt: nearbyUpdatedAt ?? this.nearbyUpdatedAt,
      imageRejectedAt: imageRejectedAt ?? this.imageRejectedAt,
      imageRejectedReason: imageRejectedReason ?? this.imageRejectedReason,
      imageNeedsReview: imageNeedsReview ?? this.imageNeedsReview,
      hidden: hidden ?? this.hidden,
      isDuplicate: isDuplicate ?? this.isDuplicate,
      duplicateOf: duplicateOf ?? this.duplicateOf,
      invalidPlace: invalidPlace ?? this.invalidPlace,
      invalidReason: invalidReason ?? this.invalidReason,
      needsReview: needsReview ?? this.needsReview,
      outingNeedsReview: outingNeedsReview ?? this.outingNeedsReview,
      outingNeedsReviewReason:
          outingNeedsReviewReason ?? this.outingNeedsReviewReason,
      cityNeedsReview: cityNeedsReview ?? this.cityNeedsReview,
      cityReviewReason: cityReviewReason ?? this.cityReviewReason,
      imagesValidatedAt: imagesValidatedAt ?? this.imagesValidatedAt,
      dataValidatedAt: dataValidatedAt ?? this.dataValidatedAt,
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