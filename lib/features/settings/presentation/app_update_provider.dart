import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_update_service.dart';

final FutureProvider<String> appVersionProvider = FutureProvider<String>((
  Ref ref,
) async {
  final PackageInfo packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version;
});

final NotifierProvider<AppUpdateNotifier, AppUpdateState> appUpdateProvider =
    NotifierProvider<AppUpdateNotifier, AppUpdateState>(AppUpdateNotifier.new);

class AppUpdateState {
  const AppUpdateState({
    this.update,
    this.isChecking = false,
    this.isDownloading = false,
    this.message,
  });

  final AppUpdate? update;
  final bool isChecking;
  final bool isDownloading;
  final String? message;
}

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() => const AppUpdateState();

  Future<void> check() async {
    state = const AppUpdateState(isChecking: true);
    try {
      final AppUpdate? update = await AppUpdateService().checkForUpdate();
      state = AppUpdateState(
        update: update,
        message: update == null ? '当前已是最新版本。' : '发现 v${update.version}，可以下载更新。',
      );
    } catch (error) {
      state = AppUpdateState(message: '更新检测失败：$error');
    }
  }

  Future<void> download() async {
    final AppUpdate? update = state.update;
    if (update == null) {
      return;
    }
    state = AppUpdateState(update: update, isDownloading: true);
    try {
      final String path = await AppUpdateService().download(update);
      state = AppUpdateState(update: update, message: '下载并校验完成：$path');
    } catch (error) {
      state = AppUpdateState(update: update, message: '更新下载失败：$error');
    }
  }
}
