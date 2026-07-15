import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'desktop_ffmpeg.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';

Future<List<PlayerSubtitleLine>> extractEmbeddedEnglishSubtitles({
  required String videoPath,
  required List<SubtitleTrack> tracks,
}) async {
  final int index = tracks.indexWhere(
    (SubtitleTrack track) => track.language == 'eng' || track.language == 'en',
  );
  if (index < 0) return const <PlayerSubtitleLine>[];
  final String? ffmpeg = await findDesktopFfmpeg();
  if (ffmpeg == null) return const <PlayerSubtitleLine>[];
  final ProcessResult result = await Process.run(ffmpeg, <String>[
    '-v',
    'error',
    '-i',
    videoPath,
    '-map',
    '0:s:$index',
    '-f',
    'srt',
    '-',
  ]);
  if (result.exitCode != 0 || result.stdout is! String) {
    return const <PlayerSubtitleLine>[];
  }
  return parseSubtitleLines(result.stdout as String);
}
