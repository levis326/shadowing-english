import 'dart:async';

import 'package:common_learn_english/features/player/presentation/full_transcript_reader.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/transcript_reader_session.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:common_learn_english/features/shared/domain/word_lookup_entry.dart';
import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

void main() {
  const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
    PlayerSubtitleLine(
      startTime: '00:01',
      english: 'Guess what I bought?',
      chinese: '猜猜我买了什么？',
      startMs: 1000,
      endMs: 3000,
      words: <PlayerSubtitleWord>[
        PlayerSubtitleWord(text: 'Guess', startMs: 1000, endMs: 1400),
        PlayerSubtitleWord(text: 'what', startMs: 1400, endMs: 1800),
        PlayerSubtitleWord(text: 'I', startMs: 1800, endMs: 2100),
        PlayerSubtitleWord(text: 'bought', startMs: 2100, endMs: 3000),
      ],
    ),
  ];

  test(
    'AI glossary wins and offline dictionary fills missing meanings',
    () async {
      final TranscriptReaderSnapshot snapshot =
          await buildTranscriptReaderSnapshot(
            courseTitle: '测试课程',
            episodeTitle: '第 01 集',
            lines: lines,
            activeLineIndex: 0,
            currentWordIndex: 1,
            generatedMeanings: const <String, String>{'guess': '猜测；猜想'},
            dictionary: _TestDictionary(),
          );

      expect(snapshot.meanings['guess'], '猜测；猜想');
      expect(snapshot.meanings['what'], '什么');
      expect(snapshot.meanings.containsKey('i'), isFalse);

      final TranscriptReaderSnapshot restored =
          TranscriptReaderSnapshot.fromJson(snapshot.toJson());
      expect(restored.lines.single.words.length, 4);
      expect(restored.progress.wordIndex, 1);
    },
  );

  test('progress delivery retries while the reader window starts', () async {
    int attempts = 0;
    TranscriptReaderProgress? received;

    final bool sent = await sendTranscriptReaderProgressWithRetry(
      progress: const TranscriptReaderProgress(lineIndex: 2, wordIndex: 5),
      retryDelay: Duration.zero,
      send: (TranscriptReaderProgress progress) async {
        attempts += 1;
        if (attempts < 3) throw StateError('window handler is not ready');
        received = progress;
      },
    );

    expect(sent, isTrue);
    expect(attempts, 3);
    expect(received?.lineIndex, 2);
    expect(received?.wordIndex, 5);
  });

  testWidgets('renders every word meaning and moves the active word box', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: FullTranscriptReaderScreen(
          snapshot: const TranscriptReaderSnapshot(
            courseTitle: '测试课程',
            episodeTitle: '第 01 集',
            lines: lines,
            meanings: <String, String>{
              'guess': '猜测',
              'what': '什么',
              'bought': '购买',
            },
            progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
          ),
          progressListenable: progress,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guess'), findsOneWidget);
    expect(find.text('购买'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reader-locate-current-word')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reader-word-box-what-true')),
      findsOneWidget,
    );

    progress.value = const TranscriptReaderProgress(lineIndex: 0, wordIndex: 3);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('reader-word-box-what-false')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reader-word-box-bought?-true')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reader-translation-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('购买'), findsNothing);
    expect(find.text('Guess'), findsOneWidget);
  });

  testWidgets('separates subtitle lines into readable paragraphs', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);
    const List<PlayerSubtitleLine> paragraphLines = <PlayerSubtitleLine>[
      ...lines,
      PlayerSubtitleLine(
        startTime: '00:04',
        english: 'This is the next sentence.',
        chinese: '这是下一句。',
        startMs: 4000,
        endMs: 6000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: FullTranscriptReaderScreen(
          snapshot: const TranscriptReaderSnapshot(
            courseTitle: '测试课程',
            episodeTitle: '第 01 集',
            lines: paragraphLines,
            meanings: <String, String>{},
            progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
          ),
          progressListenable: progress,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder selectionArea = find.byKey(
      const ValueKey<String>('full-transcript-selection-area'),
    );
    expect(selectionArea, findsOneWidget);
    expect(
      find.descendant(of: selectionArea, matching: find.text('Guess')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: selectionArea, matching: find.text('This')),
      findsOneWidget,
    );

    expect(
      find.descendant(of: selectionArea, matching: find.text('\n')),
      findsWidgets,
    );

    final Finder activeLine = find.byKey(
      const ValueKey<String>('reader-line-0-true'),
    );
    final Finder alternateLine = find.byKey(
      const ValueKey<String>('reader-line-1-false'),
    );
    final BoxDecoration activeDecoration =
        tester.widget<AnimatedContainer>(activeLine).decoration!
            as BoxDecoration;
    final BoxDecoration alternateDecoration =
        tester.widget<AnimatedContainer>(alternateLine).decoration!
            as BoxDecoration;

    expect(activeDecoration.color, const Color(0xFFE8F7ED));
    expect((activeDecoration.border! as Border).left.width, 3);
    expect((activeDecoration.border! as Border).bottom.width, 1);
    expect(alternateDecoration.color, const Color(0x99FFFFFF));
    expect(
      tester.widget<AnimatedContainer>(activeLine).margin,
      const EdgeInsets.only(bottom: 14),
    );
  });

  testWidgets('lazily builds a long transcript', (WidgetTester tester) async {
    final List<PlayerSubtitleLine> longTranscript =
        List<PlayerSubtitleLine>.generate(
          200,
          (int index) => PlayerSubtitleLine(
            startTime: '00:${index.toString().padLeft(2, '0')}',
            english: 'Sentence number $index',
            chinese: '第 $index 句',
            startMs: index * 1000,
            endMs: (index + 1) * 1000,
          ),
        );
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: FullTranscriptReaderScreen(
          snapshot: TranscriptReaderSnapshot(
            courseTitle: '测试课程',
            episodeTitle: '长字幕',
            lines: longTranscript,
            meanings: const <String, String>{},
            progress: const TranscriptReaderProgress(
              lineIndex: 0,
              wordIndex: 0,
            ),
          ),
          progressListenable: progress,
          onClose: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('reader-line-0-true')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reader-line-199-false')),
      findsNothing,
    );
  });

  testWidgets('full transcript playback keeps the per-line loop control', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);
    bool requestedFullPlayback = false;
    int? requestedLineIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: FullTranscriptReaderScreen(
          snapshot: const TranscriptReaderSnapshot(
            courseTitle: '测试课程',
            episodeTitle: '第 01 集',
            lines: lines,
            meanings: <String, String>{},
            progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
          ),
          progressListenable: progress,
          onPlayFullTranscript: () {
            requestedFullPlayback = true;
          },
          onToggleLineLoop: (int index) {
            requestedLineIndex = index;
            progress.value = TranscriptReaderProgress(
              lineIndex: index,
              wordIndex: 0,
              loopingLineIndex: index,
            );
          },
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('reader-play-full-transcript')),
    );
    await tester.pumpAndSettle();
    expect(requestedFullPlayback, isTrue);

    final Finder loopButton = find.byKey(
      const ValueKey<String>('reader-line-loop-0'),
    );
    expect(loopButton, findsOneWidget);

    await tester.tap(loopButton);
    await tester.pumpAndSettle();

    expect(requestedLineIndex, 0);
    expect(find.byTooltip('关闭单句循环'), findsOneWidget);
    expect(
      TranscriptReaderProgress.fromJson(
        progress.value.toJson(),
      ).loopingLineIndex,
      0,
    );
  });

  testWidgets('shows the full sentence translation below word meanings', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FullTranscriptReaderScreen(
            snapshot: const TranscriptReaderSnapshot(
              courseTitle: '测试课程',
              episodeTitle: '第 01 集',
              lines: lines,
              meanings: <String, String>{'guess': '猜测'},
              progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
            ),
            progressListenable: progress,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('猜猜我买了什么？'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reader-sentence-translation')),
      findsOneWidget,
    );
  });

  testWidgets(
    'full transcript TTS pauses between lines and highlights narrated words',
    (WidgetTester tester) async {
      final ValueNotifier<TranscriptReaderProgress> progress =
          ValueNotifier<TranscriptReaderProgress>(
            const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
          );
      addTearDown(progress.dispose);
      final List<String> spokenLines = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            wordPronunciationServiceProvider.overrideWith(
              (Ref ref) => WordPronunciationService(
                speakOverride: (String text) async => spokenLines.add(text),
              ),
            ),
          ],
          child: MaterialApp(
            home: FullTranscriptReaderScreen(
              snapshot: const TranscriptReaderSnapshot(
                courseTitle: '测试课程',
                episodeTitle: '第 01 集',
                lines: <PlayerSubtitleLine>[
                  ...lines,
                  PlayerSubtitleLine(
                    startTime: '00:04',
                    english: 'This is the next sentence.',
                    chinese: '这是下一句。',
                    startMs: 4000,
                    endMs: 6000,
                  ),
                ],
                meanings: <String, String>{},
                progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
              ),
              progressListenable: progress,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('reader-play-full-transcript')),
      );
      await tester.pump();

      expect(spokenLines, <String>['Guess what I bought?']);

      await tester.pump(const Duration(milliseconds: 750));
      expect(
        find.byKey(const ValueKey<String>('reader-word-box-what-true')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 2200));
      expect(spokenLines, <String>['Guess what I bought?']);

      await tester.pump(const Duration(milliseconds: 200));
      expect(spokenLines, <String>[
        'Guess what I bought?',
        'This is the next sentence.',
      ]);
      expect(
        find.byKey(const ValueKey<String>('reader-line-1-true')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('full transcript TTS can pause, continue, and stop on close', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);
    final List<String> spokenLines = <String>[];
    Completer<void>? activeSpeech;
    int stopCount = 0;
    bool closed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          wordPronunciationServiceProvider.overrideWith(
            (Ref ref) => WordPronunciationService(
              speakOverride: (String text) async {
                spokenLines.add(text);
                activeSpeech = Completer<void>();
                await activeSpeech!.future;
              },
              stopOverride: () async {
                stopCount += 1;
                final Completer<void>? speech = activeSpeech;
                if (speech != null && !speech.isCompleted) {
                  speech.complete();
                }
              },
            ),
          ),
        ],
        child: MaterialApp(
          home: FullTranscriptReaderScreen(
            snapshot: const TranscriptReaderSnapshot(
              courseTitle: '测试课程',
              episodeTitle: '第 01 集',
              lines: lines,
              meanings: <String, String>{},
              progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
            ),
            progressListenable: progress,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder listenButton = find.byKey(
      const ValueKey<String>('reader-play-full-transcript'),
    );
    await tester.tap(listenButton);
    await tester.pump();
    expect(spokenLines, <String>['Guess what I bought?']);
    expect(find.text('暂停'), findsOneWidget);

    await tester.tap(listenButton);
    await tester.pumpAndSettle();
    expect(stopCount, 1);
    expect(find.text('继续'), findsOneWidget);

    await tester.tap(listenButton);
    await tester.pump();
    expect(spokenLines, <String>[
      'Guess what I bought?',
      'Guess what I bought?',
    ]);
    expect(find.text('暂停'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭逐词全文'));
    await tester.pumpAndSettle();
    expect(stopCount, 2);
    expect(closed, isTrue);
  });

  testWidgets('tapping a reader word opens the anchored lookup popup', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FullTranscriptReaderScreen(
            snapshot: const TranscriptReaderSnapshot(
              courseTitle: '测试课程',
              episodeTitle: '第 01 集',
              lines: lines,
              meanings: <String, String>{'guess': '猜测'},
              progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
            ),
            progressListenable: progress,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guess'));
    await tester.pumpAndSettle();

    final Finder popup = find.byKey(
      const ValueKey<String>('word-lookup-popup-card'),
    );
    expect(popup, findsOneWidget);
    expect(find.text('翻译来源：字幕词义'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reader-word-box-what-true')),
      findsOneWidget,
    );
    final Rect popupRect = tester.getRect(popup);
    expect(popupRect.left, greaterThanOrEqualTo(0));
    expect(popupRect.top, greaterThanOrEqualTo(0));
    expect(popupRect.right, lessThanOrEqualTo(900));
    expect(popupRect.bottom, lessThanOrEqualTo(700));

    progress.value = const TranscriptReaderProgress(lineIndex: 0, wordIndex: 3);
    await tester.pumpAndSettle();
    expect(popup, findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
  });

  testWidgets('reader word popup shows the english lookup explanation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          learningSettingsProvider.overrideWith(
            _ConfiguredLearningSettingsNotifier.new,
          ),
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => WordLookupService(
              remoteLookupOverride:
                  ({
                    required String rawWord,
                    String? contextSentence,
                    required LearningSettingsState settings,
                  }) async {
                    return const WordLookupEntry(
                      word: 'Guess',
                      phonetic: '/ɡes/',
                      type: 'verb',
                      definitionEn:
                          'To give an answer without knowing all the facts.',
                      usageEn:
                          'Use guess when an answer is based on limited information.',
                      exampleSentenceEn: 'Can you guess who called me?',
                      definitionCn: '猜测；猜想',
                      sourceLabel: 'API',
                    );
                  },
            ),
          ),
        ],
        child: MaterialApp(
          home: FullTranscriptReaderScreen(
            snapshot: const TranscriptReaderSnapshot(
              courseTitle: '测试课程',
              episodeTitle: '第 01 集',
              lines: lines,
              meanings: <String, String>{'guess': '猜测'},
              progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
            ),
            progressListenable: progress,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guess'));
    await tester.pumpAndSettle();

    expect(find.text('英文说明'), findsOneWidget);
    expect(
      find.textContaining('To give an answer without knowing all the facts.'),
      findsOneWidget,
    );
    expect(find.text('Can you guess who called me?'), findsOneWidget);
    expect(find.text('翻译来源：API'), findsOneWidget);
  });

  testWidgets('locate button scrolls back to the current word', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
        );
    addTearDown(progress.dispose);
    final List<PlayerSubtitleLine> longTranscript =
        List<PlayerSubtitleLine>.generate(
          24,
          (int index) => PlayerSubtitleLine(
            startTime: '00:${index.toString().padLeft(2, '0')}',
            english: 'Guess what I bought?',
            chinese: '',
            startMs: index * 1000,
            endMs: (index + 1) * 1000,
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: FullTranscriptReaderScreen(
          snapshot: TranscriptReaderSnapshot(
            courseTitle: '测试课程',
            episodeTitle: '第 01 集',
            lines: longTranscript,
            meanings: const <String, String>{'what': '什么'},
            progress: const TranscriptReaderProgress(
              lineIndex: 0,
              wordIndex: 1,
            ),
          ),
          progressListenable: progress,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();

    final Finder activeWord = find.byKey(
      const ValueKey<String>('reader-word-box-what-true'),
    );
    expect(activeWord, findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('reader-locate-current-word')),
    );
    await tester.pumpAndSettle();

    expect(activeWord, findsOneWidget);
    expect(tester.getCenter(activeWord).dy, inInclusiveRange(80, 360));
  });
}

class _TestDictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    return switch (rawWord) {
      'what' => const OfflineWordDefinition(
        translation: '什么',
        phonetic: '',
        partOfSpeech: '',
      ),
      'bought' => const OfflineWordDefinition(
        translation: '购买',
        phonetic: '',
        partOfSpeech: '',
      ),
      _ => null,
    };
  }
}

class _ConfiguredLearningSettingsNotifier extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() {
    return LearningSettingsState.defaults().copyWith(
      translationProvider: 'OpenAI',
      translationApiKey: 'test-key',
      translationBaseUrl: 'https://example.invalid/v1',
      translationModel: 'test-model',
    );
  }
}
