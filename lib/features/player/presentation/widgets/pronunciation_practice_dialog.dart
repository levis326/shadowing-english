import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../shared/data/local_pronunciation_service.dart';

/// A dialog that records the user reading the target sentence and shows a
/// per-word pronunciation score returned by the local Wav2Vec2 server.
class PronunciationPracticeDialog extends StatefulWidget {
  const PronunciationPracticeDialog({
    super.key,
    required this.sentence,
  });

  final String sentence;

  @override
  State<PronunciationPracticeDialog> createState() =>
      _PronunciationPracticeDialogState();
}

class _PronunciationPracticeDialogState
    extends State<PronunciationPracticeDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _evaluating = false;
  PronunciationResult? _result;
  String? _error;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

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
          _error = '没有麦克风权限，请在系统设置中允许录音后重试。';
        });
        return;
      }
      final Directory tempDir = await getTemporaryDirectory();
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
        _error = null;
      });
    }
  }

  Future<void> _evaluate(String wavPath) async {
    setState(() {
      _evaluating = true;
      _error = null;
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
        _error = '发音评测失败，请确认已安装最新版本后重试。';
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

  @override
  Widget build(BuildContext context) {
    final PronunciationResult? result = _result;
    return AlertDialog(
      title: const Text('跟读评测'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
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
              const SizedBox(height: 16),
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
                  icon: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
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
                      child: Text(
                        word.word,
                        style: TextStyle(
                          fontSize: 16,
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
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFD5483F)),
                ),
              ],
            ],
          ),
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
}
