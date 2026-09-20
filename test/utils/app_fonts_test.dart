import 'package:common_learn_english/my_app.dart';
import 'package:common_learn_english/utils/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('简体中文字体排在中日韩回退顺序的最前面', () {
    // Windows / macOS / Linux(Android) 各自的简体中文字体。
    expect(kCjkFontFallback, contains('Microsoft YaHei UI'));
    expect(kCjkFontFallback, contains('PingFang SC'));
    expect(kCjkFontFallback, contains('Noto Sans CJK SC'));
    // 简体字体要排在繁体/日文字体（如果有）之前。
    final int yahei = kCjkFontFallback.indexOf('Microsoft YaHei UI');
    final int pinyin = kCjkFontFallback.indexOf('PingFang SC');
    expect(yahei, 0);
    expect(pinyin, lessThan(kCjkFontFallback.length));
  });

  test('应用主题的所有文字样式都带上中文回退字体', () {
    for (final Brightness brightness in Brightness.values) {
      final ThemeData theme = buildAppTheme(brightness);
      final TextTheme textTheme = theme.textTheme;
      final List<TextStyle?> styles = <TextStyle?>[
        textTheme.displayLarge,
        textTheme.headlineSmall,
        textTheme.titleLarge,
        textTheme.titleMedium,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.labelLarge,
        textTheme.labelSmall,
      ];
      for (final TextStyle? style in styles) {
        expect(style, isNotNull);
        // 拉丁字形仍然用打包的 Nunito。
        expect(style!.fontFamily, 'Nunito');
        // 汉字回退到简体中文字体，避免出现日文/繁体字形（如「门」）。
        expect(style.fontFamilyFallback, kCjkFontFallback);
      }
    }
  });
}
