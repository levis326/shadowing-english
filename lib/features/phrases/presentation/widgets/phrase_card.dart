import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../phrase_book_provider.dart';

enum _PhraseAction { edit, review, source, delete }

class PhraseCard extends StatelessWidget {
  const PhraseCard({
    required this.phrase,
    required this.isSpeaking,
    required this.onSpeak,
    required this.onEdit,
    required this.onDelete,
    required this.onMarkForReview,
    required this.onOpenSource,
    super.key,
  });

  final PhraseEntry phrase;
  final bool isSpeaking;
  final VoidCallback onSpeak;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMarkForReview;
  final VoidCallback onOpenSource;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 720;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppDesignTokens.borderGray, width: 2),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 22,
              vertical: compact ? 16 : 18,
            ),
            child: compact ? _buildCompact() : _buildWide(),
          ),
        );
      },
    );
  }

  Widget _buildWide() {
    return Row(
      children: <Widget>[
        _PlayButton(onPressed: onSpeak, isSpeaking: isSpeaking),
        const SizedBox(width: 16),
        Expanded(flex: 5, child: _PhraseText(phrase: phrase)),
        const SizedBox(width: 20),
        SizedBox(width: 180, child: _SourceMeta(phrase: phrase)),
        const SizedBox(width: 12),
        SizedBox(width: 112, child: _ReviewStatus(phrase: phrase)),
        const SizedBox(width: 6),
        _PhraseMenu(
          onEdit: onEdit,
          onDelete: onDelete,
          onMarkForReview: onMarkForReview,
          onOpenSource: onOpenSource,
        ),
      ],
    );
  }

  Widget _buildCompact() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PlayButton(onPressed: onSpeak, isSpeaking: isSpeaking),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _PhraseText(phrase: phrase),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _SourceMeta(phrase: phrase),
                  _ReviewStatus(phrase: phrase),
                ],
              ),
            ],
          ),
        ),
        _PhraseMenu(
          onEdit: onEdit,
          onDelete: onDelete,
          onMarkForReview: onMarkForReview,
          onOpenSource: onOpenSource,
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed, required this.isSpeaking});

  final VoidCallback onPressed;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: isSpeaking ? '停止朗读' : '播放英文',
      icon: Icon(isSpeaking ? Icons.pause_rounded : Icons.play_arrow_rounded),
      color: AppDesignTokens.primaryBlueDark,
      style: IconButton.styleFrom(
        minimumSize: const Size(56, 56),
        backgroundColor: isSpeaking
            ? AppDesignTokens.skyLight
            : AppDesignTokens.appWhite,
        side: const BorderSide(color: AppDesignTokens.primaryBlue, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class _PhraseText extends StatelessWidget {
  const _PhraseText({required this.phrase});

  final PhraseEntry phrase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          phrase.english,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.35,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          phrase.chinese,
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        if (phrase.note?.trim().isNotEmpty ?? false) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            phrase.note!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppDesignTokens.primaryBlueDark,
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceMeta extends StatelessWidget {
  const _SourceMeta({required this.phrase});

  final PhraseEntry phrase;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${phrase.course} · ${phrase.episode}\n${phrase.time}',
      style: const TextStyle(
        fontSize: 12,
        height: 1.45,
        color: AppDesignTokens.textSecondary,
      ),
    );
  }
}

class _ReviewStatus extends StatelessWidget {
  const _ReviewStatus({required this.phrase});

  final PhraseEntry phrase;

  @override
  Widget build(BuildContext context) {
    final bool due = phrase.isDue();
    final String label = phrase.isMastered
        ? '已掌握'
        : due
        ? '今天复习'
        : '第 ${phrase.rating} 阶段';
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: due
            ? AppDesignTokens.primaryBlueDark
            : phrase.isMastered
            ? AppDesignTokens.brandGreenDark
            : AppDesignTokens.textSecondary,
      ),
    );
  }
}

class _PhraseMenu extends StatelessWidget {
  const _PhraseMenu({
    required this.onEdit,
    required this.onDelete,
    required this.onMarkForReview,
    required this.onOpenSource,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMarkForReview;
  final VoidCallback onOpenSource;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PhraseAction>(
      tooltip: '更多操作',
      onSelected: (_PhraseAction action) {
        switch (action) {
          case _PhraseAction.edit:
            onEdit();
            return;
          case _PhraseAction.review:
            onMarkForReview();
            return;
          case _PhraseAction.source:
            onOpenSource();
            return;
          case _PhraseAction.delete:
            onDelete();
            return;
        }
      },
      itemBuilder: (BuildContext context) =>
          const <PopupMenuEntry<_PhraseAction>>[
            PopupMenuItem<_PhraseAction>(
              value: _PhraseAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('编辑'),
              ),
            ),
            PopupMenuItem<_PhraseAction>(
              value: _PhraseAction.review,
              child: ListTile(
                leading: Icon(Icons.refresh_rounded),
                title: Text('加入今天复习'),
              ),
            ),
            PopupMenuItem<_PhraseAction>(
              value: _PhraseAction.source,
              child: ListTile(
                leading: Icon(Icons.open_in_new_rounded),
                title: Text('打开原视频'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem<_PhraseAction>(
              value: _PhraseAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline_rounded),
                title: Text('删除'),
              ),
            ),
          ],
    );
  }
}
