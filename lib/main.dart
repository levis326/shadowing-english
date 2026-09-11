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
import 'features/shared/data/local_nllb_translation.dart';
import 'features/shared/data/local_pronunciation_service.dart';
import 'flavors/app_flavor.dart';
import 'hive/hive.dart';
import 'my_app.dart';
import 'utils/app_locale.dart';
import 'utils/portable_preferences.dart';

/// Try using const constructors as much as possible!

Future<void> main(List<String> args) async {
  FlavorConfig.setFlavor(AppFlavor.prod);
  await bootstrap(args: args);
}

AppLifecycleListener? _appLifecycleListener;

/// Kills the long-lived local whisper-server, nllb-server and
/// pronunciation-server processes when the app exits, so the bundled
/// directories are not left locked by orphans.
void _registerLifecycleCleanup() {
  _appLifecycleListener ??= AppLifecycleListener(
    onDetach: () {
      unawaited(localWhisperService.shutdown());
      unawaited(localNllbTranslationService.shutdown());
      unawaited(localPronunciationService.shutdown());
    },
  );
}

Future<void> bootstrap({List<String> args = const <String>[]}) async {
  /// Initialize packages
  WidgetsFlutterBinding.ensureInitialized();

  /// 必须在 easy_localization 初始化之前：它内部会读 shared_preferences，
  /// 而 Windows 上那会在 `%APPDATA%` 里创建文件/目录。
  installPortablePreferenceStore();
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
        supportedLocales: supportedAppLocales,

        /// 界面语言由 `<数据目录>/prefs.hive` 保存，不用 shared_preferences。
        saveLocale: false,
        startLocale: readSavedAppLocale(),
        path: Strings.localizationsPath,
        fallbackLocale: fallbackAppLocale,
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

  // Intercept the window close so the local whisper-server child process is
  // killed before the app exits; otherwise it keeps the install folder locked.
  await windowManager.setPreventClose(true);
  windowManager.addListener(_AppWindowListener());
}

class _AppWindowListener with WindowListener {
  @override
  void onWindowClose() {
    unawaited(_shutdownAndClose());
  }

  Future<void> _shutdownAndClose() async {
    try {
      await localWhisperService.shutdown();
      await localNllbTranslationService.shutdown();
      await localPronunciationService.shutdown();
    } finally {
      await windowManager.destroy();
    }
  }
}
