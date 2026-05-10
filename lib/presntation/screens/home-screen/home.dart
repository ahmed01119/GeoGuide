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

part 'home_planner_section.dart';
part 'home_search_places_section.dart';
part 'home_logic_sections.dart';

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
  bool _homeLoading = true;
  bool _homeLoadFailed = false;

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

  void _showHomeNotification(
    String message, {
    Color? backgroundColor,
  }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? const Color.fromARGB(255, 42, 40, 40),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      ),
    );
  }

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

  // Data/search/planner/computed/misc logic moved to home_logic_sections.dart

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
                                border:
                                    Border.all(color: const Color(0xFFE8DDD1)),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
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
                                    final placesToShow =
                                        _touristAndOutingOnly(_allLandmarks);

                                    placesToShow.sort(
                                      (a, b) => _placeScore(b)
                                          .compareTo(_placeScore(a)),
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
              top: _botOffset.dy.clamp(
                0.0,
                MediaQuery.of(context).size.height - 130,
              ),
              child: BotButton(
                initialOffset: _botOffset,
                onDragEnd: (offset) {
                  setState(() {
                    _botOffset = Offset(
                      offset.dx,
                      offset.dy.clamp(
                        0.0,
                        MediaQuery.of(context).size.height - 130,
                      ),
                    );
                  });
                },
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
          child: SizedBox(
            width: 68,
            height: 68,
            child: FloatingActionButton(
              onPressed: _openCamera,
              backgroundColor: AppColors.chestnutBrown,
              shape: const CircleBorder(
                side: BorderSide(color: AppColors.white, width: 4),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.white,
                size: 30,
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: const _FixedCenterDockedFabLocation(),
        bottomNavigationBar: const CustomBottomNavBar(),
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
                  AppColors.ivoryCream
                  
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
                    border: Border.all(color: Colors.white.withOpacity(0.22)),
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
            child: Icon(icon, color: AppColors.chestnutBrown, size: 28),
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

class _FixedCenterDockedFabLocation extends FloatingActionButtonLocation {
  const _FixedCenterDockedFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final fabWidth = scaffoldGeometry.floatingActionButtonSize.width;
    final fabHeight = scaffoldGeometry.floatingActionButtonSize.height;
    final scaffoldSize = scaffoldGeometry.scaffoldSize;

    final dx = (scaffoldSize.width - fabWidth) / 2;
    final dy = scaffoldGeometry.contentBottom - (fabHeight / 2);

    return Offset(dx, dy);
  }
}
