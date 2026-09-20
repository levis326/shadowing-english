import 'dart:io';

import 'package:media_kit/media_kit.dart';

import '../../../utils/text_encoding.dart';
import 'desktop_ffmpeg.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';

/// 把 ffmpeg 输出的 `.srt` 字节解析成字幕行（自动识别 UTF-8 / GBK 等编码）。
List<PlayerSubtitleLine> parseEmbeddedSubtitleBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    return const <PlayerSubtitleLine>[];
  }
  return parseSubtitleLines(decodeTextBytes(bytes));
}

Future<List<PlayerSubtitleLine>> extractEmbeddedEnglishSubtitles({
  required String videoPath,
  required List<SubtitleTrack> tracks,
}) async {
  try {
    final int index = tracks.indexWhere(
      (SubtitleTrack track) =>
          track.language == 'eng' || track.language == 'en',
    );
    if (index < 0) return const <PlayerSubtitleLine>[];
    final String? ffmpeg = await findDesktopFfmpeg();
    if (ffmpeg == null) return const <PlayerSubtitleLine>[];
    final ProcessResult result = await Process.run(
      ffmpeg,
      <String>[
        '-v',
        'error',
        '-i',
        videoPath,
        '-map',
        '0:s:$index',
        '-f',
        'srt',
        '-',
      ],
      // 取原始字节自己解码：ffmpeg 输出 UTF-8，而 Dart 默认按 systemEncoding
      // 解（中文 Windows 是 GBK），会把内嵌字幕里的中文读成乱码。
      stdoutEncoding: null,
    );
    if (result.exitCode != 0 || result.stdout is! List<int>) {
      return const <PlayerSubtitleLine>[];
    }
    return parseEmbeddedSubtitleBytes(result.stdout as List<int>);
  } catch (_) {
    // Embedded subtitles are optional and must not prevent video playback.
    return const <PlayerSubtitleLine>[];
  }
}
