import 'dart:convert';

import 'package:common_learn_english/features/player/presentation/embedded_subtitle_reference.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseEmbeddedSubtitleBytes 解析 ffmpeg 输出的 UTF-8 字幕', () {
    final List<PlayerSubtitleLine> lines = parseEmbeddedSubtitleBytes(
      utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nHello there\n'),
    );

    expect(lines, hasLength(1));
    expect(lines.single.english, 'Hello there');
    expect(lines.single.startMs, 1000);
  });

  test('parseEmbeddedSubtitleBytes 也能解析 GBK 的内嵌字幕', () {
    // ffmpeg 正常输出 UTF-8，但旧视频里的内嵌字幕可能是 GBK；
    // 这里验证字节是先解码、再解析，而不是按 systemEncoding 硬解。
    final List<PlayerSubtitleLine> lines = parseEmbeddedSubtitleBytes(<int>[
      ...utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n'),
      0xC4, 0xE3, 0xBA, 0xC3, // 你好
      ...utf8.encode('\n'),
    ]);

    expect(lines, hasLength(1));
    expect(lines.single.english, '你好');
  });

  test('parseEmbeddedSubtitleBytes 对空输出返回空列表', () {
    expect(parseEmbeddedSubtitleBytes(const <int>[]), isEmpty);
  });
}
