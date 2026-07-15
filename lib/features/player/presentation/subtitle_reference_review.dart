import 'dart:convert';

import 'player_mock_state.dart';

class SubtitleReferenceReview {
  const SubtitleReferenceReview({
    required this.comparedLines,
    required this.differentLines,
  });

  final int comparedLines;
  final int differentLines;
}

SubtitleReferenceReview reviewGeneratedSubtitles({
  required List<PlayerSubtitleLine> generated,
  required List<PlayerSubtitleLine> reference,
}) {
  int compared = 0;
  int different = 0;
  for (final PlayerSubtitleLine line in generated) {
    final PlayerSubtitleLine? match = _closest(line, reference);
    if (match == null || match.english.trim().isEmpty) continue;
    compared += 1;
    if (_normalized(line.english) != _normalized(match.english)) different += 1;
  }
  return SubtitleReferenceReview(
    comparedLines: compared,
    differentLines: different,
  );
}

List<PlayerSubtitleLine> adoptReferenceSubtitles({
  required List<PlayerSubtitleLine> generated,
  required List<PlayerSubtitleLine> reference,
}) => reference
    .map((PlayerSubtitleLine line) {
      final PlayerSubtitleLine? generatedMatch = _closest(line, generated);
      final List<String> referenceWords = _englishWords(line.english);
      final List<PlayerSubtitleWord> timedWords =
          generatedMatch != null &&
              generatedMatch.words.length == referenceWords.length &&
              generatedMatch.words.every(
                (PlayerSubtitleWord word) =>
                    word.startMs >= line.startMs && word.endMs <= line.endMs,
              )
          ? List<PlayerSubtitleWord>.generate(referenceWords.length, (
              int index,
            ) {
              final PlayerSubtitleWord timing = generatedMatch.words[index];
              return PlayerSubtitleWord(
                text: referenceWords[index],
                startMs: timing.startMs,
                endMs: timing.endMs,
                confidence: timing.confidence,
              );
            }, growable: false)
          : const <PlayerSubtitleWord>[];
      return PlayerSubtitleLine(
        startTime: line.startTime,
        english: line.english,
        chinese: line.chinese.isNotEmpty
            ? line.chinese
            : generatedMatch?.chinese ?? '',
        startMs: line.startMs,
        endMs: line.endMs,
        words: timedWords,
      );
    })
    .toList(growable: false);

String subtitleLinesToJson(
  List<PlayerSubtitleLine> lines, {
  Map<String, String> wordDefinitions = const <String, String>{},
}) => const JsonEncoder.withIndent('  ').convert(<String, Object?>{
  'lines': lines
      .map(
        (PlayerSubtitleLine line) => <String, Object?>{
          'startTime': line.startTime,
          'english': line.english,
          'chinese': line.chinese,
          'startMs': line.startMs,
          'endMs': line.endMs,
          'words': line.words
              .map(
                (PlayerSubtitleWord word) => <String, Object?>{
                  'text': word.text,
                  'startMs': word.startMs,
                  'endMs': word.endMs,
                  if (word.confidence != null) 'confidence': word.confidence,
                },
              )
              .toList(growable: false),
        },
      )
      .toList(growable: false),
  'glossary': wordDefinitions.entries
      .map(
        (MapEntry<String, String> entry) => <String, String>{
          'word': entry.key,
          'definitionCn': entry.value,
        },
      )
      .toList(growable: false),
});

List<String> _englishWords(String value) =>
    RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?")
        .allMatches(value)
        .map((Match match) => match.group(0)!)
        .toList(growable: false);

PlayerSubtitleLine? _closest(
  PlayerSubtitleLine target,
  List<PlayerSubtitleLine> candidates,
) {
  PlayerSubtitleLine? closest;
  int distance = 2000;
  for (final PlayerSubtitleLine candidate in candidates) {
    final int candidateDistance = (candidate.startMs - target.startMs).abs();
    if (candidateDistance < distance) {
      closest = candidate;
      distance = candidateDistance;
    }
  }
  return closest;
}

String _normalized(String value) => value
    .replaceAll(RegExp(r'\[[^\]]*\]'), '')
    .replaceAll(RegExp('[^a-z0-9]+', caseSensitive: false), '')
    .toLowerCase();
