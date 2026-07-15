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
