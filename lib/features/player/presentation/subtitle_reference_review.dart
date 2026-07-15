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
      return PlayerSubtitleLine(
        startTime: line.startTime,
        english: line.english,
        chinese: line.chinese.isNotEmpty
            ? line.chinese
            : generatedMatch?.chinese ?? '',
        startMs: line.startMs,
        endMs: line.endMs,
      );
    })
    .toList(growable: false);

String subtitleLinesToJson(List<PlayerSubtitleLine> lines) =>
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'lines': lines
          .map(
            (PlayerSubtitleLine line) => <String, Object?>{
              'startTime': line.startTime,
              'english': line.english,
              'chinese': line.chinese,
              'startMs': line.startMs,
              'endMs': line.endMs,
            },
          )
          .toList(growable: false),
    });

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
