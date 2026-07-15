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
