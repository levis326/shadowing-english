import 'package:common_learn_english/features/player/presentation/desktop_whisper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS resolves whisper-server inside the app bundle', () {
    final List<String> candidates = desktopWhisperServerCandidates(
      operatingSystem: 'macos',
      resolvedExecutable:
          '/Applications/Shadowing English.app/Contents/MacOS/app',
    );

    expect(
      candidates.first,
      '/Applications/Shadowing English.app/Contents/Resources/whisper/whisper-server',
    );
    expect(candidates, contains('whisper-server'));
  });

  test('Windows resolves whisper-server.exe next to the executable', () {
    final List<String> candidates = desktopWhisperServerCandidates(
      operatingSystem: 'windows',
      resolvedExecutable: r'C:\Shadowing English\common_learn_english.exe',
    );

    expect(candidates.first, r'C:\Shadowing English\whisper\whisper-server.exe');
  });

  test('Linux resolves whisper-server under the bundle lib directory', () {
    final List<String> candidates = desktopWhisperServerCandidates(
      operatingSystem: 'linux',
      resolvedExecutable: '/opt/shadowing-english/common_learn_english',
    );

    expect(candidates.first, '/opt/shadowing-english/lib/whisper/whisper-server');
  });

  test('model resolves next to the bundled whisper binary', () {
    final List<String> candidates = desktopWhisperModelCandidates(
      operatingSystem: 'windows',
      resolvedExecutable: r'C:\App\common_learn_english.exe',
    );

    expect(candidates.first, r'C:\App\whisper\ggml-small.en.bin');
  });
}
