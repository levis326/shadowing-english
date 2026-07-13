import 'package:common_learn_english/features/player/presentation/widgets/player_top_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clears the macOS window controls', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerTopBar(
              courseTitle: '课程',
              episodeTitle: '第 01 集',
              onBack: () {},
            ),
          ),
        ),
      );

      expect(
        tester.getTopLeft(find.byType(TextButton)).dy,
        greaterThanOrEqualTo(28),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
