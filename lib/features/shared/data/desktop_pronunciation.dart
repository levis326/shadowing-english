import 'dart:io';

/// Filename of the local pronunciation evaluation server bundled with the app.
const String desktopPronunciationBinaryName = 'pronunciation-server';

/// Name of the bundled wav2vec2-large-960h checkpoint (torchaudio cache
/// layout). The large model scores pronunciation noticeably better than the
/// previous base-960h model and drives the per-syllable scores.
const String desktopPronunciationModelFileName =
    'wav2vec2_fairseq_large_ls960_asr_ls960.pth';

List<String> desktopPronunciationBinaryCandidates({
  String? operatingSystem,
  String? resolvedExecutable,
}) {
  final String os = operatingSystem ?? Platform.operatingSystem;
  final String executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String? dir = desktopPronunciationDir(os, executable, separator);
  final String binary = os == 'windows'
      ? '$desktopPronunciationBinaryName.exe'
      : desktopPronunciationBinaryName;
  return <String>[
    if (dir != null) '$dir$separator$binary',
    binary,
  ];
}

Future<String?> findDesktopPronunciationBinary() async {
  for (final String candidate in desktopPronunciationBinaryCandidates()) {
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

/// Returns the bundled model directory (containing
/// `hub/checkpoints/<model>.pth`), or null when not bundled.
Future<String?> findDesktopPronunciationModelDir() async {
  final String os = Platform.operatingSystem;
  final String executable = Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String? dir = desktopPronunciationDir(os, executable, separator);
  if (dir == null) return null;
  final String checkpoint =
      '$dir${separator}hub${separator}checkpoints'
      '$separator$desktopPronunciationModelFileName';
  return File(checkpoint).existsSync() ? dir : null;
}

String? desktopPronunciationDir(
  String os,
  String executable,
  String separator,
) {
  final String executableDir = _parent(executable, separator);
  return switch (os) {
    'macos' =>
      '${_parent(executableDir, separator)}${separator}Resources'
          '${separator}pronunciation',
    'windows' => '$executableDir${separator}pronunciation',
    'linux' => '$executableDir${separator}lib${separator}pronunciation',
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
