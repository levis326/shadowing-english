import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../utils/app_paths.dart';
import '../../import_course/domain/import_match.dart';
import '../../player/presentation/asr_subtitle_cache.dart';
import '../../player/presentation/player_subtitle_loader.dart';
import 'library_mock_data.dart';

const String _libraryCatalogStorageKey = 'imported_library_courses_v1';

final NotifierProvider<LibraryCatalogNotifier, List<LibraryCourseData>>
libraryCatalogProvider =
    NotifierProvider<LibraryCatalogNotifier, List<LibraryCourseData>>(
      LibraryCatalogNotifier.new,
    );

class LibraryCatalogNotifier extends Notifier<List<LibraryCourseData>> {
  @override
  List<LibraryCourseData> build() {
    const List<LibraryCourseData> baseCatalog = libraryCourses;

    if (!Hive.isBoxOpen('prefs')) {
      return baseCatalog;
    }

    final String? stored = Hive.box<String>(
      'prefs',
    ).get(_libraryCatalogStorageKey);
    if (stored == null || stored.isEmpty) {
      return baseCatalog;
    }

    return <LibraryCourseData>[...baseCatalog, ..._decodeCourses(stored)];
  }

  Future<bool> importCourse(LibraryCourseData course) async {
    if (libraryCourses.any((LibraryCourseData item) => item.id == course.id)) {
      return false;
    }
    state = <LibraryCourseData>[
      course,
      ...state.where((LibraryCourseData item) => item.id != course.id),
    ];
    await _persistImportedCourses();
    return true;
  }

  Future<void> updateCoursesMetadata({
    required Set<String> courseIds,
    String? title,
    String? sourceLabel,
    String? coverImage,
  }) async {
    if (courseIds.isEmpty) {
      return;
    }
    // 便携化：自定义封面复制进应用数据目录（`<数据目录>/covers/`），
    // 随程序文件夹一起移动，换电脑后封面不会失效。封面文件很小，
    // 这里用同步复制，避免在只驱动帧的测试环境里等待真实异步 IO。
    final String? storedCover = coverImage == null || coverImage.trim().isEmpty
        ? null
        : (_copyCoverIntoDataDirectory(coverImage.trim()) ?? coverImage.trim());
    state = state
        .map((LibraryCourseData course) {
          if (!courseIds.contains(course.id)) {
            return course;
          }
          return course.copyWith(
            title: title == null || title.trim().isEmpty ? null : title.trim(),
            sourceLabel: sourceLabel == null || sourceLabel.trim().isEmpty
                ? null
                : sourceLabel.trim(),
            coverImage: storedCover,
          );
        })
        .toList(growable: false);
    await _persistImportedCourses();
  }

  /// 把封面文件同步复制到 `<数据目录>/covers/`；已在数据目录内则原样返回，
  /// 复制失败（或数据目录未解析）返回 null，调用方回退到原始路径。
  String? _copyCoverIntoDataDirectory(String sourcePath) {
    final String dataRootPath = AppPaths.dataDirectoryPathSync() ?? '';
    if (dataRootPath.isEmpty) {
      return null;
    }
    try {
      final File source = File(sourcePath);
      if (!source.existsSync()) {
        return null;
      }
      final String normalizedSource = source.path.replaceAll(
        String.fromCharCode(92),
        '/',
      );
      final String normalizedRoot = dataRootPath.replaceAll(
        String.fromCharCode(92),
        '/',
      );
      if (normalizedSource.startsWith('$normalizedRoot/')) {
        return source.path;
      }
      final String fileName = source.path.split(Platform.pathSeparator).last;
      final File target = File(
        '$dataRootPath${Platform.pathSeparator}covers'
        '${Platform.pathSeparator}$fileName',
      );
      if (target.path == source.path) {
        return source.path;
      }
      if (!target.existsSync() || target.lengthSync() != source.lengthSync()) {
        target.parent.createSync(recursive: true);
        source.copySync(target.path);
      }
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateEpisodeProgress({
    required String episodeId,
    required Duration position,
    required Duration duration,
  }) async {
    if (duration <= Duration.zero || position <= Duration.zero) {
      return;
    }
    final int nextProgress =
        ((position.inMilliseconds * 100) / duration.inMilliseconds)
            .round()
            .clamp(0, 100);
    bool changed = false;
    state = state
        .map((LibraryCourseData course) {
          final LibraryEpisodeItem? current = course.episodes
              .where((LibraryEpisodeItem item) => item.id == episodeId)
              .firstOrNull;
          if (current == null || nextProgress <= current.progressPercent) {
            return course;
          }
          changed = true;
          final List<LibraryEpisodeItem> episodes = course.episodes
              .map(
                (LibraryEpisodeItem item) => item.id == episodeId
                    ? item.copyWith(
                        progressPercent: nextProgress,
                        completed: nextProgress == 100,
                        lastWatchedStr: '刚刚学习',
                        progressTimeStr: _formatDuration(position),
                        totalTimeStr: _formatDuration(duration),
                      )
                    : item,
              )
              .toList(growable: false);
          final int completedEpisodes = episodes
              .where((LibraryEpisodeItem item) => item.completed)
              .length;
          final int courseProgress =
              (episodes.fold<int>(0, (int sum, LibraryEpisodeItem item) {
                        return sum + item.progressPercent;
                      }) /
                      episodes.length)
                  .round();
          return course.copyWith(
            episodes: episodes,
            progressPercent: courseProgress,
            completedEpisodes: completedEpisodes,
            lastStudiedStr: '刚刚学习',
          );
        })
        .toList(growable: false);
    if (changed) {
      await _persistImportedCourses();
    }
  }

  /// Attaches generated `.srt` subtitles to an episode so they are recognized
  /// as the episode's subtitles on subsequent loads. When a Chinese `.zh.srt`
  /// is provided it is attached as the Chinese subtitle as well, so the
  /// episode keeps showing bilingual subtitles even after the AI subtitle
  /// cache has been cleared.
  Future<void> attachSubtitleToEpisode({
    required String episodeId,
    required String enSubtitlePath,
    String? zhSubtitlePath,
  }) async {
    bool changed = false;
    state = state
        .map((LibraryCourseData course) {
          final LibraryEpisodeItem? current = course.episodes
              .where((LibraryEpisodeItem item) => item.id == episodeId)
              .firstOrNull;
          if (current == null) {
            return course;
          }
          changed = true;
          final List<LibrarySubtitleTrackItem> tracks =
              <LibrarySubtitleTrackItem>[
                LibrarySubtitleTrackItem(
                  languageCode: 'en',
                  languageLabel: '英文字幕',
                  path: enSubtitlePath,
                ),
                if (zhSubtitlePath != null && zhSubtitlePath.isNotEmpty)
                  LibrarySubtitleTrackItem(
                    languageCode: 'zh',
                    languageLabel: '中文字幕',
                    path: zhSubtitlePath,
                  ),
                ...current.subtitleTracks.where(
                  (LibrarySubtitleTrackItem track) =>
                      !track.languageCode.toLowerCase().startsWith('en') &&
                      !track.languageCode.toLowerCase().startsWith('zh'),
                ),
              ];
          final List<LibraryEpisodeItem> episodes = course.episodes
              .map(
                (LibraryEpisodeItem item) => item.id == episodeId
                    ? item.copyWith(
                        hasEnglishSubtitles: true,
                        hasChineseSubtitles:
                            zhSubtitlePath != null && zhSubtitlePath.isNotEmpty,
                        enSubtitleAsset: enSubtitlePath,
                        cnSubtitleAsset: zhSubtitlePath,
                        subtitleTracks: tracks,
                      )
                    : item,
              )
              .toList(growable: false);
          return course.copyWith(episodes: episodes);
        })
        .toList(growable: false);
    if (changed) {
      await _persistImportedCourses();
    }
  }

  /// 删掉随视频保存的生成字幕（`.en.srt` / `.zh.srt`）后，把剧集上对它们的
  /// 引用一并清掉：只清“程序生成的”那份，用户自己导入的字幕不受影响。
  Future<void> detachGeneratedSubtitles({
    required String episodeId,
    required String videoPath,
  }) async {
    if (videoPath.trim().isEmpty) {
      return;
    }
    final File video = File(videoPath);
    final Set<String> generatedNames = <String>{
      generatedSubtitleSrtFileName(videoPath).toLowerCase(),
      generatedSubtitleSrtFileName(videoPath, languageCode: 'zh').toLowerCase(),
    };
    bool isGenerated(String? path) {
      if (path == null || path.trim().isEmpty) {
        return false;
      }
      final String normalized = path.replaceAll(r'\', '/');
      final String name = normalized.split('/').last.toLowerCase();
      return generatedNames.contains(name) &&
          normalized.startsWith(
            video.parent.path.replaceAll(r'\', '/'),
          );
    }

    bool changed = false;
    state = state
        .map((LibraryCourseData course) {
          final LibraryEpisodeItem? current = course.episodes
              .where((LibraryEpisodeItem item) => item.id == episodeId)
              .firstOrNull;
          if (current == null) {
            return course;
          }
          final bool enGenerated = isGenerated(current.enSubtitleAsset);
          final bool zhGenerated = isGenerated(current.cnSubtitleAsset);
          if (!enGenerated && !zhGenerated) {
            return course;
          }
          changed = true;
          // 只移除指向“程序生成文件”的轨道，用户自己导入的字幕保留。
          final List<LibrarySubtitleTrackItem> tracks = current.subtitleTracks
              .where(
                (LibrarySubtitleTrackItem track) => !isGenerated(track.path),
              )
              .toList(growable: false);
          final List<LibraryEpisodeItem> episodes = course.episodes
              .map(
                (LibraryEpisodeItem item) => item.id == episodeId
                    ? item
                          .withoutGeneratedSubtitles(
                            clearEnglish: enGenerated,
                            clearChinese: zhGenerated,
                          )
                          .copyWith(subtitleTracks: tracks)
                    : item,
              )
              .toList(growable: false);
          return course.copyWith(episodes: episodes);
        })
        .toList(growable: false);
    if (changed) {
      await _persistImportedCourses();
    }
  }

  /// Resets watch progress for every episode while keeping the courses
  /// themselves (used by 设置 → 清除应用缓存与生词记录).
  Future<void> resetEpisodeProgress() async {
    state = state
        .map((LibraryCourseData course) {
          final List<LibraryEpisodeItem> episodes = course.episodes
              .map(
                (LibraryEpisodeItem item) => item.copyWith(
                  completed: false,
                  progressPercent: 0,
                  lastWatchedStr: '',
                  progressTimeStr: '',
                  totalTimeStr: '',
                ),
              )
              .toList(growable: false);
          return course.copyWith(
            episodes: episodes,
            progressPercent: 0,
            completedEpisodes: 0,
            lastStudiedStr: '',
          );
        })
        .toList(growable: false);
    await _persistImportedCourses();
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> deleteCourses(Set<String> courseIds) async {
    if (courseIds.isEmpty) {
      return;
    }
    final List<LibraryCourseData> removedCourses = state
        .where((LibraryCourseData course) => courseIds.contains(course.id))
        .toList(growable: false);
    state = state
        .where((LibraryCourseData course) => !courseIds.contains(course.id))
        .toList(growable: false);
    await _deleteManagedImportDirectories(removedCourses);
    await _persistImportedCourses();
  }

  /// 删除全部已导入课程，包括它们复制到程序数据目录的视频、字幕文件，
  /// 以及对应的 AI 字幕缓存。内置课程不在此列，用户自己的原始视频文件
  /// （导入时的来源）也不会被删除。返回删除的课程数量。
  Future<int> deleteAllImportedCourses() async {
    final Set<String> baseCourseIds = libraryCourses
        .map((LibraryCourseData course) => course.id)
        .toSet();
    final List<LibraryCourseData> importedCourses = state
        .where(
          (LibraryCourseData course) => !baseCourseIds.contains(course.id),
        )
        .toList(growable: false);
    if (importedCourses.isEmpty) {
      return 0;
    }
    // 先清理 AI 字幕缓存（含该剧集的生成任务目录）。
    for (final LibraryCourseData course in importedCourses) {
      for (final LibraryEpisodeItem episode in course.episodes) {
        final String? videoPath = episode.videoAsset;
        if (videoPath == null || videoPath.isEmpty) {
          continue;
        }
        try {
          final File cacheFile = await const AsrSubtitleCache().cacheFileFor(
            episodeId: episode.id,
            videoPath: videoPath,
          );
          final Directory episodeCacheDir = cacheFile.parent;
          if (episodeCacheDir.existsSync()) {
            await episodeCacheDir.delete(recursive: true);
          }
        } catch (_) {
          // 单个缓存清理失败不影响课程删除。
        }
      }
    }
    await deleteCourses(
      importedCourses.map((LibraryCourseData course) => course.id).toSet(),
    );
    return importedCourses.length;
  }

  Future<bool> importCourseFromMatches({
    required List<ImportMatchRow> rows,
    required String videoFolder,
    required String subtitleFolder,
    String sourceLabel = '本地资源',
    String? targetCourseId,
    String? courseTitle,
  }) async {
    if (rows.isEmpty) {
      return false;
    }

    final LibraryCourseData? targetCourse = targetCourseId == null
        ? null
        : state
              .where((LibraryCourseData item) => item.id == targetCourseId)
              .firstOrNull;
    if (targetCourseId != null && targetCourse == null) {
      return false;
    }

    final String courseId =
        targetCourse?.id ?? _buildCourseId(videoFolder, rows);

    // 便携化：本地导入的视频/字幕先复制进应用数据目录
    // （`<数据目录>/imported_sources/<courseId>/`），课程媒体随程序文件夹移动，
    // 换电脑/换盘符后依然能播放；已在数据目录内的文件不重复复制。
    final List<ImportMatchRow> storedRows = await _copyRowsIntoDataDirectory(
      rows,
      courseId: courseId,
    );

    // 复制之后再按“存储后的路径”过滤已存在的剧集：重复导入同一批文件不会
    // 产生重复剧集（存储路径由源文件名决定，因此可稳定比较）。
    final List<ImportMatchRow> newRows = targetCourse == null
        ? storedRows
        : storedRows
              .where(
                (ImportMatchRow row) => !targetCourse.episodes.any(
                  (LibraryEpisodeItem episode) =>
                      episode.videoAsset == row.videoPath,
                ),
              )
              .toList(growable: false);
    if (newRows.isEmpty) {
      return false;
    }

    final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
      for (int index = 0; index < storedRows.length; index++)
        _buildEpisodeItem(
          storedRows[index],
          courseId: courseId,
          episodeId: _buildEpisodeId(
            courseId,
            storedRows[index],
            (targetCourse?.episodes.length ?? 0) + index,
          ),
          coverImage: '',
        ),
    ];

    if (targetCourse != null) {
      final List<LibraryEpisodeItem> mergedEpisodes = <LibraryEpisodeItem>[
        ...targetCourse.episodes,
        ...episodes,
      ];
      state = state
          .map(
            (LibraryCourseData course) => course.id == targetCourse.id
                ? course.copyWith(
                    description: '已导入课程 ${mergedEpisodes.length} 集',
                    totalEpisodes: mergedEpisodes.length,
                    episodes: mergedEpisodes,
                  )
                : course,
          )
          .toList(growable: false);
      await _persistImportedCourses();
      return true;
    }

    return importCourse(
      LibraryCourseData(
        id: courseId,
        title: courseTitle == null || courseTitle.trim().isEmpty
            ? _buildCourseTitle(videoFolder, rows)
            : courseTitle.trim(),
        description: '已导入课程 ${episodes.length} 集',
        sourceLabel: sourceLabel,
        coverImage: '',
        level: '自定义',
        category: '自选课程',
        progressPercent: 0,
        totalWords: 0,
        completedEpisodes: 0,
        totalEpisodes: episodes.length,
        lastStudiedStr: '刚刚导入',
        rating: 4.7,
        episodes: episodes,
      ),
    );
  }

  Future<void> _persistImportedCourses() async {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }

    // Paths below the app data directory are persisted in the portable
    // `{appdata}/...` form so they survive moving the app folder.
    final String dataRootPath = (await AppPaths.dataDirectory()).path;
    final List<Map<String, Object?>> importedCourses = state
        .where(
          (LibraryCourseData course) => !libraryCourses.any(
            (LibraryCourseData base) => base.id == course.id,
          ),
        )
        .map((LibraryCourseData course) => _serializeCourse(course, dataRootPath))
        .toList(growable: false);

    if (importedCourses.isEmpty) {
      await Hive.box<String>('prefs').delete(_libraryCatalogStorageKey);
      return;
    }

    await Hive.box<String>(
      'prefs',
    ).put(_libraryCatalogStorageKey, jsonEncode(importedCourses));
  }

  Map<String, Object?> _serializeCourse(
    LibraryCourseData course,
    String dataRootPath,
  ) {
    return <String, Object?>{
      'id': course.id,
      'title': course.title,
      'description': course.description,
      'sourceLabel': course.sourceLabel,
      'coverImage': _toStoredPath(course.coverImage, dataRootPath) ?? '',
      'level': course.level,
      'category': course.category,
      'progressPercent': course.progressPercent,
      'totalWords': course.totalWords,
      'completedEpisodes': course.completedEpisodes,
      'totalEpisodes': course.totalEpisodes,
      'lastStudiedStr': course.lastStudiedStr,
      'rating': course.rating,
      'episodes': course.episodes
          .map(
            (LibraryEpisodeItem item) => <String, Object?>{
              'id': item.id,
              'numberStr': item.numberStr,
              'title': item.title,
              'durationMinutes': item.durationMinutes,
              'hasChineseSubtitles': item.hasChineseSubtitles,
              'hasEnglishSubtitles': item.hasEnglishSubtitles,
              'completed': item.completed,
              'progressPercent': item.progressPercent,
              'coverImage': _toStoredPath(item.coverImage, dataRootPath) ?? '',
              'lastWatchedStr': item.lastWatchedStr,
              'progressTimeStr': item.progressTimeStr,
              'totalTimeStr': item.totalTimeStr,
              'videoAsset': _toStoredPath(item.videoAsset, dataRootPath),
              'enSubtitleAsset': _toStoredPath(
                item.enSubtitleAsset,
                dataRootPath,
              ),
              'cnSubtitleAsset': _toStoredPath(
                item.cnSubtitleAsset,
                dataRootPath,
              ),
              'subtitleTracks': item.subtitleTracks
                  .map(
                    (LibrarySubtitleTrackItem track) => <String, Object?>{
                      'languageCode': track.languageCode,
                      'languageLabel': track.languageLabel,
                      'path': _toStoredPath(track.path, dataRootPath),
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  /// Persisted form of a path: portable `{appdata}/...` when the path lives
  /// under the app data directory, otherwise unchanged.
  String? _toStoredPath(String? path, String dataRootPath) {
    if (path == null || path.trim().isEmpty || dataRootPath.isEmpty) {
      return path;
    }
    return AppPaths.toPortablePath(path, dataRootPath) ?? path;
  }

  /// Copies each row's video and subtitle files into
  /// `<数据目录>/imported_sources/<courseId>/` so imported courses travel with
  /// the app folder. Files already inside the data directory are left as-is.
  Future<List<ImportMatchRow>> _copyRowsIntoDataDirectory(
    List<ImportMatchRow> rows, {
    required String courseId,
  }) async {
    final Directory dataRoot = await AppPaths.dataDirectory();
    final String dataRootPath = dataRoot.path;

    final List<ImportMatchRow> storedRows = <ImportMatchRow>[];
    for (final ImportMatchRow row in rows) {
      final String? copiedVideo = await _copyIntoDataDirectory(
        row.videoPath,
        dataRootPath,
        courseId,
      );
      final Map<String, ImportSubtitleTrack> tracks =
          <String, ImportSubtitleTrack>{};
      for (final MapEntry<String, ImportSubtitleTrack> entry
          in row.subtitleTracks.entries) {
        final String? copiedTrack = await _copyIntoDataDirectory(
          entry.value.path,
          dataRootPath,
          courseId,
        );
        tracks[entry.key] = ImportSubtitleTrack(
          languageCode: entry.value.languageCode,
          languageLabel: entry.value.languageLabel,
          path: copiedTrack ?? entry.value.path,
        );
      }
      storedRows.add(
        row.copyWith(
          videoPath: copiedVideo ?? row.videoPath,
          subtitleTracks: tracks,
        ),
      );
    }
    return storedRows;
  }

  /// Copies one file into the course folder inside the app data directory.
  /// Returns the new path, the original path when the file is already inside
  /// the data directory, or null when copying failed (callers then keep the
  /// original in-place path).
  Future<String?> _copyIntoDataDirectory(
    String sourcePath,
    String dataRootPath,
    String courseId,
  ) async {
    if (sourcePath.trim().isEmpty) {
      return null;
    }
    final File source = File(sourcePath);
    if (!source.existsSync()) {
      return null;
    }
    final String normalizedSource = source.path.replaceAll(
      String.fromCharCode(92),
      '/',
    );
    final String normalizedRoot = dataRootPath.replaceAll(
      String.fromCharCode(92),
      '/',
    );
    if (normalizedSource.startsWith('$normalizedRoot/')) {
      return source.path;
    }
    final String fileName = source.path.split(Platform.pathSeparator).last;
    final File target = File(
      '$dataRootPath${Platform.pathSeparator}imported_sources'
      '${Platform.pathSeparator}$courseId${Platform.pathSeparator}$fileName',
    );
    if (target.path == source.path) {
      return source.path;
    }
    try {
      if (!target.existsSync() || target.lengthSync() != source.lengthSync()) {
        await target.parent.create(recursive: true);
        await source.copy(target.path);
      }
      return target.path;
    } catch (_) {
      // Best effort: on failure the original in-place path is still usable.
      return null;
    }
  }

  List<LibraryCourseData> _decodeCourses(String raw) {
    try {
      final List<Object?> parsed = jsonDecode(raw) as List<Object?>;
      return parsed
          .cast<Map<String, Object?>>()
          .map((Map<String, Object?> courseJson) {
            final List<LibraryEpisodeItem> episodes = _decodeEpisodes(
              courseId: courseJson['id']! as String,
              episodesJson: courseJson['episodes'] as List<Object?>?,
            );

            return LibraryCourseData(
              id: courseJson['id']! as String,
              title: courseJson['title']! as String,
              description: courseJson['description']! as String,
              sourceLabel: courseJson['sourceLabel'] as String? ?? '本地资源',
              coverImage:
                  _resolveStoredPath(courseJson['coverImage'] as String?) ?? '',
              level: courseJson['level']! as String,
              category: courseJson['category']! as String,
              progressPercent: courseJson['progressPercent']! as int,
              totalWords: courseJson['totalWords']! as int,
              completedEpisodes: courseJson['completedEpisodes']! as int,
              totalEpisodes: episodes.length,
              lastStudiedStr: courseJson['lastStudiedStr']! as String,
              rating: (courseJson['rating'] as num?)?.toDouble() ?? 0.0,
              episodes: episodes,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <LibraryCourseData>[];
    }
  }

  List<LibraryEpisodeItem> _decodeEpisodes({
    required String courseId,
    required List<Object?>? episodesJson,
  }) {
    if (episodesJson == null) {
      return const <LibraryEpisodeItem>[];
    }

    final Set<String> seenIds = <String>{};
    final List<Map<String, Object?>> items = episodesJson
        .cast<Map<String, Object?>>()
        .where(_shouldKeepStoredEpisode)
        .toList(growable: false);
    return <LibraryEpisodeItem>[
      for (int index = 0; index < items.length; index++)
        _decodeEpisodeItem(
          courseId: courseId,
          json: items[index],
          index: index,
          seenIds: seenIds,
        ),
    ];
  }

  LibraryEpisodeItem _decodeEpisodeItem({
    required String courseId,
    required Map<String, Object?> json,
    required int index,
    required Set<String> seenIds,
  }) {
    final String storedId = json['id'] as String? ?? '';
    final String resolvedId = storedId.isNotEmpty && seenIds.add(storedId)
        ? storedId
        : '$courseId-ep${(index + 1).toString().padLeft(2, '0')}';
    seenIds.add(resolvedId);

    return LibraryEpisodeItem(
      id: resolvedId,
      numberStr: json['numberStr']! as String,
      title: json['title']! as String,
      durationMinutes: json['durationMinutes']! as int,
      hasChineseSubtitles: json['hasChineseSubtitles']! as bool,
      hasEnglishSubtitles: json['hasEnglishSubtitles']! as bool,
      completed: json['completed']! as bool,
      progressPercent: json['progressPercent']! as int,
      coverImage: _resolveStoredPath(json['coverImage'] as String?) ?? '',
      lastWatchedStr: json['lastWatchedStr'] as String?,
      progressTimeStr: json['progressTimeStr'] as String?,
      totalTimeStr: json['totalTimeStr'] as String?,
      videoAsset: _resolveStoredPath(json['videoAsset'] as String?),
      enSubtitleAsset: _resolveStoredPath(json['enSubtitleAsset'] as String?),
      cnSubtitleAsset: _resolveStoredPath(json['cnSubtitleAsset'] as String?),
      subtitleTracks:
          ((json['subtitleTracks'] as List<Object?>?) ?? const <Object?>[])
              .cast<Map<String, Object?>>()
              .where(
                (Map<String, Object?> track) => ImportMatcher.isImportablePath(
                  track['path'] as String? ?? '',
                ),
              )
              .map(
                (Map<String, Object?> track) => LibrarySubtitleTrackItem(
                  languageCode: track['languageCode']! as String,
                  languageLabel: track['languageLabel']! as String,
                  path:
                      _resolveStoredPath(track['path'] as String?) ??
                      track['path']! as String,
                ),
              )
              .toList(growable: false),
    );
  }

  String _buildCourseId(String videoFolder, List<ImportMatchRow> rows) {
    final String prefix = videoFolder.isNotEmpty
        ? _slug(videoFolder.split(RegExp(r'[\\/]')).last.replaceAll('-', '_'))
        : rows.isNotEmpty
        ? _slug(_stripExtension(rows.first.videoFile))
        : 'imported_course';
    return rows.isNotEmpty && rows.first.videoFile.isNotEmpty
        ? '$prefix-${_slug(rows.first.videoFile)}'
        : 'imported_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _buildCourseTitle(String videoFolder, List<ImportMatchRow> rows) {
    final List<String> segments = videoFolder
        .split(RegExp(r'[\\/]'))
        .where((String item) => item.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isNotEmpty && segments.last.trim().isNotEmpty) {
      return segments.last.trim();
    }
    if (rows.isNotEmpty) {
      return _stripExtension(rows.first.videoFile).trim();
    }
    return '已导入课程';
  }

  bool _shouldKeepStoredEpisode(Map<String, Object?> json) {
    final String videoPath = json['videoAsset'] as String? ?? '';
    if (!ImportMatcher.isImportablePath(videoPath)) {
      return false;
    }

    final List<String> subtitlePaths = <String>[
      json['enSubtitleAsset'] as String? ?? '',
      json['cnSubtitleAsset'] as String? ?? '',
      ...(((json['subtitleTracks'] as List<Object?>?) ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map((Map<String, Object?> track) => track['path'] as String? ?? '')),
    ].where((String path) => path.trim().isNotEmpty).toList(growable: false);

    final bool containsVerifySubtitle = subtitlePaths.any(
      (String path) => !ImportMatcher.isImportablePath(path),
    );
    if (!containsVerifySubtitle) {
      return true;
    }

    final String normalizedVideoName = videoPath
        .replaceAll(r'\', '/')
        .split('/')
        .last
        .toLowerCase();
    final String normalizedTitle = (json['title'] as String? ?? '')
        .trim()
        .toLowerCase();
    return !normalizedVideoName.startsWith('lesson') &&
        !normalizedTitle.startsWith('lesson');
  }

  String? _sanitizeStoredPath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return path;
    }
    return ImportMatcher.isImportablePath(path) ? path : null;
  }

  String? _cachedDataRootPath;

  /// Current portable data root used to resolve stored paths; empty when the
  /// platform has no portable layout.
  String get _dataRootPathSync =>
      _cachedDataRootPath ??= AppPaths.portableDataRootPathSync() ?? '';

  /// Loads a stored path into a usable absolute path:
  ///  1. portable `{appdata}/...` paths are resolved against the current data
  ///     root;
  ///  2. paths that no longer exist are rebased onto the current data root
  ///     when they point below an app-managed folder (`imported_sources`,
  ///     `asr_subtitles`) — this recovers videos after the app folder moved
  ///     (new drive letter / new computer) or after old user-profile data was
  ///     migrated next to the executable.
  String? _resolveStoredPath(String? path) {
    final String? sanitized = _sanitizeStoredPath(path);
    if (sanitized == null) {
      return sanitized;
    }
    final String dataRootPath = _dataRootPathSync;
    if (dataRootPath.isEmpty) {
      return sanitized;
    }
    final String resolved = AppPaths.resolvePortablePath(
      sanitized,
      dataRootPath,
    );
    if (File(resolved).existsSync() || Directory(resolved).existsSync()) {
      return resolved;
    }
    return AppPaths.rebasePathToDataRoot(resolved, dataRootPath) ?? resolved;
  }

  String _buildEpisodeId(String courseId, ImportMatchRow row, int index) {
    final int episodeNumber = index + 1;
    return '$courseId-ep${episodeNumber.toString().padLeft(2, '0')}';
  }

  LibraryEpisodeItem _buildEpisodeItem(
    ImportMatchRow row, {
    required String courseId,
    required String episodeId,
    required String coverImage,
  }) {
    final String number = _extractEpisodeNumber(
      row.episodeName,
    ).toString().padLeft(2, '0');
    return LibraryEpisodeItem(
      subtitleTracks: row.subtitleTracks.values
          .map(
            (ImportSubtitleTrack track) => LibrarySubtitleTrackItem(
              languageCode: track.languageCode,
              languageLabel: track.languageLabel,
              path: track.path,
            ),
          )
          .toList(growable: false),
      id: episodeId,
      numberStr: number,
      title: row.episodeName,
      durationMinutes: 30,
      hasChineseSubtitles: row.hasChinese,
      hasEnglishSubtitles: row.hasEnglish,
      completed: false,
      progressPercent: 0,
      coverImage: coverImage,
      videoAsset: row.videoPath,
      enSubtitleAsset: row.englishSubtitlePath,
      cnSubtitleAsset: row.chineseSubtitlePath,
    );
  }

  int _extractEpisodeNumber(String name) {
    final RegExp matcher = RegExp(r'(\d+)');
    final Match? match = matcher.firstMatch(name);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '0') ?? 0;
  }

  String _stripExtension(String value) {
    final int index = value.lastIndexOf('.');
    if (index <= 0) {
      return value;
    }
    return value.substring(0, index);
  }

  String _slug(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_\$'), '');
  }

  Future<void> _deleteManagedImportDirectories(
    List<LibraryCourseData> courses,
  ) async {
    final Set<String> directories = <String>{};
    for (final LibraryCourseData course in courses) {
      for (final LibraryEpisodeItem episode in course.episodes) {
        for (final String? path in <String?>[
          episode.videoAsset,
          episode.enSubtitleAsset,
          episode.cnSubtitleAsset,
          ...episode.subtitleTracks.map(
            (LibrarySubtitleTrackItem item) => item.path,
          ),
        ]) {
          final String? managedDirectory = _managedImportDirectoryForPath(path);
          if (managedDirectory != null) {
            directories.add(managedDirectory);
          }
        }
      }
    }

    final List<String> sortedDirectories = directories.toList(growable: false)
      ..sort((String a, String b) => b.length.compareTo(a.length));
    for (final String directoryPath in sortedDirectories) {
      final Directory directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        continue;
      }
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        // ponytail: best-effort cleanup; stale files are less bad than blocked deletion.
      }
    }
  }

  String? _managedImportDirectoryForPath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }
    final String normalized = rawPath.replaceAll(r'\', '/');
    const String marker = '/imported_sources/';
    final int markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }

    final String prefix = normalized.substring(0, markerIndex + marker.length);
    final List<String> segments = normalized
        .substring(markerIndex + marker.length)
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }

    final List<String> managedSegments =
        segments.first == 'confirmed_imports' && segments.length >= 2
        ? <String>['confirmed_imports', segments[1]]
        : <String>[segments.first];
    return '$prefix${managedSegments.join('/')}';
  }
}
