import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Local backup & cache maintenance used by the settings screen.
///
/// Data is backed up into the `backup` subdirectory of the application
/// support directory (the directory where the app keeps its local data),
/// i.e. `<应用数据目录>/backup/<时间戳>/shadowing_backup.json`.
class LocalDataBackupService {
  const LocalDataBackupService({
    this.appSupportDirectory = getApplicationSupportDirectory,
    this.temporaryDirectory = getTemporaryDirectory,
  });

  final Future<Directory> Function() appSupportDirectory;
  final Future<Directory> Function() temporaryDirectory;

  /// Writes a complete snapshot of the locally stored learning data
  /// (the Hive `prefs` box: 生词本、短语本、学习记录、设置、课程与进度等)
  /// into a timestamped folder under `<应用数据目录>/backup/`.
  Future<File> backupToLocal() async {
    final Directory root = await appSupportDirectory();
    final Directory targetDir = Directory(
      '${root.path}${Platform.pathSeparator}backup'
      '${Platform.pathSeparator}${_timestampDirName()}',
    );
    await targetDir.create(recursive: true);

    final Map<String, dynamic> data = <String, dynamic>{};
    if (Hive.isBoxOpen('prefs')) {
      final Box<String> prefs = Hive.box<String>('prefs');
      for (final dynamic key in prefs.keys) {
        final String? raw = prefs.get(key);
        Object? value = raw;
        if (raw != null && raw.isNotEmpty) {
          try {
            value = jsonDecode(raw);
          } catch (_) {
            value = raw;
          }
        }
        data[key.toString()] = value;
      }
    }

    final File file = File(
      '${targetDir.path}${Platform.pathSeparator}shadowing_backup.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'app': 'TideSparrow English',
        'schemaVersion': 1,
        'backedUpAt': DateTime.now().toIso8601String(),
        'data': data,
      }),
      flush: true,
    );
    return file;
  }

  /// Deletes generated caches:
  ///  - the AI subtitle cache directory (`<应用数据目录>/asr_subtitles`);
  ///  - leftover app temp files (`pron_reading*.wav`, `cle_asr_*` chunks).
  ///
  /// Returns the number of removed files.
  Future<int> clearCachedFiles() async {
    int removed = 0;

    final Directory root = await appSupportDirectory();
    final Directory asrCache = Directory(
      '${root.path}${Platform.pathSeparator}asr_subtitles',
    );
    if (asrCache.existsSync()) {
      removed += _countFiles(asrCache);
      try {
        asrCache.deleteSync(recursive: true);
      } catch (_) {
        // Best effort; the count above is still reported.
      }
    }

    final List<Directory> tempRoots = <Directory>[
      Directory.systemTemp,
      await temporaryDirectory(),
    ];
    for (final Directory tempRoot in tempRoots) {
      if (!tempRoot.existsSync()) {
        continue;
      }
      for (final FileSystemEntity entity in tempRoot.listSync(
        followLinks: false,
      )) {
        final String name = entity.path
            .split(Platform.pathSeparator)
            .last;
        if (!name.startsWith('pron_reading') && !name.startsWith('cle_asr_')) {
          continue;
        }
        try {
          if (entity is Directory) {
            removed += _countFiles(entity);
            entity.deleteSync(recursive: true);
          } else if (entity is File) {
            removed += 1;
            entity.deleteSync();
          }
        } catch (_) {
          // Best effort; locked files are skipped.
        }
      }
    }
    return removed;
  }

  int _countFiles(Directory directory) {
    if (!directory.existsSync()) {
      return 0;
    }
    int count = 0;
    for (final FileSystemEntity entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        count += 1;
      }
    }
    return count;
  }

  String _timestampDirName() {
    final DateTime now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
