import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../utils/app_paths.dart';
import 'hive_registrar.g.dart';

/// 初始化本地数据。
///
/// 所有数据只保存在程序数据目录（桌面端即 `common_learn_english.exe` 同级的
/// `data` 文件夹），**不读取也不导入** Windows 用户目录（`%APPDATA%`、文档目录）
/// 中的任何旧数据：新解压的程序一定从初始状态开始。
Future<void> initHive() async {
  if (!kIsWeb) {
    final String path = (await AppPaths.dataDirectory()).path;
    Hive
      ..init(path)
      ..registerAdapters();
  }
  await Hive.openBox<String>('prefs');
}

/// Initializes Hive for boxes opened outside [initHive]
/// (the login and theme boxes). Uses the same portable data directory as
/// [initHive]; on web it keeps the default browser storage.
Future<void> initHiveStorage() async {
  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    Hive.init((await AppPaths.dataDirectory()).path);
  }
}
