import 'package:flutter/material.dart';

class PhraseFilterBar extends StatelessWidget {
  const PhraseFilterBar({
    required this.selected,
    required this.onSelected,
    required this.reviewCount,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    const List<String> filters = <String>['全部生词例句', '今日收藏', '需要复习'];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: filters
          .map((String value) {
            final bool active = value == selected;
            final bool review = value == '需要复习';
            return ChoiceChip(
              label: Text(review ? '$value ($reviewCount)' : value),
              selected: active,
              onSelected: (_) => onSelected(value),
              selectedColor: review
                  ? const Color(0xFF8F1D1D)
                  : const Color(0xFF0F7A43),
              backgroundColor: review
                  ? const Color(0xFFFFF0F0)
                  : const Color(0xFFF2F4F6),
              labelStyle: TextStyle(
                color: active
                    ? Colors.white
                    : review
                    ? const Color(0xFF8F1D1D)
                    : const Color(0xFF4D5A52),
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
              side: BorderSide(
                color: active
                    ? (review
                          ? const Color(0xFF8F1D1D)
                          : const Color(0xFF0F7A43))
                    : (review
                          ? const Color(0xFFF0B7B7)
                          : const Color(0xFFDCE3DC)),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}
