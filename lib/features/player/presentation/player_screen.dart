import 'package:flutter/material.dart';

import 'pad_landscape_player_screen.dart';
import 'pad_portrait_player_screen.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({
    required this.episodeId,
    this.initialStartTime,
    this.autoPlay = false,
    this.autoOpenFullscreen = false,
    super.key,
  });

  final String episodeId;
  final String? initialStartTime;
  final bool autoPlay;
  final bool autoOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool isPortrait = size.height > size.width;

    if (isPortrait) {
      return PadPortraitPlayerScreen(
        key: ValueKey<String>(episodeId),
        episodeId: episodeId,
        initialStartTime: initialStartTime,
        autoPlay: autoPlay,
        autoOpenFullscreen: autoOpenFullscreen,
      );
    }

    return PadLandscapePlayerScreen(
      key: ValueKey<String>(episodeId),
      episodeId: episodeId,
      initialStartTime: initialStartTime,
      autoPlay: autoPlay,
      autoOpenFullscreen: autoOpenFullscreen,
    );
  }
}
