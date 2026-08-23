import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'player_media_source.dart';
import 'player_mock_state.dart';

Future<List<PlayerSubtitleLine>> loadSubtitleLinesFromAsset(
  String assetPath,
) async {
  final String raw = await rootBundle.loadString(assetPath);
  return parseSubtitleLines(raw);
}

Future<List<PlayerSubtitleLine>> loadSubtitleLines(String source) async {
  final String raw = await loadPlayerTextSource(source);
  return parseSubtitleLines(raw);
}

List<PlayerSubtitleLine> mergeSubtitleLines({
  required List<PlayerSubtitleLine> englishLines,
  required List<PlayerSubtitleLine> chineseLines,
}) {
  if (englishLines.isEmpty) {
    return const <PlayerSubtitleLine>[];
  }

  return List<PlayerSubtitleLine>.generate(englishLines.length, (int index) {
    final PlayerSubtitleLine englishLine = englishLines[index];
    final String chinese = index < chineseLines.length
        ? (chineseLines[index].chinese.isNotEmpty
              ? chineseLines[index].chinese
              : chineseLines[index].english)
        : '';

    return PlayerSubtitleLine(
      startTime: englishLine.startTime,
      english: englishLine.english,
      chinese: chinese,
      startMs: englishLine.startMs,
      endMs: englishLine.endMs,
      words: englishLine.words,
    );
  });
}

List<PlayerSubtitleLine> parseSubtitleLines(String rawSubtitle) {
  final String trimmed = rawSubtitle.trimLeft();
  if (trimmed.startsWith('{')) {
    return _parseGeneratedWordsJson(rawSubtitle);
  }

  // ponytail: parser supports SRT/VTT lines with basic bilingual cue split, no extra dependency.
  final List<String> lines = rawSubtitle
      .replaceAll('\r\n', '\n')
      .replaceAll('\uFEFF', '')
      .split('\n');
  final List<PlayerSubtitleLine> result = <PlayerSubtitleLine>[];

  final RegExp timingLine = RegExp(
    r'(?:(\d+:)?\d{2}:\d{2}[.,]\d{1,3})\s*-->\s*'
    r'(?:(\d+:)?\d{2}:\d{2}[.,]\d{1,3})',
  );

  for (int index = 0; index < lines.length; index++) {
    final String rawLine = lines[index].trim();
    if (rawLine.startsWith('WEBVTT')) {
      continue;
    }
    final Match? match = timingLine.firstMatch(rawLine);
    if (match == null) {
      continue;
    }

    final List<String> parts = rawLine.split('-->');
    if (parts.length != 2) {
      continue;
    }

    final int? startMs = _parseTimestampToMs(parts[0].trim());
    final int? endMs = _parseTimestampToMs(parts[1].trim());
    if (startMs == null || endMs == null || endMs <= startMs) {
      continue;
    }

    final List<String> textLines = <String>[];
    index += 1;
    while (index < lines.length) {
      final String textLine = lines[index].trim();
      if (textLine.isEmpty) {
        break;
      }
      textLines.add(textLine);
      index += 1;
    }
    final List<String> cleanedLines = textLines
        .map(
          (String textLine) => textLine
              .replaceAll(RegExp('<[^>]+>'), '')
              .trim()
              .replaceAll(RegExp(r'\{[^}]*\}'), ''),
        )
        .where((String textLine) => textLine.isNotEmpty)
        .toList(growable: false);
    if (cleanedLines.isEmpty) {
      continue;
    }

    final _DualLanguageLinePair pair = _splitDualLanguageLine(cleanedLines);
    result.add(
      PlayerSubtitleLine(
        startTime: _formatTimestamp(startMs),
        english: pair.english,
        chinese: pair.chinese,
        startMs: startMs,
        endMs: endMs,
      ),
    );
  }

  return result;
}

List<PlayerSubtitleLine> _parseGeneratedWordsJson(String rawSubtitle) {
  final Object? decoded = jsonDecode(rawSubtitle);
  if (decoded is! Map<String, dynamic>) {
    return const <PlayerSubtitleLine>[];
  }
  final Object? rawLines = decoded['lines'];
  if (rawLines is! List<dynamic>) {
    return const <PlayerSubtitleLine>[];
  }

  return rawLines
      .whereType<Map<String, dynamic>>()
      .map(_parseGeneratedWordsLine)
      .whereType<PlayerSubtitleLine>()
      .toList(growable: false);
}

Map<String, String> parseSubtitleGlossary(String rawSubtitle) {
  final Object? decoded = jsonDecode(rawSubtitle);
  if (decoded is! Map<String, dynamic>) return const <String, String>{};
  final Map<String, String> glossary = <String, String>{};
  for (final Object? item
      in decoded['glossary'] as List<dynamic>? ?? const <dynamic>[]) {
    if (item is! Map<String, dynamic>) continue;
    final String word = (item['word'] as String? ?? '').trim().toLowerCase();
    final String definition = (item['definitionCn'] as String? ?? '').trim();
    if (RegExp(r'^[a-z]{2,}$').hasMatch(word) && definition.isNotEmpty) {
      glossary.putIfAbsent(word, () => definition);
    }
  }
  return glossary;
}

PlayerSubtitleLine? _parseGeneratedWordsLine(Map<String, dynamic> json) {
  final int? startMs = _intOrNull(json['startMs']);
  final int? endMs = _intOrNull(json['endMs']);
  if (startMs == null || endMs == null || endMs <= startMs) {
    return null;
  }

  final List<PlayerSubtitleWord> words =
      (json['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> wordJson) {
            final String text = (wordJson['text'] as String? ?? '').trim();
            final int? wordStartMs = _intOrNull(wordJson['startMs']);
            final int? wordEndMs = _intOrNull(wordJson['endMs']);
            if (text.isEmpty ||
                wordStartMs == null ||
                wordEndMs == null ||
                wordEndMs <= wordStartMs ||
                wordStartMs < startMs ||
                wordEndMs > endMs) {
              return null;
            }
            return PlayerSubtitleWord(
              text: text,
              startMs: wordStartMs,
              endMs: wordEndMs,
              confidence: _doubleOrNull(wordJson['confidence']),
            );
          })
          .whereType<PlayerSubtitleWord>()
          .toList(growable: false);

  return PlayerSubtitleLine(
    startTime: _formatTimestamp(startMs),
    english: (json['english'] as String? ?? '').trim(),
    chinese: (json['chinese'] as String? ?? '').trim(),
    startMs: startMs,
    endMs: endMs,
    words: words,
  );
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return null;
}

double? _doubleOrNull(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

int? _parseTimestampToMs(String? value) {
  if (value == null) {
    return null;
  }
  final RegExp match = RegExp(
    r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?$',
  );
  final Match? matchResult = match.firstMatch(value.trim());
  if (matchResult == null) {
    return null;
  }

  final int hours = int.tryParse(matchResult.group(1) ?? '0') ?? 0;
  final int minutes = int.tryParse(matchResult.group(2) ?? '0') ?? 0;
  final int seconds = int.tryParse(matchResult.group(3) ?? '0') ?? 0;
  final String normalizedMilliseconds = matchResult.group(4) ?? '0';
  final int milliseconds = int.parse(
    normalizedMilliseconds.padRight(3, '0').substring(0, 3),
  );
  return (((hours * 60 + minutes) * 60) + seconds) * 1000 + milliseconds;
}

String _formatTimestamp(int milliseconds) {
  final int totalSeconds = milliseconds ~/ 1000;
  final int totalMinutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${totalMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Converts word-level subtitle lines into a standard `.srt` document.
String subtitleLinesToSrt(List<PlayerSubtitleLine> lines, {bool chinese = false}) {
  final StringBuffer buffer = StringBuffer();
  int cueIndex = 0;
  for (final PlayerSubtitleLine line in lines) {
    final String text = (chinese ? line.chinese : line.english).trim();
    if (text.isEmpty || line.endMs <= line.startMs) {
      continue;
    }
    cueIndex += 1;
    buffer
      ..writeln(cueIndex)
      ..writeln(
        '${_srtTimestamp(line.startMs)} --> ${_srtTimestamp(line.endMs)}',
      )
      ..writeln(text)
      ..writeln();
  }
  return buffer.toString();
}

String _srtTimestamp(int milliseconds) {
  final int hours = milliseconds ~/ 3600000;
  final int minutes = (milliseconds % 3600000) ~/ 60000;
  final int seconds = (milliseconds % 60000) ~/ 1000;
  final int millis = milliseconds % 1000;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')},'
      '${millis.toString().padLeft(3, '0')}';
}

/// Returns the `.srt` filename derived from the video filename, e.g.
/// `Friends-S01E01.mp4` -> `Friends-S01E01.en.srt`.
String generatedSubtitleSrtFileName(
  String videoPath, {
  String languageCode = 'en',
}) {
  final String fileName = _fileNameOf(videoPath);
  final int dotIndex = fileName.lastIndexOf('.');
  final String stem = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  return '$stem.$languageCode.srt';
}

/// Returns the list of `.srt` filenames that [saveGeneratedSubtitleSrt] will
/// write for the given lines (`.en.srt`, plus `.zh.srt` when Chinese exists).
List<String> generatedSubtitleSrtFileNames(
  String videoPath,
  List<PlayerSubtitleLine> lines,
) {
  final bool hasChinese = lines.any(
    (PlayerSubtitleLine line) => line.chinese.trim().isNotEmpty,
  );
  return <String>[
    generatedSubtitleSrtFileName(videoPath),
    if (hasChinese) generatedSubtitleSrtFileName(videoPath, languageCode: 'zh'),
  ];
}

/// Saves the generated subtitle next to the video as `<basename>.en.srt` and
/// returns the written file path. When the lines contain Chinese translations,
/// a `<basename>.zh.srt` is written alongside it as well.
Future<String> saveGeneratedSubtitleSrt({
  required String videoPath,
  required List<PlayerSubtitleLine> lines,
}) async {
  final String enPath = '${File(videoPath).parent.path}'
      '${Platform.pathSeparator}${generatedSubtitleSrtFileName(videoPath)}';
  await File(enPath).writeAsString(subtitleLinesToSrt(lines), flush: true);

  final bool hasChinese = lines.any(
    (PlayerSubtitleLine line) => line.chinese.trim().isNotEmpty,
  );
  if (hasChinese) {
    final String zhPath = '${File(videoPath).parent.path}'
        '${Platform.pathSeparator}${generatedSubtitleSrtFileName(videoPath, languageCode: 'zh')}';
    await File(zhPath).writeAsString(
      subtitleLinesToSrt(lines, chinese: true),
      flush: true,
    );
  }
  return enPath;
}

String _fileNameOf(String path) {
  final int slash = path.lastIndexOf('/') + 1;
  final int backslash = path.lastIndexOf(String.fromCharCode(92)) + 1;
  final int index = slash > backslash ? slash : backslash;
  return index <= 0 ? path : path.substring(index);
}

_DualLanguageLinePair _splitDualLanguageLine(List<String> lines) {
  if (lines.isEmpty) {
    return const _DualLanguageLinePair(english: '', chinese: '');
  }
  if (lines.length == 1) {
    return _DualLanguageLinePair(english: lines.first, chinese: '');
  }

  final String firstLine = lines.first;
  final String secondLine = lines[1];
  if (!_containsChinese(secondLine) && !_containsChinese(firstLine)) {
    return _DualLanguageLinePair(english: lines.join(' '), chinese: '');
  }
  if (_containsChinese(secondLine) &&
      !_containsChinese(firstLine) &&
      lines.length == 2) {
    return _DualLanguageLinePair(english: firstLine, chinese: secondLine);
  }

  return _DualLanguageLinePair(
    english: firstLine,
    chinese: lines.sublist(1).join(' '),
  );
}

bool _containsChinese(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

class _DualLanguageLinePair {
  const _DualLanguageLinePair({required this.english, required this.chinese});

  final String english;
  final String chinese;
}
