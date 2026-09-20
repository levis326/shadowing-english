import 'dart:convert';

import 'package:common_learn_english/utils/text_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

/// 中文 Windows 记事本 / 老播放器常见的 GBK 字节。
const List<int> _gbkNiHaoShiJie = <int>[
  0xC4, 0xE3, 0xBA, 0xC3, 0xA3, 0xAC, 0xCA, 0xC0, 0xBD, 0xE7,
];

List<int> _ascii(String text) => utf8.encode(text);

void main() {
  group('decodeTextBytes', () {
    test('UTF-8 中文原样解出', () {
      expect(decodeTextBytes(utf8.encode('你好，世界')), '你好，世界');
      expect(decodeTextBytes(utf8.encode('Hello world')), 'Hello world');
      expect(decodeTextBytes(const <int>[]), '');
    });

    test('UTF-8 BOM 不会留在结果里', () {
      final List<int> bytes = <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('中文字幕'),
      ];
      expect(decodeTextBytes(bytes), '中文字幕');
    });

    test('GBK（中文 Windows 的 ANSI）能读出来', () {
      // 同一段字节按 UTF-8 解会直接报错——这正是“字幕文件读取失败”的原因。
      expect(
        () => utf8.decode(_gbkNiHaoShiJie),
        throwsFormatException,
      );
      expect(decodeTextBytes(_gbkNiHaoShiJie), '你好，世界');
    });

    test('GBK 的 .srt 文件（时间轴 + 中文混排）', () {
      final List<int> bytes = <int>[
        ..._ascii('1\n00:00:01,000 --> 00:00:03,000\n'),
        ..._gbkNiHaoShiJie,
        ..._ascii('\n\n2\n00:00:04,000 --> 00:00:06,000\n'),
        ..._ascii('Goodbye\n'),
      ];
      final String text = decodeTextBytes(bytes);
      expect(text, contains('00:00:01,000 --> 00:00:03,000'));
      expect(text, contains('你好，世界'));
      expect(text, contains('Goodbye'));
    });

    test('CP936 的 0x80 是欧元符号', () {
      expect(decodeTextBytes(<int>[0x80]), '€');
    });

    test('GB18030 四字节生僻字与表情', () {
      // U+20000、U+1F600 的 GB18030 四字节形式。
      expect(decodeTextBytes(<int>[0x95, 0x32, 0x82, 0x36]), '\u{20000}');
      expect(decodeTextBytes(<int>[0x94, 0x39, 0xFC, 0x36]), '😀');
      expect(decodeTextBytes(<int>[0xE3, 0x32, 0x9A, 0x35]), '\u{10FFFF}');
    });

    test('UTF-16（带 BOM）也能读', () {
      expect(
        decodeTextBytes(<int>[
          0xFF,
          0xFE,
          0x2D,
          0x4E,
          0x87,
          0x65,
          0x41,
          0x00,
          0x42,
          0x00,
          0x43,
          0x00,
        ]),
        '中文ABC',
      );
      expect(
        decodeTextBytes(<int>[
          0xFE,
          0xFF,
          0x4E,
          0x2D,
          0x65,
          0x87,
          0x00,
          0x41,
          0x00,
          0x42,
          0x00,
          0x43,
        ]),
        '中文ABC',
      );
    });

    test('没有 BOM 的 UTF-16LE 靠 NUL 分布识别', () {
      expect(
        decodeTextBytes(<int>[
          0x2D,
          0x4E,
          0x87,
          0x65,
          0x41,
          0x00,
          0x42,
          0x00,
          0x43,
          0x00,
        ]),
        '中文ABC',
      );
    });

    test('彻底认不出的字节也不会抛异常', () {
      expect(
        () => decodeTextBytes(const <int>[0xC0, 0xC1, 0xF5, 0xFF, 0xFE]),
        returnsNormally,
      );
      expect(
        decodeTextBytes(const <int>[0xFF, 0xFF, 0xFF]),
        contains(String.fromCharCode(kUnicodeReplacementCharacter)),
      );
    });
  });

  group('decodeGbkBytes', () {
    test('已知码位映射正确', () {
      expect(decodeGbkBytes(<int>[0xD6, 0xD0]), '中');
      expect(decodeGbkBytes(<int>[0xCE, 0xC4]), '文');
      expect(decodeGbkBytes(<int>[0xC4, 0xE3]), '你');
      expect(decodeGbkBytes(<int>[0xBA, 0xC3]), '好');
      expect(decodeGbkBytes(<int>[0xA1, 0xA1]), '\u3000');
      // ASCII 直接透传。
      expect(decodeGbkBytes(_ascii('ABC 123')), 'ABC 123');
    });

    test('内置表完整（126×190 个双字节码位）', () {
      expect(gbkDecodeTable(), hasLength(126 * 190));
      // 已映射码位数（未映射为 0xFFFD）。
      final int mapped = gbkDecodeTable()
          .where((int code) => code != kUnicodeReplacementCharacter)
          .length;
      expect(mapped, 21791);
    });

    test('任何字节组合都不会越界或抛异常', () {
      expect(
        () => decodeGbkBytes(List<int>.generate(256, (int i) => i)),
        returnsNormally,
      );
      for (int lead = 0x81; lead <= 0xFF; lead += 1) {
        for (int trail = 0x00; trail <= 0xFF; trail += 1) {
          expect(() => decodeGbkBytes(<int>[lead, trail]), returnsNormally);
        }
      }
    });
  });

  group('写出 UTF-8 BOM', () {
    test('utf8BytesWithBom 带 BOM 且能读回', () {
      final List<int> bytes = utf8BytesWithBom('中英双语字幕');
      expect(bytes.take(3), <int>[0xEF, 0xBB, 0xBF]);
      expect(decodeTextBytes(bytes), '中英双语字幕');
    });

    test('stripBom / countReplacementCharacters', () {
      expect(stripBom('\uFEFFabc'), 'abc');
      expect(stripBom('abc'), 'abc');
      expect(containsReplacementCharacter('a\uFFFDb'), isTrue);
      expect(countReplacementCharacters('a\uFFFDb\uFFFD'), 2);
      expect(countReplacementCharacters('中文'), 0);
    });
  });
}
