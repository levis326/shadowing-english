import 'package:media_kit/media_kit.dart';

typedef VideoPlayerBackendInitializer = void Function();

void initializeVideoPlayerBackend({
  VideoPlayerBackendInitializer ensureInitialized = MediaKit.ensureInitialized,
}) {
  ensureInitialized();
}
