import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../player_mock_state.dart';

/// 字幕区：直接显示全部双语字幕（带序号）。单击某句快速定位播放。
class SubtitleNavigatorPanel extends StatefulWidget {
  const SubtitleNavigatorPanel({
    required this.lines,
    required this.activeIndex,
    required this.fontScale,
    required this.onTapLine,
    required this.onCollectWord,
    this.onFavoriteWord,
    required this.onBookmarkLine,
    required this.onLoopFromLine,
    required this.onDictationLine,
    required this.onAiExplain,
    this.loopingLineIndex,
    this.onPronounce,
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    this.showAiGenerateSubtitles = false,
    this.generatingAiSubtitles = false,
    this.aiSubtitleProgressValue,
    this.aiSubtitleProgressText,
    this.aiSubtitlePreviewText,
    this.aiSubtitleErrorText,
    this.onGenerateAiSubtitles,
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final int activeIndex;
  final double fontScale;
  final ValueChanged<int> onTapLine;
  final ValueChanged<String> onCollectWord;
  final ValueChanged<String>? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
  final ValueChanged<int> onLoopFromLine;
  final ValueChanged<int> onDictationLine;
  final ValueChanged<int> onAiExplain;
  final int? loopingLineIndex;
  final VoidCallback? onPronounce;
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? aiSubtitleProgressValue;
  final String? aiSubtitleProgressText;
  final String? aiSubtitlePreviewText;
  final String? aiSubtitleErrorText;
  final VoidCallback? onGenerateAiSubtitles;

  @override
  State<SubtitleNavigatorPanel> createState() => _SubtitleNavigatorPanelState();
}

class _SubtitleNavigatorPanelState extends State<SubtitleNavigatorPanel> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  bool _autoFollowCurrentLine = true;
  int? _regeneratingAiLineIndex;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      _autoFollowCurrentLine = false;
    });
  }

  @override
  void didUpdateWidget(covariant SubtitleNavigatorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _rowKeyFor(int index) {
    return _rowKeys[index] ??= GlobalKey(debugLabel: 'subtitle-nav-$index');
  }

  void _scheduleScrollToActiveLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autoFollowCurrentLine) {
        return;
      }
      final BuildContext? activeContext =
          _rowKeys[widget.activeIndex]?.currentContext;
      if (activeContext != null) {
        Scrollable.ensureVisible(
          activeContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      if (widget.showAiGenerateSubtitles) {
        return _AiSubtitlePlaceholder(
          generating: widget.generatingAiSubtitles,
          progressValue: widget.aiSubtitleProgressValue,
          progressText: widget.aiSubtitleProgressText,
          previewText: widget.aiSubtitlePreviewText,
          errorText: widget.aiSubtitleErrorText,
          onGenerate: widget.onGenerateAiSubtitles,
        );
      }
      return const Center(
        child: Text(
          '当前剧集没有可用字幕或视频',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5F6368),
          ),
        ),
      );
    }

    final bool hasAiActions =
        widget.onRegenerateAiSubtitles != null ||
        widget.onDeleteAiSubtitles != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF1EE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.closed_caption_rounded,
                color: Color(0xFF53625A),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '字幕',
                    style: TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '单击句子定位播放',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (hasAiActions)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () {
                      _autoFollowCurrentLine = true;
                      _scheduleScrollToActiveLine();
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 16),
                    label: const Text('定位当前'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (widget.onRegenerateAiSubtitles != null)
                    TextButton.icon(
                      onPressed: widget.onRegenerateAiSubtitles,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('重新生成'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (widget.onDeleteAiSubtitles != null)
                    TextButton.icon(
                      onPressed: widget.onDeleteAiSubtitles,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('切回原始字幕'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              )
            else
              TextButton.icon(
                onPressed: () {
                  _autoFollowCurrentLine = true;
                  _scheduleScrollToActiveLine();
                },
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('定位当前'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _autoFollowCurrentLine = false;
        }
        return false;
      },
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(2),
        itemCount: widget.lines.length,
        itemBuilder: _buildLine,
        separatorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: <Widget>[
              SizedBox(height: 4),
              Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFE6EBE7),
              ),
              SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLine(BuildContext context, int index) {
    final PlayerSubtitleLine line = widget.lines[index];
    final bool active = index == widget.activeIndex;
    final bool isLooping = index == widget.loopingLineIndex;
    final bool isPast = index < widget.activeIndex;
    final double textOpacity = active ? 1 : (isPast ? 0.84 : 0.60);

    return InkWell(
      key: _rowKeyFor(index),
      onTap: () => widget.onTapLine(index),
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFFFF5) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppDesignTokens.brandGreen
                : const Color(0xFFE1E7E1),
            width: active ? 2.5 : 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? AppDesignTokens.brandGreen
                        : const Color(0xFFEDF1EE),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: active
                          ? Colors.white
                          : const Color(
                              0xFF7E8A82,
                            ).withValues(alpha: textOpacity),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildWordLine(line, index, active, textOpacity),
                      if (line.chinese.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          line.chinese,
                          style: TextStyle(
                            fontSize: 14 * widget.fontScale,
                            color: active
                                ? const Color(0xFF708077)
                                : const Color(
                                    0xFFB7C2BA,
                                  ).withValues(alpha: textOpacity),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (active) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _SmallActionButton(
                    icon: Icons.repeat_one_rounded,
                    tooltip: '从这里开始循环',
                    active: isLooping,
                    onPressed: () => widget.onLoopFromLine(index),
                  ),
                  const SizedBox(width: 8),
                  _SmallActionButton(
                    icon: Icons.star_rounded,
                    tooltip: '收藏到短语库',
                    onPressed: () => widget.onBookmarkLine(index),
                  ),
                  const SizedBox(width: 8),
                  _SmallActionButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: '更多操作',
                    onPressed: () =>
                        unawaited(_openActions(context, line, index)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWordLine(
    PlayerSubtitleLine line,
    int index,
    bool active,
    double textOpacity,
  ) {
    final List<String> tokens = line.english
        .split(' ')
        .where((String rawWord) => rawWord.isNotEmpty)
        .toList(growable: false);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: tokens.map((String token) {
        return InkWell(
          onTap: active ? () => _openWordLookup(token, line.english) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Text(
              token,
              style: TextStyle(
                fontSize: active
                    ? 17 * widget.fontScale
                    : (17 * widget.fontScale) - 2,
                fontWeight: FontWeight.w600,
                color: active
                    ? AppDesignTokens.textPrimary
                    : AppDesignTokens.textPrimary.withValues(
                        alpha: textOpacity,
                      ),
                height: 1.35,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  void _openWordLookup(String rawWord, String contextSentence) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: 336,
            height: 520,
            child: WordLookupPopupCard(
              rawWord: rawWord,
              contextSentence: contextSentence,
              maxHeight: 520,
              onClose: () => Navigator.of(dialogContext).pop(),
              onCollect: () {
                Navigator.of(dialogContext).pop();
                widget.onCollectWord(rawWord);
              },
              onFavorite: widget.onFavoriteWord == null
                  ? null
                  : () => widget.onFavoriteWord!(rawWord),
              onPronounce: widget.onPronounce,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openActions(
    BuildContext context,
    PlayerSubtitleLine line,
    int index,
  ) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('收藏到短语库'),
                  onTap: () => Navigator.of(context).pop('bookmark'),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: const Text('复制英文'),
                  onTap: () => Navigator.of(context).pop('copy-en'),
                ),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: const Text('复制中英双语'),
                  onTap: () => Navigator.of(context).pop('copy-bi'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI 解释这句话'),
                  onTap: () => Navigator.of(context).pop('ai-explain'),
                ),
                if (widget.onRegenerateAiLine != null)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('AI 重新生成当前句'),
                    subtitle: const Text('只替换这一句，失败时保留原句'),
                    trailing: _regeneratingAiLineIndex == index
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    enabled: _regeneratingAiLineIndex == null,
                    onTap: _regeneratingAiLineIndex == null
                        ? () => Navigator.of(context).pop('regenerate-ai-line')
                        : null,
                  ),
                ListTile(
                  leading: const Icon(Icons.repeat_one_rounded),
                  title: const Text('从这里开始循环'),
                  onTap: () => Navigator.of(context).pop('loop'),
                ),
                ListTile(
                  leading: const Icon(Icons.record_voice_over_rounded),
                  title: const Text('逐句练习'),
                  onTap: () => Navigator.of(context).pop('dictation'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null) {
      return;
    }

    switch (action) {
      case 'bookmark':
        widget.onBookmarkLine(index);
        return;
      case 'copy-en':
        await Clipboard.setData(ClipboardData(text: line.english));
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制英文');
        return;
      case 'copy-bi':
        await Clipboard.setData(
          ClipboardData(text: '${line.english}\n${line.chinese}'),
        );
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制中英双语');
        return;
      case 'loop':
        widget.onLoopFromLine(index);
        return;
      case 'dictation':
        widget.onDictationLine(index);
        return;
      case 'ai-explain':
        widget.onAiExplain(index);
        return;
      case 'regenerate-ai-line':
        final Future<void> Function(int index)? regenerate =
            widget.onRegenerateAiLine;
        if (regenerate == null || _regeneratingAiLineIndex != null) return;
        setState(() {
          _regeneratingAiLineIndex = index;
        });
        try {
          await regenerate(index);
        } finally {
          if (mounted) {
            setState(() {
              _regeneratingAiLineIndex = null;
            });
          }
        }
        return;
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: active
              ? const Color(0xFFDFF8C8)
              : AppDesignTokens.softWhite,
          foregroundColor: active
              ? AppDesignTokens.brandGreenDark
              : AppDesignTokens.textSecondary,
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

class _AiSubtitlePlaceholder extends StatelessWidget {
  const _AiSubtitlePlaceholder({
    required this.generating,
    required this.progressValue,
    required this.progressText,
    required this.previewText,
    required this.errorText,
    required this.onGenerate,
  });

  final bool generating;
  final double? progressValue;
  final String? progressText;
  final String? previewText;
  final String? errorText;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.auto_awesome_rounded,
              size: 34,
              color: Color(0xFF9AA69E),
            ),
            const SizedBox(height: 12),
            const Text(
              '当前视频没有字幕',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF53625A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '可生成可随播放逐词高亮的 AI 词级同步字幕。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF7E8A82),
              ),
            ),
            const SizedBox(height: 14),
            if (!generating && (errorText?.isNotEmpty ?? false)) ...<Widget>[
              SizedBox(
                width: 320,
                child: Text(
                  '生成失败：$errorText',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFFC62828),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (generating) ...<Widget>[
              SizedBox(
                width: 240,
                child: LinearProgressIndicator(value: progressValue),
              ),
              const SizedBox(height: 10),
              Text(
                progressText ?? '正在准备音频...',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF53625A),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 300,
                height: 44,
                child: Text(
                  previewText?.isNotEmpty ?? false ? previewText! : '等待识别文本...',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF53625A),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: generating ? null : onGenerate,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(
                generating ? '正在生成词级同步字幕...' : 'AI生成可跟读的词级同步字幕',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
