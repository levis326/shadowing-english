import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/word_lookup_popup.dart';
import '../../words/data/offline_word_dictionary.dart';
import 'player_mock_state.dart';

class TranscriptReaderProgress {
  const TranscriptReaderProgress({
    required this.lineIndex,
    required this.wordIndex,
    this.loopingLineIndex,
  });

  factory TranscriptReaderProgress.fromJson(Map<dynamic, dynamic> json) {
    return TranscriptReaderProgress(
      lineIndex: json['lineIndex'] as int? ?? 0,
      wordIndex: json['wordIndex'] as int? ?? 0,
      loopingLineIndex: json['loopingLineIndex'] as int?,
    );
  }

  final int lineIndex;
  final int wordIndex;
  final int? loopingLineIndex;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lineIndex': lineIndex,
    'wordIndex': wordIndex,
    'loopingLineIndex': loopingLineIndex,
  };
}

class TranscriptReaderSnapshot {
  const TranscriptReaderSnapshot({
    required this.courseTitle,
    required this.episodeTitle,
    required this.lines,
    required this.meanings,
    required this.progress,
  });

  factory TranscriptReaderSnapshot.fromJson(Map<dynamic, dynamic> json) {
    return TranscriptReaderSnapshot(
      courseTitle: json['courseTitle'] as String? ?? '',
      episodeTitle: json['episodeTitle'] as String? ?? '',
      lines: (json['lines'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(_lineFromJson)
          .toList(growable: false),
      meanings:
          (json['meanings'] as Map<dynamic, dynamic>? ??
                  const <dynamic, dynamic>{})
              .map(
                (dynamic key, dynamic value) =>
                    MapEntry<String, String>(key as String, value as String),
              ),
      progress: TranscriptReaderProgress.fromJson(
        json['progress'] as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{},
      ),
    );
  }

  final String courseTitle;
  final String episodeTitle;
  final List<PlayerSubtitleLine> lines;
  final Map<String, String> meanings;
  final TranscriptReaderProgress progress;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'courseTitle': courseTitle,
    'episodeTitle': episodeTitle,
    'lines': lines.map(_lineToJson).toList(growable: false),
    'meanings': meanings,
    'progress': progress.toJson(),
  };
}

Future<TranscriptReaderSnapshot> buildTranscriptReaderSnapshot({
  required String courseTitle,
  required String episodeTitle,
  required List<PlayerSubtitleLine> lines,
  required int activeLineIndex,
  required int currentWordIndex,
  int? loopingLineIndex,
  required Map<String, String> generatedMeanings,
  required OfflineWordDictionary dictionary,
}) async {
  final Set<String> words = <String>{
    for (final PlayerSubtitleLine line in lines)
      for (final String token in transcriptReaderTokens(line))
        if (normalizeTranscriptReaderWord(token).isNotEmpty)
          normalizeTranscriptReaderWord(token),
  };
  final List<String> missingWords = words
      .where((String word) => (generatedMeanings[word] ?? '').trim().isEmpty)
      .toList(growable: false);
  final List<OfflineWordDefinition?> offlineDefinitions = await Future.wait(
    missingWords.map(dictionary.lookup),
  );
  final Map<String, String> meanings = <String, String>{
    for (final String word in words)
      if ((generatedMeanings[word] ?? '').trim().isNotEmpty)
        word: generatedMeanings[word]!.trim(),
  };
  for (int index = 0; index < missingWords.length; index++) {
    final String translation =
        offlineDefinitions[index]?.translation.trim() ?? '';
    if (translation.isNotEmpty) {
      meanings[missingWords[index]] = translation;
    }
  }

  return TranscriptReaderSnapshot(
    courseTitle: courseTitle,
    episodeTitle: episodeTitle,
    lines: lines,
    meanings: meanings,
    progress: TranscriptReaderProgress(
      lineIndex: activeLineIndex,
      wordIndex: currentWordIndex,
      loopingLineIndex: loopingLineIndex,
    ),
  );
}

List<String> transcriptReaderTokens(PlayerSubtitleLine line) => line.english
    .trim()
    .split(RegExp(r'\s+'))
    .where((String token) => token.isNotEmpty)
    .toList(growable: false);

String normalizeTranscriptReaderWord(String value) {
  final Match? match = RegExp("[A-Za-z]+(?:['’][A-Za-z]+)?").firstMatch(value);
  return (match?.group(0) ?? '').toLowerCase().replaceAll('’', "'");
}

class FullTranscriptReaderScreen extends StatefulWidget {
  const FullTranscriptReaderScreen({
    required this.snapshot,
    required this.progressListenable,
    required this.onClose,
    this.onToggleLineLoop,
    super.key,
  });

  final TranscriptReaderSnapshot snapshot;
  final ValueListenable<TranscriptReaderProgress> progressListenable;
  final VoidCallback onClose;
  final ValueChanged<int>? onToggleLineLoop;

  @override
  State<FullTranscriptReaderScreen> createState() =>
      _FullTranscriptReaderScreenState();
}

class _FullTranscriptReaderScreenState
    extends State<FullTranscriptReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _activeWordKey = GlobalKey();
  late TranscriptReaderProgress _progress;
  bool _showTranslations = true;
  String? _activeLookupTokenId;
  OverlayEntry? _lookupOverlayEntry;

  @override
  void initState() {
    super.initState();
    _progress = widget.progressListenable.value;
    widget.progressListenable.addListener(_handleProgressChanged);
    _scrollController.addListener(_dismissWordLookup);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActiveWord());
  }

  @override
  void didUpdateWidget(FullTranscriptReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressListenable != widget.progressListenable) {
      oldWidget.progressListenable.removeListener(_handleProgressChanged);
      widget.progressListenable.addListener(_handleProgressChanged);
      _progress = widget.progressListenable.value;
    }
  }

  @override
  void dispose() {
    _removeWordLookupOverlay();
    widget.progressListenable.removeListener(_handleProgressChanged);
    _scrollController
      ..removeListener(_dismissWordLookup)
      ..dispose();
    super.dispose();
  }

  void _handleProgressChanged() {
    final TranscriptReaderProgress next = widget.progressListenable.value;
    if (next.lineIndex == _progress.lineIndex &&
        next.wordIndex == _progress.wordIndex &&
        next.loopingLineIndex == _progress.loopingLineIndex) {
      return;
    }
    setState(() => _progress = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActiveWord());
  }

  Future<void> _revealActiveWord() async {
    if (!mounted) return;
    final BuildContext? activeContext = _activeWordKey.currentContext;
    if (activeContext != null) {
      await Scrollable.ensureVisible(
        activeContext,
        alignment: 0.42,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (!_scrollController.hasClients || widget.snapshot.lines.length < 2) {
      return;
    }
    final double target =
        _scrollController.position.maxScrollExtent *
        (_progress.lineIndex / (widget.snapshot.lines.length - 1));
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    final BuildContext? revealedContext = _activeWordKey.currentContext;
    if (revealedContext != null && revealedContext.mounted) {
      await Scrollable.ensureVisible(
        revealedContext,
        alignment: 0.42,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _dismissWordLookup() {
    if (_lookupOverlayEntry == null && _activeLookupTokenId == null) return;
    _removeWordLookupOverlay();
  }

  void _removeWordLookupOverlay() {
    _lookupOverlayEntry?.remove();
    _lookupOverlayEntry = null;
    _activeLookupTokenId = null;
  }

  void _toggleWordLookup({
    required BuildContext anchorContext,
    required String rawWord,
    required String contextSentence,
    required String tokenId,
    required String fallbackDefinitionCn,
  }) {
    if (_activeLookupTokenId == tokenId) {
      _removeWordLookupOverlay();
      return;
    }
    _removeWordLookupOverlay();

    final OverlayState overlayState = Overlay.of(context, rootOverlay: true);
    final RenderBox overlayBox =
        overlayState.context.findRenderObject()! as RenderBox;
    final RenderBox anchorBox = anchorContext.findRenderObject()! as RenderBox;
    final Offset anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final Size anchorSize = anchorBox.size;
    final Size overlaySize = overlayBox.size;
    const double popupWidth = 336;
    const double preferredPopupHeight = 520;
    const double viewportPadding = 16;
    const double popupGap = 8;
    final double popupHeight = (overlaySize.height - (viewportPadding * 2))
        .clamp(120.0, preferredPopupHeight);
    final double availableRight =
        overlaySize.width - (anchorTopLeft.dx + anchorSize.width);
    final double availableLeft = anchorTopLeft.dx;
    final double availableBelow =
        overlaySize.height - (anchorTopLeft.dy + anchorSize.height);
    final bool canShowRight = availableRight >= popupWidth + popupGap;
    final bool canShowLeft = availableLeft >= popupWidth + popupGap;
    final bool showRight = canShowRight || !canShowLeft;
    final bool showSide = canShowRight || canShowLeft;
    final bool showAbove =
        !showSide &&
        availableBelow < popupHeight + viewportPadding &&
        anchorTopLeft.dy > availableBelow;

    final double left;
    final double top;
    if (showSide) {
      left = showRight
          ? (anchorTopLeft.dx + anchorSize.width + popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            )
          : (anchorTopLeft.dx - popupWidth - popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            );
      top = (anchorTopLeft.dy + (anchorSize.height / 2) - (popupHeight / 2))
          .clamp(
            viewportPadding,
            overlaySize.height - popupHeight - viewportPadding,
          );
    } else {
      left = (anchorTopLeft.dx + (anchorSize.width / 2) - (popupWidth / 2))
          .clamp(
            viewportPadding,
            overlaySize.width - popupWidth - viewportPadding,
          );
      top = showAbove
          ? (anchorTopLeft.dy - popupHeight - popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            )
          : (anchorTopLeft.dy + anchorSize.height + popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            );
    }

    _lookupOverlayEntry = OverlayEntry(
      builder: (BuildContext overlayContext) => Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissWordLookup,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: popupWidth,
            child: Material(
              color: Colors.transparent,
              child: WordLookupPopupCard(
                rawWord: rawWord,
                contextSentence: contextSentence,
                fallbackDefinitionCn: fallbackDefinitionCn,
                showAbove: showAbove,
                showSide: showSide,
                showRight: showRight,
                maxHeight: popupHeight,
                onClose: _dismissWordLookup,
              ),
            ),
          ),
        ],
      ),
    );
    overlayState.insert(_lookupOverlayEntry!);
    _activeLookupTokenId = tokenId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F9F4),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ReaderHeader(
              courseTitle: widget.snapshot.courseTitle,
              episodeTitle: widget.snapshot.episodeTitle,
              showTranslations: _showTranslations,
              onTranslationChanged: (bool value) {
                setState(() => _showTranslations = value);
              },
              onLocateCurrentWord: _revealActiveWord,
              onClose: widget.onClose,
            ),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 80),
                  itemCount: widget.snapshot.lines.length,
                  itemBuilder: (BuildContext context, int lineIndex) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: _ReaderLine(
                        line: widget.snapshot.lines[lineIndex],
                        meanings: widget.snapshot.meanings,
                        lineIndex: lineIndex,
                        activeLineIndex: _progress.lineIndex,
                        activeWordIndex: _progress.wordIndex,
                        activeWordKey: _activeWordKey,
                        showTranslations: _showTranslations,
                        isLooping: _progress.loopingLineIndex == lineIndex,
                        onToggleLoop: widget.onToggleLineLoop == null
                            ? null
                            : () => widget.onToggleLineLoop!(lineIndex),
                        onWordTap:
                            (
                              BuildContext anchorContext,
                              String token,
                              int wordIndex,
                            ) {
                              _toggleWordLookup(
                                anchorContext: anchorContext,
                                rawWord: token,
                                contextSentence:
                                    widget.snapshot.lines[lineIndex].english,
                                tokenId: '$lineIndex-$wordIndex',
                                fallbackDefinitionCn:
                                    widget
                                        .snapshot
                                        .meanings[normalizeTranscriptReaderWord(
                                      token,
                                    )] ??
                                    '',
                              );
                            },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.courseTitle,
    required this.episodeTitle,
    required this.showTranslations,
    required this.onTranslationChanged,
    required this.onLocateCurrentWord,
    required this.onClose,
  });

  final String courseTitle;
  final String episodeTitle;
  final bool showTranslations;
  final ValueChanged<bool> onTranslationChanged;
  final VoidCallback onLocateCurrentWord;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppDesignTokens.borderGray)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppDesignTokens.brandGreenDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  courseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$episodeTitle · 逐词全文',
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '翻译',
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                key: const ValueKey<String>('reader-translation-toggle'),
                value: showTranslations,
                onChanged: onTranslationChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            key: const ValueKey<String>('reader-locate-current-word'),
            onPressed: onLocateCurrentWord,
            tooltip: '定位到当前单词',
            icon: const Icon(
              Icons.my_location_rounded,
              color: AppDesignTokens.brandGreenDark,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onClose,
            tooltip: '关闭逐词全文',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ReaderLine extends StatelessWidget {
  const _ReaderLine({
    required this.line,
    required this.meanings,
    required this.lineIndex,
    required this.activeLineIndex,
    required this.activeWordIndex,
    required this.activeWordKey,
    required this.showTranslations,
    required this.isLooping,
    required this.onToggleLoop,
    required this.onWordTap,
  });

  final PlayerSubtitleLine line;
  final Map<String, String> meanings;
  final int lineIndex;
  final int activeLineIndex;
  final int activeWordIndex;
  final GlobalKey activeWordKey;
  final bool showTranslations;
  final bool isLooping;
  final VoidCallback? onToggleLoop;
  final void Function(BuildContext context, String token, int wordIndex)
  onWordTap;

  @override
  Widget build(BuildContext context) {
    final List<String> tokens = transcriptReaderTokens(line);
    final bool isActive = lineIndex == activeLineIndex;
    return AnimatedContainer(
      key: ValueKey<String>('reader-line-$lineIndex-$isActive'),
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFE8F7ED)
            : lineIndex.isOdd
            ? const Color(0x99FFFFFF)
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isActive ? AppDesignTokens.brandGreen : Colors.transparent,
            width: 3,
          ),
          bottom: const BorderSide(color: Color(0xFFD7E4DA)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                line.startTime,
                style: const TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton.filledTonal(
                key: ValueKey<String>('reader-line-loop-$lineIndex'),
                onPressed: onToggleLoop,
                tooltip: isLooping ? '关闭单句循环' : '循环播放这一句',
                style: IconButton.styleFrom(
                  backgroundColor: isLooping
                      ? const Color(0xFFDFF8C8)
                      : const Color(0xFFF4F6F4),
                  foregroundColor: isLooping
                      ? AppDesignTokens.brandGreenDark
                      : AppDesignTokens.textSecondary,
                ),
                icon: const Icon(Icons.repeat_one_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 12,
            children: <Widget>[
              for (int wordIndex = 0; wordIndex < tokens.length; wordIndex++)
                Builder(
                  builder: (BuildContext wordContext) => _WordMeaningTile(
                    key: isActive && wordIndex == activeWordIndex
                        ? activeWordKey
                        : ValueKey<String>('reader-word-$lineIndex-$wordIndex'),
                    token: tokens[wordIndex],
                    meaning:
                        meanings[normalizeTranscriptReaderWord(
                          tokens[wordIndex],
                        )] ??
                        '—',
                    active: isActive && wordIndex == activeWordIndex,
                    showMeaning: showTranslations,
                    onTap: () =>
                        onWordTap(wordContext, tokens[wordIndex], wordIndex),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WordMeaningTile extends StatelessWidget {
  const _WordMeaningTile({
    required this.token,
    required this.meaning,
    required this.active,
    required this.showMeaning,
    required this.onTap,
    super.key,
  });

  final String token;
  final String meaning;
  final bool active;
  final bool showMeaning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey<String>('reader-word-box-$token-$active'),
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minWidth: 52, maxWidth: 180),
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFDDF7EA) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? AppDesignTokens.brandGreen : Colors.transparent,
              width: active ? 2 : 1,
            ),
            boxShadow: active
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x2410B981),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                token,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active
                      ? AppDesignTokens.brandGreenDark
                      : AppDesignTokens.textPrimary,
                  fontSize: 25,
                  height: 1.08,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              if (showMeaning) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  meaning,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8A5A12),
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _lineToJson(PlayerSubtitleLine line) => <String, dynamic>{
  'startTime': line.startTime,
  'english': line.english,
  'chinese': line.chinese,
  'startMs': line.startMs,
  'endMs': line.endMs,
  'words': line.words
      .map(
        (PlayerSubtitleWord word) => <String, dynamic>{
          'text': word.text,
          'startMs': word.startMs,
          'endMs': word.endMs,
          'confidence': word.confidence,
        },
      )
      .toList(growable: false),
};

PlayerSubtitleLine _lineFromJson(Map<dynamic, dynamic> json) {
  return PlayerSubtitleLine(
    startTime: json['startTime'] as String? ?? '',
    english: json['english'] as String? ?? '',
    chinese: json['chinese'] as String? ?? '',
    startMs: json['startMs'] as int? ?? 0,
    endMs: json['endMs'] as int? ?? 0,
    words: (json['words'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> word) => PlayerSubtitleWord(
            text: word['text'] as String? ?? '',
            startMs: word['startMs'] as int? ?? 0,
            endMs: word['endMs'] as int? ?? 0,
            confidence: (word['confidence'] as num?)?.toDouble(),
          ),
        )
        .toList(growable: false),
  );
}
