import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../../../utils/app_paths.dart';
import '../../../shared/data/local_pronunciation_service.dart';

/// A dialog offering two sentence-practice modes for the selected line:
///  - 跟读评测: record the user reading the sentence and show per-word scores.
///  - 听写: replay the sentence and let the user type what they heard.
class SentencePracticeDialog extends StatefulWidget {
  const SentencePracticeDialog({
    super.key,
    required this.sentence,
    this.onReplay,
  });

  final String sentence;
  final VoidCallback? onReplay;

  @override
  State<SentencePracticeDialog> createState() => _SentencePracticeDialogState();
}

class _SentencePracticeDialogState extends State<SentencePracticeDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Pronunciation state.
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _evaluating = false;
  PronunciationResult? _result;
  String? _pronError;

  // Dictation state.
  final TextEditingController _dictationController = TextEditingController();
  List<bool>? _dictationMarks;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dictationController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // --- Pronunciation ---

  Future<void> _toggleRecording() async {
    if (_recording) {
      final String? path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
      });
      if (path != null) {
        await _evaluate(path);
      }
    } else {
      final bool ok = await _recorder.hasPermission();
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _pronError = '没有麦克风权限，请在系统设置中允许录音后重试。';
        });
        return;
      }
      final Directory tempDir = await AppPaths.tempDirectory();
      final String path =
          '${tempDir.path}${Platform.pathSeparator}pron_reading.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _result = null;
        _pronError = null;
      });
    }
  }

  Future<void> _evaluate(String wavPath) async {
    setState(() {
      _evaluating = true;
      _pronError = null;
    });
    try {
      final Uint8List bytes = await File(wavPath).readAsBytes();
      final PronunciationResult result = await localPronunciationService
          .evaluate(audioBytes: bytes, text: widget.sentence);
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pronError = '发音评测失败，请确认已安装最新版本后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _evaluating = false;
        });
      }
    }
  }

  Color _wordColor(double score) {
    if (score >= 0.7) return const Color(0xFF2E9E5B);
    if (score >= 0.4) return const Color(0xFFE0A106);
    return const Color(0xFFD5483F);
  }

  /// 词内按音节着色显示：每个音节单独用其得分配色，音节之间用“·”分隔；
  /// 旧版服务没有音节数据时退回整词配色。
  Widget _buildWordScoreText(PronunciationWordScore word, double fontSize) {
    final List<PronunciationSyllableScore> syllables = word.syllables;
    if (syllables.isEmpty) {
      return Text(
        word.word,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: _wordColor(word.score),
        ),
      );
    }
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (int index = 0; index < syllables.length; index++) ...<
            InlineSpan
          >[
            if (index > 0)
              TextSpan(
                text: '·',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: const Color(0x997E8A82),
                ),
              ),
            TextSpan(
              text: syllables[index].syllable,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: _wordColor(syllables[index].score),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Dictation ---

  List<String> _normalizedWords(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList(growable: false);
  }

  void _checkDictation() {
    final List<String> target = _normalizedWords(widget.sentence);
    final List<String> typed = _normalizedWords(_dictationController.text);
    setState(() {
      _dictationMarks = <bool>[
        for (int i = 0; i < target.length; i++)
          i < typed.length && typed[i] == target[i],
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('逐句练习'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.sentence,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              tabs: const <Tab>[
                Tab(text: '跟读评测'),
                Tab(text: '听写'),
              ],
            ),
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _buildPronunciationTab(),
                  _buildDictationTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildPronunciationTab() {
    final PronunciationResult? result = _result;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: _evaluating ? null : _toggleRecording,
              style: FilledButton.styleFrom(
                backgroundColor: _recording
                    ? const Color(0xFFD5483F)
                    : const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
              label: Text(
                _recording
                    ? '停止并评测'
                    : _evaluating
                    ? '评测中…'
                    : '开始跟读',
              ),
            ),
          ),
          if (_evaluating) ...<Widget>[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (result != null) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Text(
                  '总分',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5F6368),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(result.score * 100).round()}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _wordColor(result.score),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.words.map((PronunciationWordScore word) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _wordColor(word.score).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _buildWordScoreText(word, 16),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 6),
            const Text(
              '按音节着色：绿色=标准 · 黄色=一般 · 红色=需改进',
              style: TextStyle(fontSize: 12, color: Color(0xFF7E8A82)),
            ),
          ],
          if (_pronError != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_pronError!, style: const TextStyle(color: Color(0xFFD5483F))),
          ],
        ],
      ),
    );
  }

  Widget _buildDictationTab() {
    final List<bool>? marks = _dictationMarks;
    final List<String> targetWords = _normalizedWords(widget.sentence);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onReplay,
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text('重播本句'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dictationController,
            maxLines: 2,
            onChanged: (_) => setState(() => _dictationMarks = null),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入你听到的内容…',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _checkDictation,
            child: const Text('提交'),
          ),
          if (marks != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '正确 ${marks.where((bool ok) => ok).length}/${targetWords.length} 词',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: marks.contains(false)
                    ? const Color(0xFFE0A106)
                    : const Color(0xFF2E9E5B),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (int i = 0; i < targetWords.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: marks[i]
                          ? const Color(0x1F2E9E5B)
                          : const Color(0x1FD5483F),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      targetWords[i],
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: marks[i]
                            ? const Color(0xFF2E9E5B)
                            : const Color(0xFFD5483F),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
