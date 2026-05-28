part of 'home.dart';

final Set<String> _homeBackgroundGenerationKeys = <String>{};

extension _HomeLogicSections on _HomeState {
  // ════════════════════════════════════════════════════════
  //  DATA LOADING
  // ════════════════════════════════════════════════════════

  void _onAdminPlaceChanged(Landmark fresh) {
    if (!mounted || fresh.id.trim().isEmpty) return;

    final normalizedFresh = _withClearCardName(fresh);

    List<Landmark> mergeInto(
      List<Landmark> current, {
      required String? cityName,
      required bool onlyIfBelongsToSelectedCity,
    }) {
      if (onlyIfBelongsToSelectedCity && _selectedCity != null) {
        if (!_landmarkMatchesCity(normalizedFresh, _selectedCity!)) {
          return current;
        }
      }

      var replaced = false;
      final merged = <Landmark>[];

      for (final item in current) {
        if (_sameVisiblePlace(item, normalizedFresh)) {
          if (!replaced) {
            merged.add(normalizedFresh);
            replaced = true;
          }
          continue;
        }
        merged.add(item);
      }

      if (!replaced && _isGoodHomeCardPlace(normalizedFresh)) {
        merged.insert(0, normalizedFresh);
      }

      return _sortForHome(
        _preferFirestoreOverSeeds(merged),
        cityName: cityName,
      );
    }

    setState(() {
      _allLandmarks = mergeInto(
        _allLandmarks,
        cityName: null,
        onlyIfBelongsToSelectedCity: false,
      );

      if (_selectedCity != null) {
        _cityLandmarks = mergeInto(
          _cityLandmarks,
          cityName: _selectedCity!.name,
          onlyIfBelongsToSelectedCity: true,
        );
      }

      if (_searchActive) {
        _searchResults = mergeInto(
          _searchResults,
          cityName: _selectedCity?.name,
          onlyIfBelongsToSelectedCity: false,
        );
      }
    });

    if (kDebugMode) {
      debugPrint(
        '[HomeApplyAdminPlaceChange] id=${normalizedFresh.id} '
        'name=${normalizedFresh.name} image=${normalizedFresh.imageUrl}',
      );
    }
  }


  Future<void> _loadAllLandmarks() async {
    try {
      final all = await _repo.loadAll();
      if (!mounted) return;

      final storedOnly = _prepareHomePlaces(all);
      final placesToShow = storedOnly.isNotEmpty
          ? storedOnly
          : _localEgyptSeedPlaces();

      setState(() {
        // Show database/local seed data immediately.
        // Never block Home rendering waiting for external APIs.
        _allLandmarks = _sortForHome(
          _prepareHomePlaces(placesToShow),
          cityName: null,
        );
        _homeLoading = false;
        _homeLoadFailed = false;

        final selected = _selectedCity;
        if (selected != null) {
          final matching = _landmarksForCity(_allLandmarks, selected);
          if (matching.isNotEmpty) {
            _cityLandmarks = _sortForHome(
              _prepareHomePlaces([
                ..._landmarksForCity(_cityLandmarks, selected),
                ...matching,
              ]),
              cityName: selected.name,
            );
          }
        }
      });

      // If Firebase is totally empty, persist curated local seed cards once.
      // This is not API generation; it only makes the next launch faster.
      if (storedOnly.isEmpty) {
        unawaited(_persistHomePlacesInBackground(
          _localEgyptSeedPlaces(),
          reason: 'initial_local_egypt_seeds_when_empty',
        ));
      }

      // Do not run broad "All Egypt" API generation on cold start; it is heavy
      // and unrelated to the user's current city. City pages trigger their own
      // guarded background fill when needed.
    } catch (e) {
      print('[Home] loadAll error: $e');
      if (mounted) {
        setState(() {
          _homeLoading = false;
          _homeLoadFailed = true;
        });
      }
    }
  }

  Future<void> _loadCityLandmarks(
    City city, {
    bool forceRefresh = false,
  }) async {
    final currentCityOnly = _landmarksForCity(_cityLandmarks, city);

    if (!forceRefresh &&
        _lastCityId == city.id &&
        currentCityOnly.isNotEmpty &&
        currentCityOnly.length == _cityLandmarks.length) {
      return;
    }

    _resetSearch();

    // 1) Instant UI from memory/Firebase/local famous seeds.
    final instantStored = _sortForHome(
      _prepareHomePlaces([
        ..._landmarksForCity(_allLandmarks, city),
        ..._localSeedPlacesForCity(city.name),
      ]),
      cityName: city.name,
    );

    setState(() {
      _selectedCity = city;
      _lastCityId = city.id;
      _homeLoading = instantStored.isEmpty;
      _homeLoadFailed = false;
      _cityLandmarks = instantStored;
    });

    // Persist local famous seeds only as a safety net, without blocking UI.
    if (instantStored.isNotEmpty) {
      unawaited(_persistHomePlacesInBackground(
        instantStored,
        defaultCity: city,
        reason: 'instant_city_seeds_${city.name}',
      ));
    }

    try {
      // 2) Load database data. Use cityId + city-name fallback because older
      // generated docs may have an empty/wrong cityId but correct city/address.
      final cachedById = await _repo.loadCity(city.id);
      final all = await _repo.loadAll();
      if (!mounted) return;

      final cleanedAll = _prepareHomePlaces([
        ...all,
        ..._localEgyptSeedPlaces(),
      ]);
      final fallbackByName = _landmarksForCity(cleanedAll, city);
      final storedCityPlaces = _sortForHome(
        _prepareHomePlaces([
          ...cachedById,
          ...fallbackByName,
          ...instantStored,
        ]),
        cityName: city.name,
      );

      if (_selectedCity?.id == city.id) {
        setState(() {
          _allLandmarks = _sortForHome(cleanedAll, cityName: null);
          _cityLandmarks = storedCityPlaces;
          _homeLoading = false;
          _homeLoadFailed = false;
        });
      }

      // 3) Smart background generation. It runs only when famous tourist/outing
      // places are missing, and only once per city in this app session unless
      // forceRefresh=true.
      // TEMP DEMO SAFE MODE:
// Disable background generation before discussion to prevent wrong city data
// and save Firebase quota.
// if (forceRefresh || _shouldGenerateCityHighlights(storedCityPlaces, city)) {
//   unawaited(Future<void>.delayed(
//     const Duration(milliseconds: 750),
//     () => _refreshCityTouristPlacesInBackground(city, force: forceRefresh),
//   ));
// }
    } catch (e) {
      print('[Home] loadCity error: $e');
      if (mounted) {
        setState(() {
          _homeLoading = false;
          _homeLoadFailed = true;
        });
      }
    }
  }

  Future<void> _refreshCityTouristPlacesInBackground(
    City city, {
    bool force = false,
  }) async {
    final key = 'city_highlights_${_normalizeCityText(city.name)}';
    if (!force && !_homeBackgroundGenerationKeys.add(key)) {
      print('[Home] skip duplicate background tourist generation for ${city.name}');
      return;
    }

    try {
      print('[Home] background tourist/outing generation started for ${city.name}');
      final before = _prepareHomePlaces([
        ..._landmarksForCity(_cityLandmarks, city),
        ..._landmarksForCity(_allLandmarks, city),
      ]);

      final generated = await _loadTouristPlacesForCity(city.name);
      if (!mounted || generated.isEmpty) return;
      if (_selectedCity?.id != city.id) return;

      final missingOnly = _onlyMissingPlaces(generated, before);
      final valid = _touristAndOutingOnly(missingOnly);
      if (valid.isEmpty) return;

      unawaited(_persistHomePlacesInBackground(
        valid,
        defaultCity: city,
        reason: 'city_missing_tourist_outing_generated_${city.name}',
      ));

      setState(() {
        _cityLandmarks = _sortForHome(
          _prepareHomePlaces([
            ..._landmarksForCity(_cityLandmarks, city),
            ..._landmarksForCity(valid, city),
          ]),
          cityName: city.name,
        );
        _allLandmarks = _sortForHome(
          _prepareHomePlaces([..._allLandmarks, ...valid]),
          cityName: null,
        );
      });

      print('[Home] background tourist/outing generation done for ${city.name}: ${valid.length}');
    } catch (e) {
      print('[Home] background tourist generation error for ${city.name}: $e');
    }
  }

  Future<void> _refreshCityInBackground(City city) async {
    try {
      print('[Home] background refresh started for ${city.name}');

      final refreshed = await AppInjector.pipeline.fetchOrLoadLandmarks(
        city,
        forceRefresh: true,
        onProgress: (msg) => print('[Pipeline] $msg'),
      );

      if (!mounted) return;
      if (_selectedCity?.id != city.id) return;

      final valid = _filterAndDedup(refreshed);
      if (valid.isEmpty) return;

      setState(() {
        _cityLandmarks = _filterAndDedup([
          ..._landmarksForCity(valid, city),
          ..._landmarksForCity(_cityLandmarks, city),
        ]);
        _allLandmarks = _filterAndDedup([...valid, ..._allLandmarks]);
      });

      unawaited(_loadAllLandmarks());
      print('[Home] background refresh done: ${valid.length} places');
    } catch (e) {
      print('[Home] background refresh error: $e');
    }
  }

  Future<void> _refreshHomeAndScrollTop() async {
    try {
      if (_pageScrollCtrl.hasClients) {
        await _pageScrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }

      print('[Home] bottom nav refresh tapped');

      if (_selectedCity != null) {
        final city = _selectedCity!;
        _lastCityId = null;
        await _loadCityLandmarks(city, forceRefresh: true);
      } else {
        _resetSearch();
        context.read<UserCubit>().getAllCities();
        await _loadAllLandmarks();
      }
    } catch (e) {
      print('[Home] refresh home error: $e');
    }
  }

  // ════════════════════════════════════════════════════════
  //  SEARCH
  // ════════════════════════════════════════════════════════

  void _onSearchChanged(String value) {
    final trimmed = value.trim();
    setState(() => _searchQuery = trimmed);

    _suggestionDebounce?.cancel();

    if (trimmed.isEmpty) {
      setState(() {
        _fetchingSuggestions = false;
        _suggestions = [];
      });
      return;
    }

    _suggestionDebounce = Timer(const Duration(milliseconds: 260), () async {
      await _fetchSuggestions(trimmed);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _fetchingSuggestions = true);
    try {
      final hints = await _search.getHints(
        query,
        // Hints should also work across Egypt. The selected city is only a
        // filter after the user submits a generic category query.
        cityName: null,
      );
      if (!mounted) return;
      if (_searchCtrl.text.trim() != query.trim()) return;
      setState(() {
        _suggestions = hints;
        _fetchingSuggestions = false;
      });
    } catch (_) {
      if (mounted) setState(() => _fetchingSuggestions = false);
    }
  }

  Future<void> _onSearchSubmitted(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    _suggestionDebounce?.cancel();

    setState(() {
      _searchQuery = trimmed;
      _correctedQuery = trimmed;
      _searchActive = true;
      _searching = true;
      _searchResults = [];
      _suggestions = [];
    });

    try {
      final result = await _search.searchPlaces(
        query: trimmed,
        cityId: _selectedCity?.id,
        cityName: _selectedCity?.name,
        maxResults: 12,
      );

      if (!mounted) return;

      // Search must depend on Firebase/SearchEngine results only.
      // If Firebase has no match, SearchEngine will generate/load the place.
      // Do NOT fall back to local seeds here, because local_seed_* cards are
      // not real Firebase docs and should not appear as search results.
      final exactResults = _filterAndDedup(
        _preferFirestoreOverSeeds([
          ...result.results,
        ]),
      );

      final contextCity = _cityForSearch(
        detectedCity: result.detectedCity,
        cityIntent: result.cityIntent,
        results: exactResults,
        query: trimmed,
      );

      final isCategorySearch = result.isGenericCategoryQuery;

      final categoryExactResults = isCategorySearch
          ? _onlySearchCategory(exactResults, result.detectedCategory)
          : exactResults;

      // Show city context only for named-place searches.
      // Example: "Cairo Tower" => Cairo Tower + tourist/outing places.
      // Category searches like "cafes in Cairo" must show only cafes.
      final shouldShowCityContext =
          !isCategorySearch && contextCity != null && categoryExactResults.isNotEmpty;

      final localContext = shouldShowCityContext
          ? _searchContextPlacesForCity(contextCity, categoryExactResults)
          : const <Landmark>[];

      final displayResults = shouldShowCityContext
          ? _sortSearchResultsWithCityContext(
              exactResults: categoryExactResults,
              contextPlaces: localContext,
              query: trimmed,
              city: contextCity,
            )
          : (_filterAndDedup(categoryExactResults)
                ..sort(
                  (a, b) =>
                      _searchCardScore(b).compareTo(_searchCardScore(a)),
                ))
              .take(12)
              .toList();

      if (kDebugMode) {
        debugPrint(
          '[Home] search query="$trimmed" '
          'exact=${categoryExactResults.length} '
          'context=${localContext.length} '
          'display=${displayResults.length} '
          'showCityContext=$shouldShowCityContext '
          'isCategorySearch=$isCategorySearch '
          'city=${contextCity?.name ?? 'unknown'}',
        );
      }

      final persistableExactResults =
          categoryExactResults.where((lm) => !_isLocalSeedPlace(lm)).toList();
      final persistablePlaces = _filterAndDedup(persistableExactResults);

      if (persistablePlaces.isNotEmpty) {
        // Save only the real results of the submitted search.
        // Do not persist local seeds or city-context cards from this flow.
        unawaited(_persistHomePlacesInBackground(
          persistablePlaces,
          defaultCity: contextCity,
          reason: 'search_saved_to_real_city_${_normalizeCityText(trimmed)}',
        ));
      }

      setState(() {
        _correctedQuery = result.correctedQuery;
        _searchResults = displayResults;
        _suggestions = result.suggestions;
        _searching = false;
        _searchActive = true;

        if (displayResults.isNotEmpty) {
          _allLandmarks = _sortForHome(
            _prepareHomePlaces([...displayResults, ..._allLandmarks]),
            cityName: null,
          );
        }

        if (contextCity != null) {
          _selectedCity = contextCity;
          _lastCityId = contextCity.id;

          _cityLandmarks = _sortForHome(
            _prepareHomePlaces([
              ...displayResults,
              ...localContext,
              ..._landmarksForCity(_allLandmarks, contextCity),
              ..._localSeedPlacesForCity(contextCity.name),
            ]),
            cityName: contextCity.name,
          );
        }
      });

      if (shouldShowCityContext &&
          _searchContextPlacesForCity(contextCity, categoryExactResults).length < 6) {
        unawaited(_refreshSearchCityContextInBackground(
          city: contextCity,
          exactResults: categoryExactResults,
          query: trimmed,
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Home] search error: $e');
      }
      if (mounted) {
        setState(() {
          _searchResults = [];
          _searching = false;
        });
      }
    }
  }

  List<Landmark> _onlySearchCategory(
    List<Landmark> items,
    String? category,
  ) {
    final normalizedCategory = PlaceCategoryNormalizer.normalize(
      category ?? '',
    );

    if (normalizedCategory.trim().isEmpty ||
        !PlaceCategoryNormalizer.allowed.contains(normalizedCategory)) {
      return _filterAndDedup(items);
    }

    return _filterAndDedup(items).where((lm) {
      final cat = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
      );
      return cat == normalizedCategory;
    }).toList();
  }

  List<Landmark> _localExactMatchesForQuery(String query) {
    final q = _normalizeCityText(query);
    if (q.isEmpty) return const [];

    final seeds = _localEgyptSeedPlaces();

    bool matches(Landmark lm) {
      final name = _normalizeCityText(_clearDisplayName(lm.name));

      if (name == q || name.contains(q) || q.contains(name)) return true;

      final aliases = <String, List<String>>{
        'great pyramid of giza': [
          'great pyramid',
          'great pyramid of giza',
          'pyramids',
          'pyramid',
          'giza pyramids',
          'giza pyramid',
          'pyramids of giza',
          'الأهرامات',
          'الاهرامات',
          'اهرامات',
          'أهرامات',
          'اهرامات الجيزة',
          'أهرامات الجيزة',
          'الهرم',
          'هرم الجيزة',
        ],
        'great sphinx of giza': [
          'sphinx',
          'giza sphinx',
          'ابو الهول',
          'أبو الهول',
        ],
        'valley of the kings': [
          'valley kings',
          'king valley',
          'وادي الملوك',
          'وادى الملوك',
        ],
        'karnak temple': ['karnak', 'الكرنك'],
        'luxor temple': ['luxor temple', 'معبد الأقصر', 'معبد الاقصر'],
        'temple of hatshepsut': ['hatshepsut', 'حتشبسوت', 'الدير البحري'],
        'abu simbel temples': ['abu simbel', 'أبو سمبل', 'ابو سمبل'],
        'philae temple': ['philae', 'فيلة', 'فيله'],
        'bibliotheca alexandrina': [
          'alexandria library',
          'مكتبة الاسكندرية',
          'مكتبة الإسكندرية',
        ],
        'citadel of qaitbay': ['qaitbay', 'قلعة قايتباي'],
        'khan el khalili': ['khan', 'khalili', 'خان الخليلي'],
      };

      final lmAliases = aliases[name] ?? const <String>[];
      return lmAliases.any((a) {
        final alias = _normalizeCityText(a);
        return alias == q || alias.contains(q) || q.contains(alias);
      });
    }

    final result = seeds.where(matches).toList();
    result.sort((a, b) => _searchCardScore(b).compareTo(_searchCardScore(a)));
    return result;
  }

  City? _cityForSearch({
    String? detectedCity,
    String? cityIntent,
    required List<Landmark> results,
    required String query,
  }) {
    final fromIntent = _findCityByName(cityIntent);
    if (fromIntent != null) return fromIntent;

    final fromDetected = _findCityByName(detectedCity);
    if (fromDetected != null) return fromDetected;

    for (final lm in results) {
      final city = _cityForLandmark(lm);
      if (city != null) return city;
    }

    return null;
  }

  City? _findCityByName(String? raw) {
    final target = _normalizeCityText(raw ?? '');
    if (target.isEmpty) return null;

    for (final city in _cities) {
      if (_normalizeCityText(city.name) == target) return city;
    }

    return null;
  }

  List<Landmark> _searchContextPlacesForCity(
    City city,
    List<Landmark> exactResults,
  ) {
    // In search mode, do not use local seeds for context.
    // Context should come only from Firebase / already generated real places.
    final context = _touristAndOutingOnly([
      ..._landmarksForCity(_allLandmarks, city),
      ..._landmarksForCity(_cityLandmarks, city),
    ]);

    final exactKeys = exactResults.map(_placeIdentityKey).toSet();

    final filtered = context.where((lm) {
      final key = _placeIdentityKey(lm);
      return key.trim().isNotEmpty &&
          !exactKeys.contains(key) &&
          _landmarkMatchesCity(lm, city);
    }).toList();

    filtered.sort((a, b) => _cityDisplayScore(b, city.name)
        .compareTo(_cityDisplayScore(a, city.name)));

    return filtered.take(10).toList();
  }

  List<Landmark> _sortSearchResultsWithCityContext({
    required List<Landmark> exactResults,
    required List<Landmark> contextPlaces,
    required String query,
    required City? city,
  }) {
    final queryNorm = _normalizeCityText(query);

    final exact = _filterAndDedup(exactResults);
    exact.sort((a, b) => _searchCardScore(b).compareTo(_searchCardScore(a)));

    final context = _filterAndDedup(contextPlaces);
    if (city != null) {
      context.sort((a, b) => _cityDisplayScore(b, city.name)
          .compareTo(_cityDisplayScore(a, city.name)));
    }

    final merged = _filterAndDedup([...exact, ...context]);

    merged.sort((a, b) {
      final aKey = _placeIdentityKey(a);
      final bKey = _placeIdentityKey(b);

      final aFromExact = exact.any((e) => _placeIdentityKey(e) == aKey);
      final bFromExact = exact.any((e) => _placeIdentityKey(e) == bKey);
      if (aFromExact != bFromExact) return aFromExact ? -1 : 1;

      final aName = _normalizeCityText(a.name);
      final bName = _normalizeCityText(b.name);

      final aExactText = queryNorm.isNotEmpty &&
          (aName == queryNorm ||
              aName.contains(queryNorm) ||
              queryNorm.contains(aName));
      final bExactText = queryNorm.isNotEmpty &&
          (bName == queryNorm ||
              bName.contains(queryNorm) ||
              queryNorm.contains(bName));
      if (aExactText != bExactText) return aExactText ? -1 : 1;

      if (city != null) {
        return _cityDisplayScore(b, city.name)
            .compareTo(_cityDisplayScore(a, city.name));
      }

      return _searchCardScore(b).compareTo(_searchCardScore(a));
    });

    return merged.take(12).toList();
  }

  Future<void> _refreshSearchCityContextInBackground({
    required City city,
    required List<Landmark> exactResults,
    required String query,
  }) async {
    final key =
        'search_context_${_normalizeCityText(city.name)}_${_normalizeCityText(query)}';
    if (!_homeBackgroundGenerationKeys.add(key)) return;

    try {
      print('[Home] search city context generation started for ${city.name}');

      final generated = await _loadTouristPlacesForCity(city.name);
      if (!mounted || generated.isEmpty) return;

      final valid = _touristAndOutingOnly(generated);
      if (valid.isEmpty) return;

      unawaited(_persistHomePlacesInBackground(
        valid,
        defaultCity: city,
        reason: 'search_city_context_${city.name}',
      ));

      if (!mounted || !_searchActive) return;

      final context = _filterAndDedup([
        ..._searchContextPlacesForCity(city, exactResults),
        ...valid,
      ]);

      final display = _sortSearchResultsWithCityContext(
        exactResults: exactResults,
        contextPlaces: context,
        query: query,
        city: city,
      );

      if (display.isEmpty) return;

      setState(() {
        _selectedCity = city;
        _lastCityId = city.id;
        _searchResults = display;

        _allLandmarks = _sortForHome(
          _prepareHomePlaces([...display, ...valid, ..._allLandmarks]),
          cityName: null,
        );

        _cityLandmarks = _sortForHome(
          _prepareHomePlaces([
            ...display,
            ..._landmarksForCity(valid, city),
            ..._landmarksForCity(_allLandmarks, city),
            ..._landmarksForCity(_cityLandmarks, city),
          ]),
          cityName: city.name,
        );
      });

      print('[Home] search city context generation done for ${city.name}: ${valid.length}');
    } catch (e) {
      print('[Home] search city context generation error: $e');
    }
  }

  void _onSearchCleared() => _resetSearch();

  void _resetSearch() {
    _suggestionDebounce?.cancel();
    setState(() {
      _searchActive = false;
      _searching = false;
      _fetchingSuggestions = false;
      _searchQuery = '';
      _correctedQuery = '';
      _searchResults = [];
      _suggestions = [];
      _searchCtrl.clear();
    });
  }


  List<Landmark> _localEgyptSeedPlaces() {
    const data = [
      ('Great Pyramid of Giza', 'Giza', 'Giza Plateau', 29.9792, 31.1342),
      ('Grand Egyptian Museum', 'Giza', 'Giza, Egypt', 29.9880, 31.1162),
      ('Great Sphinx of Giza', 'Giza', 'Giza Plateau', 29.9753, 31.1376),
      ('Egyptian Museum', 'Cairo', 'Tahrir Square, Cairo', 30.0478, 31.2336),
      ('Khan el-Khalili', 'Cairo', 'Islamic Cairo', 30.0477, 31.2625),
      ('Citadel of Cairo', 'Cairo', 'Salah Salem, Cairo', 30.0286, 31.2599),
      ('Cairo Tower', 'Cairo', 'Gezira Island, Cairo', 30.0459, 31.2243),
      ('Abdeen Palace', 'Cairo', 'Downtown Cairo', 30.0433, 31.2480),
      ('Luxor Temple', 'Luxor', 'Luxor City', 25.6994, 32.6392),
      ('Karnak Temple', 'Luxor', 'Karnak, Luxor', 25.7188, 32.6573),
      ('Valley of the Kings', 'Luxor', 'West Bank, Luxor', 25.7402, 32.6014),
      ('Temple of Hatshepsut', 'Luxor', 'Deir el-Bahari, Luxor', 25.7382, 32.6066),
      ('Abu Simbel Temples', 'Aswan', 'Abu Simbel, Aswan', 22.3372, 31.6258),
      ('Philae Temple', 'Aswan', 'Agilkia Island, Aswan', 24.0251, 32.8840),
      ('Temple of Kom Ombo', 'Aswan', 'Kom Ombo, Aswan', 24.4522, 32.9286),
      ('Temple of Edfu', 'Aswan', 'Edfu, Aswan', 24.9777, 32.8734),
      ('Bibliotheca Alexandrina', 'Alexandria', 'Alexandria Corniche', 31.2089, 29.9092),
      ('Citadel of Qaitbay', 'Alexandria', 'Eastern Harbor, Alexandria', 31.2140, 29.8856),
      ('Montaza Palace', 'Alexandria', 'Montaza, Alexandria', 31.2875, 30.0156),
      ('Catacombs of Kom El Shoqafa', 'Alexandria', 'Kom El Shoqafa, Alexandria', 31.1786, 29.8929),
      ('Siwa Oasis', 'Siwa', 'Siwa, Matrouh', 29.2032, 25.5195),
    ];

    return data.map((e) {
      return Landmark(
        id: 'local_seed_${_normalizeCityText(e.$1)}',
        name: e.$1,
        cityId: '',
        city: e.$2,
        category: 'tourist',
        description: '${e.$1}, ${e.$3}',
        shortDescription: '${e.$1}, ${e.$3}',
        fullDescription: '',
        history: '',
        imageUrl: '',
        mediaUrls: const [],
        lat: e.$4,
        lng: e.$5,
        address: e.$3,
        rating: 0,
        openingHours: '',
        location: '${e.$4}, ${e.$5}',
        ticketPrice: null,
        wikipediaUrl: null,
        createdAt: DateTime.now(),
        sources: const {'provider': 'local_home_seed'},
      );
    }).toList();
  }

  List<Landmark> _localSeedPlacesForCity(String cityName) {
    final city = _normalizeCityText(cityName);
    return _localEgyptSeedPlaces()
        .where((lm) => _normalizeCityText(lm.city) == city)
        .toList();
  }

  Future<void> _persistHomePlacesInBackground(
    List<Landmark> places, {
    City? defaultCity,
    required String reason,
  }) async {
    try {
      final clean = _prepareHomePlaces(places);
      if (clean.isEmpty) return;

      print('[Home] persist background started: $reason count=${clean.length}');

      final saved = <Landmark>[];
      final seen = <String>{};

      for (final place in clean) {
        final normalizedCategory = PlaceCategoryNormalizer.normalize(
          place.category,
          contextText: '${place.name} ${place.shortDescription} ${place.description}',
        );

        // Persist all allowed categories so Search works generally:
        // tourist, hotel, restaurant, cafe, outing.
        // Home/Top Places still filters display to tourist + outing only.
        if (!PlaceCategoryNormalizer.allowed.contains(normalizedCategory)) {
          continue;
        }

        final key =
            '${_normalizeCityText(place.name)}|$normalizedCategory|${_normalizeCityText(place.city)}';
        if (!seen.add(key)) continue;

        final cityForPlace = defaultCity ?? _cityForLandmark(place, defaultCity: defaultCity);
        final cityId = cityForPlace?.id ?? place.cityId;
        final cityName = cityForPlace?.name ?? place.city;
        final now = DateTime.now();

        final toSave = place.copyWith(
          // local/temporary UI ids must not be used as Firestore ids.
          id: place.id.startsWith('local_seed_') || place.id.startsWith('overpass_')
              ? ''
              : place.id,
          cityId: cityId,
          city: cityName.trim().isNotEmpty ? cityName : place.city,
          createdAt: place.createdAt ?? now,
          updatedAt: now,
        );

        final id = await _repo.save(toSave);
        saved.add(toSave.copyWith(id: id));
      }

      if (!mounted || saved.isEmpty) return;

      setState(() {
        _allLandmarks = _sortForHome(
          _prepareHomePlaces([...saved, ..._allLandmarks]),
          cityName: null,
        );

        final selected = _selectedCity;
        if (selected != null) {
          _cityLandmarks = _sortForHome(
            _prepareHomePlaces([
              ..._landmarksForCity(_cityLandmarks, selected),
              ..._landmarksForCity(saved, selected),
            ]),
            cityName: selected.name,
          );
        }
      });

      print('[Home] persist background done: $reason saved=${saved.length}');

      // Refresh Home memory after saving generated/search results so the UI
      // and the next search can see newly persisted places quickly instead of
      // waiting for older in-memory lists.
      unawaited(_loadAllLandmarks());

      if (defaultCity != null && saved.isNotEmpty) {
        try {
          final verify = await _repo.loadCity(defaultCity.id);
          final homeVisible = _landmarksForCity(
            _prepareHomePlaces(verify),
            defaultCity,
          ).length;
          print(
            '[Home] persist verify cityId=${defaultCity.id} cityName=${defaultCity.name} '
            'saved=${saved.length} cityQueryRaw=${verify.length} homeVisible=$homeVisible',
          );
          if (saved.isNotEmpty && homeVisible == 0) {
            print(
              '[Home] persist verify mismatch: same query the city page uses returned '
              'no home-visible rows. Example saved.cityId=${saved.first.cityId} '
              'saved.city="${saved.first.city}" (repo may filter empty/Egypt-only city text).',
            );
          }
          if (!mounted) return;
          setState(() {
            _allLandmarks = _sortForHome(
              _prepareHomePlaces([...verify, ..._allLandmarks]),
              cityName: null,
            );
            if (_selectedCity?.id == defaultCity.id) {
              _cityLandmarks = _sortForHome(
                _prepareHomePlaces([
                  ..._landmarksForCity(_cityLandmarks, defaultCity),
                  ..._landmarksForCity(verify, defaultCity),
                ]),
                cityName: defaultCity.name,
              );
            }
          });
        } catch (e) {
          print('[Home] persist verify error: $e');
        }
      }
    } catch (e) {
      print('[Home] persist background error for $reason: $e');
    }
  }

  City? _cityForLandmark(Landmark place, {City? defaultCity}) {
    final canonicalCity = _canonicalCityForHomePlace(place);
    if (canonicalCity.isNotEmpty) {
      final canonical = _findCityByName(canonicalCity);
      if (canonical != null) return canonical;
    }

    if (defaultCity != null && _landmarkMatchesCity(place, defaultCity)) {
      return defaultCity;
    }

    final placeCity = _normalizeCityText(place.city);
    final placeAddress = _normalizeCityText(place.address);
    final placeText = _normalizeCityText(
      '${place.name} ${place.city} ${place.address} ${place.shortDescription} ${place.description}',
    );

    for (final city in _cities) {
      final cityText = _normalizeCityText(city.name);
      if (cityText.isEmpty) continue;

      if (placeCity == cityText ||
          placeAddress.contains(cityText) ||
          placeText.contains(cityText)) {
        return city;
      }
    }

    if (place.lat != 0 && place.lng != 0) {
      final giza = _findCityByName('Giza');
      if (giza != null &&
          place.lat >= 29.90 &&
          place.lat <= 30.08 &&
          place.lng >= 31.05 &&
          place.lng <= 31.22) {
        return giza;
      }

      final cairo = _findCityByName('Cairo');
      if (cairo != null &&
          place.lat >= 29.90 &&
          place.lat <= 30.20 &&
          place.lng > 31.22 &&
          place.lng <= 31.45) {
        return cairo;
      }
    }

    return defaultCity;
  }

  Future<List<Landmark>> _loadTouristPlacesForCity(String cityName) async {
    try {
      final queries = <String>[
        // Famous tourist highlights
        'tourist attractions in $cityName',
        'famous landmarks in $cityName',
        'historic sites in $cityName',
        'museums in $cityName',
        // Outing/family places
        'outing places in $cityName',
        'parks in $cityName',
        'gardens in $cityName',
        'malls in $cityName',
        'beaches in $cityName',
      ];

      final collected = <Landmark>[];
      for (final q in queries) {
        final result = await _search.searchPlaces(
          query: q,
          cityName: cityName,
          maxResults: 24,
        );
        collected.addAll(result.results);
        if (_touristAndOutingOnly(collected).length >= 16) break;
      }

      final valid = _touristAndOutingOnly(_filterAndDedup(collected));
      valid.sort((a, b) => _cityDisplayScore(b, cityName)
          .compareTo(_cityDisplayScore(a, cityName)));
      return valid;
    } catch (e) {
      print('[Home] city tourist/outing fallback error: $e');
      return const [];
    }
  }

  Future<List<Landmark>> _loadDefaultEgyptTopPlaces() async {
    try {
      final collected = <Landmark>[];

      final broadQueries = [
        'famous tourist attractions in Egypt',
        'best landmarks in Egypt',
        'outing places in Egypt',
        'famous parks and gardens in Egypt',
      ];

      for (final q in broadQueries) {
        final result = await _search.searchPlaces(
          query: q,
          cityName: null,
          maxResults: 24,
        );
        collected.addAll(result.results);
        if (_touristAndOutingOnly(collected).length >= 18) break;
      }

      // Target famous places one by one so missing highlights are generated
      // under their real city instead of being attached to the current dropdown.
      if (_touristAndOutingOnly(collected).length < 12) {
        const seedQueries = [
          'Great Pyramid of Giza',
          'Great Sphinx of Giza',
          'Grand Egyptian Museum',
          'Egyptian Museum',
          'Cairo Tower',
          'Citadel of Cairo',
          'Khan el-Khalili',
          'Luxor Temple',
          'Karnak Temple',
          'Valley of the Kings',
          'Abu Simbel Temples',
          'Philae Temple',
          'Bibliotheca Alexandrina',
          'Citadel of Qaitbay',
          'Montaza Palace',
          'Siwa Oasis',
        ];

        for (final q in seedQueries) {
          final result = await _search.searchPlaces(
            query: q,
            cityName: null,
            maxResults: 3,
          );
          collected.addAll(result.results);
          if (_touristAndOutingOnly(collected).length >= 18) break;
        }
      }

      final valid = _touristAndOutingOnly(_filterAndDedup(collected));
      return _sortForHome(valid, cityName: null);
    } catch (e) {
      print('[Home] default Egypt top places error: $e');
      return const [];
    }
  }

  // ════════════════════════════════════════════════════════
  //  PLANNER
  // ════════════════════════════════════════════════════════

  Future<void> _generatePlan(int days) async {
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a city first.')),
      );
      return;
    }

    final source = _plannerSource;
    if (source.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough places in this city to build a plan yet.'),
        ),
      );
      return;
    }

    if (_generatingPlan) return;
    setState(() => _generatingPlan = true);

    try {
      final result = await _planner.generatePlan(
        landmarks: source,
        days: days,
        cityName: _selectedCity!.name,
        variationSeed: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) return;

      if (result.days.isEmpty || result.days.every((d) => d.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not enough places to generate a plan.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.engine == PlannerEngine.gemini
                ? 'AI plan generated for ${_selectedCity!.name}!'
                : 'Smart plan generated for ${_selectedCity!.name}!',
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlannerScreen(plan: result.days),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate plan. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPlan = false);
    }
  }

  // ════════════════════════════════════════════════════════
  //  COMPUTED PROPERTIES
  // ════════════════════════════════════════════════════════

  List<Landmark> get _displayedPlaces {
    if (_searchActive) {
      // SearchEngine already puts the best exact/generated match first.
      // Keep this order so rating/images never push another card above it.
      return _filterAndDedup(_searchResults);
    }

    // City selected: show tourist places + outings in this city.
    // Use BOTH _cityLandmarks and _allLandmarks because generated places may be
    // saved with city='Cairo' but cityId empty/older, so relying only on
    // loadCity(city.id) can incorrectly show an empty city page.
    if (_selectedCity != null) {
      final selected = _selectedCity!;
      final cityPlaces = _touristAndOutingOnly(
        _filterAndDedup(
          _preferFirestoreOverSeeds([
            ..._landmarksForCity(_cityLandmarks, selected),
            ..._landmarksForCity(_allLandmarks, selected),
            ..._localSeedPlacesForCity(selected.name),
          ]),
        ),
      );
      cityPlaces.sort((a, b) => _cityDisplayScore(b, selected.name)
          .compareTo(_cityDisplayScore(a, selected.name)));
      return cityPlaces;
    }

    // All Egypt selected: show the most famous tourist landmarks only.
    return _egyptTopPlaces;
  }

  List<Landmark> get _egyptTopPlaces {
    return _egyptTopPlacesFrom(_allLandmarks).take(20).toList();
  }

  List<Landmark> _egyptTopPlacesFrom(List<Landmark> source) {
    // Top Places must show ONLY tourist + outing places across Egypt.
    // This also allows places like Cairo Zoo / gardens / parks to appear,
    // while preventing hotels/restaurants/cafes from entering the carousel.
    final filtered = _touristAndOutingOnly(
      _preferFirestoreOverSeeds([
        ...source,
        ..._localEgyptSeedPlaces(),
      ]),
    );

    filtered.sort((a, b) {
      final famousCompare =
          _famousEgyptScore(b).compareTo(_famousEgyptScore(a));
      if (famousCompare != 0) return famousCompare;
      return _placeScore(b).compareTo(_placeScore(a));
    });

    return filtered;
  }

  List<Landmark> _sortForHome(List<Landmark> items, {String? cityName}) {
    final list = _prepareHomePlaces(items);
    list.sort((a, b) {
      final famousCompare = cityName == null
          ? _famousEgyptScore(b).compareTo(_famousEgyptScore(a))
          : _famousCityScore(b, cityName).compareTo(_famousCityScore(a, cityName));
      if (famousCompare != 0) return famousCompare;
      return _placeScore(b).compareTo(_placeScore(a));
    });
    return list;
  }

  int _famousEgyptScore(Landmark lm) {
    final name = lm.name.trim().toLowerCase();

    const famous = {
      'great pyramid of giza': 1000,
      'pyramids of giza': 995,
      'great sphinx of giza': 990,
      'grand egyptian museum': 980,
      'egyptian museum': 970,
      'khan el-khalili': 960,
      'cairo tower': 950,
      'citadel of cairo': 940,
      'luxor temple': 930,
      'karnak temple': 920,
      'valley of the kings': 910,
      'hatshepsut temple': 900,
      'temple of hatshepsut': 900,
      'abu simbel temples': 890,
      'abu simbel': 890,
      'philae temple': 880,
      'temple of edfu': 870,
      'temple of kom ombo': 860,
      'bibliotheca alexandrina': 850,
      'alexandria library': 850,
      'citadel of qaitbay': 840,
      'montaza palace': 830,
      'catacombs of kom el shoqafa': 820,
      'siwa oasis': 810,
    };

    for (final entry in famous.entries) {
      if (name == entry.key || name.contains(entry.key) || entry.key.contains(name)) {
        return entry.value;
      }
    }

    return 0;
  }

  List<Landmark> _touristOnly(List<Landmark> items) {
    return _filterAndDedup(items).where(_isTouristPlace).toList();
  }

  bool _isTouristPlace(Landmark lm) {
    final cat = PlaceCategoryNormalizer.normalize(
      lm.category,
      contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
    );
    return cat == 'tourist';
  }

  List<Landmark> _touristAndOutingOnly(List<Landmark> items) {
    return _filterAndDedup(items).where((lm) {
      final cat = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
      );
      return cat == 'tourist' || cat == 'outing';
    }).toList();
  }

  List<Landmark> get _plannerSource {
    if (_selectedCity == null) return [];

    final base = (_searchActive && _searchResults.isNotEmpty)
        ? _searchResults.where((p) => _landmarkMatchesCity(p, _selectedCity!)).toList()
        : _filterAndDedup([
            ..._landmarksForCity(_cityLandmarks, _selectedCity!),
            ..._landmarksForCity(_allLandmarks, _selectedCity!),
          ]);

    final result = _filterAndDedup(base);
    result.sort((a, b) => _plannerScore(b).compareTo(_plannerScore(a)));
    return result;
  }




  bool _isLocalSeedPlace(Landmark lm) {
    return lm.id.trim().toLowerCase().startsWith('local_seed_');
  }

  String _visibleHomeKey(Landmark lm) {
    final name = _dedupeNameKey(_clearDisplayName(lm.name));
    final cat = PlaceCategoryNormalizer.normalize(
      lm.category,
      contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
    );
    return '$name|$cat';
  }

  bool _sameVisiblePlace(Landmark a, Landmark b) {
    final aId = a.id.trim();
    final bId = b.id.trim();
    if (aId.isNotEmpty && bId.isNotEmpty && aId == bId) return true;
    return _visibleHomeKey(a) == _visibleHomeKey(b);
  }

  bool _shouldUseIncomingHomeCandidate(Landmark existing, Landmark incoming) {
    final existingSeed = _isLocalSeedPlace(existing);
    final incomingSeed = _isLocalSeedPlace(incoming);

    // A real Firebase document must always replace a local seed card for the
    // same visible place. This fixes cases like local_seed_citadel of cairo
    // staying on Home while the real Firestore document was edited.
    if (existingSeed && !incomingSeed) return true;
    if (!existingSeed && incomingSeed) return false;

    return _placeScore(incoming) > _placeScore(existing);
  }

  String _searchVisiblePlaceKey(Landmark lm) {
    final name = _dedupeNameKey(_clearDisplayName(lm.name));
    if (name.isEmpty) return '';

    final cat = PlaceCategoryNormalizer.normalize(
      lm.category,
      contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
    );

    if (cat == 'tourist' || cat == 'outing') return name;
    return '$name|$cat|${_normalizeCityText(lm.city)}';
  }

  List<Landmark> _preferFirestoreOverSeeds(List<Landmark> items) {
    final byKey = <String, Landmark>{};

    for (final lm in items) {
      if (lm.name.trim().isEmpty) continue;
      final key = _visibleHomeKey(lm);
      if (key.trim().isEmpty || key == '|') continue;

      final existing = byKey[key];
      if (existing == null || _shouldUseIncomingHomeCandidate(existing, lm)) {
        byKey[key] = lm;
      }
    }

    return byKey.values.toList();
  }

  List<Landmark> _prepareHomePlaces(List<Landmark> items) {
    final cleaned = _filterAndDedup(_preferFirestoreOverSeeds(items))
        .where(_isGoodHomeCardPlace)
        .map(_withClearCardName)
        .toList();

    // Final visual dedupe after display-name cleanup. This catches cases where
    // two saved docs become the same card name after aliases are applied.
    final byKey = <String, Landmark>{};
    for (final lm in cleaned) {
      final cat = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
      );
      final key = '${_dedupeNameKey(lm.name)}|$cat';
      final existing = byKey[key];
      if (existing == null || _placeScore(lm) > _placeScore(existing)) {
        byKey[key] = lm.copyWith(category: cat);
      }
    }

    return byKey.values.toList();
  }

  bool _isGoodHomeCardPlace(Landmark lm) {
    final name = _normalizeCityText(lm.name);
    if (name.isEmpty) return false;

    const blockedExact = {
      'caf',
      'cafe',
      'cafes',
      'cafeteria',
      'coffee',
      'espresso',
      'restaurant',
      'hotel',
      'tourist',
      'tourists',
      'attraction',
      'attractions',
      'landmark',
      'landmarks',
      'outing',
      'outings',
      'مقهي',
      'مقهى',
      'كافيه',
      'مطعم',
      'فندق',
    };
    if (blockedExact.contains(name)) return false;

    if (RegExp(r'\b(street|road|avenue|district|area|zone|neighborhood|neighbourhood|city|village|town)\b')
        .hasMatch(name)) {
      return false;
    }
    if (RegExp(r'(شارع|طريق|منطقة|منطقه|حي|حى|مدينة|مدينه|قرية|قريه)')
        .hasMatch(lm.name)) {
      return false;
    }

    return true;
  }

  Landmark _withClearCardName(Landmark lm) {
    final clearName = _clearDisplayName(lm.name);
    if (clearName == lm.name.trim()) return lm;
    return lm.copyWith(name: clearName);
  }

  String _clearDisplayName(String raw) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final n = _normalizeCityText(text);

    const aliases = {
      'great pyramid': 'Great Pyramid of Giza',
      'giza pyramid': 'Great Pyramid of Giza',
      'pyramids of giza': 'Pyramids of Giza',
      'great pyramid of giza': 'Great Pyramid of Giza',
      'grand egyptian museum': 'Grand Egyptian Museum',
      'egyptian museum': 'Egyptian Museum',
      'cairo citadel': 'Citadel of Cairo',
      'citadel of cairo': 'Citadel of Cairo',
      'saladin citadel': 'Citadel of Cairo',
      'qaitbay citadel': 'Citadel of Qaitbay',
      'citadel of qaitbay': 'Citadel of Qaitbay',
      'alexandria library': 'Bibliotheca Alexandrina',
      'bibliotheca alexandrina': 'Bibliotheca Alexandrina',
      'khan el khalili': 'Khan el-Khalili',
      'khan el-khalili': 'Khan el-Khalili',
      'valley of the kings': 'Valley of the Kings',
      'abu simbel': 'Abu Simbel Temples',
      'abu simbel temples': 'Abu Simbel Temples',
      'philae temple': 'Philae Temple',
      'luxor temple': 'Luxor Temple',
      'karnak temple': 'Karnak Temple',
      'abdeen palace': 'Abdeen Palace',
      'montaza palace': 'Montaza Palace',
      'montazah palace': 'Montaza Palace',
    };

    return aliases[n] ?? text;
  }

  double _cityDisplayScore(Landmark lm, String cityName) {
    final cityScore = _famousCityScore(lm, cityName).toDouble();
    return cityScore + _placeScore(lm);
  }

  int _famousCityScore(Landmark lm, String cityName) {
    final name = _normalizeCityText(lm.name);
    final city = _normalizeCityText(cityName);

    final byCity = <String, Map<String, int>>{
      'giza': {
        'great pyramid of giza': 10000,
        'pyramids of giza': 9950,
        'grand egyptian museum': 9900,
        'great sphinx of giza': 9800,
        'egyptian museum': 9700,
        'the pharaonic village': 9600,
        'africa safari park': 9500,
      },
      'cairo': {
        'egyptian museum': 10000,
        'khan el khalili': 9900,
        'khan el-khalili': 9900,
        'citadel of cairo': 9800,
        'cairo citadel': 9800,
        'cairo tower': 9700,
        'abdeen palace': 9600,
        'umm kulthum museum': 9500,
        'naguib mahfouz museum': 9400,
        'al azhar park': 9300,
        'al-azhar park': 9300,
        'cairo zoo': 9200,
        'family park': 9100,
      },
      'luxor': {
        'valley of the kings': 10000,
        'karnak temple': 9900,
        'luxor temple': 9800,
        'temple of hatshepsut': 9700,
        'hatshepsut temple': 9700,
        'luxor museum': 9600,
        'luxor souk': 9500,
      },
      'aswan': {
        'abu simbel temples': 10000,
        'abu simbel': 10000,
        'philae temple': 9900,
        'kom ombo temple': 9800,
        'temple of kom ombo': 9800,
        'edfu temple': 9700,
        'temple of edfu': 9700,
        'aswan botanical garden': 9600,
        'nubian museum': 9500,
      },
      'alexandria': {
        'bibliotheca alexandrina': 10000,
        'alexandria library': 10000,
        'citadel of qaitbay': 9900,
        'qaitbay citadel': 9900,
        'montaza palace': 9800,
        'montazah palace': 9800,
        'catacombs of kom el shoqafa': 9700,
        'stanley bridge': 9600,
        'alexandria corniche': 9500,
      },
    };

    final map = byCity[city] ?? const <String, int>{};
    for (final entry in map.entries) {
      if (name == entry.key || name.contains(entry.key) || entry.key.contains(name)) {
        return entry.value;
      }
    }

    return _famousEgyptScore(lm);
  }

  List<Landmark> _landmarksForCity(List<Landmark> items, City city) {
    return _filterAndDedup(
      items.where((lm) => _landmarkMatchesCity(lm, city)).toList(),
    );
  }

  /// Strict city matching for Home/Top Places.
  ///
  /// The old matching used cityId and also searched the address/description.
  /// That can keep a wrong card visible if Firestore saved an old/wrong cityId
  /// or if the text contains another city name.
  ///
  /// This method first fixes famous/canonical places by name/coordinates, then
  /// falls back to exact city fields. It does not change Firebase data.
  bool _landmarkMatchesCity(Landmark lm, City city) {
  final cityName = _normalizeCityText(city.name);
  if (cityName.isEmpty) return false;

  final name = _normalizeCityText(lm.name);
  if (name.isEmpty) return false;

  // Known places override Firebase mistakes
  final knownCity = _knownCityForPlaceName(name);
  if (knownCity != null) {
    return knownCity == cityName;
  }

  final lmCity = _normalizeCityText(lm.city);
  final address = _normalizeCityText(lm.address);
  final text = _normalizeCityText(
    '${lm.name} ${lm.city} ${lm.address} ${lm.shortDescription} ${lm.description}',
  );

  if (lmCity == cityName) return true;
  if (address.contains(cityName)) return true;
  if (text.contains(cityName)) return true;

  // Use cityId only as a final fallback, not first
  final cityId = city.id.trim();
  if (cityId.isNotEmpty && lm.cityId.trim() == cityId) return true;

  return false;
}

String? _knownCityForPlaceName(String normalizedName) {
  const known = {
    'cairo tower': 'cairo',
    'egyptian museum': 'cairo',
    'khan el khalili': 'cairo',
    'khan el-khalili': 'cairo',
    'citadel of cairo': 'cairo',
    'abdeen palace': 'cairo',

    'great pyramid of giza': 'giza',
    'pyramids of giza': 'giza',
    'great sphinx of giza': 'giza',
    'grand egyptian museum': 'giza',

    'luxor temple': 'luxor',
    'karnak temple': 'luxor',
    'valley of the kings': 'luxor',
    'temple of hatshepsut': 'luxor',

    'abu simbel temples': 'aswan',
    'philae temple': 'aswan',
    'temple of kom ombo': 'aswan',
    'temple of edfu': 'aswan',

    'bibliotheca alexandrina': 'alexandria',
    'alexandria library': 'alexandria',
    'citadel of qaitbay': 'alexandria',
    'montaza palace': 'alexandria',
  };

  for (final entry in known.entries) {
    final key = _normalizeCityText(entry.key);
    if (normalizedName == key ||
        normalizedName.contains(key) ||
        key.contains(normalizedName)) {
      return entry.value;
    }
  }

  return null;
}

  String _canonicalCityForHomePlace(Landmark lm) {
    final name = _normalizeCityText(_clearDisplayName(lm.name));
    final text = _normalizeCityText(
      '${lm.name} ${lm.city} ${lm.address} ${lm.shortDescription} ${lm.description} ${lm.fullDescription}',
    );

    bool hasAny(List<String> words) {
      return words.any((word) {
        final w = _normalizeCityText(word);
        return w.isNotEmpty && (name == w || name.contains(w) || text.contains(w));
      });
    }

    if (hasAny(const [
      'great pyramid of giza',
      'pyramids of giza',
      'great sphinx of giza',
      'sphinx of giza',
      'grand egyptian museum',
      'the pharaonic village',
      'africa safari park',
      'أهرامات الجيزة',
      'اهرامات الجيزة',
      'أبو الهول',
      'ابو الهول',
    ])) {
      return 'giza';
    }

    if (hasAny(const [
      'cairo tower',
      'egyptian museum',
      'khan el khalili',
      'khan el-khalili',
      'citadel of cairo',
      'cairo citadel',
      'abdeen palace',
      'umm kulthum museum',
      'naguib mahfouz museum',
      'al azhar park',
      'al-azhar park',
      'cairo zoo',
      'family park',
      'برج القاهرة',
      'برج القاهره',
      'خان الخليلي',
      'قلعة صلاح الدين',
    ])) {
      return 'cairo';
    }

    if (hasAny(const [
      'valley of the kings',
      'karnak temple',
      'luxor temple',
      'temple of hatshepsut',
      'hatshepsut temple',
      'luxor museum',
      'وادي الملوك',
      'وادى الملوك',
      'الكرنك',
      'معبد الأقصر',
      'معبد الاقصر',
    ])) {
      return 'luxor';
    }

    if (hasAny(const [
      'abu simbel temples',
      'abu simbel',
      'philae temple',
      'kom ombo temple',
      'temple of kom ombo',
      'edfu temple',
      'temple of edfu',
      'aswan botanical garden',
      'nubian museum',
      'أبو سمبل',
      'ابو سمبل',
      'فيلة',
      'فيله',
    ])) {
      return 'aswan';
    }

    if (hasAny(const [
      'bibliotheca alexandrina',
      'alexandria library',
      'citadel of qaitbay',
      'qaitbay citadel',
      'montaza palace',
      'montazah palace',
      'catacombs of kom el shoqafa',
      'stanley bridge',
      'alexandria corniche',
      'مكتبة الإسكندرية',
      'مكتبة الاسكندرية',
      'قلعة قايتباي',
    ])) {
      return 'alexandria';
    }

    if (hasAny(const ['siwa oasis', 'واحة سيوة', 'سيوة'])) {
      return 'siwa';
    }

    // Coordinate fallback for generated docs whose city field is empty.
    if (lm.lat != 0 && lm.lng != 0) {
      if (lm.lat >= 29.90 && lm.lat <= 30.08 &&
          lm.lng >= 31.05 && lm.lng <= 31.22) {
        return 'giza';
      }

      if (lm.lat >= 29.90 && lm.lat <= 30.20 &&
          lm.lng > 31.22 && lm.lng <= 31.45) {
        return 'cairo';
      }
    }

    return '';
  }

  String _normalizeCityText(String value) {
    return value
        .toLowerCase()
        .replaceAll('governorate', '')
        .replaceAll('egypt', '')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _shouldGenerateCityHighlights(List<Landmark> stored, City city) {
    final key = 'city_highlights_${_normalizeCityText(city.name)}';
    if (_homeBackgroundGenerationKeys.contains(key)) return false;

    final touristOuting = _touristAndOutingOnly(stored);
    if (touristOuting.length < 8) return true;

    final cityFamous = touristOuting
        .where((lm) => _famousCityScore(lm, city.name) >= 9000)
        .length;
    return cityFamous < 5;
  }

  List<Landmark> _onlyMissingPlaces(
    List<Landmark> incoming,
    List<Landmark> existing,
  ) {
    final existingKeys = existing.map(_placeIdentityKey).toSet();
    final result = <Landmark>[];

    for (final lm in incoming) {
      final key = _placeIdentityKey(lm);
      if (key.trim().isEmpty) continue;
      if (existingKeys.add(key)) result.add(lm);
    }

    return result;
  }

  String _placeIdentityKey(Landmark lm) {
    return '${_normalizeCityText(_clearDisplayName(lm.name))}|${_normalizeCityText(lm.city)}';
  }

  List<Landmark> _filterAndDedup(List<Landmark> items) {
    final byKey = <String, Landmark>{};

    for (final lm in items) {
      if (lm.name.trim().isEmpty) continue;
      if (!PlaceCategoryNormalizer.isAllowed(lm.category, contextText: lm.name)) {
        continue;
      }

      final clearName = _clearDisplayName(lm.name);
      final normalizedCategory = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
      );

      final normalizedName = _dedupeNameKey(clearName);

      // For the Home/Top Places experience, the same visible place must appear
      // once even if Firebase has multiple spellings or different city values
      // like "Cairo", "Giza", "Giza, Cairo", or empty cityId.
      //
      // Tourist + outing places are the only categories allowed in Top Places,
      // so they dedupe by canonical name. Other categories keep city in the key
      // to avoid collapsing unrelated cafes/hotels with similar names.
      final key = (normalizedCategory == 'tourist' || normalizedCategory == 'outing')
          ? '$normalizedName|$normalizedCategory'
          : '$normalizedName|$normalizedCategory|${_normalizeCityText(lm.city)}';

      final candidate = lm.copyWith(
        name: clearName,
        category: normalizedCategory,
      );

      final existing = byKey[key];
      if (existing == null || _shouldUseIncomingHomeCandidate(existing, candidate)) {
        byKey[key] = candidate;
      }
    }

    return byKey.values.toList();
  }

  String _dedupeNameKey(String value) {
    return _normalizeCityText(value)
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'\b(the|of|el|al|egypt|cairo|giza)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _placeScore(Landmark lm) {
    double score = lm.rating * 5 +
        lm.mediaUrls.length * 1.2 +
        (lm.imageUrl.trim().isNotEmpty ? 4 : 0) +
        (lm.shortDescription.trim().isNotEmpty ? 2 : 0);

    final cat = PlaceCategoryNormalizer.normalize(lm.category, contextText: lm.name);
    if (cat == 'tourist') score += 12;
    if (cat == 'outing') score += 6;
    if (cat == 'restaurant') score += 3;
    if (cat == 'cafe') score += 2;
    if (cat == 'hotel') score += 1;

    return score;
  }

  double _searchCardScore(Landmark lm) {
    final query = _searchQuery.trim().toLowerCase();
    final corrected = _correctedQuery.trim().toLowerCase();
    final name = lm.name.trim().toLowerCase();

    double score = 0;

    if (query.isNotEmpty) {
      if (name == query) score += 10000;
      if (name.startsWith(query)) score += 6000;
      if (name.contains(query) || query.contains(name)) score += 4000;
      score += _tokenOverlapScore(name, query) * 2500;
    }

    if (corrected.isNotEmpty && corrected != query) {
      if (name == corrected) score += 9000;
      if (name.startsWith(corrected)) score += 5000;
      if (name.contains(corrected) || corrected.contains(name)) score += 3500;
      score += _tokenOverlapScore(name, corrected) * 2000;
    }

    // Normal quality score is only a tie breaker in search mode.
    score += _placeScore(lm);
    return score;
  }

  double _tokenOverlapScore(String name, String query) {
    final nameTokens = name
        .split(RegExp(r'[^a-z0-9\u0600-\u06ff]+'))
        .where((e) => e.length > 2)
        .toSet();
    final queryTokens = query
        .split(RegExp(r'[^a-z0-9\u0600-\u06ff]+'))
        .where((e) => e.length > 2)
        .toList();

    if (nameTokens.isEmpty || queryTokens.isEmpty) return 0;

    var hits = 0;
    for (final token in queryTokens) {
      if (nameTokens.contains(token) ||
          nameTokens.any((n) => n.contains(token) || token.contains(n))) {
        hits++;
      }
    }

    return hits / queryTokens.length;
  }

  double _plannerScore(Landmark lm) {
    double score = _placeScore(lm);
    if (lm.wikipediaUrl?.isNotEmpty == true) score += 3;
    if (lm.lat != 0 && lm.lng != 0) score += 2;
    return score;
  }

  // ════════════════════════════════════════════════════════
  //  MISC
  // ════════════════════════════════════════════════════════

  void _scrollRight() {
    if (!_scrollCtrl.hasClients) return;
    final next = (_scrollCtrl.offset + 200).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(next,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _scrollLeft() {
    if (!_scrollCtrl.hasClients) return;
    final prev = (_scrollCtrl.offset - 200).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(prev,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _openCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null) return;

      final AiImageDetails details =
          await LandmarkImageAiService().describeImage(image);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiImageDetailsScreen(
            imageFile: image,
            details: details,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Camera AI error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image AI error: $e'),
        ),
      );
    }
  }
}

