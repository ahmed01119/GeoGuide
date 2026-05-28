// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:geoguide/cubit/user_cubit.dart';

import '../../../../models.dart/landmark_model.dart';
import 'place_card.dart';

class TopPlacesSection extends StatelessWidget {
  final List<Landmark> places;
  final ScrollController scrollController;
  final VoidCallback onScrollLeft;
  final VoidCallback onScrollRight;
  final bool canScrollLeft;

  /// ✅ Optional so old calls will not break.
  /// Pass the currently selected city name here.
  /// Examples: "Giza", "Cairo", "Alexandria", "All Egypt".
  final String? selectedCity;

  const TopPlacesSection({
    super.key,
    required this.places,
    required this.scrollController,
    required this.onScrollLeft,
    required this.onScrollRight,
    required this.canScrollLeft,
    this.selectedCity,
  });

  bool _hasValidName(Landmark place) {
    return place.name.trim().isNotEmpty;
  }

  bool _isAllEgypt(String city) {
    final normalized = city.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'all egypt' ||
        normalized == 'egypt' ||
        normalized == 'all' ||
        normalized == 'all cities';
  }

  bool _sameCity(Landmark place, String currentCity) {
    // City filtering is handled before this widget in Home, using the strict
    // matcher from home_logic_sections.dart. Here we only keep compatibility
    // with old calls and avoid hiding valid All Egypt cards.
    return true;
  }

  List<Landmark> _filterValidPlaces(List<Landmark> sourcePlaces) {
    return sourcePlaces.where(_hasValidName).toList();
  }

  @override
  Widget build(BuildContext context) {
    List<Landmark> allLandmarks = [];

    final userState = context.watch<UserCubit>().state;
    if (userState is GetAllLandmarksSuccess) {
      allLandmarks = userState.landmarks;
    }

    final filteredPlaces = _filterValidPlaces(places);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// ── HEADER ─────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppText.topPlaces,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E251F),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Handpicked places worth exploring',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8B817A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        /// ── LIST ─────────────────────────────
        SizedBox(
          height: 320, // ✅ FIX: كان 270 وده قليل على الكارد الجديد
          child: Stack(
            children: [
              filteredPlaces.isEmpty
                  ? Container(
                      width: double.infinity,
                      height: 280,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F4EF),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off_outlined,
                              size: 36,
                              color: Color(0xFF8D6E63),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'No places found',
                              style: TextStyle(
                                color: Color(0xFF8D6E63),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      itemCount: filteredPlaces.length,
                      itemBuilder: (context, index) {
                        final place = filteredPlaces[index];

                        return Padding(
                          padding: EdgeInsets.only(
                            right:
                                index == filteredPlaces.length - 1 ? 6 : 14,
                          ),
                          child: SizedBox(
                            width: 210, // ✅ لازم نفس عرض الكارد
                            child: HeroMode(
                              enabled: false,
                              child: PlaceCard(
                                key: ValueKey(
                                  '${place.id}_${place.name}_${place.city}_${place.imageUrl}_${place.imagesRefreshedAt}_${place.mediaUrls.length}_${place.lat}_${place.lng}',
                                ),
                                place: place,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

              /// سهم شمال
              if (filteredPlaces.isNotEmpty && canScrollLeft)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _arrowButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: onScrollLeft,
                    ),
                  ),
                ),

              /// سهم يمين
              if (filteredPlaces.isNotEmpty)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _arrowButton(
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: onScrollRight,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// ── Arrow Button ─────────────────────────
  Widget _arrowButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: AppColors.chestnutBrown,
          size: 18,
        ),
        onPressed: onTap,
      ),
    );
  }
}
