import 'package:common_learn_english/utils/portable_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('installPortablePreferenceStore', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      SharedPreferencesStorePlatform.instance =
          InMemorySharedPreferencesStore.empty();
    });

    test('desktop uses an in-memory store instead of %APPDATA%', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      installPortablePreferenceStore();
      expect(
        SharedPreferencesStorePlatform.instance,
        isA<InMemorySharedPreferencesStore>(),
      );
    });

    test('shared_preferences stays usable and never touches the file system',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      installPortablePreferenceStore();

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);

      await prefs.setString('locale', 'tr');
      expect(prefs.getString('locale'), 'tr');
      // 值只留在内存里，重新读取（同一 store）仍然是内存数据。
      expect(
        SharedPreferencesStorePlatform.instance,
        isA<InMemorySharedPreferencesStore>(),
      );
    });

    test('non-desktop platforms keep the default platform store', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final SharedPreferencesStorePlatform before =
          SharedPreferencesStorePlatform.instance;
      installPortablePreferenceStore();
      expect(SharedPreferencesStorePlatform.instance, same(before));
    });
  });
}
