import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/shadowing_focus_panel.dart';
import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestDictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    return switch (rawWord) {
      'try' => const OfflineWordDefinition(
        translation: '尝试',
        phonetic: 'trai',
        partOfSpeech: '',
      ),
      'it' => const OfflineWordDefinition(
        translation: '它',
        phonetic: 'it',
        partOfSpeech: '',
      ),
      'today' => const OfflineWordDefinition(
        translation: '今天',
        phonetic: "tә'dei",
        partOfSpeech: '',
      ),
      _ => null,
    };
  }
}

void main() {
  const PlayerSubtitleLine tryItLine = PlayerSubtitleLine(
    startTime: '00:01',
    english: 'Try it today.',
    chinese: '今天就试试吧。',
    startMs: 1000,
    endMs: 2500,
  );

  test('convertEcdictPhoneticToIpa 转换为接近 IPA 的音标', () {
    expect(convertEcdictPhoneticToIpa('trai'), 'traɪ');
    expect(convertEcdictPhoneticToIpa('it'), 'ɪt');
    expect(convertEcdictPhoneticToIpa("tә'dei"), 'təˈdeɪ');
    expect(convertEcdictPhoneticToIpa("'raitiŋ"), 'ˈraɪtɪŋ');
    expect(convertEcdictPhoneticToIpa('θiŋk'), 'θɪŋk');
    expect(convertEcdictPhoneticToIpa('bu:st'), 'buːst');
  });

  Widget buildPanel({
    PlayerSubtitleLine line = tryItLine,
    VoidCallback? onArmRecording,
  }) {
    return ProviderScope(
      // ignore: always_specify_types
      overrides: [
        offlineWordDictionaryProvider.overrideWithValue(_TestDictionary()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 640,
            child: ShadowingFocusPanel(
              line: line,
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: false,
              onCollectWord: (_) {},
              onArmRecording: onArmRecording ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('跟读区显示句子、音标、中文翻译与点击录音入口', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildPanel());
    await tester.pumpAndSettle();

    expect(find.text('跟读'), findsOneWidget);
    // 句子按单词渲染。
    expect(find.text('Try'), findsOneWidget);
    expect(find.text('today.'), findsOneWidget);
    // 音标行。
    expect(find.text('/traɪ/ /ɪt/ /təˈdeɪ/'), findsOneWidget);
    // 整句中文翻译。
    expect(find.text('今天就试试吧。'), findsOneWidget);
    // 录音入口。
    expect(find.text('点击录音'), findsOneWidget);
    expect(find.text('句子播放完毕后会自动开始录音'), findsOneWidget);
  });

  testWidgets('点击录音后进入已开启自动录音状态并通知播放页', (
    WidgetTester tester,
  ) async {
    bool armed = false;
    await tester.pumpWidget(
      buildPanel(
        onArmRecording: () {
          armed = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('点击录音'));
    await tester.pump();

    expect(armed, isTrue);
    expect(find.text('已开启自动录音'), findsOneWidget);
    expect(find.text('句子播放完毕后会自动开始录音（点击取消）'), findsOneWidget);
  });

  testWidgets('没有字幕内容时显示占位文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildPanel(
        line: const PlayerSubtitleLine(
          startTime: '00:00',
          english: '',
          chinese: '',
          startMs: 0,
          endMs: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无字幕内容'), findsOneWidget);
    expect(find.text('点击录音'), findsNothing);
  });
}
