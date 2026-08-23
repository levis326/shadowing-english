import 'dart:io';

/// Default filename of the bundled Whisper model. The multilingual small model
/// auto-detects the spoken language instead of being limited to English.
const String desktopWhisperModelFileName = 'ggml-small.bin';

List<String> desktopWhisperServerCandidates({
  String? operatingSystem,
  String? resolvedExecutable,
}) {
  final String os = operatingSystem ?? Platform.operatingSystem;
  final String executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String? dir = _desktopWhisperDir(os, executable, separator);
  final String binary = os == 'windows' ? 'whisper-server.exe' : 'whisper-server';
  return <String>[
    if (dir != null) '$dir$separator$binary',
    'whisper-server',
  ];
}

List<String> desktopWhisperModelCandidates({
  String? operatingSystem,
  String? resolvedExecutable,
  String modelFileName = desktopWhisperModelFileName,
}) {
  final String os = operatingSystem ?? Platform.operatingSystem;
  final String executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String? dir = _desktopWhisperDir(os, executable, separator);
  return <String>[
    if (dir != null) '$dir$separator$modelFileName',
  ];
}

Future<String?> findDesktopWhisperServer() async {
  for (final String candidate in desktopWhisperServerCandidates()) {
    try {
      final ProcessResult result = await Process.run(candidate, <String>[
        '--help',
      ]);
      if (result.exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

Future<String?> findDesktopWhisperModel() async {
  for (final String candidate in desktopWhisperModelCandidates()) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

String? _desktopWhisperDir(String os, String executable, String separator) {
  final String executableDir = _parent(executable, separator);
  return switch (os) {
    'macos' =>
      '${_parent(executableDir, separator)}${separator}Resources${separator}whisper',
    'windows' => '$executableDir${separator}whisper',
    'linux' => '$executableDir${separator}lib${separator}whisper',
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
