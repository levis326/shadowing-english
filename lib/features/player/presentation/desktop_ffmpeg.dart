import 'dart:io';

List<String> desktopFfmpegCandidates({
  String? operatingSystem,
  String? resolvedExecutable,
}) {
  final String os = operatingSystem ?? Platform.operatingSystem;
  final String executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final String separator = os == 'windows' ? r'\' : '/';
  final String executableDir = _parent(executable, separator);
  final List<String> bundled = switch (os) {
    'macos' => <String>[
      '${_parent(executableDir, separator)}${separator}Resources${separator}ffmpeg${separator}ffmpeg',
    ],
    'windows' => <String>[
      '$executableDir${separator}ffmpeg${separator}ffmpeg.exe',
    ],
    'linux' => <String>[
      '$executableDir${separator}lib${separator}ffmpeg${separator}ffmpeg',
    ],
    _ => const <String>[],
  };
  return <String>[
    ...bundled,
    'ffmpeg',
    if (os == 'macos') ...<String>[
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
    ],
  ];
}

Future<String?> findDesktopFfmpeg() async {
  for (final String candidate in desktopFfmpegCandidates()) {
    try {
      final ProcessResult result = await Process.run(candidate, <String>[
        '-version',
      ]);
      if (result.exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

String _parent(String path, String separator) {
  final String normalized = separator == r'\'
      ? path.replaceAll('/', separator)
      : path.replaceAll(r'\', separator);
  final int index = normalized.lastIndexOf(separator);
  return index <= 0 ? normalized : normalized.substring(0, index);
}
