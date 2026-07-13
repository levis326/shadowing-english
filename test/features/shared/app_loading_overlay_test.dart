import 'package:common_learn_english/features/shared/presentation/app_loading_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading message only when enabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLoadingOverlay(
          isLoading: true,
          message: '正在打开课程...',
          child: Placeholder(),
        ),
      ),
    );

    expect(find.text('正在打开课程...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: AppLoadingOverlay(
          isLoading: false,
          message: '正在打开课程...',
          child: Placeholder(),
        ),
      ),
    );

    expect(find.text('正在打开课程...'), findsNothing);
  });
}
