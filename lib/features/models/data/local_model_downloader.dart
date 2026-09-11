import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/local_model.dart';
import 'local_model_store.dart';

/// 单个模型的下载状态。
class LocalModelDownloadState {
  const LocalModelDownloadState({
    required this.modelId,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.completed = false,
  });

  final String modelId;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final bool completed;

  double? get progress {
    if (totalBytes <= 0) {
      return null;
    }
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get statusLabel {
    if (completed) {
      return '已下载';
    }
    if (error != null) {
      return '下载失败：$error';
    }
    if (totalBytes <= 0) {
      return '正在连接…';
    }
    return '已下载 ${formatModelSize(receivedBytes)} / ${formatModelSize(totalBytes)}';
  }
}

/// 供测试替换的 Dio 实例。
final Provider<Dio> localModelDioProvider = Provider<Dio>((Ref ref) => Dio());

/// 负责把模型文件下载到数据目录（断点续传 + 校验和 + 镜像回退）。
class LocalModelDownloader {
  LocalModelDownloader({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// 下载一个模型的所有文件；[onProgress] 汇报累计进度（含已完成的文件）。
  Future<void> download(
    LocalModelInfo model, {
    void Function(int received, int total)? onProgress,
  }) async {
    final Directory? dir = LocalModelStore.modelDirectory(model);
    if (dir == null) {
      throw StateError('应用数据目录不可用，无法保存模型。');
    }
    await dir.create(recursive: true);
    final int totalBytes = model.totalBytes;
    int completedBytes = 0;
    for (final LocalModelFile file in model.files) {
      final File target = File(localModelFilePath(dir, file));
      await target.parent.create(recursive: true);
      final File part = File('${target.path}.part');
      await _downloadFile(
        file,
        part,
        onProgress: (int received, int _) =>
            onProgress?.call(completedBytes + received, totalBytes),
      );
      final String digest = await _sha256Of(part);
      if (digest.toLowerCase() != file.sha256.toLowerCase()) {
        try {
          await part.delete();
        } catch (_) {}
        throw StateError('${file.fileName} 校验失败，请重试。');
      }
      if (target.existsSync()) {
        try {
          await target.delete();
        } catch (_) {}
      }
      await part.rename(target.path);
      completedBytes += file.sizeBytes;
      onProgress?.call(completedBytes, totalBytes);
    }
  }

  Future<void> _downloadFile(
    LocalModelFile file,
    File part, {
    required void Function(int received, int total) onProgress,
  }) async {
    Object? lastError;
    for (final String url in <String>[file.mirrorUrl, file.fallbackUrl]) {
      for (int attempt = 1; attempt <= 3; attempt += 1) {
        try {
          await _downloadOnce(Uri.parse(url), part, onProgress);
          return;
        } catch (error) {
          lastError = error;
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    throw StateError('下载失败：${lastError ?? '未知错误'}');
  }

  Future<void> _downloadOnce(
    Uri url,
    File part,
    void Function(int received, int total) onProgress,
  ) async {
    int downloaded = part.existsSync() ? part.lengthSync() : 0;
    final Response<ResponseBody> response = await _dio.getUri<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: downloaded > 0
            ? <String, String>{'Range': 'bytes=$downloaded-'}
            : null,
        validateStatus: (int? status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final bool resuming = downloaded > 0 && response.statusCode == 206;
    if (!resuming) {
      downloaded = 0;
    }
    final int contentLength =
        int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;
    final int total = contentLength > 0 ? downloaded + contentLength : 0;
    onProgress(downloaded, total);
    final IOSink sink = part.openWrite(
      mode: resuming ? FileMode.append : FileMode.write,
    );
    try {
      await for (final List<int> chunk in response.data!.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress(downloaded, total);
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && downloaded < total) {
      throw StateError('下载中断（$downloaded/$total 字节）');
    }
  }

  Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}

/// 模型下载进度状态（按模型 id 索引）。
class LocalModelDownloadsNotifier
    extends Notifier<Map<String, LocalModelDownloadState>> {
  @override
  Map<String, LocalModelDownloadState> build() =>
      const <String, LocalModelDownloadState>{};

  Future<bool> download(LocalModelInfo model) async {
    final LocalModelDownloadState? current = state[model.id];
    if (current != null && current.completed && current.error == null) {
      return true;
    }
    _set(
      LocalModelDownloadState(modelId: model.id, totalBytes: model.totalBytes),
    );
    try {
      final LocalModelDownloader downloader = LocalModelDownloader(
        dio: ref.read(localModelDioProvider),
      );
      await downloader.download(
        model,
        onProgress: (int received, int total) => _set(
          LocalModelDownloadState(
            modelId: model.id,
            receivedBytes: received,
            totalBytes: total,
          ),
        ),
      );
      _set(
        LocalModelDownloadState(
          modelId: model.id,
          receivedBytes: model.totalBytes,
          totalBytes: model.totalBytes,
          completed: true,
        ),
      );
      return true;
    } catch (error) {
      _set(
        LocalModelDownloadState(
          modelId: model.id,
          totalBytes: model.totalBytes,
          error: _errorMessage(error),
        ),
      );
      return false;
    }
  }

  /// 清除某个模型的下载状态（取消展示错误/进度）。
  void clear(String modelId) {
    final Map<String, LocalModelDownloadState> next =
        Map<String, LocalModelDownloadState>.from(state)..remove(modelId);
    state = next;
  }

  void _set(LocalModelDownloadState value) {
    state = <String, LocalModelDownloadState>{
      ...state,
      value.modelId: value,
    };
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final int? status = error.response?.statusCode;
      if (status != null) {
        return '网络错误（HTTP $status）';
      }
      return '网络错误，请检查网络后重试。';
    }
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }
}

final NotifierProvider<
  LocalModelDownloadsNotifier,
  Map<String, LocalModelDownloadState>
>
localModelDownloadsProvider =
    NotifierProvider<
      LocalModelDownloadsNotifier,
      Map<String, LocalModelDownloadState>
    >(LocalModelDownloadsNotifier.new);
