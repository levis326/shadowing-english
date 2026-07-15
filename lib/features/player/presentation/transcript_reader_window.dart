import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

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
    _TranscriptReaderWindowApp(
      controller: controller,
      initialSnapshot: snapshot,
    ),
  );
  return true;
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
    required this.initialSnapshot,
  });

  final WindowController controller;
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
        onClose: windowManager.close,
      ),
    );
  }
}
