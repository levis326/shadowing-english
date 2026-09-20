import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/utils/text_file_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// 中文 Windows 记事本 / 老播放器常见的 GBK 字节（“你好，世界”）。
const List<int> _gbkHello = <int>[
  0xC4, 0xE3, 0xBA, 0xC3, 0xA3, 0xAC, 0xCA, 0xC0, 0xBD, 0xE7,
];

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('text-file-io-');
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('UTF-8 字幕文件读取', () async {
    final File file = File('${dir.path}${Platform.pathSeparator}utf8.srt')
      ..writeAsStringSync(
        '1\n00:00:01,000 --> 00:00:02,000\n你好，世界\n',
      );
    expect(await readTextFileTolerant(file.path), contains('你好，世界'));
    expect(readTextFileTolerantSync(file.path), contains('你好，世界'));
  });

  test('GBK 字幕文件读取（ANSI）', () async {
    final File file = File('${dir.path}${Platform.pathSeparator}gbk.srt')
      ..writeAsBytesSync(<int>[
        ...utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n'),
        ..._gbkHello,
        ...utf8.encode('\n'),
      ]);
    final String text = await readTextFileTolerant(file.path);
    expect(text, contains('你好，世界'));
    expect(readTextFileTolerantSync(file.path), contains('你好，世界'));
  });

  test('UTF-16LE（记事本的 Unicode）字幕文件读取', () async {
    final File file = File('${dir.path}${Platform.pathSeparator}utf16.srt');
    final List<int> body = '中文字幕'.codeUnits
        .expand((int unit) => <int>[unit & 0xFF, (unit >> 8) & 0xFF])
        .toList(growable: false);
    file.writeAsBytesSync(<int>[0xFF, 0xFE, ...body]);
    expect(await readTextFileTolerant(file.path), '中文字幕');
  });

  test('writeTextFileWithBom 写出带 BOM 的 UTF-8，并能读回', () async {
    final String path = '${dir.path}${Platform.pathSeparator}export.en.srt';
    await writeTextFileWithBom(path, '1\n00:00:01,000 --> 00:00:02,000\n你好\n');
    final List<int> bytes = File(path).readAsBytesSync();
    expect(bytes.take(3), <int>[0xEF, 0xBB, 0xBF]);
    expect(await readTextFileTolerant(path), startsWith('1\n'));
    expect(await readTextFileTolerant(path), contains('你好'));
  });

  test('不存在的文件照常抛异常（调用方自己兜底）', () async {
    await expectLater(
      readTextFileTolerant('${dir.path}${Platform.pathSeparator}nope.srt'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
