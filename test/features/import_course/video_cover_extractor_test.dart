import 'package:common_learn_english/features/import_course/domain/video_cover_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'initializeVideoCoverExtractor delegates to the configured initializer',
    () async {
      bool initialized = false;

      await initializeVideoCoverExtractor(
        initializeImpl: () async {
          initialized = true;
        },
      );

      expect(initialized, isTrue);
    },
  );
}
