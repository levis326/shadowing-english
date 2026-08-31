import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../../utils/app_paths.dart';
import '../../../shared/data/local_pronunciation_service.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../../../words/data/offline_word_dictionary.dart';
import '../player_mock_state.dart';
import 'subtitle_word_highlight_style.dart';

/// 跟读区：显示当前句的外语句子、逐词音标、整句中文翻译，以及
/// 「点击录音」内嵌跟读流程。点击录音后先播放本句，播完自动开始
/// 录音，再次点击停止并在当前界面给出逐词发音评测。
class ShadowingFocusPanel extends ConsumerStatefulWidget {
  const ShadowingFocusPanel({
    required this.line,
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    this.subtitleWordHighlightStyle = '绿色填充',
    this.subtitleWordHighlightBorderWidth = 2.5,
    required this.onCollectWord,
    this.onFavoriteWord,
    required this.onArmRecording,
    this.onPronounce,
    super.key,
  });

  final PlayerSubtitleLine line;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final ValueChanged<String> onCollectWord;
  final ValueChanged<String>? onFavoriteWord;
  final VoidCallback onArmRecording;
  final VoidCallback? onPronounce;

  @override
  ConsumerState<ShadowingFocusPanel> createState() =>
      ShadowingFocusPanelState();
}

enum ShadowingRecordPhase { idle, armed, recording, evaluating, done }

class ShadowingFocusPanelState extends ConsumerState<ShadowingFocusPanel> {
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
    unawaited(_ensureIpaForLine());
  }

  @override
  void didUpdateWidget(covariant ShadowingFocusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String oldKey = '${oldWidget.line.startMs}-${oldWidget.line.endMs}-${oldWidget.line.english}';
    final String newKey = '${widget.line.startMs}-${widget.line.endMs}-${widget.line.english}';
    if (oldKey != newKey) {
      if (_phase == ShadowingRecordPhase.recording) {
        unawaited(_recorder.stop());
      }
      _phase = ShadowingRecordPhase.idle;
      _result = null;
      _recordError = null;
      unawaited(_ensureIpaForLine());
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  /// 由播放页在句子播完后回调，自动开始录音。
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
      final Directory tempDir = await AppPaths.tempDirectory();
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
          .evaluate(audioBytes: bytes, text: widget.line.english);
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

  Future<void> _ensureIpaForLine() async {
    final String sentenceKey =
        '${widget.line.startMs}-${widget.line.endMs}-${widget.line.english}';
    if (_ipaLookupSentenceKey == sentenceKey) {
      return;
    }
    _ipaLookupSentenceKey = sentenceKey;
    _ipaForActiveLine = const <String?>[];
    if (widget.line.english.trim().isEmpty) {
      return;
    }

    final List<String> words = widget.line.english
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
      final String currentKey =
          '${widget.line.startMs}-${widget.line.endMs}-${widget.line.english}';
      if (!mounted || currentKey != sentenceKey) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _ipaForActiveLine = phonetics;
    });
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    final PlayerSubtitleLine line = widget.line;
    final bool hasLine = line.english.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        const SizedBox(height: 10),
        const Text(
          '跟读',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '听本句，再模仿朗读',
          style: TextStyle(
            color: AppDesignTokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: !hasLine
              ? const Center(
                  child: Text(
                    '暂无字幕内容',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9AA69E),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSentence(line),
                      if (_ipaForActiveLine.isNotEmpty &&
                          _ipaForActiveLine.any(
                            (String? value) => value != null,
                          )) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          _ipaForActiveLine
                              .map(
                                (String? value) =>
                                    value == null ? '' : '/$value/',
                              )
                              .where((String value) => value.isNotEmpty)
                              .join(' '),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8A6D1B),
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (line.chinese.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          line.chinese,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF53625A),
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _buildRecordArea(line),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSentence(PlayerSubtitleLine line) {
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
            widget.highlightWords &&
            line.words.isNotEmpty &&
            widget.currentWordIndex == tokenIndex;
        return InkWell(
          onTap: () => _openWordLookup(token, line.english),
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
                fontSize: 22 * widget.fontScale,
                fontWeight: highlighted ? FontWeight.w800 : FontWeight.w700,
                color: AppDesignTokens.textPrimary,
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
