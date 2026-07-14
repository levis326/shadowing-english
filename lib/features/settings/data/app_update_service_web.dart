class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.checksumUrl,
  });

  final String version;
  final String assetName;
  final String downloadUrl;
  final String checksumUrl;
}

class AppUpdateService {
  Future<AppUpdate?> checkForUpdate() {
    throw UnsupportedError('Web 版不支持从 GitHub Release 更新。');
  }

  Future<String> download(AppUpdate update) {
    throw UnsupportedError('Web 版不支持从 GitHub Release 更新。');
  }
}
