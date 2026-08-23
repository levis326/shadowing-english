import 'package:media_kit/media_kit.dart';

List<SubtitleTrack> embeddedSubtitleTracks(Iterable<SubtitleTrack> tracks) {
  return tracks
      .where((SubtitleTrack track) => track.id != 'auto' && track.id != 'no')
      .toList(growable: false);
}

String embeddedSubtitleTrackLabel(SubtitleTrack track) {
  final String language = switch (track.language) {
    'eng' || 'en' => '英语',
    'chi' || 'zho' || 'zh' => '中文',
    final String value when value.trim().isNotEmpty => value,
    _ => '未知语言',
  };
  final String? title = track.title?.trim();
  return title == null || title.isEmpty ? language : '$language · $title';
}

const String embeddedSubtitleModeOff = '关闭内置字幕';
const String embeddedSubtitleModeForeign = '外文';
const String embeddedSubtitleModeBilingual = '双语';
const List<String> embeddedSubtitleModes = <String>[
  embeddedSubtitleModeOff,
  embeddedSubtitleModeForeign,
  embeddedSubtitleModeBilingual,
];

bool _isEnglishSubtitleTrack(SubtitleTrack track) {
  final String language = (track.language ?? '').trim().toLowerCase();
  return language == 'eng' || language == 'en';
}

bool _isChineseSubtitleTrack(SubtitleTrack track) {
  final String language = (track.language ?? '').trim().toLowerCase();
  return language == 'chi' || language == 'zho' || language == 'zh';
}

/// Maps a built-in subtitle display mode to a concrete embedded track.
///
/// `外文` prefers the English (foreign-language) track and `双语` prefers the
/// Chinese track (paired with the app's foreign learning subtitle to form a
/// bilingual view). Falls back to the first available track when no matching
/// language exists.
SubtitleTrack? embeddedSubtitleTrackForMode(
  List<SubtitleTrack> tracks,
  String mode,
) {
  if (mode == embeddedSubtitleModeOff || tracks.isEmpty) {
    return null;
  }
  final bool wantEnglish = mode == embeddedSubtitleModeForeign;
  for (final SubtitleTrack track in tracks) {
    final bool matches = wantEnglish
        ? _isEnglishSubtitleTrack(track)
        : _isChineseSubtitleTrack(track);
    if (matches) {
      return track;
    }
  }
  return tracks.first;
}
