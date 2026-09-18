import 'dart:io';

import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';

/// 生成来源标记：这份 AI 字幕是用「字幕文本文件」生成的
/// （本地 Whisper 只负责时间轴，文字以文件为准）。
const String subtitleTextSourceLabel = 'subtitle-text';

/// 「字幕文本文件」的解析结果。
class SubtitleTextSource {
  const SubtitleTextSource({
    required this.lines,
    required this.hasTimings,
    this.fileName = '',
  });

  /// 文件里的字幕行。纯文本时 startMs/endMs 为 0（时间轴稍后由本地
  /// Whisper 对齐），带时间轴的 .srt/.vtt 时直接可用。
  final List<PlayerSubtitleLine> lines;

  /// 文件是否自带时间轴（`.srt` / `.vtt`）。
  final bool hasTimings;

  final String fileName;

  int get sentenceCount => lines.length;

  String get displayName => fileName.isEmpty ? '字幕文本' : fileName;
}

/// 解析字幕文本文件的内容。
///
///  - 带时间轴（含 `-->`）的 `.srt` / `.vtt`，或应用导出的词级 JSON：直接用文件里的时间轴；
///  - 纯文本：按句子标点拆成一句一条，没有时间轴，之后由本地 Whisper 对齐。
SubtitleTextSource parseSubtitleTextFile(String raw, {String fileName = ''}) {
  final String normalized = raw.replaceAll('\r\n', '\n').replaceAll('\uFEFF', '');
  // 带时间轴的 .srt/.vtt，或应用自己导出的词级 JSON 字幕，都自带时间轴。
  if (_hasTimingCues(normalized) || normalized.trimLeft().startsWith('{')) {
    final List<PlayerSubtitleLine> timed = parseSubtitleLines(normalized)
        .where((PlayerSubtitleLine line) => line.english.trim().isNotEmpty)
        .toList(growable: false);
    if (timed.isNotEmpty) {
      return SubtitleTextSource(
        lines: timed,
        hasTimings: true,
        fileName: fileName,
      );
    }
  }
  final List<PlayerSubtitleLine> sentences = splitSubtitleTextIntoSentences(
    normalized,
  )
      .map(
        (String text) => PlayerSubtitleLine(
          startTime: '00:00',
          english: text,
          chinese: '',
          startMs: 0,
          endMs: 0,
        ),
      )
      .toList(growable: false);
  return SubtitleTextSource(
    lines: sentences,
    hasTimings: false,
    fileName: fileName,
  );
}

/// 读取并解析字幕文本文件（支持 `UTF-8`，带 BOM 也能识别）。
Future<SubtitleTextSource> loadSubtitleTextFile(String path) async {
  final String raw = await File(path).readAsString();
  return parseSubtitleTextFile(raw, fileName: _fileName(path));
}

/// 把纯文本按句子标点拆成一句一条（与 AI 字幕的拆行规则一致：
/// `. , ! ? ; : 。 ， ！ ？ ； ：`，逗号等由后续拆行步骤处理）。
List<String> splitSubtitleTextIntoSentences(String raw) {
  final List<String> sentences = <String>[];
  final StringBuffer buffer = StringBuffer();
  const String enders = '.!?;:。！？；：';
  const String closers = '"\'”’)]）】》';
  final List<int> runes = raw.replaceAll('\r\n', '\n').runes.toList();

  void flush() {
    final String text = buffer.toString().trim();
    buffer.clear();
    if (text.isEmpty) {
      return;
    }
    if (!text.contains(RegExp('[A-Za-z0-9]')) &&
        !text.contains(RegExp(r'[\u4e00-\u9fff]'))) {
      return;
    }
    sentences.add(text);
  }

  for (int index = 0; index < runes.length; index += 1) {
    final String char = String.fromCharCode(runes[index]);
    if (char == '\n') {
      flush();
      continue;
    }
    buffer.write(char);
    if (!enders.contains(char)) {
      continue;
    }
    // 小数点（3.5）与省略号不当作句子结束。
    if (char == '.') {
      final String? previous = index > 0
          ? String.fromCharCode(runes[index - 1])
          : null;
      final String? next = index + 1 < runes.length
          ? String.fromCharCode(runes[index + 1])
          : null;
      if (next == '.') {
        continue;
      }
      if (previous != null &&
          next != null &&
          _isDigit(previous) &&
          _isDigit(next)) {
        continue;
      }
    }
    // 把紧跟在标点后的引号、括号一起并进这一句。
    int cursor = index + 1;
    while (cursor < runes.length &&
        closers.contains(String.fromCharCode(runes[cursor]))) {
      buffer.write(String.fromCharCode(runes[cursor]));
      cursor += 1;
    }
    index = cursor - 1;
    flush();
  }
  flush();
  return sentences;
}

bool _hasTimingCues(String raw) {
  return RegExp(
    r'\d{1,2}:\d{2}(:\d{2})?[.,]\d{1,3}\s*-->\s*'
    r'\d{1,2}:\d{2}(:\d{2})?[.,]\d{1,3}',
  ).hasMatch(raw);
}

bool _isDigit(String char) => char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;

String _fileName(String path) {
  final String normalized = path.replaceAll(r'\', '/');
  final int index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}
