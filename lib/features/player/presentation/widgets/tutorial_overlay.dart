import 'package:flutter/material.dart';

class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({required this.onDismiss, super.key});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 26),
            child: Column(
              children: <Widget>[
                const Spacer(),
                const Text(
                  '逐句聚焦精听',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '保持节奏简单一些：点句子、单句循环、逐句推进，直到这一句真正听清。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFD0D0D4),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                const _InstructionRow(
                  icon: Icons.touch_app_rounded,
                  title: '点击任意字幕',
                  body: '直接跳到你想单独精听的那一句。',
                ),
                const SizedBox(height: 12),
                const _InstructionRow(
                  icon: Icons.replay_rounded,
                  title: '单句循环',
                  body: '围绕一句反复听，直到语感和节奏顺下来。',
                  highlighted: true,
                ),
                const SizedBox(height: 12),
                const _InstructionRow(
                  icon: Icons.skip_next_rounded,
                  title: '继续下一句',
                  body: '这一句能完整听清之后，再往后推进。',
                ),
                const Spacer(),
                TextButton(
                  onPressed: onDismiss,
                  child: const Text(
                    '开始学习',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({
    required this.icon,
    required this.title,
    required this.body,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFF2B2B31)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Color(0xFFD0D0D4),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
