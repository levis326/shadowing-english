import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config/theme/theme_logic.dart';
import 'config/theme/theme_ui_model.dart';
import 'flavors/app_flavor.dart';
import 'router/app_router.dart';
import 'utils/app_fonts.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeUiModel currentTheme = ref.watch(themeLogicProvider);
    final GoRouter router = ref.watch(goRouterProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: MaterialApp.router(
        routerConfig: router,

        /// Localization is not available for the title.
        title: FlavorConfig.appName,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),

        themeMode: currentTheme.themeMode,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        builder: (BuildContext context, Widget? child) {
          final MediaQueryData mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: TextScaler.linear(
                _textScaleForWidth(mediaQuery.size.width),
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

double _textScaleForWidth(double width) {
  if (width <= 430) {
    return 0.82;
  }
  if (width <= 768) {
    return 0.86;
  }
  if (width <= 1280) {
    return 0.91;
  }
  return 0.95;
}

/// 应用主题（测试里也直接用这个函数检查字体回退等设置）。
ThemeData buildAppTheme(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xFF0875D8),
    primary: const Color(0xFF0875D8),
    surface: isDark ? const Color(0xFF17181D) : Colors.white,
  ).copyWith(
    primary: const Color(0xFF0875D8),
    onPrimary: Colors.white,
    secondary: const Color(0xFFD9D8DE),
    onSecondary: const Color(0xFF222226),
    surface: isDark ? const Color(0xFF17181D) : Colors.white,
    onSurface: isDark ? Colors.white : const Color(0xFF050505),
  );

  /// Nunito 字体已通过 pubspec 的 `fonts:` 直接打包，这里只用字体族名。
  /// 不再走 google_fonts：它会把字体缓存到
  /// `getApplicationSupportDirectory()`（Windows 上是 `%APPDATA%`），
  /// 还会在缺字体时联网下载，都不符合"全部数据放在程序目录"的要求。
  ///
  /// `fontFamilyFallback` 显式指定简体中文字体：Nunito 没有汉字字形，
  /// 不指定时会回退到日文/繁体中文字体，出现「门」等字形不合简体规范的问题。
  final TextTheme textTheme = ThemeData.light().textTheme
      .apply(fontFamily: 'Nunito', fontFamilyFallback: kCjkFontFallback)
      .apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    textTheme: textTheme,
    visualDensity: const VisualDensity(horizontal: -0.5, vertical: -0.5),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF101115)
        : const Color(0xFFEFEFF2),
    cardColor: colorScheme.surface,
    dividerColor: isDark ? const Color(0xFF2C2D33) : const Color(0xFFD8D8DD),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF0875D8),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      margin: EdgeInsets.zero,
    ),
  );
}

Future<void> setPreferredOrientations() {
  return SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}
