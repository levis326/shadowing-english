import 'package:flutter/material.dart';

import '../../navigation/presentation/floating_bottom_nav.dart';
import '../../navigation/presentation/navigation_destination.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.body,
    super.key,
    this.header,
    this.currentDestination,
    this.backgroundColor = const Color(0xFFEFEFF2),
    this.useSafeArea = true,
  });

  final Widget body;
  final Widget? header;
  final AppNavDestination? currentDestination;
  final Color backgroundColor;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final Widget content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          children: <Widget>[
            if (header != null) header!,
            Expanded(child: body),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      body: useSafeArea ? SafeArea(child: content) : content,
      bottomNavigationBar: currentDestination == null
          ? null
          : FloatingBottomNav(current: currentDestination!),
    );
  }
}
