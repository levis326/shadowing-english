import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/pad_compact.dart';

class GuideSectionCard extends StatelessWidget {
  const GuideSectionCard({
    required this.step,
    required this.title,
    required this.body,
    required this.icon,
    this.isKey = false,
    super.key,
  });

  final String step;
  final String title;
  final String body;
  final IconData icon;
  final bool isKey;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          margin: EdgeInsets.only(left: compact ? 20 : 24),
          padding: EdgeInsets.all(compact ? 20 : 24),
          decoration: BoxDecoration(
            color: isKey ? const Color(0xFFF7FCF8) : Colors.white,
            borderRadius: BorderRadius.circular(compact ? 20 : 24),
            border: Border.all(
              color: isKey ? const Color(0xFFB8D7C4) : const Color(0xFFE1E6DF),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (isKey)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 10,
                      vertical: compact ? 5 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFFFF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '关键步骤',
                      style: TextStyle(
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F7A43),
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: compact ? 42 : 48,
                    height: compact ? 42 : 48,
                    decoration: BoxDecoration(
                      color: isKey
                          ? const Color(0xFF16C784)
                          : const Color(0xFFD4E3DA),
                      borderRadius: BorderRadius.circular(compact ? 14 : 16),
                    ),
                    child: Icon(
                      icon,
                      color: isKey
                          ? const Color(0xFF004C30)
                          : const Color(0xFF57665E),
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: compact ? 16 : 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF191C1E),
                          ),
                        ),
                        SizedBox(height: compact ? 6 : 8),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: compact ? 13 : 14,
                            height: 1.55,
                            color: const Color(0xFF526157),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: compact ? 18 : 20,
          child: Container(
            width: compact ? 32 : 36,
            height: compact ? 32 : 36,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isKey
                    ? const Color(0xFF0F7A43)
                    : const Color(0xFF8D9891),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                step,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: isKey
                      ? const Color(0xFF0F7A43)
                      : const Color(0xFF53625A),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
