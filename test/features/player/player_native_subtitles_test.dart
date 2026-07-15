import 'package:common_learn_english/features/player/presentation/player_native_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('keeps only selectable embedded subtitle tracks', () {
    final List<SubtitleTrack> tracks = embeddedSubtitleTracks(<SubtitleTrack>[
      SubtitleTrack.auto(),
      SubtitleTrack.no(),
      const SubtitleTrack('1', 'SDH', 'eng'),
      const SubtitleTrack('2', 'Simplified', 'chi'),
    ]);

    expect(tracks.map((SubtitleTrack track) => track.id), <String>['1', '2']);
  });

  test('uses readable labels for embedded subtitle tracks', () {
    expect(
      embeddedSubtitleTrackLabel(const SubtitleTrack('2', 'Simplified', 'chi')),
      '中文 · Simplified',
    );
  });
}
