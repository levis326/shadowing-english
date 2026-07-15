import 'package:common_learn_english/features/player/presentation/desktop_ffmpeg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS checks the app bundle before system ffmpeg', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'macos',
      resolvedExecutable:
          '/Applications/Shadowing English.app/Contents/MacOS/app',
    );

    expect(
      candidates.first,
      '/Applications/Shadowing English.app/Contents/Resources/ffmpeg/ffmpeg',
    );
    expect(candidates, contains('ffmpeg'));
  });

  test('Windows checks the packaged executable next to the app', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'windows',
      resolvedExecutable: r'C:\Shadowing English\common_learn_english.exe',
    );

    expect(candidates.first, r'C:\Shadowing English\ffmpeg\ffmpeg.exe');
  });

  test('Linux checks the relocatable bundle library directory', () {
    final List<String> candidates = desktopFfmpegCandidates(
      operatingSystem: 'linux',
      resolvedExecutable: '/opt/shadowing-english/common_learn_english',
    );

    expect(candidates.first, '/opt/shadowing-english/lib/ffmpeg/ffmpeg');
  });
}
