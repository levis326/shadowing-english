import 'player_mock_state.dart';

/// 每句最短时长：太短会让 `usableReferenceSubtitles` 过滤掉该行。
const int _minLineDurationMs = 120;

/// 用本地 Whisper 的识别结果，给「只有文本、没有时间轴」的字幕行套上时间轴。
///
/// 文本以 [reference] 为准（来自用户的字幕文本文件），时间来自 [recognition]：
/// 先按词相似度做单调对齐（同一段音频的两份文本顺序一致），识别里多出来的行
/// 会被跳过，参考里没能配上的行则在相邻锚点之间按字数比例插值。
List<PlayerSubtitleLine> assignTimingsFromRecognition({
  required List<PlayerSubtitleLine> reference,
  required List<PlayerSubtitleLine> recognition,
  int fallbackEndMs = 0,
}) {
  if (reference.isEmpty) {
    return const <PlayerSubtitleLine>[];
  }
  final List<PlayerSubtitleLine> timedRecognition = recognition
      .where(
        (PlayerSubtitleLine line) =>
            line.endMs > line.startMs && _tokens(line.english).isNotEmpty,
      )
      .toList(growable: false)
    ..sort(
      (PlayerSubtitleLine a, PlayerSubtitleLine b) =>
          a.startMs.compareTo(b.startMs),
    );
  if (timedRecognition.isEmpty) {
    return const <PlayerSubtitleLine>[];
  }

  final List<List<String>> referenceTokens = reference
      .map((PlayerSubtitleLine line) => _tokens(line.english))
      .toList(growable: false);
  final List<List<String>> recognitionTokens = timedRecognition
      .map((PlayerSubtitleLine line) => _tokens(line.english))
      .toList(growable: false);

  final Map<int, int> matches = _alignSequences(
    referenceTokens: referenceTokens,
    recognitionTokens: recognitionTokens,
  );

  final int totalEndMs = timedRecognition.last.endMs > fallbackEndMs
      ? timedRecognition.last.endMs
      : fallbackEndMs;
  final List<int> starts = List<int>.filled(reference.length, -1);
  final List<int> ends = List<int>.filled(reference.length, -1);
  matches.forEach((int referenceIndex, int recognitionIndex) {
    starts[referenceIndex] = timedRecognition[recognitionIndex].startMs;
    ends[referenceIndex] = timedRecognition[recognitionIndex].endMs;
  });

  // 相邻锚点之间的连续未匹配行按字数比例分配时间。
  int index = 0;
  int? previousEndMs;
  while (index < reference.length) {
    if (starts[index] >= 0) {
      previousEndMs = ends[index];
      index += 1;
      continue;
    }
    int runEnd = index;
    while (runEnd < reference.length && starts[runEnd] < 0) {
      runEnd += 1;
    }
    final int runStartMs = previousEndMs ?? 0;
    final int nextStartMs = runEnd < reference.length
        ? starts[runEnd]
        : totalEndMs;
    final List<int> weights = <int>[
      for (int i = index; i < runEnd; i += 1)
        referenceTokens[i].isEmpty ? 1 : referenceTokens[i].length,
    ];
    _distributeTimings(
      starts: starts,
      ends: ends,
      from: index,
      to: runEnd,
      startMs: runStartMs,
      endMs: nextStartMs > runStartMs ? nextStartMs : runStartMs + _minLineDurationMs,
      weights: weights,
    );
    previousEndMs = ends[runEnd - 1];
    index = runEnd;
  }

  return <PlayerSubtitleLine>[
    for (int i = 0; i < reference.length; i += 1)
      PlayerSubtitleLine(
        startTime: reference[i].startTime,
        english: reference[i].english,
        chinese: reference[i].chinese,
        startMs: starts[i],
        endMs: ends[i],
        words: reference[i].words,
      ),
  ];
}

void _distributeTimings({
  required List<int> starts,
  required List<int> ends,
  required int from,
  required int to,
  required int startMs,
  required int endMs,
  required List<int> weights,
}) {
  final int count = to - from;
  if (count <= 0) {
    return;
  }
  final int span = endMs - startMs;
  final int totalWeight = weights.fold<int>(0, (int sum, int w) => sum + w);
  int cursor = startMs;
  for (int i = 0; i < count; i += 1) {
    final bool last = i == count - 1;
    int duration = ((span * weights[i]) / (totalWeight == 0 ? 1 : totalWeight))
        .round();
    if (duration < _minLineDurationMs) {
      duration = _minLineDurationMs;
    }
    final int lineEnd = last ? endMs : cursor + duration;
    starts[from + i] = cursor;
    ends[from + i] = lineEnd > cursor ? lineEnd : cursor + _minLineDurationMs;
    cursor = ends[from + i];
  }
}

/// 单调序列对齐（类似 Needleman–Wunsch）：返回 参考下标 -> 识别下标。
Map<int, int> _alignSequences({
  required List<List<String>> referenceTokens,
  required List<List<String>> recognitionTokens,
}) {
  const double gapPenalty = -0.6;
  final int n = referenceTokens.length;
  final int m = recognitionTokens.length;
  final List<List<double>> score = List<List<double>>.generate(
    n + 1,
    (int i) => List<double>.filled(m + 1, 0),
  );
  final List<List<int>> choice = List<List<int>>.generate(
    n + 1,
    (int i) => List<int>.filled(m + 1, 0),
  );
  for (int i = 1; i <= n; i += 1) {
    score[i][0] = score[i - 1][0] + gapPenalty;
    choice[i][0] = 1;
  }
  for (int j = 1; j <= m; j += 1) {
    score[0][j] = score[0][j - 1] + gapPenalty;
    choice[0][j] = 2;
  }
  for (int i = 1; i <= n; i += 1) {
    for (int j = 1; j <= m; j += 1) {
      final double similarity = _similarity(
        referenceTokens[i - 1],
        recognitionTokens[j - 1],
      );
      final double match = score[i - 1][j - 1] + similarity;
      final double skipReference = score[i - 1][j] + gapPenalty;
      final double skipRecognition = score[i][j - 1] + gapPenalty;
      // 得分相同时优先“先消耗前面的参考句/识别句”，这样同一段语音里
      // 连续多句只匹配上第一句时，后面的句子会落在锚点之间的空隙里，
      // 而不是把后面的句子提前配到更早的识别句上。
      if (skipReference >= match && skipReference >= skipRecognition) {
        score[i][j] = skipReference;
        choice[i][j] = 1;
      } else if (skipRecognition >= match) {
        score[i][j] = skipRecognition;
        choice[i][j] = 2;
      } else {
        score[i][j] = match;
        choice[i][j] = 0;
      }
    }
  }
  final Map<int, int> matches = <int, int>{};
  int i = n;
  int j = m;
  while (i > 0 && j > 0) {
    switch (choice[i][j]) {
      case 0:
        matches[i - 1] = j - 1;
        i -= 1;
        j -= 1;
      case 1:
        i -= 1;
      default:
        j -= 1;
    }
  }
  return matches;
}

/// 相似度 = 参考句的词有多少按顺序出现在识别句里（0~1）。
///
/// 用「包含度」而不是对称比例：Whisper 常把相邻两三句合成一段，
/// 或把一句拆成多段，包含度能让同一段语音的两种文本正确配对，
/// 而不是被 SRT/文本里的重复用词（"sentence here" 之类）带偏。
double _similarity(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) {
    return 0;
  }
  final List<int> previous = List<int>.filled(b.length + 1, 0);
  final List<int> current = List<int>.filled(b.length + 1, 0);
  for (int i = 1; i <= a.length; i += 1) {
    for (int j = 1; j <= b.length; j += 1) {
      current[j] = a[i - 1] == b[j - 1]
          ? previous[j - 1] + 1
          : (previous[j] > current[j - 1] ? previous[j] : current[j - 1]);
    }
    for (int j = 0; j <= b.length; j += 1) {
      previous[j] = current[j];
      current[j] = 0;
    }
  }
  return previous[b.length] / a.length;
}

List<String> _tokens(String text) => RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?")
    .allMatches(text)
    .map((RegExpMatch match) => match.group(0)!.toLowerCase())
    .toList(growable: false);
