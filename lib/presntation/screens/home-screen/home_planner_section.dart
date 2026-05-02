part of 'home.dart';

extension _HomePlannerSection on _HomeState {
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
      onPressed: (_selectedCity == null || source.isEmpty || _generatingPlan)
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
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ],
            ),
    );
  }
}
