import 'dart:async';

import 'package:flutter/services.dart';

class PlayerSystemMediaControls {
  PlayerSystemMediaControls._();

  static const MethodChannel _channel = MethodChannel(
    'com.shadowing.english/system_media_controls',
  );

  static void bind({
    required VoidCallback onPlay,
    required VoidCallback onPause,
    required VoidCallback onToggle,
    required VoidCallback onNext,
    required VoidCallback onPrevious,
  }) {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'play':
          onPlay();
          return;
        case 'pause':
          onPause();
          return;
        case 'toggle':
          onToggle();
          return;
        case 'next':
          onNext();
          return;
        case 'previous':
          onPrevious();
          return;
      }
    });
  }

  static void unbind() {
    _channel.setMethodCallHandler(null);
  }

  static void updatePlaybackState({required bool isPlaying}) {
    unawaited(
      _channel
          .invokeMethod<void>('updatePlaybackState', <String, bool>{
            'isPlaying': isPlaying,
          })
          .catchError((Object _) {}),
    );
  }
}
