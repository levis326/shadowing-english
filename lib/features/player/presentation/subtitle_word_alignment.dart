import 'player_mock_state.dart';

class SubtitleWordAlignmentResult {
  const SubtitleWordAlignmentResult({
    required this.lines,
    required this.directWordCount,
    required this.estimatedWordCount,
    required this.ignoredAsrWordCount,
  });

  final List<PlayerSubtitleLine> lines;
  final int directWordCount;
  final int estimatedWordCount;
  final int ignoredAsrWordCount;
}

/// Keeps the imported subtitle text authoritative and uses ASR only for timing.
/// A missing ASR word is placed safely between its neighbouring matched words.
List<PlayerSubtitleLine> usableReferenceSubtitles(
  List<PlayerSubtitleLine> lines,
) {
  return lines
      .where(
        (PlayerSubtitleLine line) =>
            line.endMs > line.startMs && _tokens(line.english).isNotEmpty,
      )
      .toList(growable: false)
    ..sort(
      (PlayerSubtitleLine a, PlayerSubtitleLine b) =>
          a.startMs.compareTo(b.startMs),
    );
}

SubtitleWordAlignmentResult alignReferenceSubtitles({
  required List<PlayerSubtitleLine> reference,
  required List<PlayerSubtitleLine> recognition,
}) {
  final List<PlayerSubtitleWord> recognizedWords = recognition
      .expand((PlayerSubtitleLine line) => line.words)
      .toList(growable: false);
  int directWordCount = 0;
  int estimatedWordCount = 0;
  int usedAsrWords = 0;
  final List<PlayerSubtitleLine> lines = usableReferenceSubtitles(reference)
      .map((PlayerSubtitleLine line) {
        final List<_Token> target = _tokens(line.english);
        final int alignedEndMs = line.endMs - line.startMs < target.length
            ? line.startMs + target.length
            : line.endMs;
        final List<PlayerSubtitleWord> candidates = recognizedWords
            .where(
              (PlayerSubtitleWord word) =>
                  word.endMs > line.startMs - 800 &&
                  word.startMs < line.endMs + 800,
            )
            .toList(growable: false);
        final List<_Match> matches = _longestCommonSubsequence(
          target,
          candidates,
        );
        usedAsrWords += matches.length;
        directWordCount += matches.length;
        estimatedWordCount += target.length - matches.length;

        final Map<int, PlayerSubtitleWord> direct = <int, PlayerSubtitleWord>{
          for (final _Match match in matches)
            match.targetIndex: PlayerSubtitleWord(
              text: target[match.targetIndex].text,
              startMs: match.word.startMs.clamp(line.startMs, alignedEndMs - 1),
              endMs: match.word.endMs.clamp(line.startMs + 1, alignedEndMs),
              confidence: match.word.confidence,
            ),
        };
        final List<PlayerSubtitleWord> words = _fillMissingWords(
          target: target,
          direct: direct,
          startMs: line.startMs,
          endMs: alignedEndMs,
        );
        return PlayerSubtitleLine(
          startTime: line.startTime,
          english: line.english,
          chinese: line.chinese,
          startMs: line.startMs,
          endMs: alignedEndMs,
          words: words,
        );
      })
      .toList(growable: false);
  return SubtitleWordAlignmentResult(
    lines: lines,
    directWordCount: directWordCount,
    estimatedWordCount: estimatedWordCount,
    ignoredAsrWordCount: (recognizedWords.length - usedAsrWords).clamp(
      0,
      recognizedWords.length,
    ),
  );
}

class _Token {
  const _Token(this.text);

  final String text;

  String get normalized =>
      text.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase();
}

List<_Token> _tokens(String text) =>
    RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?")
        .allMatches(text)
        .map((Match match) => _Token(match.group(0)!))
        .toList(growable: false);

class _Match {
  const _Match(this.targetIndex, this.word);

  final int targetIndex;
  final PlayerSubtitleWord word;
}

List<_Match> _longestCommonSubsequence(
  List<_Token> target,
  List<PlayerSubtitleWord> candidates,
) {
  final List<List<int>> table = List<List<int>>.generate(
    target.length + 1,
    (_) => List<int>.filled(candidates.length + 1, 0),
  );
  for (int i = target.length - 1; i >= 0; i -= 1) {
    for (int j = candidates.length - 1; j >= 0; j -= 1) {
      final bool same =
          target[i].normalized == _Token(candidates[j].text).normalized;
      table[i][j] = same
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] > table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }
  final List<_Match> result = <_Match>[];
  int i = 0;
  int j = 0;
  while (i < target.length && j < candidates.length) {
    if (target[i].normalized == _Token(candidates[j].text).normalized) {
      result.add(_Match(i, candidates[j]));
      i += 1;
      j += 1;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      i += 1;
    } else {
      j += 1;
    }
  }
  return result;
}

List<PlayerSubtitleWord> _fillMissingWords({
  required List<_Token> target,
  required Map<int, PlayerSubtitleWord> direct,
  required int startMs,
  required int endMs,
}) {
  final List<PlayerSubtitleWord> result = <PlayerSubtitleWord>[];
  int index = 0;
  while (index < target.length) {
    final PlayerSubtitleWord? directWord = direct[index];
    if (directWord != null &&
        (result.isEmpty || directWord.startMs >= result.last.endMs)) {
      result.add(directWord);
      index += 1;
      continue;
    }
    if (directWord != null) {
      // A malformed ASR timestamp must not stall alignment or make the
      // reference text unusable. Recreate this word from its cue instead.
      direct.remove(index);
      continue;
    }
    final int blockStart = index;
    while (index < target.length && direct[index] == null) {
      index += 1;
    }
    final int lower = result.isEmpty ? startMs : result.last.endMs;
    final int upper = index < target.length ? direct[index]!.startMs : endMs;
    result.addAll(
      _interpolate(target.sublist(blockStart, index), lower, upper),
    );
  }
  if (result.length == target.length &&
      result.every(
        (PlayerSubtitleWord word) =>
            word.startMs >= startMs &&
            word.endMs > word.startMs &&
            word.endMs <= endMs,
      )) {
    return result;
  }
  return _interpolate(target, startMs, endMs);
}

List<PlayerSubtitleWord> _interpolate(
  List<_Token> tokens,
  int startMs,
  int endMs,
) {
  if (tokens.isEmpty) return const <PlayerSubtitleWord>[];
  final int span = endMs - startMs;
  final int safeEndMs;
  if (span < tokens.length) {
    // An invalidly short SRT cue cannot support precise timings; keep a valid,
    // ordered timeline instead of failing the whole subtitle generation.
    safeEndMs = startMs + tokens.length;
  } else {
    safeEndMs = endMs;
  }
  final int safeSpan = safeEndMs - startMs;
  final int totalWeight = tokens.fold<int>(
    0,
    (int sum, _Token token) => sum + token.text.length,
  );
  int cursor = startMs;
  return List<PlayerSubtitleWord>.generate(tokens.length, (int index) {
    final int remaining = tokens.length - index - 1;
    final int weighted = index == tokens.length - 1
        ? safeEndMs - cursor
        : (safeSpan * tokens[index].text.length / totalWeight).round();
    final int duration = weighted.clamp(1, safeEndMs - cursor - remaining);
    final PlayerSubtitleWord word = PlayerSubtitleWord(
      text: tokens[index].text,
      startMs: cursor,
      endMs: cursor + duration,
    );
    cursor = word.endMs;
    return word;
  }, growable: false);
}
