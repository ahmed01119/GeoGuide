part of 'home.dart';

extension _HomeSearchPlacesSection on _HomeState {
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
          BlocListener<UserCubit, UserState>(
            listenWhen: (_, curr) =>
                curr is GetAllCitiesSuccess || curr is GetAllCitiesFailure,
            listener: (context, state) {
              if (state is GetAllCitiesSuccess && state.cities.isNotEmpty) {
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
                  return const Center(child: CircularProgressIndicator());
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
                                  size: 18, color: Color(0xFF8D6E63)),
                              SizedBox(width: 8),
                              Text('All Egypt',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        ..._cities.map(
                          (city) => DropdownMenuItem<City?>(
                            value: city,
                            child: Row(
                              children: [
                                const Icon(Icons.location_city_rounded,
                                    size: 18, color: Color(0xFF8D6E63)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    city.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
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
                    _searchCtrl.selection =
                        TextSelection.fromPosition(TextPosition(offset: s.length));
                    _onSearchSubmitted(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            color: Colors.black.withOpacity(_searchFieldFocused ? 0.08 : 0.04),
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
              child: const Icon(Icons.search_rounded, color: AppColors.chestnutBrown, size: 22),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
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
        borderSide: const BorderSide(color: Color(0xFFE8DDD3), width: 1.2),
      );

  OutlineInputBorder _focusedSearchBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.chestnutBrown, width: 1.8),
      );

  Widget _buildPlacesSection(List<Landmark> places) {
    // Safety filter before rendering only.
    // It does not touch Firebase, search, planner, sorting, scrolling, or app logic.
    final List<Landmark> visiblePlaces = places.where((place) {
      final hasName = place.name.trim().isNotEmpty;
      if (!hasName) return false;

      // All Egypt means no city filtering, only remove nameless cards.
      if (_selectedCity == null) return true;

      // Use the same strict city matcher from home_logic_sections.dart.
      // This catches wrong Firebase city/cityId values for famous places
      // like Cairo Tower being saved under Giza.
      return _landmarkMatchesCity(place, _selectedCity!);
    }).toList();

    if (_searching) return _loadingCard('Searching…');
    if (_selectedCity != null && !_searchActive && visiblePlaces.isEmpty) {
      return _emptyStateCard(
        icon: Icons.location_city_outlined,
        title: 'No places found in this city yet',
        subtitle: 'Try refreshing later or choose another Egyptian city.',
      );
    }
    if (_searchActive && visiblePlaces.isEmpty) {
      return _emptyStateCard(
        icon: Icons.search_off_rounded,
        title: 'No matching places found',
        subtitle: 'Try another place name, city, or category.',
      );
    }
    if (!_searchActive && _selectedCity == null && visiblePlaces.isEmpty) {
      if (_homeLoading) {
        return _loadingCard('Finding the best places for you…');
      }

      return _emptyStateCard(
        icon: _homeLoadFailed
            ? Icons.wifi_off_rounded
            : Icons.travel_explore_rounded,
        title: _homeLoadFailed
            ? 'Could not load places right now'
            : 'No places found yet',
        subtitle: _homeLoadFailed
            ? 'Check your connection, then try refreshing again.'
            : 'Try searching for a place or choose a city.',
      );
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
          _searchActive ? 'search_$_correctedQuery' : _selectedCity?.id ?? 'all_egypt',
        ),
        places: visiblePlaces,
        scrollController: _scrollCtrl,
        onScrollLeft: _scrollLeft,
        onScrollRight: _scrollRight,
        canScrollLeft: _canScrollLeft,
        selectedCity: _selectedCity?.name ?? 'All Egypt',
      ),
    );
  }
}
