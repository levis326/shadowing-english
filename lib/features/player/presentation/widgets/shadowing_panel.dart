import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../shared/data/local_pronunciation_service.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../../../words/data/offline_word_dictionary.dart';
import '../player_mock_state.dart';
import 'subtitle_word_highlight_style.dart';

/// 跟读面板：直接显示全部字幕内容（带序号），当前句展示逐词音标与
/// 「点击录音」跟读入口。点击录音后先播放本句，播完自动开始录音，
/// 再次点击停止并给出逐词发音评测。
class ShadowingPanel extends ConsumerStatefulWidget {
  const ShadowingPanel({
    required this.lines,
    required this.activeIndex,
    required this.subtitleMode,
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    this.subtitleWordHighlightStyle = '绿色填充',
    this.subtitleWordHighlightBorderWidth = 2.5,
    required this.onTapLine,
    required this.onCollectWord,
    this.onFavoriteWord,
    required this.onBookmarkLine,
    required this.onLoopFromLine,
    required this.onDictationLine,
    required this.onAiExplain,
    this.loopingLineIndex,
    required this.isPlaying,
    required this.onTogglePlaying,
    this.onPronounce,
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    required this.onArmRecording,
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
  final String subtitleMode;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final ValueChanged<int> onTapLine;
  final ValueChanged<String> onCollectWord;
  final ValueChanged<String>? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
  final ValueChanged<int> onLoopFromLine;
  final ValueChanged<int> onDictationLine;
  final ValueChanged<int> onAiExplain;
  final int? loopingLineIndex;
  final bool isPlaying;
  final VoidCallback onTogglePlaying;
  final VoidCallback? onPronounce;
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;
  final VoidCallback onArmRecording;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? aiSubtitleProgressValue;
  final String? aiSubtitleProgressText;
  final String? aiSubtitlePreviewText;
  final String? aiSubtitleErrorText;
  final VoidCallback? onGenerateAiSubtitles;

  @override
  ConsumerState<ShadowingPanel> createState() => ShadowingPanelState();
}

enum ShadowingRecordPhase { idle, armed, recording, evaluating, done }

class ShadowingPanelState extends ConsumerState<ShadowingPanel> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  bool _autoFollowCurrentLine = true;
  int? _regeneratingAiLineIndex;

  // 跟读录音状态。
  final AudioRecorder _recorder = AudioRecorder();
  ShadowingRecordPhase _phase = ShadowingRecordPhase.idle;
  PronunciationResult? _result;
  String? _recordError;

  // 当前句的逐词音标缓存。
  final Map<String, String?> _phoneticCache = <String, String?>{};
  List<String?> _ipaForActiveLine = const <String?>[];
  String? _ipaLookupSentenceKey;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      _autoFollowCurrentLine = false;
    });
    if (widget.isPlaying) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void didUpdateWidget(covariant ShadowingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      if (_phase == ShadowingRecordPhase.recording) {
        unawaited(_recorder.stop());
      }
      _phase = ShadowingRecordPhase.idle;
      _result = null;
      _recordError = null;
    }
    if (oldWidget.activeIndex != widget.activeIndex && widget.isPlaying) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- 由播放页在句子播完后回调，自动开始录音 ---

  Future<void> onSentencePlaybackFinished() async {
    if (!mounted || _phase != ShadowingRecordPhase.armed) {
      return;
    }
    await _startRecording();
  }

  // --- 录音流程 ---

  void _handleMainButton() {
    switch (_phase) {
      case ShadowingRecordPhase.idle:
        setState(() {
          _phase = ShadowingRecordPhase.armed;
          _result = null;
          _recordError = null;
        });
        widget.onArmRecording();
        return;
      case ShadowingRecordPhase.armed:
        setState(() {
          _phase = ShadowingRecordPhase.idle;
        });
        return;
      case ShadowingRecordPhase.recording:
        unawaited(_stopAndEvaluate());
        return;
      case ShadowingRecordPhase.evaluating:
        return;
      case ShadowingRecordPhase.done:
        setState(() {
          _phase = ShadowingRecordPhase.armed;
          _result = null;
          _recordError = null;
        });
        widget.onArmRecording();
        return;
    }
  }

  Future<void> _startRecording() async {
    if (!mounted) {
      return;
    }
    final bool ok = await _recorder.hasPermission();
    if (!ok) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = ShadowingRecordPhase.idle;
        _recordError = '没有麦克风权限，请在系统设置中允许录音后重试。';
      });
      return;
    }
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String path =
          '${tempDir.path}${Platform.pathSeparator}shadowing_reading.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = ShadowingRecordPhase.idle;
        _recordError = '无法启动录音，请重试。';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = ShadowingRecordPhase.recording;
      _recordError = null;
    });
  }

  Future<void> _stopAndEvaluate() async {
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    if (!mounted) {
      return;
    }
    if (path == null) {
      setState(() {
        _phase = ShadowingRecordPhase.idle;
        _recordError = '录音失败，请重试。';
      });
      return;
    }
    setState(() {
      _phase = ShadowingRecordPhase.evaluating;
      _recordError = null;
    });
    try {
      final Uint8List bytes = await File(path).readAsBytes();
      final PronunciationResult result = await localPronunciationService
          .evaluate(audioBytes: bytes, text: widget.lines[widget.activeIndex].english);
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = ShadowingRecordPhase.done;
        _result = result;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = ShadowingRecordPhase.idle;
        _recordError = '发音评测失败，请确认已安装最新版本后重试。';
      });
    }
  }

  // --- 音标 ---

  Future<void> _ensureIpaForActiveLine() async {
    final int index = widget.activeIndex;
    final PlayerSubtitleLine line = widget.lines[index];
    final String sentenceKey = '${line.startMs}-${line.endMs}-${line.english}';
    if (_ipaLookupSentenceKey == sentenceKey) {
      return;
    }
    _ipaLookupSentenceKey = sentenceKey;
    _ipaForActiveLine = const <String?>[];

    final List<String> words = line.english
        .split(' ')
        .where((String word) => word.trim().isNotEmpty)
        .toList(growable: false);
    final List<String?> phonetics = List<String?>.filled(words.length, null);

    final OfflineWordDictionary dictionary = ref.read(
      offlineWordDictionaryProvider,
    );
    for (int i = 0; i < words.length; i++) {
      final String rawWord = words[i].replaceAll(RegExp("[^A-Za-z'’]"), '');
      if (rawWord.isEmpty) {
        continue;
      }
      final String key = rawWord.toLowerCase();
      final String? cached = _phoneticCache[key];
      if (cached != null || _phoneticCache.containsKey(key)) {
        phonetics[i] = cached;
        continue;
      }
      try {
        final OfflineWordDefinition? definition = await dictionary.lookup(key);
        final String? converted = definition == null ||
                definition.phonetic.trim().isEmpty
            ? null
            : convertEcdictPhoneticToIpa(definition.phonetic);
        _phoneticCache[key] = converted;
        phonetics[i] = converted;
      } catch (_) {
        _phoneticCache[key] = null;
      }
      if (!mounted || widget.activeIndex != index) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (widget.activeIndex == index) {
        _ipaForActiveLine = phonetics;
      }
    });
  }

  // --- 列表滚动 ---

  GlobalKey _rowKeyFor(int index) {
    return _rowKeys[index] ??= GlobalKey(debugLabel: 'shadowing-line-$index');
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

  // --- 构建 ---

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

    if (widget.activeIndex >= 0 && widget.activeIndex < widget.lines.length) {
      unawaited(_ensureIpaForActiveLine());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: 10),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildHeader() {
    final bool hasAiActions =
        widget.onRegenerateAiSubtitles != null ||
        widget.onDeleteAiSubtitles != null;
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F5EA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.record_voice_over_rounded,
            color: Color(0xFF0F7A43),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '跟读',
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '点句子定位播放，点单词查看释义',
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
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
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
                          : const Color(0xFF7E8A82).withValues(
                              alpha: textOpacity,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildWordLine(line, index, active, textOpacity),
                      if (widget.subtitleMode == '双语' &&
                          line.chinese.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          line.chinese,
                          style: TextStyle(
                            fontSize: 15 * widget.fontScale,
                            color: active
                                ? const Color(0xFF708077)
                                : const Color(
                                    0xFFB7C2BA,
                                  ).withValues(alpha: textOpacity),
                            height: 1.45,
                          ),
                        ),
                      ],
                      if (active) ...<Widget>[
                        const SizedBox(height: 8),
                        _buildActiveExtras(line),
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
                    onPressed: () => unawaited(_openActions(context, line, index)),
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
      children: tokens.asMap().entries.map((MapEntry<int, String> entry) {
        final int tokenIndex = entry.key;
        final String token = entry.value;
        final bool highlighted =
            active &&
            widget.highlightWords &&
            line.words.isNotEmpty &&
            widget.currentWordIndex == tokenIndex;
        return InkWell(
          onTap: active ? () => _openWordLookup(token, line.english) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: SubtitleWordHighlightStyle.background(
                widget.subtitleWordHighlightStyle,
                highlighted: highlighted,
              ),
              border: Border.all(
                color: SubtitleWordHighlightStyle.borderColor(
                  widget.subtitleWordHighlightStyle,
                  highlighted: highlighted,
                ),
                width: SubtitleWordHighlightStyle.borderWidth(
                  widget.subtitleWordHighlightStyle,
                  highlighted: highlighted,
                  width: widget.subtitleWordHighlightBorderWidth,
                ),
              ),
            ),
            child: Text(
              token,
              style: TextStyle(
                fontSize: active
                    ? 20 * widget.fontScale
                    : (20 * widget.fontScale) - 2,
                fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
                color: active
                    ? AppDesignTokens.textPrimary
                    : AppDesignTokens.textPrimary.withValues(
                        alpha: textOpacity,
                      ),
                decoration: SubtitleWordHighlightStyle.textDecoration(
                  widget.subtitleWordHighlightStyle,
                  highlighted: highlighted,
                ),
                decorationColor: SubtitleWordHighlightStyle.textDecorationColor(
                  widget.subtitleWordHighlightStyle,
                  highlighted: highlighted,
                ),
                height: 1.35,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildActiveExtras(PlayerSubtitleLine line) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_ipaForActiveLine.isNotEmpty &&
            _ipaForActiveLine.any((String? value) => value != null))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _ipaForActiveLine
                  .map((String? value) => value == null ? '' : '/$value/')
                  .where((String value) => value.isNotEmpty)
                  .join(' '),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A6D1B),
                height: 1.4,
              ),
            ),
          ),
        _buildRecordArea(line),
      ],
    );
  }

  Widget _buildRecordArea(PlayerSubtitleLine line) {
    final ShadowingRecordPhase phase = _phase;
    final PronunciationResult? result = _result;

    switch (phase) {
      case ShadowingRecordPhase.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _handleMainButton,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F7A43),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.mic_rounded),
              label: const Text('点击录音'),
            ),
            const SizedBox(height: 6),
            const Text(
              '句子播放完毕后会自动开始录音',
              style: TextStyle(fontSize: 12, color: Color(0xFF7E8A82)),
            ),
            if (_recordError != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _recordError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFD5483F),
                ),
              ),
            ],
          ],
        );
      case ShadowingRecordPhase.armed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _handleMainButton,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1F6FEB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.radio_button_checked_rounded),
              label: const Text('已开启自动录音'),
            ),
            const SizedBox(height: 6),
            const Text(
              '句子播放完毕后会自动开始录音（点击取消）',
              style: TextStyle(fontSize: 12, color: Color(0xFF7E8A82)),
            ),
          ],
        );
      case ShadowingRecordPhase.recording:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _handleMainButton,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD5483F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('点击停止录音'),
            ),
          ],
        );
      case ShadowingRecordPhase.evaluating:
        return const Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              '正在检查你的录音…',
              style: TextStyle(fontSize: 13, color: Color(0xFF53625A)),
            ),
          ],
        );
      case ShadowingRecordPhase.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildResult(result, line),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _handleMainButton,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新录制你的发音'),
            ),
          ],
        );
    }
  }

  Widget _buildResult(PronunciationResult? result, PlayerSubtitleLine line) {
    if (result == null || result.words.isEmpty) {
      return const Text(
        '未检测到有效的发音，请重新录制。',
        style: TextStyle(fontSize: 13, color: Color(0xFFD5483F)),
      );
    }
    final int correct = result.words
        .where((PronunciationWordScore word) => word.score >= 0.7)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${result.words.length} 个词中 $correct 个正确',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: correct == result.words.length
                ? const Color(0xFF2E9E5B)
                : const Color(0xFFE0A106),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: result.words.map((PronunciationWordScore word) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _wordColor(word.score).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                word.word,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _wordColor(word.score),
                ),
              ),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 6),
        const Text(
          '绿色=标准 · 黄色=一般 · 红色=需改进',
          style: TextStyle(fontSize: 12, color: Color(0xFF7E8A82)),
        ),
      ],
    );
  }

  Color _wordColor(double score) {
    if (score >= 0.7) return const Color(0xFF2E9E5B);
    if (score >= 0.4) return const Color(0xFFE0A106);
    return const Color(0xFFD5483F);
  }

  // --- 单词查词 ---

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

  // --- 更多操作 ---

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

/// Converts the ECDICT phonetic notation bundled in the offline dictionary
/// into a closer IPA representation, e.g. `tә'dei` → `təˈdeɪ`.
String convertEcdictPhoneticToIpa(String phonetic) {
  return phonetic
      .replaceAll('ә', 'ə')
      .replaceAllMapped(
        RegExp('i(?!:)'),
        (Match match) => 'ɪ',
      )
      .replaceAll(':', 'ː')
      .replaceAll("'", 'ˈ');
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
