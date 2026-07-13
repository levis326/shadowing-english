import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

class PillSegmentedControl<T extends Object> extends StatelessWidget {
  const PillSegmentedControl({
    required this.value,
    required this.options,
    required this.onValueChanged,
    super.key,
  });

  final T value;
  final List<SegmentOption<T>> options;
  final ValueChanged<T> onValueChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFD9D8DE),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          backgroundColor: Colors.transparent,
          thumbColor: Colors.white,
          children: <T, Widget>{
            for (final SegmentOption<T> option in options)
              option.value: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: option.value == value
                        ? const Color(0xFF0875D8)
                        : const Color(0xFF222226),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          },
          onValueChanged: (T? nextValue) {
            if (nextValue != null) {
              onValueChanged(nextValue);
            }
          },
        ),
      ),
    );
  }
}
