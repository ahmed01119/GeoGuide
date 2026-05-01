import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';

class SearchField extends StatefulWidget {
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCleared;
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestionTap;
  final String initialValue;
  final bool isLoading;

  const SearchField({
    super.key,
    required this.onSubmitted,
    this.onChanged,
    this.onCleared,
    this.suggestions = const [],
    this.onSuggestionTap,
    this.initialValue = '',
    this.isLoading = false,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller;
  bool _hasText = false;
  bool _isFocused = false;

  List<String> get _visibleSuggestions => widget.suggestions.take(6).toList();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _hasText = widget.initialValue.trim().isNotEmpty;

    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText && mounted) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _hasText = _controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleClear() {
    _controller.clear();
    if (mounted) {
      setState(() => _hasText = false);
    }
    widget.onCleared?.call();
  }

  void _submitCurrent() {
    final trimmed = _controller.text.trim();
    if (trimmed.isNotEmpty) {
      widget.onSubmitted(trimmed);
      FocusScope.of(context).unfocus();
    }
  }

  void _applySuggestion(String suggestion) {
    _controller.text = suggestion;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
    widget.onSuggestionTap?.call(suggestion);
    FocusScope.of(context).unfocus();
    if (mounted) {
      setState(() => _hasText = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSuggestions = _isFocused && _visibleSuggestions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isFocused ? 0.08 : 0.04),
                blurRadius: _isFocused ? 20 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Focus(
            onFocusChange: (value) {
              if (mounted) {
                setState(() => _isFocused = value);
              }
            },
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: (_) => _submitCurrent(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2F241D),
              ),
              decoration: InputDecoration(
                hintText: AppText.search,
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
                  child: const Icon(
                    Icons.search_rounded,
                    color: AppColors.chestnutBrown,
                    size: 22,
                  ),
                ),
                suffixIcon: widget.isLoading
                    ? const Padding(
                        padding: EdgeInsets.only(right: 14),
                        child: SizedBox(
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
                        ),
                      )
                    : _hasText
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3EAE2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.chestnutBrown,
                                  size: 18,
                                ),
                              ),
                              onPressed: _handleClear,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IconButton(
                              onPressed: _submitCurrent,
                              icon: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3EAE2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.north_east_rounded,
                                  color: AppColors.chestnutBrown,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                border: _buildBorder(),
                enabledBorder: _buildBorder(),
                focusedBorder: _buildFocusedBorder(),
              ),
            ),
          ),
        ),
        if (showSuggestions) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _visibleSuggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final suggestion = _visibleSuggestions[index];
                return ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.chestnutBrown,
                  ),
                  title: Text(
                    suggestion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _applySuggestion(suggestion),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _buildBorder() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: const BorderSide(
        color: Color(0xFFE8DDD3),
        width: 1.2,
      ),
    );
  }

  OutlineInputBorder _buildFocusedBorder() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: const BorderSide(
        color: AppColors.chestnutBrown,
        width: 1.8,
      ),
    );
  }
}