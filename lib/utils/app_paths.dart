import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Central resolver for every app data location.
///
/// 桌面端（Windows / Linux）**严格便携**：所有文件都放在可执行文件
/// （`common_learn_english.exe`）同级的 `data` 目录里，**绝不使用**
/// `%APPDATA%`、文档目录等 Windows 用户目录 —— 这样把整个程序文件夹放在
/// U 盘里，换电脑运行也不会“丢数据”，也不会在不同电脑上产生分散的副本。
///
/// Layout (all paths relative to the executable directory):
///
///     data/                               Hive 数据（生词本、短语本、学习记录、设置）
///     data/imported_sources/              导入课程的视频与字幕文件
///     data/asr_subtitles/                 AI 字幕缓存与生成任务
///     data/models/                        在线下载的本地模型
///     data/backup/                        本地备份
///     data/temp/                          临时录音、音频分片
///     data/updates/                       更新安装包下载
///     data/covers/                        自定义封面
///     data/Shadowing English/AI Subtitles/  导出的字幕文件
///
/// 只有 Android / iOS / macOS / web 这些无法把数据放在程序目录的平台，
/// 才使用 `path_provider` 提供的系统目录。
class AppPaths {
  AppPaths._();

  /// Prefix marking a path stored relative to the app data directory, e.g.
  /// `{appdata}/imported_sources/<course>/video.mp4`. Imported course paths
  /// are persisted in this form so they keep working when the app folder
  /// moves (USB drive letter changes, different computers).
  static const String portablePathPrefix = '{appdata}/';

  static String? _cachedDataDirectoryPath;
  static Future<Directory?>? _portableDataDirectory;

  /// Desktop platforms that use the portable, exe-relative layout.
  static bool get supportsPortableLayout =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// The directory that contains the running executable.
  static String get executableDirectory =>
      File(Platform.resolvedExecutable).parent.path;

  /// `<exe目录>/data`（桌面端恒定返回，不做可写性回退）；
  /// 其他平台返回 null，由调用方使用系统目录。
  static String? portableDataRootPathSync() => supportsPortableLayout
      ? '$executableDirectory${Platform.pathSeparator}data'
      : null;

  /// 已解析过的数据目录路径（同步返回）。应用启动时 [dataDirectory] 会写入缓存，
  /// 因此常规运行时这里总有值；桌面端恒定返回 exe 同级的 `data`，
  /// 其他平台在缓存前返回 null。
  static String? dataDirectoryPathSync() =>
      _cachedDataDirectoryPath ?? portableDataRootPathSync();

  static bool? _dataDirectoryWritableCache;

  /// 诊断用：数据目录当前是否可写（结果会缓存，首次调用时才真正探测）。
  /// 不可写时所有本地数据都会保存失败，设置页会给出提示
  /// （例如把程序解压到了 Program Files 这类受保护目录）。
  static bool isDataDirectoryWritableSync() =>
      _dataDirectoryWritableCache ??= _probeDataDirectoryWritableSync();

  static bool _probeDataDirectoryWritableSync() {
    final String? root = dataDirectoryPathSync();
    if (root == null || root.isEmpty) {
      return false;
    }
    final Directory dir = Directory(root);
    final File probe = File(
      '${dir.path}${Platform.pathSeparator}'
      '.cle_write_probe_${pid}_${Random().nextInt(1 << 32)}',
    );
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      probe
        ..writeAsStringSync('ok', flush: true)
        ..deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Converts an absolute path under [dataRootPath] into the portable
  /// `{appdata}/...` form; returns null for paths outside the data root.
  static String? toPortablePath(String absolutePath, String dataRootPath) {
    final String root = _normalizePath(dataRootPath);
    final String path = _normalizePath(absolutePath);
    if (path == root || !path.startsWith('$root/')) {
      return null;
    }
    return '$portablePathPrefix${path.substring(root.length + 1)}';
  }

  /// Resolves a stored path that may use the portable `{appdata}/...` form
  /// against [dataRootPath]. Other paths are returned unchanged.
  static String resolvePortablePath(String storedPath, String dataRootPath) {
    if (!storedPath.startsWith(portablePathPrefix)) {
      return storedPath;
    }
    final String relative = storedPath
        .substring(portablePathPrefix.length)
        .replaceAll('/', Platform.pathSeparator);
    return '$dataRootPath${Platform.pathSeparator}$relative';
  }

  /// Tries to rebase an absolute path that no longer exists onto the current
  /// data root. Paths below a known app-managed folder (`imported_sources`,
  /// `asr_subtitles`) are matched by their relative suffix, which makes old
  /// absolute paths (previous drive letter, older data locations) work again
  /// after the app folder moved. Returns null when no existing file can be
  /// found under the data root.
  static String? rebasePathToDataRoot(String path, String dataRootPath) {
    final String normalized = path.replaceAll(String.fromCharCode(92), '/');
    for (final String marker in <String>[
      'imported_sources',
      'asr_subtitles',
    ]) {
      final int index = normalized.indexOf('/$marker/');
      if (index < 0) {
        continue;
      }
      final String suffix = normalized.substring(index + 1);
      final String candidate =
          '$dataRootPath${Platform.pathSeparator}${suffix.replaceAll('/', Platform.pathSeparator)}';
      if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static String _normalizePath(String path) {
    return path.replaceAll(String.fromCharCode(92), '/');
  }

  /// `<exe目录>/data`（桌面端，恒可用）或 null（其他平台）。
  static Future<Directory?> portableDataDirectory() {
    final String? root = portableDataRootPathSync();
    if (root == null) {
      return Future<Directory?>.value();
    }
    return _portableDataDirectory ??= Directory(root).create(recursive: true);
  }

  /// Root directory for persistent app data (Hive boxes and caches).
  /// 桌面端只使用 exe 同级的 `data`；解析结果会缓存，供
  /// [dataDirectoryPathSync] 同步读取。
  static Future<Directory> dataDirectory() async {
    final Directory? portable = await portableDataDirectory();
    if (portable != null) {
      _cachedDataDirectoryPath = portable.path;
      return portable;
    }
    final Directory dir = await getApplicationSupportDirectory();
    _cachedDataDirectoryPath = dir.path;
    return dir;
  }

  /// Directory for transient files (recordings, audio chunks).
  /// 桌面端固定为 `<exe目录>/data/temp`，不使用系统临时目录。
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
  /// 桌面端固定为 `<exe目录>/data/updates`。
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
  /// `Shadowing English/AI Subtitles`. 桌面端就是数据目录本身，
  /// 其他平台使用系统下载目录。
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
