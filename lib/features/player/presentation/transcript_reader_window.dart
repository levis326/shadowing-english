import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:window_manager/window_manager.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/domain/word_lookup_entry.dart';
import 'full_transcript_reader.dart';
import 'transcript_reader_session.dart';

Future<bool> maybeRunTranscriptReaderWindow() async {
  if (!supportsTranscriptReaderWindow) return false;

  await windowManager.ensureInitialized();
  final WindowController controller =
      await WindowController.fromCurrentEngine();
  final Map<String, dynamic>? arguments = _decodeArguments(
    controller.arguments,
  );
  if (arguments?['type'] != transcriptReaderWindowType) return false;

  final TranscriptReaderSnapshot snapshot = TranscriptReaderSnapshot.fromJson(
    arguments!['snapshot'] as Map<dynamic, dynamic>,
  );
  final String parentWindowId = arguments['parentWindowId'] as String? ?? '';
  const WindowOptions options = WindowOptions(
    size: Size(940, 760),
    minimumSize: Size(620, 520),
    center: true,
    title: '逐词全文',
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(
    ProviderScope(
      overrides: <Override>[
        if (parentWindowId.isNotEmpty)
          wordLookupServiceProvider.overrideWith(
            (Ref ref) =>
                _TranscriptReaderProxyWordLookupService(parentWindowId),
          ),
      ],
      child: _TranscriptReaderWindowApp(
        controller: controller,
        parentWindowId: parentWindowId,
        initialSnapshot: snapshot,
      ),
    ),
  );
  return true;
}

class _TranscriptReaderProxyWordLookupService extends WordLookupService {
  const _TranscriptReaderProxyWordLookupService(this.parentWindowId);

  final String parentWindowId;

  @override
  Future<WordLookupEntry> lookupWord({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) {
    return _lookupWordInMainWindow(
      parentWindowId: parentWindowId,
      rawWord: rawWord,
      contextSentence: contextSentence ?? '',
    ).catchError(
      (_) => WordLookupEntry(
        word: rawWord,
        phonetic: '',
        type: '英文单词',
        definitionEn: 'The player is closed. Showing the saved meaning.',
        usageEn: '',
        exampleSentenceEn: '',
        definitionCn: '播放器已关闭，显示字幕内置词义。',
        sourceLabel: '未配置',
      ),
    );
  }

  @override
  Future<String?> translateSentence({
    required String sentence,
    required LearningSettingsState settings,
  }) async {
    try {
      return await WindowController.fromWindowId(
        parentWindowId,
      ).invokeMethod<String>('translateSentence', sentence);
    } catch (_) {
      return null;
    }
  }
}

Future<WordLookupEntry> _lookupWordInMainWindow({
  required String parentWindowId,
  required String rawWord,
  required String contextSentence,
}) async {
  final WindowController parent = WindowController.fromWindowId(parentWindowId);
  final Map<dynamic, dynamic>? result = await parent
      .invokeMethod<Map<dynamic, dynamic>>('lookupWord', <String, dynamic>{
        'rawWord': rawWord,
        'contextSentence': contextSentence,
      });
  if (result == null) {
    throw StateError('Main window returned no word details');
  }
  return WordLookupEntry.fromJson(result);
}

Map<String, dynamic>? _decodeArguments(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

class _TranscriptReaderWindowApp extends StatefulWidget {
  const _TranscriptReaderWindowApp({
    required this.controller,
    required this.parentWindowId,
    required this.initialSnapshot,
  });

  final WindowController controller;
  final String parentWindowId;
  final TranscriptReaderSnapshot initialSnapshot;

  @override
  State<_TranscriptReaderWindowApp> createState() =>
      _TranscriptReaderWindowAppState();
}

class _TranscriptReaderWindowAppState
    extends State<_TranscriptReaderWindowApp> {
  late TranscriptReaderSnapshot _snapshot;
  late final ValueNotifier<TranscriptReaderProgress> _progress;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _progress = ValueNotifier<TranscriptReaderProgress>(_snapshot.progress);
    widget.controller.setWindowMethodHandler(_handleWindowMethod);
  }

  @override
  void dispose() {
    widget.controller.setWindowMethodHandler(null);
    _progress.dispose();
    super.dispose();
  }

  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    switch (call.method) {
      case 'progress':
        _progress.value = TranscriptReaderProgress.fromJson(
          call.arguments as Map<dynamic, dynamic>,
        );
        return _progress.value.toJson();
      case 'replaceSnapshot':
        final TranscriptReaderSnapshot next = TranscriptReaderSnapshot.fromJson(
          call.arguments as Map<dynamic, dynamic>,
        );
        setState(() => _snapshot = next);
        _progress.value = next.progress;
        return null;
      case 'focus':
        await windowManager.show();
        await windowManager.focus();
        return null;
      default:
        throw MissingPluginException('Unknown reader method: ${call.method}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '逐词全文',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
        fontFamily: 'Nunito',
      ),
      home: FullTranscriptReaderScreen(
        snapshot: _snapshot,
        progressListenable: _progress,
        onPlayFullTranscript: widget.parentWindowId.isEmpty
            ? null
            : _playFullTranscript,
        onToggleLineLoop: widget.parentWindowId.isEmpty
            ? null
            : _toggleLineLoop,
        onClose: windowManager.close,
      ),
    );
  }

  Future<void> _playFullTranscript() async {
    await WindowController.fromWindowId(
      widget.parentWindowId,
    ).invokeMethod<void>('playFullTranscript');
  }

  Future<void> _toggleLineLoop(int lineIndex) async {
    final Map<dynamic, dynamic>? result = await WindowController.fromWindowId(
      widget.parentWindowId,
    ).invokeMethod<Map<dynamic, dynamic>>('toggleLineLoop', lineIndex);
    if (result != null) {
      _progress.value = TranscriptReaderProgress.fromJson(result);
    }
  }
}
