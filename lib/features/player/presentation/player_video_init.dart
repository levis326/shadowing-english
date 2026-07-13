import 'dart:async';

import 'package:media_kit/media_kit.dart';

typedef VideoInitializationRunner = Future<void> Function();

Future<void> waitForVideoInitialization(
  VideoInitializationRunner initialize, {
  Duration timeout = const Duration(seconds: 8),
}) {
  return initialize().timeout(timeout);
}

Future<void> waitForPlayerReady(
  Player player, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  bool hasDuration = player.state.duration > Duration.zero;
  bool hasVideoSize =
      (player.state.width ?? 0) > 0 && (player.state.height ?? 0) > 0;
  if (hasDuration && hasVideoSize) {
    return;
  }

  final Completer<void> completer = Completer<void>();
  StreamSubscription<Duration>? durationSubscription;
  StreamSubscription<int?>? widthSubscription;
  StreamSubscription<int?>? heightSubscription;

  void completeIfReady() {
    if (!completer.isCompleted && hasDuration && hasVideoSize) {
      completer.complete();
    }
  }

  durationSubscription = player.stream.duration.listen((Duration duration) {
    if (duration > Duration.zero) {
      hasDuration = true;
      completeIfReady();
    }
  });
  widthSubscription = player.stream.width.listen((int? width) {
    hasVideoSize = (width ?? 0) > 0 && (player.state.height ?? 0) > 0;
    completeIfReady();
  });
  heightSubscription = player.stream.height.listen((int? height) {
    hasVideoSize = (player.state.width ?? 0) > 0 && (height ?? 0) > 0;
    completeIfReady();
  });

  try {
    await completer.future.timeout(timeout);
  } finally {
    await durationSubscription.cancel();
    await widthSubscription.cancel();
    await heightSubscription.cancel();
  }
}
