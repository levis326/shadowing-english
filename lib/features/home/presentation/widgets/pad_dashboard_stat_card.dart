import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/pad_compact.dart';

class PadDashboardStatCard extends StatelessWidget {
  const PadDashboardStatCard({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
    this.accentColor = AppDesignTokens.primaryBlue,
    this.accentBackground = AppDesignTokens.skyLight,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color accentColor;
  final Color accentBackground;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;

    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(compact ? 28 : 32),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentBackground,
              borderRadius: BorderRadius.circular(18),
            ),
            child: SizedBox(
              width: compact ? 42 : 48,
              height: compact ? 42 : 48,
              child: Icon(icon, color: accentColor, size: compact ? 24 : 28),
            ),
          ),
          SizedBox(height: compact ? 14 : 16),
          Text(
            title,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            value,
            style: TextStyle(
              fontSize: compact ? 24 : 30,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
