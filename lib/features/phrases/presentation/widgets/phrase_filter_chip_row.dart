import 'package:flutter/material.dart';

class PhraseFilterChipRow extends StatelessWidget {
  const PhraseFilterChipRow({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF53625A),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options
              .map((String option) {
                final bool isActive = option == selected;
                return ChoiceChip(
                  label: Text(option),
                  selected: isActive,
                  onSelected: (_) => onSelected(option),
                  selectedColor: const Color(0xFFE5F5EA),
                  backgroundColor: const Color(0xFFF2F4F6),
                  labelStyle: TextStyle(
                    color: isActive
                        ? const Color(0xFF0F7A43)
                        : const Color(0xFF53625A),
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: isActive
                        ? const Color(0xFF0F7A43)
                        : const Color(0xFFDCE4DA),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}
