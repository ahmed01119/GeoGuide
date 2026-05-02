part of 'home.dart';

extension _HomeLogicSections on _HomeState {
  // ════════════════════════════════════════════════════════
  //  DATA LOADING
  // ════════════════════════════════════════════════════════

  Future<void> _loadAllLandmarks() async {
    try {
      final all = await _repo.loadAll();
      if (!mounted) return;
      setState(() {
        _allLandmarks = _filterAndDedup(all);
      });
    } catch (e) {
      print('[Home] loadAll error: $e');
    }
  }

  Future<void> _loadCityLandmarks(
    City city, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _lastCityId == city.id && _cityLandmarks.isNotEmpty) {
      return;
    }

    _resetSearch();

    final shouldClearCurrentList =
        _selectedCity?.id != city.id || _cityLandmarks.isEmpty;

    setState(() {
      _selectedCity = city;
      _lastCityId = city.id;
      if (shouldClearCurrentList) {
        _cityLandmarks = [];
      }
    });

    try {
      final cached = await _repo.loadCity(city.id);
      if (!mounted) return;

      if (_selectedCity?.id == city.id) {
        setState(() {
          _cityLandmarks = _filterAndDedup(cached);
        });
      }

      if (forceRefresh) {
        await _refreshCityInBackground(city);
      } else {
        unawaited(_refreshCityInBackground(city));
      }
    } catch (e) {
      print('[Home] loadCity error: $e');
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
        _cityLandmarks = valid;
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
        cityName: _selectedCity?.name,
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
        cityId: null,
        cityName: _selectedCity?.name,
        maxResults: 10,
      );

      if (!mounted) return;

      if (result.detectedCity != null && result.detectedCity!.trim().isNotEmpty) {
        final found = _cities.where((c) {
          final lc = c.name.trim().toLowerCase();
          final dc = result.detectedCity!.trim().toLowerCase();
          return lc == dc || lc.contains(dc) || dc.contains(lc);
        }).toList();

        if (found.isNotEmpty) {
          final detected = found.first;
          _selectedCity = detected;
          _lastCityId = detected.id;

          _repo.loadCity(detected.id).then((landmarks) {
            if (!mounted) return;
            setState(() {
              _cityLandmarks = _filterAndDedup(landmarks);
            });
          }).catchError((e) {
            print('[Home] auto-load detected city error: $e');
          });
        }
      }

      setState(() {
        _correctedQuery = result.correctedQuery;
        _searchResults = _filterAndDedup(result.results);
        _suggestions = result.suggestions;
        _searching = false;
        _searchActive = true;
      });
    } catch (e) {
      print('[Home] search error: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _searching = false;
        });
      }
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
      final results = _filterAndDedup(_searchResults);
      results.sort((a, b) => _placeScore(b).compareTo(_placeScore(a)));
      return results;
    }

    if (_selectedCity != null) {
      final touristPlaces = _touristOnly(_cityLandmarks);
      touristPlaces.sort((a, b) => _placeScore(b).compareTo(_placeScore(a)));
      return touristPlaces;
    }

    return _egyptTopPlaces;
  }

  List<Landmark> get _egyptTopPlaces {
    final filtered = _touristOnly(_allLandmarks);
    filtered.sort((a, b) => _placeScore(b).compareTo(_placeScore(a)));
    return filtered;
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
        ? _searchResults.where((p) => p.cityId == _selectedCity!.id).toList()
        : _cityLandmarks;

    final result = _filterAndDedup(base);
    result.sort((a, b) => _plannerScore(b).compareTo(_plannerScore(a)));
    return result;
  }

  List<Landmark> _filterAndDedup(List<Landmark> items) {
    final seen = <String>{};
    final result = <Landmark>[];
    for (final lm in items) {
      if (lm.id.trim().isEmpty) continue;
      if (!PlaceCategoryNormalizer.isAllowed(lm.category, contextText: lm.name)) {
        continue;
      }
      final key = '${lm.name.trim().toLowerCase()}|${lm.city.trim().toLowerCase()}';
      if (seen.add(key)) result.add(lm);
    }
    return result;
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
    bool dialogShown = false;

    try {
      final picked = await _picker.pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 85,
      );

      if (picked == null) return;
      if (!mounted) return;

      dialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.chestnutBrown),
        ),
      );

      final details = await LandmarkImageAiService().describeImage(picked);
      if (!mounted) return;

      if (dialogShown) {
        Navigator.pop(context);
        dialogShown = false;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiImageDetailsScreen(
            imageFile: picked,
            details: details,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      if (dialogShown) {
        Navigator.pop(context);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not analyze image: $e'),
          backgroundColor: AppColors.chestnutBrown,
        ),
      );
    }
  }
}
