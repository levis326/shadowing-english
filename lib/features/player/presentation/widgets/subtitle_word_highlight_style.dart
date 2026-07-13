import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';

class SubtitleWordHighlightStyle {
  const SubtitleWordHighlightStyle._();

  static Color background(String style, {required bool highlighted}) {
    if (!highlighted) {
      return Colors.transparent;
    }
    switch (style) {
      case '黄色填充':
        return const Color(0xFFFFF4C2);
      case '蓝色填充':
        return const Color(0xFFE0F2FE);
      case '下划线':
        return const Color(0xFFE6FAFF);
      case '描边':
        return const Color(0xFFF1F5F9);
      default:
        return Colors.transparent;
    }
  }

  static Color borderColor(String style, {required bool highlighted}) {
    if (!highlighted) {
      return Colors.transparent;
    }
    switch (style) {
      case '黄色填充':
        return const Color(0xFFFFC107);
      case '蓝色填充':
        return const Color(0xFF2196F3);
      case '描边':
        return const Color(0xFF64748B);
      case '下划线':
        return Colors.transparent;
      default:
        return AppDesignTokens.brandGreen;
    }
  }

  static double borderWidth(String style, {required bool highlighted}) {
    return highlighted && style != '下划线' ? 1.5 : 0;
  }

  static TextDecoration? textDecoration(
    String style, {
    required bool highlighted,
  }) {
    return highlighted && style == '下划线' ? TextDecoration.underline : null;
  }

  static Color? textDecorationColor(String style, {required bool highlighted}) {
    return highlighted && style == '下划线' ? const Color(0xFF66E3FF) : null;
  }
}
