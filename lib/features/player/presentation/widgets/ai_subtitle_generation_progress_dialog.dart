import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../asr_subtitle_service.dart';

Future<void> showAiSubtitleGenerationProgressDialog({
  required BuildContext context,
  required ValueListenable<AsrSubtitleProgress> progress,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在生成 AI 词级字幕'),
        content: ValueListenableBuilder<AsrSubtitleProgress>(
          valueListenable: progress,
          builder:
              (
                BuildContext context,
                AsrSubtitleProgress value,
                Widget? child,
              ) => SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LinearProgressIndicator(
                      value: value.totalChunks == 0 ? null : value.value,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      value.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      value.previewText?.isNotEmpty ?? false
                          ? value.previewText!
                          : '等待识别文本...',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '生成期间无需重复点击，完成后会自动切换到 AI 字幕。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF5F6368)),
                    ),
                  ],
                ),
              ),
        ),
      ),
    ),
  );
}
