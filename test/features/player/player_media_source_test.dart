import 'dart:io';

import 'package:common_learn_english/features/player/presentation/player_media_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns file uri for local sources', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp();
    final File file = File('${tempDir.path}/sample.rm')..writeAsStringSync('x');

    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    expect(createPlayerMediaUri(file.path), Uri.file(file.path).toString());
  });

  test('keeps network sources unchanged', () {
    expect(
      createPlayerMediaUri('https://example.com/video.mp4'),
      'https://example.com/video.mp4',
    );
  });
}
