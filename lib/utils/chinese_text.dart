/// 简体中文排版整理（只动标点与空白，不改用词、不做繁简转换）。
///
/// 翻译模型（NLLB、各大在线翻译）经常把中文标点写成半角：`我在阿根廷北部吃过
/// 凯门鳄,而且很好吃.`。中文正文应使用全角标点 `，。！？；：`，字符之间也不该
/// 有多余空格，这里统一处理：
///
/// * `, . ? ! : ; ( )` → `，。？！：；（）`（只在中文语境下转换，
///   数字里的 `1,000` / `3.5`、英文缩写 `vi.` 这类保持原样）；
/// * 去掉中文字符之间的空格；
/// * 去掉全角标点前的空格。
///
/// 用户自己导入/编辑的字幕文本不会被改写。
String normalizeChineseText(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty || !containsCjk(trimmed)) {
    return trimmed;
  }
  final List<String> chars = trimmed.runes
      .map(String.fromCharCode)
      .toList(growable: false);
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < chars.length; index += 1) {
    final String char = chars[index];
    final String previous = index > 0 ? chars[index - 1] : '';
    final String next = index + 1 < chars.length ? chars[index + 1] : '';
    buffer.write(_normalizePunctuation(char, previous, next));
  }
  String result = buffer.toString();
  // 中文字符之间的空格（可能有多处，循环到稳定）。
  String previousPass;
  do {
    previousPass = result;
    result = result.replaceAllMapped(
      RegExp(r'([\u3400-\u9fff])\s+([\u3400-\u9fff])'),
      (Match match) => '${match.group(1)}${match.group(2)}',
    );
  } while (result != previousPass);
  // 全角标点前后都不留空格。
  result = result
      .replaceAllMapped(
        RegExp(r'[ \t]+([，。！？；：、）】》”’])'),
        (Match match) => match.group(1)!,
      )
      .replaceAllMapped(
        RegExp(r'([，。！？；：、（【《“])\s+'),
        (Match match) => match.group(1)!,
      );
  return result.trim();
}

/// 文本里是否含中日韩汉字。
bool containsCjk(String text) =>
    RegExp(r'[\u3400-\u9fff]').hasMatch(text);

String _normalizePunctuation(String char, String previous, String next) {
  // 数字里的逗号/小数点保持原样（1,000、3.5）。
  final bool betweenDigits = _isDigit(previous) && _isDigit(next);
  switch (char) {
    case ',':
      if (betweenDigits) {
        return char;
      }
      return _isCjk(previous) ? '，' : char;
    case '.':
      if (betweenDigits || _isLatin(previous)) {
        return char;
      }
      return _isCjk(previous) ? '。' : char;
    case '?':
      return _isCjk(previous) ? '？' : char;
    case '!':
      return _isCjk(previous) ? '！' : char;
    case ':':
      return _isCjk(previous) ? '：' : char;
    case ';':
      return _isCjk(previous) ? '；' : char;
    case '(':
      return _isCjk(next) ? '（' : char;
    case ')':
      return _isCjk(previous) ? '）' : char;
    default:
      return char;
  }
}

bool _isCjk(String char) =>
    char.isNotEmpty && RegExp(r'[\u3400-\u9fff]').hasMatch(char);

bool _isDigit(String char) =>
    char.isNotEmpty && char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;

bool _isLatin(String char) =>
    char.isNotEmpty && RegExp('[A-Za-z]').hasMatch(char);
