import 'package:common_learn_english/features/player/presentation/player_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initializes media_kit backend once', () {
    bool initialized = false;

    initializeVideoPlayerBackend(
      ensureInitialized: () {
        initialized = true;
      },
    );

    expect(initialized, isTrue);
  });
}
