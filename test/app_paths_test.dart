import 'dart:io';

import 'package:common_learn_english/utils/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppPaths portable path helpers', () {
    test('toPortablePath tokenizes paths under the data root only', () {
      final String root = '${Directory.systemTemp.path}${Platform.pathSeparator}cle-data';
      final String video =
          '$root${Platform.pathSeparator}imported_sources${Platform.pathSeparator}c1${Platform.pathSeparator}video.mp4';

      expect(AppPaths.toPortablePath(video, root),
          '${AppPaths.portablePathPrefix}imported_sources/c1/video.mp4');
      expect(
        AppPaths.toPortablePath(
          '${Directory.systemTemp.path}${Platform.pathSeparator}elsewhere.mp4',
          root,
        ),
        isNull,
      );
      expect(AppPaths.toPortablePath(root, root), isNull);
      expect(AppPaths.toPortablePath('', root), isNull);
    });

    test('resolvePortablePath resolves the token against the current root', () {
      final String root = '${Directory.systemTemp.path}${Platform.pathSeparator}cle-data';
      const String stored = '${AppPaths.portablePathPrefix}imported_sources/c1/video.mp4';

      expect(
        AppPaths.resolvePortablePath(stored, root),
        '$root${Platform.pathSeparator}imported_sources'
        '${Platform.pathSeparator}c1${Platform.pathSeparator}video.mp4',
      );
      expect(AppPaths.resolvePortablePath('/plain/absolute.mp4', root),
          '/plain/absolute.mp4');
    });

    test('rebasePathToDataRoot recovers moved app-managed files', () {
      final Directory dataRoot = Directory.systemTemp.createTempSync(
        'cle-rebase-root-',
      );
      addTearDown(() => dataRoot.deleteSync(recursive: true));
      final Directory courseDir = Directory(
        '${dataRoot.path}${Platform.pathSeparator}imported_sources'
        '${Platform.pathSeparator}course-1',
      )..createSync(recursive: true);
      final File video = File(
        '${courseDir.path}${Platform.pathSeparator}video.mp4',
      )..writeAsStringSync('video');

      // Old absolute path from a previous drive letter / user profile.
      final String stalePath =
          'X:${Platform.pathSeparator}old${Platform.pathSeparator}'
          'imported_sources${Platform.pathSeparator}course-1'
          '${Platform.pathSeparator}video.mp4';
      expect(
        AppPaths.rebasePathToDataRoot(stalePath, dataRoot.path),
        video.path,
      );

      // Paths outside app-managed folders cannot be rebased.
      final String unrelated = 'X:${Platform.pathSeparator}old'
          '${Platform.pathSeparator}movies${Platform.pathSeparator}video.mp4';
      expect(AppPaths.rebasePathToDataRoot(unrelated, dataRoot.path), isNull);
    });
  });
}
