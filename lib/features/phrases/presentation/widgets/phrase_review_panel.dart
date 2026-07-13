import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../phrase_book_provider.dart';

class PhraseReviewPanel extends StatelessWidget {
  const PhraseReviewPanel({
    required this.phrase,
    required this.reviewIndex,
    required this.total,
    required this.revealed,
    required this.onReveal,
    required this.onPrevious,
    required this.onSkip,
    required this.onPlaySource,
    required this.onListenToSource,
    required this.onResult,
    super.key,
  });

  final PhraseEntry phrase;
  final int reviewIndex;
  final int total;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback? onPrevious;
  final VoidCallback? onSkip;
  final VoidCallback onPlaySource;
  final VoidCallback onListenToSource;
  final ValueChanged<PhraseReviewResult> onResult;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 840;
    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 28,
                    compact ? 12 : 24,
                    compact ? 16 : 28,
                    compact ? 24 : 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(
                        constraints: BoxConstraints(
                          minHeight: compact ? 190 : 220,
                        ),
                        padding: EdgeInsets.all(compact ? 24 : 38),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: AppDesignTokens.skyLight.withValues(
                            alpha: 0.62,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppDesignTokens.primaryBlue,
                            width: 2,
                          ),
                          boxShadow: AppDesignTokens.toyCardShadow,
                        ),
                        child: Text(
                          phrase.chinese,
                          style: TextStyle(
                            fontSize: compact ? 28 : 34,
                            fontWeight: FontWeight.w900,
                            height: 1.45,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: onPlaySource,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('播放原句'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(132, 56),
                              foregroundColor: AppDesignTokens.primaryBlueDark,
                              side: const BorderSide(
                                color: AppDesignTokens.primaryBlue,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                          ),
                          Text(
                            '${phrase.course} · ${phrase.episode} · ${phrase.time}',
                            style: const TextStyle(
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: onListenToSource,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('打开原视频'),
                          ),
                        ],
                      ),
                      if (revealed) ...<Widget>[
                        SizedBox(height: compact ? 20 : 28),
                        Container(
                          padding: EdgeInsets.all(compact ? 20 : 26),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.appWhite,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppDesignTokens.borderGray,
                              width: 2,
                            ),
                            boxShadow: AppDesignTokens.toyCardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                '英文原句',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppDesignTokens.primaryBlueDark,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                phrase.english,
                                style: TextStyle(
                                  fontSize: compact ? 24 : 30,
                                  fontWeight: FontWeight.w900,
                                  height: 1.4,
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _ReviewActionDock(
          revealed: revealed,
          onPrevious: onPrevious,
          onSkip: onSkip,
          onReveal: onReveal,
          onResult: onResult,
        ),
      ],
    );
  }
}

class _ReviewActionDock extends StatelessWidget {
  const _ReviewActionDock({
    required this.revealed,
    required this.onPrevious,
    required this.onSkip,
    required this.onReveal,
    required this.onResult,
  });

  final bool revealed;
  final VoidCallback? onPrevious;
  final VoidCallback? onSkip;
  final VoidCallback onReveal;
  final ValueChanged<PhraseReviewResult> onResult;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 840;
    final Widget navigation = Wrap(
      spacing: 4,
      children: <Widget>[
        TextButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('上一条'),
        ),
        TextButton.icon(
          onPressed: onSkip,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('暂时跳过'),
        ),
      ],
    );
    final Widget action = revealed
        ? _AssessmentActions(onResult: onResult)
        : FilledButton.icon(
            onPressed: onReveal,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text(
              '显示英文答案',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: AppDesignTokens.borderGray),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x180E305D),
            blurRadius: 14,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: EdgeInsets.all(compact ? 10 : 14),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        navigation,
                        const SizedBox(height: 8),
                        action,
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        navigation,
                        const SizedBox(width: 12),
                        Expanded(child: action),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssessmentActions extends StatelessWidget {
  const _AssessmentActions({required this.onResult});

  final ValueChanged<PhraseReviewResult> onResult;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 840;
    final List<Widget> buttons = <Widget>[
      _ResultButton(
        label: '需要再练',
        timing: '本轮再来',
        icon: Icons.refresh_rounded,
        color: Colors.red,
        onPressed: () => onResult(PhraseReviewResult.needPractice),
      ),
      _ResultButton(
        label: '差不多',
        timing: '明天复习',
        icon: Icons.sentiment_neutral_rounded,
        color: AppDesignTokens.orange,
        onPressed: () => onResult(PhraseReviewResult.almost),
      ),
      _ResultButton(
        label: '能用上',
        timing: '进入下一阶段',
        icon: Icons.check_circle_rounded,
        color: AppDesignTokens.brandGreenDark,
        onPressed: () => onResult(PhraseReviewResult.canUse),
      ),
    ];
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons
            .expand(
              (Widget button) => <Widget>[button, const SizedBox(height: 10)],
            )
            .toList(growable: false),
      );
    }
    return Row(
      children: buttons
          .map(
            (Widget button) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: button,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ResultButton extends StatelessWidget {
  const _ResultButton({
    required this.label,
    required this.timing,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final String timing;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        height: 64,
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(color: color, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                Text(timing, style: TextStyle(fontSize: 10, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
