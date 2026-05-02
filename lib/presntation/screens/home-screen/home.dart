// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:ui';
 import 'package:flutter/foundation.dart'; 
import 'package:geoguide/services/landmark_image_ai_service.dart';
import 'package:geoguide/presntation/screens/ai-image-details/ai_image_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/presntation/screens/home-screen/home-widgets/bot-botton.dart';
import 'package:geoguide/presntation/screens/home-screen/home-widgets/custom_bottom_nav_bar.dart';
import 'package:geoguide/presntation/screens/home-screen/home-widgets/home_header_image.dart';
import 'package:geoguide/presntation/screens/home-screen/home-widgets/top_places_section.dart';
import 'package:geoguide/presntation/screens/home-screen/planner-screen.dart';
import 'package:geoguide/presntation/screens/places-screen/places.dart';
import 'package:geoguide/presntation/screens/plans-screen/plans-screen.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/place_repository.dart';
import 'package:geoguide/services/planner_ai_service.dart';
import 'package:geoguide/services/search-service.dart';
import 'package:image_picker/image_picker.dart';

class Home extends StatefulWidget {
  static const routeName = '/home';
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // ── Services ──────────────────────────────────────────────
  final PlaceRepository _repo = AppInjector.repository;
  final SearchEngine _search = AppInjector.search;
  final PlannerService _planner = AppInjector.planner;
  final FirebaseService _firebase = AppInjector.firebase;
  final ImagePicker _picker = ImagePicker();

  // ── State ─────────────────────────────────────────────────
  List<Landmark> _allLandmarks = [];
  List<Landmark> _cityLandmarks = [];
  List<Landmark> _searchResults = [];
  List<City> _cities = [];
  List<String> _suggestions = [];

  String _searchQuery = '';
  String _correctedQuery = '';

  bool _searching = false;
  bool _searchActive = false;
  bool _fetchingSuggestions = false;
  bool _generatingPlan = false;
  bool _searchFieldFocused = false;

  City? _selectedCity;
  String? _lastCityId;
  int _plannerDays = 2;

  Offset _botOffset = const Offset(20, 100);
  // Horizontal controller used by TopPlacesSection.
  final ScrollController _scrollCtrl = ScrollController();

  // Page controller used only for Home refresh scroll-to-top.
  final ScrollController _pageScrollCtrl = ScrollController();

  bool _canScrollLeft = false;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _suggestionDebounce;

  @override
  void initState() {
    super.initState();

    _scrollCtrl.addListener(() {
      if (!mounted) return;
      setState(() => _canScrollLeft = _scrollCtrl.offset > 0);
    });

    _firebase.fixCorruptLandmarkCityIds().then((_) {
      if (!mounted) return;
      context.read<UserCubit>().getAllCities();
      _loadAllLandmarks();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _pageScrollCtrl.dispose();
    _searchCtrl.dispose();
    _suggestionDebounce?.cancel();
    super.dispose();
  }

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
      // 1) Show saved Firestore data quickly.
      final cached = await _repo.loadCity(city.id);
      if (!mounted) return;

      if (_selectedCity?.id == city.id) {
        setState(() {
          _cityLandmarks = _filterAndDedup(cached);
        });
      }

      // 2) Then refresh this city in the background.
      // This lets the pipeline add new places or update incomplete ones
      // without freezing the UI or changing the page design.
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

      // Keep the all-Egypt list updated too, so Explore/All Places sees
      // newly saved records after a city refresh.
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
        _lastCityId = null; // force city reload even if same city is selected
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

    _suggestionDebounce =
        Timer(const Duration(milliseconds: 260), () async {
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

        // مهم جدًا:
        // لا نرسل cityId أثناء البحث، لأن cityId كان بيقفل النتائج على
        // المدينة المختارة حتى لو المستخدم كتب مكان في مدينة تانية.
        cityId: null,

        // cityName مجرد hint يساعد الترتيب، مش فلتر إجباري.
        cityName: _selectedCity?.name,
        maxResults: 10,
      );

      if (!mounted) return;

      // لو السيرش اكتشف مدينة مختلفة، نختارها ونحمّل بياناتها في الخلفية
      // علشان الـ Home يفضل متزامن مع نتائج البحث.
      if (result.detectedCity != null &&
          result.detectedCity!.trim().isNotEmpty) {
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
          content: Text(
              'Not enough places in this city to build a plan yet.'),
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

      if (result.days.isEmpty ||
          result.days.every((d) => d.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Not enough places to generate a plan.')),
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
          const SnackBar(
              content: Text('Could not generate plan. Please try again.')),
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
  // أثناء البحث: اعرض نتائج البحث عادي بأي category موجودة
  if (_searchActive) {
    final results = _filterAndDedup(_searchResults);
    results.sort((a, b) => _placeScore(b).compareTo(_placeScore(a)));
    return results;
  }

  // بدون بحث + مدينة مختارة: اعرض السياحي فقط في المدينة
  if (_selectedCity != null) {
    final touristPlaces = _touristOnly(_cityLandmarks);
    touristPlaces.sort((a, b) => _placeScore(b).compareTo(_placeScore(a)));
    return touristPlaces;
  }

  // بدون بحث + All Egypt: اعرض السياحي فقط على مستوى مصر
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
        ? _searchResults
            .where((p) => p.cityId == _selectedCity!.id)
            .toList()
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
      if (!PlaceCategoryNormalizer.isAllowed(lm.category,
          contextText: lm.name)) {
        continue;
      }
      final key =
          '${lm.name.trim().toLowerCase()}|${lm.city.trim().toLowerCase()}';
      if (seen.add(key)) result.add(lm);
    }
    return result;
  }

  double _placeScore(Landmark lm) {
    double score = lm.rating * 5 +
        lm.mediaUrls.length * 1.2 +
        (lm.imageUrl.trim().isNotEmpty ? 4 : 0) +
        (lm.shortDescription.trim().isNotEmpty ? 2 : 0);

    final cat = PlaceCategoryNormalizer.normalize(lm.category,
        contextText: lm.name);
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
    final next = (_scrollCtrl.offset + 200).clamp(
        0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(next,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _scrollLeft() {
    if (!_scrollCtrl.hasClients) return;
    final prev = (_scrollCtrl.offset - 200).clamp(
        0.0, _scrollCtrl.position.maxScrollExtent);
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
        child: CircularProgressIndicator(
          color: AppColors.chestnutBrown,
        ),
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

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final displayedPlaces = _displayedPlaces;
    final media = MediaQuery.of(context);
    final maxBotTop = media.size.height - 130;

    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F1EB),
        body: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: Color(0xFFF7F1EB)),
            ),
            CustomScrollView(
              controller: _pageScrollCtrl,
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeroSection(context)),
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F1EB),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTopPanel(),
                          const SizedBox(height: 22),
                          _buildSectionHeader(
                            title: _searchActive
                                ? 'Search Results'
                                : _selectedCity != null
                                    ? 'Explore ${_selectedCity!.name}'
                                    : 'Top Places in Egypt',
                            subtitle: _searchActive
                                ? 'Best matches and related places.'
                                : _selectedCity != null
                                    ? 'Browse remarkable places in this city.'
                                    : 'Discover remarkable places across Egypt.',
                          ),
                          const SizedBox(height: 16),
                          // Corrected query banner
                          if (_searchActive &&
                              _correctedQuery.isNotEmpty &&
                              _correctedQuery.toLowerCase() !=
                                  _searchQuery.toLowerCase())
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F4EF),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: const Color(0xFFE8DDD1)),
                              ),
                              child: Text(
                                'Showing results for "$_correctedQuery"',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6F5646),
                                ),
                              ),
                            ),
                          // Places grid / list
                          _buildPlacesSection(displayedPlaces),
                          const SizedBox(height: 24),
                          _buildPlannerSection(context),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.chestnutBrown,
                                side: const BorderSide(
                                    color: AppColors.chestnutBrown),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.bookmarks_rounded),
                              label: const Text(
                                'View Saved Plans',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SavedPlansPage(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildSectionHeader(
                            title: 'Explore More',
                            subtitle:
                                'Browse all available destinations in one place.',
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: AppColors.chestnutBrown,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.explore_outlined),
                              label: const Text(
                                'View All Places',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) {
  final placesToShow = _touristAndOutingOnly(_allLandmarks);

  placesToShow.sort(
    (a, b) => _placeScore(b).compareTo(_placeScore(a)),
  );

  return Places(places: placesToShow);
},
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Draggable bot button
            Positioned(
              left: _botOffset.dx,
              top: _botOffset.dy.clamp(0.0, maxBotTop),
              child: BotButton(
                initialOffset: _botOffset,
                onDragEnd: (offset) => setState(() {
                  _botOffset = Offset(
                    offset.dx,
                    offset.dy.clamp(0.0, maxBotTop),
                  );
                }),
              ),
            ),
          ],
        ),
        floatingActionButton: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.chestnutBrown.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: _openCamera,
            backgroundColor: AppColors.chestnutBrown,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.white, width: 3),
            ),
            child: const Icon(Icons.camera_alt_rounded,
                color: AppColors.white, size: 30),
          ),
        ),
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: CustomBottomNavBar(
          currentIndex: 0,
          onHomeRefresh: _refreshHomeAndScrollTop,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  WIDGET BUILDERS
  // ════════════════════════════════════════════════════════

  Widget _buildHeroSection(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortest = media.size.shortestSide;
    final isTablet = shortest >= 600;
    final heroHeight = isTablet ? 340.0 : 280.0;

    final titleText = _searchActive
        ? 'Find the perfect place'
        : _selectedCity != null
            ? 'Explore ${_selectedCity!.name}'
            : 'Discover Egypt';

    final bodyText = _searchActive && _searchQuery.isNotEmpty
        ? 'Searching for "$_searchQuery"'
        : _selectedCity != null
            ? 'Explore remarkable places in ${_selectedCity!.name}.'
            : 'Explore iconic landmarks and experiences across Egypt.';

    return SizedBox(
      height: heroHeight,
      child: Stack(
        children: [
          const Positioned.fill(child: HomeHeaderImage()),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.16),
                    Colors.black.withOpacity(0.08),
                    Colors.black.withOpacity(0.42),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 26,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: EdgeInsets.all(isTablet ? 20 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Explore Egypt',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        titleText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTablet ? 30 : 26,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bodyText,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: isTablet ? 14.5 : 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Find your next destination',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E251F),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _selectedCity == null
                ? 'Search across Egypt or choose a city.'
                : 'Search within ${_selectedCity!.name}.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7E746C),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // City dropdown — driven by UserCubit for city list
          BlocListener<UserCubit, UserState>(
            listenWhen: (_, curr) =>
                curr is GetAllCitiesSuccess || curr is GetAllCitiesFailure,
            listener: (context, state) {
              if (state is GetAllCitiesSuccess &&
                  state.cities.isNotEmpty) {
                setState(() => _cities = state.cities);
              }
            },
            child: BlocBuilder<UserCubit, UserState>(
              buildWhen: (_, curr) =>
                  curr is GetAllCitiesLoading ||
                  curr is GetAllCitiesSuccess ||
                  curr is GetAllCitiesFailure,
              builder: (context, state) {
                if (state is GetAllCitiesLoading && _cities.isEmpty) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                if (state is GetAllCitiesFailure) {
                  return Text(state.errMessage,
                      style: const TextStyle(color: Colors.red));
                }
                if (_cities.isEmpty) return const SizedBox();

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4EF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE8DDD1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<City?>(
                      value: _selectedCity,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      borderRadius: BorderRadius.circular(18),
                      items: [
                        const DropdownMenuItem<City?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(Icons.public_rounded,
                                  size: 18,
                                  color: Color(0xFF8D6E63)),
                              SizedBox(width: 8),
                              Text('All Egypt',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        ..._cities.map(
                          (city) => DropdownMenuItem<City?>(
                            value: city,
                            child: Row(
                              children: [
                                const Icon(Icons.location_city_rounded,
                                    size: 18,
                                    color: Color(0xFF8D6E63)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    city.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (city) {
                        if (city == null) {
                          _suggestionDebounce?.cancel();
                          setState(() {
                            _selectedCity = null;
                            _cityLandmarks = [];
                            _lastCityId = null;
                          });
                          _resetSearch();
                          return;
                        }
                        _loadCityLandmarks(city);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          _buildSearchField(),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions.map((s) {
                return GestureDetector(
                  onTap: () {
                    _searchCtrl.text = s;
                    _searchCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: s.length),
                    );
                    _onSearchSubmitted(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EAE2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE0D6CC)),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5A4033),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final hasText = _searchCtrl.text.trim().isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(_searchFieldFocused ? 0.08 : 0.04),
            blurRadius: _searchFieldFocused ? 20 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Focus(
        onFocusChange: (v) {
          if (mounted) setState(() => _searchFieldFocused = v);
        },
        child: TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2F241D),
          ),
          onChanged: _onSearchChanged,
          onSubmitted: _onSearchSubmitted,
          decoration: InputDecoration(
            hintText: 'Search places, temples, museums…',
            hintStyle: const TextStyle(
              color: Color(0xFF9A8F87),
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EAE2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.search_rounded,
                  color: AppColors.chestnutBrown, size: 22),
            ),
            suffixIcon: hasText
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3EAE2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: AppColors.chestnutBrown, size: 18),
                      ),
                      onPressed: _onSearchCleared,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: _fetchingSuggestions
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.chestnutBrown,
                                ),
                              ),
                            ),
                          )
                        : const Icon(Icons.north_east_rounded,
                            color: Color(0xFFB7AAA1), size: 20),
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
                vertical: 18, horizontal: 18),
            border: _searchBorder(),
            enabledBorder: _searchBorder(),
            focusedBorder: _focusedSearchBorder(),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _searchBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide:
            const BorderSide(color: Color(0xFFE8DDD3), width: 1.2),
      );

  OutlineInputBorder _focusedSearchBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
            color: AppColors.chestnutBrown, width: 1.8),
      );

  Widget _buildPlacesSection(List<Landmark> places) {
    if (_searching) {
      return _loadingCard('Searching…');
    }

    if (_selectedCity != null &&
        !_searchActive &&
        places.isEmpty) {
      return _emptyStateCard(
        icon: Icons.location_city_outlined,
        title: 'No places found in this city yet',
        subtitle:
            'Try refreshing later or choose another Egyptian city.',
      );
    }

    if (_searchActive && places.isEmpty) {
      return _emptyStateCard(
        icon: Icons.search_off_rounded,
        title: 'No matching places found',
        subtitle:
            'Try another place name, city, or category.',
      );
    }

    if (!_searchActive && _selectedCity == null && places.isEmpty) {
      return _loadingCard('Finding the best places for you…');
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TopPlacesSection(
        key: ValueKey(
          _searchActive
              ? 'search_$_correctedQuery'
              : _selectedCity?.id ?? 'all_egypt',
        ),
        places: places,
        scrollController: _scrollCtrl,
        onScrollLeft: _scrollLeft,
        onScrollRight: _scrollRight,
        canScrollLeft: _canScrollLeft,
      ),
    );
  }

  Widget _buildPlannerSection(BuildContext context) {
    final source = _plannerSource;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return Container(
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Plan Your Visit',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E251F),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _selectedCity != null
                ? 'Choose how many days you will stay in ${_selectedCity!.name}.'
                : 'Select a city first, then choose how many days.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF81756C),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 430;
              if (stacked) {
                return Column(
                  children: [
                    _plannerDaysDropdown(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: _plannerButton(source),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _plannerDaysDropdown()),
                  const SizedBox(width: 12),
                  SizedBox(height: 54, child: _plannerButton(source)),
                ],
              );
            },
          ),
          if (_selectedCity != null && source.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '${source.length} places available in ${_selectedCity!.name}',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF8B817A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _plannerDaysDropdown() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DDD1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _plannerDays,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF8D6E63)),
          borderRadius: BorderRadius.circular(18),
          items: [1, 2, 3, 4, 5, 6, 7]
              .map((d) => DropdownMenuItem(
                    value: d,
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 17, color: Color(0xFF8D6E63)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '$d day${d > 1 ? 's' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E251F)),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _plannerDays = v);
          },
        ),
      ),
    );
  }

  Widget _plannerButton(List<Landmark> source) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.chestnutBrown,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      onPressed:
          (_selectedCity == null || source.isEmpty || _generatingPlan)
              ? null
              : () => _generatePlan(_plannerDays),
      child: _generatingPlan
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.2),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'Generate Plan',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(
      {required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2E251F),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF7E746C),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _loadingCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.chestnutBrown,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6F625A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyStateCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F1EB),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon,
                color: AppColors.chestnutBrown, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E251F),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7E746C),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}