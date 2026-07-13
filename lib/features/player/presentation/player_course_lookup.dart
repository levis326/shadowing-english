import '../../library/presentation/library_mock_data.dart';

class PlayerCourseLookupResult {
  const PlayerCourseLookupResult({
    this.course,
    this.episode,
    this.videoAsset,
    this.englishSubtitleAsset,
    this.chineseSubtitleAsset,
    this.subtitleTracks = const <LibrarySubtitleTrackItem>[],
  });

  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;
  final String? videoAsset;
  final String? englishSubtitleAsset;
  final String? chineseSubtitleAsset;
  final List<LibrarySubtitleTrackItem> subtitleTracks;

  bool get hasEpisode => episode != null;
}

PlayerCourseLookupResult resolvePlayerCourseForEpisode({
  required List<LibraryCourseData> courses,
  required String episodeId,
}) {
  for (final LibraryCourseData course in courses) {
    for (final LibraryEpisodeItem episode in course.episodes) {
      if (episode.id == episodeId) {
        return PlayerCourseLookupResult(
          course: course,
          episode: episode,
          videoAsset: episode.videoAsset,
          englishSubtitleAsset:
              episode.enSubtitleAsset ?? _resolveTrackPath(episode, 'en'),
          chineseSubtitleAsset:
              episode.cnSubtitleAsset ?? _resolveTrackPath(episode, 'zh'),
          subtitleTracks: episode.subtitleTracks,
        );
      }
    }
  }
  return const PlayerCourseLookupResult();
}

String? _resolveTrackPath(LibraryEpisodeItem episode, String languageCode) {
  for (final LibrarySubtitleTrackItem track in episode.subtitleTracks) {
    if (track.languageCode.toLowerCase().startsWith(languageCode)) {
      return track.path;
    }
  }
  return null;
}
