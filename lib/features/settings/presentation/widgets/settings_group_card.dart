import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/pad_compact.dart';

class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: compact ? 16 : 18, color: const Color(0xFF0F7A43)),
            SizedBox(width: compact ? 6 : 8),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F7A43),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 10 : 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(compact ? 20 : 24),
            border: Border.all(color: const Color(0xFFE1E6DF)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
