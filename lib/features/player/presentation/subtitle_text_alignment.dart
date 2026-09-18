import 'player_mock_state.dart';

/// 每句最短时长：太短会让 `usableReferenceSubtitles` 过滤掉该行。
const int _minLineDurationMs = 120;

/// 用本地 Whisper 的识别结果，给「只有文本、没有时间轴」的字幕行套上时间轴。
///
/// 文本以 [reference] 为准（来自用户的字幕文本文件），时间来自 [recognition]：
/// 先按词相似度做单调对齐（同一段音频的两份文本顺序一致，且**允许多句共用
/// 一句识别结果**——Whisper 常把好几句话合成一段），同一段识别结果覆盖的
/// 若干句话按字数比例平分它的时间；识别里多出来的行会被跳过；参考里没能
/// 配上的行则在相邻锚点之间按字数比例插值。
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

  final List<int> assignment = _alignSequences(
    referenceTokens: referenceTokens,
    recognitionTokens: recognitionTokens,
  );

  final int totalEndMs = timedRecognition.last.endMs > fallbackEndMs
      ? timedRecognition.last.endMs
      : fallbackEndMs;
  final List<int> starts = List<int>.filled(reference.length, -1);
  final List<int> ends = List<int>.filled(reference.length, -1);

  // 连续若干句落在同一段识别结果上时，按字数比例平分这一段的时间。
  int index = 0;
  while (index < reference.length) {
    final int recognitionIndex = assignment[index];
    if (recognitionIndex < 0) {
      index += 1;
      continue;
    }
    int runEnd = index;
    while (runEnd < reference.length &&
        assignment[runEnd] == recognitionIndex) {
      runEnd += 1;
    }
    _distributeTimings(
      starts: starts,
      ends: ends,
      from: index,
      to: runEnd,
      startMs: timedRecognition[recognitionIndex].startMs,
      endMs: timedRecognition[recognitionIndex].endMs,
      weights: <int>[
        for (int i = index; i < runEnd; i += 1)
          referenceTokens[i].isEmpty ? 1 : referenceTokens[i].length,
      ],
    );
    index = runEnd;
  }

  // 相邻锚点之间的连续未匹配行按字数比例分配时间。
  index = 0;
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
    _distributeTimings(
      starts: starts,
      ends: ends,
      from: index,
      to: runEnd,
      startMs: runStartMs,
      endMs: nextStartMs > runStartMs
          ? nextStartMs
          : runStartMs + _minLineDurationMs,
      weights: <int>[
        for (int i = index; i < runEnd; i += 1)
          referenceTokens[i].isEmpty ? 1 : referenceTokens[i].length,
      ],
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

/// 单调对齐：返回每句参考文本对应的识别结果下标（-1 表示识别里没有对应内容）。
///
/// 与“每句只能配一段”的普通序列对齐不同，这里允许**多句共用同一段识别
/// 结果**（Whisper 常把多句合成一段），也允许参考句没有对应内容、识别段
/// 多出来（音乐、噪声）。相似度太低的配对会被判为“配不上”，交给插值处理。
List<int> _alignSequences({
  required List<List<String>> referenceTokens,
  required List<List<String>> recognitionTokens,
}) {
  const double minSimilarity = 0.34;
  const double stayPenalty = 0.1;
  const double skipRecognitionPenalty = 0.6;
  final int n = referenceTokens.length;
  final int m = recognitionTokens.length;
  final List<List<double>> score = List<List<double>>.generate(
    n + 1,
    (int i) => List<double>.filled(m + 1, double.negativeInfinity),
  );
  // choice: 0=配到上一段、1=配到当前段（与上一句共用）、2=这句没配上、3=跳过这段识别
  final List<List<int>> choice = List<List<int>>.generate(
    n + 1,
    (int i) => List<int>.filled(m + 1, 2),
  );
  score[0][0] = 0;
  for (int i = 1; i <= n; i += 1) {
    // 还没有识别结果可用：这些参考句暂时没配上。
    score[i][0] = 0;
    choice[i][0] = 2;
  }
  for (int j = 1; j <= m; j += 1) {
    score[0][j] = score[0][j - 1] - skipRecognitionPenalty;
    choice[0][j] = 3;
  }
  for (int i = 1; i <= n; i += 1) {
    for (int j = 1; j <= m; j += 1) {
      final double gain = _similarity(
            referenceTokens[i - 1],
            recognitionTokens[j - 1],
          ) -
          minSimilarity;
      double best = score[i - 1][j];
      int bestChoice = 2;
      final double match = score[i - 1][j - 1] + gain;
      if (match > best) {
        best = match;
        bestChoice = 0;
      }
      final double stay = score[i - 1][j] + gain - stayPenalty;
      if (stay > best) {
        best = stay;
        bestChoice = 1;
      }
      final double skip = score[i][j - 1] - skipRecognitionPenalty;
      if (skip > best) {
        best = skip;
        bestChoice = 3;
      }
      score[i][j] = best;
      choice[i][j] = bestChoice;
    }
  }
  int bestJ = 0;
  double bestScore = double.negativeInfinity;
  for (int j = 0; j <= m; j += 1) {
    if (score[n][j] > bestScore) {
      bestScore = score[n][j];
      bestJ = j;
    }
  }
  final List<int> assignment = List<int>.filled(n, -1);
  int i = n;
  int j = bestJ;
  while (i > 0) {
    final int selected = choice[i][j];
    if (selected == 0 || selected == 1) {
      assignment[i - 1] = j - 1;
      i -= 1;
      if (selected == 0) {
        j -= 1;
      }
    } else if (selected == 3) {
      j -= 1;
    } else {
      i -= 1;
    }
  }
  return assignment;
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
