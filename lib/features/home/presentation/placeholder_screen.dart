import 'package:flutter/material.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/app_shell.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.destination, super.key});

  final AppNavDestination destination;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      currentDestination: destination,
      header: _Header(title: destination.label),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
        children: <Widget>[
          Text(
            destination.title,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: Color(0xFF050505),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            destination.subtitle,
            style: const TextStyle(
              color: Color(0xFF68686D),
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          _FeatureCard(
            title: destination.title,
            body:
                'This section is visually ready so navigation feels complete, but the current version still centers on intensive listening with your imported local content.',
          ),
          const SizedBox(height: 16),
          const _FeatureCard(
            title: 'Recommended next step',
            body:
                'Open Learn or go to the library to import your own video and subtitle files.',
            tone: Color(0xFFFFE6D6),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.apps_rounded),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 46),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.body,
    this.tone = Colors.white,
  });

  final String title;
  final String body;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFF68686D),
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
