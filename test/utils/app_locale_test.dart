import 'dart:io';

import 'package:common_learn_english/utils/app_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  group('app locale store', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = Directory.systemTemp.createTempSync('app-locale-test-');
      Hive.init(hiveDir.path);
    });

    tearDown(() async {
      if (Hive.isBoxOpen('prefs')) {
        await Hive.box<String>('prefs').close();
      }
      await Hive.deleteBoxFromDisk('prefs');
      hiveDir.deleteSync(recursive: true);
    });

    test('returns null when the prefs box has not been opened yet', () {
      expect(readSavedAppLocale(), isNull);
      // 未初始化时读写都不应该抛异常。
      expect(saveAppLocale(const Locale('tr')), completes);
      expect(clearSavedAppLocale(), completes);
    });

    test('returns null when nothing was saved yet', () async {
      await Hive.openBox<String>('prefs');
      expect(readSavedAppLocale(), isNull);
    });

    test('saves and reads the selected locale', () async {
      await Hive.openBox<String>('prefs');
      await saveAppLocale(const Locale('tr'));
      expect(readSavedAppLocale(), const Locale('tr'));
      expect(Hive.box<String>('prefs').get('app_locale_v1'), 'tr');

      await saveAppLocale(const Locale('en'));
      expect(readSavedAppLocale(), const Locale('en'));
    });

    test('ignores unknown or malformed stored values', () async {
      final Box<String> box = await Hive.openBox<String>('prefs');
      await box.put('app_locale_v1', 'klingon');
      expect(readSavedAppLocale(), isNull);

      await box.put('app_locale_v1', '');
      expect(readSavedAppLocale(), isNull);
    });

    test('clears the saved locale', () async {
      await Hive.openBox<String>('prefs');
      await saveAppLocale(const Locale('tr'));
      await clearSavedAppLocale();
      expect(readSavedAppLocale(), isNull);
    });

    test('supported locales match the fallback contract', () {
      expect(
        supportedAppLocales.map((Locale l) => l.languageCode),
        <String>['en', 'tr'],
      );
      expect(supportedAppLocales, contains(fallbackAppLocale));
    });
  });
}
