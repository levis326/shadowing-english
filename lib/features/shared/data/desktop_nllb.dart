import 'dart:io';

/// Default filename of the bundled SentencePiece tokenizer for the NLLB model.
const String desktopNllbTokenizerFileName = 'sentencepiece.bpe.model';

/// NLLB-200 language codes. The app ships the model that supports 200
/// languages, so these are parameterizable for future multi-language support.
const String desktopNllbSourceLanguage = 'eng_Latn';
const String desktopNllbTargetLanguage = 'zho_Hans';

/// Filename of the CTranslate2 translation binary bundled with the app.
const String desktopNllbBinaryName = 'nllb-translate';

List<String> desktopNllbBinaryCandidates({
  String? operatingSystem,
  String? resolvedExecutable,
}) {
  final String os = operatingSystem ?? Platform.operatingSystem;
  final String executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String? dir = desktopNllbDir(
    os,
    executable,
    separator,
  );
  final String binary = os == 'windows'
      ? '$desktopNllbBinaryName.exe'
      : desktopNllbBinaryName;
  return <String>[
    if (dir != null) '$dir$separator$binary',
    binary,
  ];
}

Future<String?> findDesktopNllbBinary() async {
  for (final String candidate in desktopNllbBinaryCandidates()) {
    try {
      final ProcessResult result = await Process.run(
        candidate,
        <String>['--help'],
      );
      if (result.exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

Future<String?> findDesktopNllbModelDir() async {
  final String os = Platform.operatingSystem;
  final String executable = Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String? dir = desktopNllbDir(os, executable, separator);
  if (dir == null) return null;
  if (File('$dir${separator}model.bin').existsSync()) return dir;
  return null;
}

Future<String?> findDesktopNllbTokenizer() async {
  final String os = Platform.operatingSystem;
  final String executable = Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String? dir = desktopNllbDir(os, executable, separator);
  if (dir == null) return null;
  final String candidate =
      '$dir$separator$desktopNllbTokenizerFileName';
  return File(candidate).existsSync() ? candidate : null;
}

String? desktopNllbDir(String os, String executable, String separator) {
  final String executableDir = _parent(executable, separator);
  return switch (os) {
    'macos' =>
      '${_parent(executableDir, separator)}${separator}Resources${separator}nllb',
    'windows' => '$executableDir${separator}nllb',
    'linux' => '$executableDir${separator}lib${separator}nllb',
    _ => null,
  };
}

String _parent(String path, String separator) {
  final String normalized = separator == r'\'
      ? path.replaceAll('/', separator)
      : path.replaceAll(r'\', separator);
  final int index = normalized.lastIndexOf(separator);
  return index <= 0 ? normalized : normalized.substring(0, index);
}
