import 'dart:io';

import 'text_encoding.dart';

/// 读取用户提供的文本文件（字幕 `.srt` / `.vtt`、纯文本字幕、导入预览）：
/// 自动识别 UTF-8 / UTF-8 BOM / UTF-16 / GBK（中文 Windows 的 ANSI）。
Future<String> readTextFileTolerant(String path) async {
  final List<int> bytes = await File(path).readAsBytes();
  return decodeTextBytes(bytes);
}

/// [readTextFileTolerant] 的同步版本。
String readTextFileTolerantSync(String path) {
  return decodeTextBytes(File(path).readAsBytesSync());
}

/// 写 UTF-8 + BOM 的文本文件：用于导出/保存 `.srt`，让中文 Windows 上的
/// 播放器与记事本都能正确识别 UTF-8（应用自己解析时会去掉 BOM）。
Future<void> writeTextFileWithBom(String path, String content) {
  return File(path).writeAsBytes(utf8BytesWithBom(content), flush: true);
}
