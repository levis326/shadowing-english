import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Central resolver for every app data location.
///
/// On Windows / Linux desktop builds the app is fully portable: all data is
/// stored under the directory that contains the executable
/// (`common_learn_english.exe`), using relative sub-paths, so the whole app
/// folder can live on a USB drive and run on any computer without touching
/// the Windows user profile.
///
/// Layout (all paths relative to the executable directory):
///
///     data/                               Hive 数据（生词本、短语本、学习记录、
///                                         设置、登录信息）
///     data/asr_subtitles/                 AI 字幕缓存与生成任务
///     data/imported_sources/              在线导入的视频课程
///     data/backup/                        本地备份
///     data/temp/                          临时录音、音频分片
///     data/updates/                       更新安装包下载
///     data/Shadowing English/AI Subtitles/  导出的字幕文件
///
/// When the executable directory is not writable (e.g. the app was installed
/// into a protected folder), or on Android / iOS / macOS / web, the platform
/// directories provided by `path_provider` are used instead.
class AppPaths {
  AppPaths._();

  static Future<Directory?>? _portableDataDirectory;

  /// Desktop platforms that support the portable, exe-relative layout.
  static bool get supportsPortableLayout =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// The directory that contains the running executable.
  static String get executableDirectory =>
      File(Platform.resolvedExecutable).parent.path;

  /// `<exe目录>/data` when the portable layout is available and writable;
  /// otherwise null (and platform directories are used).
  static Future<Directory?> portableDataDirectory() {
    if (!supportsPortableLayout) {
      return Future<Directory?>.value();
    }
    return _portableDataDirectory ??= _resolvePortableDataDirectory();
  }

  static Future<Directory?> _resolvePortableDataDirectory() async {
    final Directory dir = Directory(
      '$executableDirectory${Platform.pathSeparator}data',
    );
    return await _isWritable(dir) ? dir : null;
  }

  static Future<bool> _isWritable(Directory dir) async {
    try {
      await dir.create(recursive: true);
      final File probe = File(
        '${dir.path}${Platform.pathSeparator}.cle_write_probe',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Root directory for persistent app data (Hive boxes and caches).
  static Future<Directory> dataDirectory() async =>
      await portableDataDirectory() ?? await getApplicationSupportDirectory();

  /// Directory for transient files (recordings, audio chunks).
  static Future<Directory> tempDirectory() async {
    final Directory? portable = await portableDataDirectory();
    if (portable == null) {
      return getTemporaryDirectory();
    }
    final Directory dir = Directory(
      '${portable.path}${Platform.pathSeparator}temp',
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// Directory where update packages are downloaded to.
  static Future<Directory> updatesDirectory() async {
    final Directory? portable = await portableDataDirectory();
    if (portable == null) {
      final Directory root =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final Directory dir = Directory(
        '${root.path}${Platform.pathSeparator}Shadowing English',
      );
      await dir.create(recursive: true);
      return dir;
    }
    final Directory dir = Directory(
      '${portable.path}${Platform.pathSeparator}updates',
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// Base directory under which subtitle exports are placed; callers append
  /// `Shadowing English/AI Subtitles`. Returns null when no downloads
  /// directory is available, in which case callers fall back to the data
  /// directory.
  static Future<Directory?> downloadsRootDirectory() async {
    final Directory? portable = await portableDataDirectory();
    if (portable != null) {
      return portable;
    }
    try {
      return await getDownloadsDirectory();
    } catch (_) {
      return null;
    }
  }
}
