import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/player/presentation/player_course_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves subtitle paths from subtitle tracks', () {
    const List<LibraryCourseData> courses = <LibraryCourseData>[
      LibraryCourseData(
        id: 'course-1',
        title: 'Imported course',
        description: '',
        sourceLabel: '本地资源',
        coverImage: '',
        level: '自定义',
        category: '自选课程',
        progressPercent: 0,
        totalWords: 0,
        completedEpisodes: 0,
        totalEpisodes: 1,
        lastStudiedStr: '刚刚',
        rating: 4.7,
        episodes: <LibraryEpisodeItem>[
          LibraryEpisodeItem(
            id: 'course-1-ep01',
            numberStr: '01',
            title: 'Episode 1',
            durationMinutes: 30,
            hasChineseSubtitles: true,
            hasEnglishSubtitles: true,
            completed: false,
            progressPercent: 0,
            coverImage: '',
            subtitleTracks: <LibrarySubtitleTrackItem>[
              LibrarySubtitleTrackItem(
                languageCode: 'en',
                languageLabel: '英文字幕',
                path: '/tmp/episode.en.srt',
              ),
              LibrarySubtitleTrackItem(
                languageCode: 'zh-Hans',
                languageLabel: '中文字幕',
                path: '/tmp/episode.zh.srt',
              ),
            ],
          ),
        ],
      ),
    ];

    final PlayerCourseLookupResult result = resolvePlayerCourseForEpisode(
      courses: courses,
      episodeId: 'course-1-ep01',
    );

    expect(result.englishSubtitleAsset, '/tmp/episode.en.srt');
    expect(result.chineseSubtitleAsset, '/tmp/episode.zh.srt');
  });
}
