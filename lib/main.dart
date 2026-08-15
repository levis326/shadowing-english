// ignore_for_file: always_put_control_body_on_new_line

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stack_trace/stack_trace.dart' as stack_trace;
import 'package:window_manager/window_manager.dart';

import 'constants/strings.dart';
import 'features/import_course/domain/video_cover_extractor.dart';
import 'features/player/presentation/local_whisper_service.dart';
import 'features/player/presentation/player_backend.dart';
import 'features/player/presentation/transcript_reader_window.dart';
import 'flavors/app_flavor.dart';
import 'hive/hive.dart';
import 'my_app.dart';

/// Try using const constructors as much as possible!

Future<void> main(List<String> args) async {
  FlavorConfig.setFlavor(AppFlavor.prod);
  await bootstrap(args: args);
}

AppLifecycleListener? _appLifecycleListener;

/// Kills the long-lived local whisper-server process when the app exits, so
/// the bundled whisper directory is not left locked by an orphaned process.
void _registerLifecycleCleanup() {
  _appLifecycleListener ??= AppLifecycleListener(
    onDetach: () => unawaited(localWhisperService.shutdown()),
  );
}

Future<void> bootstrap({List<String> args = const <String>[]}) async {
  /// Initialize packages
  WidgetsFlutterBinding.ensureInitialized();
  _registerLifecycleCleanup();
  if (await maybeRunTranscriptReaderWindow()) {
    return;
  }
  await _configureDesktopWindow();
  await EasyLocalization.ensureInitialized();
  initializeVideoPlayerBackend();
  await initHive();
  await initializeVideoCoverExtractor();
  await setPreferredOrientations();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await FlutterDisplayMode.setHighRefreshRate();
  }

  if (kReleaseMode) {
    /// Disable debugPrint in release mode
    /// This will prevent any debugPrint statements from being executed
    /// and will not print anything to the console.
    /// You can also use a custom implementation if needed
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  runApp(
    ProviderScope(
      child: EasyLocalization(
        supportedLocales: const <Locale>[
          /// Add your supported locales here
          Locale('en'),
          Locale('tr'),
        ],
        path: Strings.localizationsPath,
        fallbackLocale: const Locale('en'),
        child: const MyApp(),
      ),
    ),
  );

  /// Add this line to get the error stack trace in release mode
  FlutterError.demangleStackTrace = (StackTrace stack) {
    if (stack is stack_trace.Trace) return stack.vmTrace;
    if (stack is stack_trace.Chain) return stack.toTrace().vmTrace;
    return stack;
  };
}

Future<void> _configureDesktopWindow() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.macOS &&
          defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.linux)) {
    return;
  }
  await windowManager.ensureInitialized();
  final WindowOptions options = defaultTargetPlatform == TargetPlatform.macOS
      ? const WindowOptions(
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: true,
        )
      : const WindowOptions();
  await windowManager.waitUntilReadyToShow(options);
}
