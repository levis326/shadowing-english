import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/app_paths.dart';
import 'hive_registrar.g.dart';

Future<void> initHive() async {
  if (!kIsWeb) {
    final String path = (await AppPaths.dataDirectory()).path;
    await _migrateLegacyDataTo(path);
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

/// Best-effort, one-time migration of previously stored data (Hive boxes,
/// AI subtitle cache, imported course videos) from the platform user
/// directories into the portable data directory, so existing users keep
/// their 生词本、学习记录与课程 after the storage-location change.
Future<void> _migrateLegacyDataTo(String targetPath) async {
  if (!AppPaths.supportsPortableLayout) {
    return;
  }
  final Directory target = Directory(targetPath);
  for (final Future<Directory> Function() legacyProvider
      in <Future<Directory> Function()>[
    getApplicationSupportDirectory,
    getApplicationDocumentsDirectory,
  ]) {
    final Directory legacy;
    try {
      legacy = await legacyProvider();
    } catch (_) {
      continue;
    }
    if (legacy.path == target.path || !legacy.existsSync()) {
      continue;
    }
    // 1. Hive box files (生词本、短语本、学习记录、设置、登录信息).
    for (final FileSystemEntity entity in legacy.listSync(
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (!name.endsWith('.hive')) {
        continue;
      }
      await _copyFileIfMissing(
        entity,
        '${target.path}${Platform.pathSeparator}$name',
      );
    }
    // 2. Heavier content, copied file-by-file so a single failure never
    //    blocks the rest; already-copied files are skipped on retry.
    for (final String sub in <String>['asr_subtitles', 'imported_sources']) {
      final Directory source = Directory(
        '${legacy.path}${Platform.pathSeparator}$sub',
      );
      if (!source.existsSync()) {
        continue;
      }
      await _copyTreeIfMissing(
        source,
        Directory('${target.path}${Platform.pathSeparator}$sub'),
      );
    }
  }
}

Future<void> _copyFileIfMissing(File source, String targetPath) async {
  try {
    if (!File(targetPath).existsSync()) {
      await source.copy(targetPath);
    }
  } catch (_) {
    // Best effort; the user can still re-import/re-generate this data.
  }
}

Future<void> _copyTreeIfMissing(Directory source, Directory target) async {
  try {
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    await for (final FileSystemEntity entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final String relative = entity.path.substring(source.path.length + 1);
      final String destination =
          '${target.path}${Platform.pathSeparator}$relative';
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File && !File(destination).existsSync()) {
        await entity.copy(destination);
      }
    }
  } catch (_) {
    // Best effort; partial copies resume on the next launch.
  }
}
