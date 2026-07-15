import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'full_transcript_reader.dart';

const String transcriptReaderWindowType = 'full-transcript-reader';

bool get supportsTranscriptReaderWindow =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

class TranscriptReaderSession {
  final ValueNotifier<TranscriptReaderProgress> progress =
      ValueNotifier<TranscriptReaderProgress>(
        const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
      );

  WindowController? _desktopWindow;
  bool _sendingProgress = false;
  TranscriptReaderProgress? _lastSentProgress;

  Future<void> open({
    required BuildContext context,
    required TranscriptReaderSnapshot snapshot,
  }) async {
    progress.value = snapshot.progress;
    if (!supportsTranscriptReaderWindow) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (BuildContext routeContext) => FullTranscriptReaderScreen(
            snapshot: snapshot,
            progressListenable: progress,
            onClose: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
      return;
    }

    final String arguments = jsonEncode(<String, dynamic>{
      'type': transcriptReaderWindowType,
      'snapshot': snapshot.toJson(),
    });
    final List<WindowController> windows = await WindowController.getAll();
    for (final WindowController window in windows) {
      if (!_isTranscriptReaderArguments(window.arguments)) continue;
      try {
        await window.invokeMethod<void>('replaceSnapshot', snapshot.toJson());
        await window.invokeMethod<void>('focus');
        await window.show();
        _desktopWindow = window;
        _scheduleProgressSend();
        return;
      } catch (_) {
        // The native window can disappear between discovery and invocation.
      }
    }

    final WindowController window = await WindowController.create(
      WindowConfiguration(arguments: arguments),
    );
    _desktopWindow = window;
    await window.show();
    _scheduleProgressSend();
  }

  void updateProgress({required int lineIndex, required int wordIndex}) {
    final TranscriptReaderProgress next = TranscriptReaderProgress(
      lineIndex: lineIndex,
      wordIndex: wordIndex,
    );
    if (progress.value.lineIndex == next.lineIndex &&
        progress.value.wordIndex == next.wordIndex) {
      return;
    }
    progress.value = next;
    _scheduleProgressSend();
  }

  void _scheduleProgressSend() {
    if (_sendingProgress || _desktopWindow == null) return;
    unawaited(_flushProgress());
  }

  Future<void> _flushProgress() async {
    final WindowController? window = _desktopWindow;
    if (window == null || _sendingProgress) return;
    _sendingProgress = true;
    try {
      while (_desktopWindow == window) {
        final TranscriptReaderProgress target = progress.value;
        if (_sameProgress(_lastSentProgress, target)) return;
        final bool sent = await sendTranscriptReaderProgressWithRetry(
          progress: target,
          send: (TranscriptReaderProgress value) async {
            final Map<dynamic, dynamic>? acknowledged = await window
                .invokeMethod<Map<dynamic, dynamic>>(
                  'progress',
                  value.toJson(),
                );
            if (acknowledged == null ||
                !_sameProgress(
                  TranscriptReaderProgress.fromJson(acknowledged),
                  value,
                )) {
              throw StateError('Transcript reader progress was not applied');
            }
          },
        );
        if (!sent) {
          final List<WindowController> windows =
              await WindowController.getAll();
          if (!windows.any(
            (WindowController item) => item.windowId == window.windowId,
          )) {
            _desktopWindow = null;
          }
          return;
        }
        _lastSentProgress = target;
        if (_sameProgress(progress.value, target)) return;
      }
    } finally {
      _sendingProgress = false;
    }
  }

  void dispose() {
    progress.dispose();
  }
}

@visibleForTesting
Future<bool> sendTranscriptReaderProgressWithRetry({
  required TranscriptReaderProgress progress,
  required Future<void> Function(TranscriptReaderProgress progress) send,
  int maxAttempts = 10,
  Duration retryDelay = const Duration(milliseconds: 100),
}) async {
  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      await send(progress);
      return true;
    } catch (_) {
      if (attempt == maxAttempts - 1) return false;
      await Future<void>.delayed(retryDelay);
    }
  }
  return false;
}

bool _sameProgress(
  TranscriptReaderProgress? left,
  TranscriptReaderProgress right,
) => left?.lineIndex == right.lineIndex && left?.wordIndex == right.wordIndex;

bool _isTranscriptReaderArguments(String arguments) {
  try {
    final Object? decoded = jsonDecode(arguments);
    return decoded is Map<String, dynamic> &&
        decoded['type'] == transcriptReaderWindowType;
  } catch (_) {
    return false;
  }
}
