import 'package:common_learn_english/features/shared/data/desktop_nllb.dart';
import 'package:common_learn_english/features/shared/data/desktop_pronunciation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop server binary candidates', () {
    test('nllb prefers the PyInstaller onedir layout on Windows', () {
      final List<String> candidates = desktopNllbBinaryCandidates(
        operatingSystem: 'windows',
        resolvedExecutable: r'D:\shadowing\common_learn_english.exe',
      );
      expect(candidates.first, r'D:\shadowing\nllb\nllb-server\nllb-server.exe');
      // 旧 onefile 布局仍然可用。
      expect(candidates, contains(r'D:\shadowing\nllb\nllb-server.exe'));
    });

    test('nllb keeps the onedir layout on Linux and macOS', () {
      expect(
        desktopNllbBinaryCandidates(
          operatingSystem: 'linux',
          resolvedExecutable: '/opt/app/common_learn_english',
        ).first,
        '/opt/app/lib/nllb/nllb-server/nllb-server',
      );
      expect(
        desktopNllbBinaryCandidates(
          operatingSystem: 'macos',
          resolvedExecutable: '/Applications/App.app/Contents/MacOS/app',
        ).first,
        '/Applications/App.app/Contents/Resources/nllb/nllb-server/'
        'nllb-server',
      );
    });

    test('pronunciation prefers the PyInstaller onedir layout on Windows', () {
      final List<String> candidates = desktopPronunciationBinaryCandidates(
        operatingSystem: 'windows',
        resolvedExecutable: r'E:\usb\common_learn_english.exe',
      );
      expect(
        candidates.first,
        r'E:\usb\pronunciation\pronunciation-server\pronunciation-server.exe',
      );
      expect(
        candidates,
        contains(r'E:\usb\pronunciation\pronunciation-server.exe'),
      );
    });

    test('unknown platforms only fall back to PATH lookup', () {
      expect(
        desktopNllbBinaryCandidates(
          operatingSystem: 'fuchsia',
          resolvedExecutable: '/tmp/app',
        ),
        <String>['nllb-server'],
      );
      expect(
        desktopPronunciationBinaryCandidates(
          operatingSystem: 'fuchsia',
          resolvedExecutable: '/tmp/app',
        ),
        <String>['pronunciation-server'],
      );
    });
  });
}
