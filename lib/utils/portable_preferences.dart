import 'package:flutter/foundation.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 把 `shared_preferences` 换成纯内存实现。
///
/// 本应用要求所有数据都放在 exe 同级的 `data` 目录（可随 U 盘整体拷贝），
/// 而 Windows 上的 `shared_preferences` 会写入
/// `%APPDATA%\com.tidesparrow\common_learn_english\shared_preferences.json`，
/// 底层 `path_provider` 甚至会**创建**该目录 —— 即使用户什么都没改。
/// `easy_localization` 初始化语言时会读取这个存储，所以这里直接替换成内存实现：
/// 读写都不会触碰用户目录，界面语言改由 Hive 的 `data/prefs.hive` 保存。
///
/// 仅在桌面端安装（Android/iOS 上平台存储是正常的应用数据位置）。
void installPortablePreferenceStore() {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.linux &&
          defaultTargetPlatform != TargetPlatform.macOS)) {
    return;
  }
  SharedPreferencesStorePlatform.instance =
      InMemorySharedPreferencesStore.empty();
}
