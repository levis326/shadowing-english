import 'dart:convert';
import 'dart:typed_data';

import 'gbk_table_data.dart';

/// 文本编码识别与解码。
///
/// 应用内部生成的文件（AI 字幕缓存、`.meta.json`、词库等）统一写 UTF-8，
/// 用 `dart:convert` 的默认 UTF-8 读写即可；这里处理的是**用户自己带来的文本**：
/// 中文 Windows 上的记事本 / 老播放器常把字幕存成 ANSI（GBK/CP936），
/// 也有人存成 UTF-16「Unicode」。这些文件如果按 UTF-8 硬读，轻则乱码，
/// 重则抛 `FormatException: Invalid UTF-8`（表现为“字幕文件读取失败”）。
///
/// 支持顺序：
///  1. UTF-8 BOM；
///  2. UTF-16 BOM（FF FE / FE FF）；
///  3. 没有 BOM 但 NUL 字节分布明显是 UTF-16 的文本；
///  4. 严格 UTF-8；
///  5. GBK / GB18030（含四字节生僻字）。
const int kUnicodeReplacementCharacter = 0xFFFD;

const List<int> _utf8Bom = <int>[0xEF, 0xBB, 0xBF];

/// 把一段字节按最可能的编码解成字符串（永不抛异常）。
String decodeTextBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    return '';
  }
  if (_startsWith(bytes, _utf8Bom)) {
    return _decodeUtf8Tolerant(bytes, 3);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return decodeUtf16Bytes(bytes.sublist(2));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return decodeUtf16Bytes(bytes.sublist(2), littleEndian: false);
  }
  final bool? utf16LittleEndian = _guessUtf16(bytes);
  if (utf16LittleEndian != null) {
    return decodeUtf16Bytes(bytes, littleEndian: utf16LittleEndian);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 不是合法 UTF-8：按中文 Windows 最常见的 ANSI（GBK/GB18030）解。
  }
  final String gbk = decodeGbkBytes(bytes);
  final String lossyUtf8 = utf8.decode(bytes, allowMalformed: true);
  // 两边都可能出现替换字符，取丢字更少的一种，避免把 UTF-8 解成乱码。
  return countReplacementCharacters(gbk) <=
          countReplacementCharacters(lossyUtf8)
      ? gbk
      : lossyUtf8;
}

/// 严格 UTF-8；失败时用可容错模式（不抛异常）。
String decodeUtf8Bytes(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// GBK / GB18030（CP936 超集）解码。未映射的字节输出 U+FFFD。
String decodeGbkBytes(List<int> bytes) {
  final Uint16List table = gbkDecodeTable();
  final StringBuffer buffer = StringBuffer();
  int index = 0;
  while (index < bytes.length) {
    final int first = bytes[index];
    if (first < 0x80) {
      buffer.writeCharCode(first);
      index += 1;
      continue;
    }
    if (first == 0x80) {
      // CP936 把 0x80 定义为欧元符号。
      buffer.writeCharCode(0x20AC);
      index += 1;
      continue;
    }
    if (first >= 0x81 && first <= 0xFE && index + 1 < bytes.length) {
      final int second = bytes[index + 1];
      if (second >= 0x30 &&
          second <= 0x39 &&
          index + 3 < bytes.length &&
          bytes[index + 2] >= 0x81 &&
          bytes[index + 2] <= 0xFE &&
          bytes[index + 3] >= 0x30 &&
          bytes[index + 3] <= 0x39) {
        buffer.writeCharCode(
          gb18030FourByteCodePoint(first, second, bytes[index + 2], bytes[index + 3]),
        );
        index += 4;
        continue;
      }
      if (second >= 0x40 && second <= 0xFE && second != 0x7F) {
        final int offset = (first - 0x81) * 190 +
            (second < 0x7F ? second - 0x40 : second - 0x41);
        final int codePoint = table[offset];
        if (codePoint != kUnicodeReplacementCharacter) {
          buffer.writeCharCode(codePoint);
          index += 2;
          continue;
        }
      }
    }
    buffer.writeCharCode(kUnicodeReplacementCharacter);
    index += 1;
  }
  return buffer.toString();
}

/// GB18030 四字节码位：先算指针，再在区间表里线性还原 Unicode。
int gb18030FourByteCodePoint(int first, int second, int third, int fourth) {
  final int pointer = ((first - 0x81) * 10 + (second - 0x30)) * 1260 +
      (third - 0x81) * 10 +
      (fourth - 0x30);
  const List<int> ranges = kGb18030FourByteRanges;
  int low = 0;
  int high = ranges.length ~/ 2 - 1;
  int best = 0;
  while (low <= high) {
    final int middle = (low + high) ~/ 2;
    final int startPointer = ranges[middle * 2];
    if (startPointer <= pointer) {
      best = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  final int codePoint = ranges[best * 2 + 1] + (pointer - ranges[best * 2]);
  if (codePoint < 0 || codePoint > 0x10FFFF) {
    return kUnicodeReplacementCharacter;
  }
  return codePoint;
}

/// UTF-16 解码（含代理对）。
String decodeUtf16Bytes(List<int> bytes, {bool littleEndian = true}) {
  final StringBuffer buffer = StringBuffer();
  int index = 0;
  while (index + 1 < bytes.length) {
    final int unit = littleEndian
        ? bytes[index] | (bytes[index + 1] << 8)
        : (bytes[index] << 8) | bytes[index + 1];
    index += 2;
    if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < bytes.length) {
      final int low = littleEndian
          ? bytes[index] | (bytes[index + 1] << 8)
          : (bytes[index] << 8) | bytes[index + 1];
      if (low >= 0xDC00 && low <= 0xDFFF) {
        index += 2;
        buffer.writeCharCode(
          0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00),
        );
        continue;
      }
    }
    buffer.writeCharCode(unit);
  }
  return buffer.toString();
}

/// 惰性解码内置的 GBK 双字节表。
Uint16List gbkDecodeTable() {
  final Uint16List? cached = _gbkTable;
  if (cached != null) {
    return cached;
  }
  final List<int> raw = base64.decode(kGbkTableBase64);
  final Uint16List table = Uint16List(raw.length ~/ 2);
  for (int i = 0; i < table.length; i += 1) {
    table[i] = (raw[i * 2] << 8) | raw[i * 2 + 1];
  }
  _gbkTable = table;
  return table;
}

Uint16List? _gbkTable;

/// UTF-8（带 BOM）字节，供导出 `.srt` 等交给外部播放器/编辑器读取的文件使用。
/// 中文 Windows 上很多播放器靠 BOM 判断 UTF-8，否则会按 ANSI 显示成乱码。
Uint8List utf8BytesWithBom(String text) {
  final List<int> body = utf8.encode(text);
  final Uint8List bytes = Uint8List(body.length + _utf8Bom.length);
  bytes
    ..setRange(0, _utf8Bom.length, _utf8Bom)
    ..setRange(_utf8Bom.length, bytes.length, body);
  return bytes;
}

/// 去掉字符串开头的 BOM（U+FEFF）。
String stripBom(String text) =>
    text.startsWith('\uFEFF') ? text.substring(1) : text;

/// 文本里是否含有 U+FFFD（解码失败的替换字符）。
bool containsReplacementCharacter(String text) =>
    text.contains(String.fromCharCode(kUnicodeReplacementCharacter));

/// 统计 U+FFFD 的个数，用来在多种解码结果里挑损失最小的一种。
int countReplacementCharacters(String text) => text.runes
    .where((int rune) => rune == kUnicodeReplacementCharacter)
    .length;

String _decodeUtf8Tolerant(List<int> bytes, int start) {
  return utf8.decode(
    start == 0 ? bytes : bytes.sublist(start),
    allowMalformed: true,
  );
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (int i = 0; i < prefix.length; i += 1) {
    if (bytes[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

/// 没有 BOM 时的 UTF-16 猜测：按 ASCII 文本“字符 + NUL”的 NUL 分布判断。
/// 返回 true 表示小端，false 表示大端，null 表示不像 UTF-16。
bool? _guessUtf16(List<int> bytes) {
  if (bytes.length < 8) {
    return null;
  }
  final int sample = bytes.length > 4096 ? 4096 : (bytes.length ~/ 2) * 2;
  if (sample < 8) {
    return null;
  }
  int evenNul = 0;
  int oddNul = 0;
  for (int i = 0; i + 1 < sample; i += 2) {
    if (bytes[i] == 0) {
      evenNul += 1;
    }
    if (bytes[i + 1] == 0) {
      oddNul += 1;
    }
  }
  final int pairs = sample ~/ 2;
  final double threshold = pairs * 0.3;
  final double tolerance = pairs * 0.05;
  if (oddNul > threshold && evenNul <= tolerance) {
    return true;
  }
  if (evenNul > threshold && oddNul <= tolerance) {
    return false;
  }
  return null;
}
