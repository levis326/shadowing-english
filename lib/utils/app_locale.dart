import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';

/// 界面语言只保存在程序数据目录的 `prefs.hive`（`prefs` box）里，
/// 不使用 `shared_preferences`：Windows 上后者会写入 `%APPDATA%`。
const String _appLocaleStorageKey = 'app_locale_v1';

/// 应用支持的界面语言，需与 `main.dart` 中 `EasyLocalization.supportedLocales`
/// 保持一致。
const List<Locale> supportedAppLocales = <Locale>[Locale('en'), Locale('tr')];

/// 兜底语言。
const Locale fallbackAppLocale = Locale('en');

/// 读取已保存的界面语言；从未保存过时返回 null，
/// 让 easy_localization 按系统语言自动选择。
Locale? readSavedAppLocale() {
  if (!Hive.isBoxOpen('prefs')) {
    return null;
  }
  final String? stored = Hive.box<String>('prefs').get(_appLocaleStorageKey);
  if (stored == null || stored.isEmpty) {
    return null;
  }
  for (final Locale locale in supportedAppLocales) {
    if (locale.languageCode == stored) {
      return locale;
    }
  }
  return null;
}

/// 保存界面语言到 `<数据目录>/prefs.hive`。
Future<void> saveAppLocale(Locale locale) async {
  if (!Hive.isBoxOpen('prefs')) {
    return;
  }
  await Hive.box<String>('prefs').put(
    _appLocaleStorageKey,
    locale.languageCode,
  );
}

/// 恢复初始状态时清空已保存的界面语言。
Future<void> clearSavedAppLocale() async {
  if (!Hive.isBoxOpen('prefs')) {
    return;
  }
  await Hive.box<String>('prefs').delete(_appLocaleStorageKey);
}
