import 'package:flutter/material.dart';

class AppDesignTokens {
  AppDesignTokens._();

  static const Color brandGreen = Color(0xFF58CC02);
  static const Color brandGreenDark = Color(0xFF46A302);
  static const Color primaryBlue = Color(0xFF1CB0F6);
  static const Color primaryBlueDark = Color(0xFF0B8FD3);
  static const Color yellow = Color(0xFFFFC800);
  static const Color orange = Color(0xFFFF9600);
  static const Color pinkLight = Color(0xFFFFD3EE);
  static const Color skyLight = Color(0xFFDDF7FF);
  static const Color purpleLight = Color(0xFFEFE3FF);
  static const Color appWhite = Color(0xFFFFFFFF);
  static const Color softWhite = Color(0xFFFAFAFA);
  static const Color softGray = Color(0xFFF2F0F4);
  static const Color borderGray = Color(0xFFE5E5E5);
  static const Color textPrimary = Color(0xFF4B4B4B);
  static const Color textSecondary = Color(0xFF777777);

  static const List<BoxShadow> toyCardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> toyButtonShadow = <BoxShadow>[
    BoxShadow(
      color: brandGreenDark,
      offset: Offset(0, 5),
    ),
  ];
}
