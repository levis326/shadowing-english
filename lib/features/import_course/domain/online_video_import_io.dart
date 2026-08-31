import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../utils/app_paths.dart';
import 'import_match.dart';

typedef OnlineVideoDownloadProgress =
    void Function(OnlineVideoImportProgress progress);

class OnlineVideoImportProgress {
  const OnlineVideoImportProgress({required this.label, this.value});

  final String label;
  final double? value;
}

class OnlineVideoImportResult {
  const OnlineVideoImportResult({
    required this.title,
    required this.videoPath,
    this.subtitleTracks = const <ImportSubtitleTrack>[],
  });

  final String title;
  final String videoPath;
  final List<ImportSubtitleTrack> subtitleTracks;
}

class OnlineVideoImporter {
  const OnlineVideoImporter({this.dio});

  final Dio? dio;
  Dio get _dio => dio ?? Dio();

  Future<OnlineVideoImportResult> downloadDirect(
    String url, {
    OnlineVideoDownloadProgress? onProgress,
  }) async {
    final Uri source = Uri.parse(url.trim());
    if (!source.hasScheme || !source.scheme.startsWith('http')) {
      throw ArgumentError('请输入有效的 http(s) 视频链接。');
    }
    final bool isHls = source.path.toLowerCase().contains('.m3u8');
    final String title = _safeName(
      source.pathSegments.isEmpty
          ? '在线视频'
          : source.pathSegments.last.split('.').first,
    );
    final Directory directory = await _newDirectory(title, url);
    final File output = File(
      '${directory.path}${Platform.pathSeparator}video.${isHls ? 'ts' : 'mp4'}',
    );
    if (isHls) {
      await _downloadHls(source, output, onProgress: onProgress);
    } else {
      await _downloadHttp(source, output, onProgress: onProgress);
    }
    return OnlineVideoImportResult(title: title, videoPath: output.path);
  }

  Future<void> _downloadHls(
    Uri source,
    File output, {
    OnlineVideoDownloadProgress? onProgress,
  }) async {
    final String manifest =
        (await _dio.get<String>(source.toString())).data ?? '';
    final Uri mediaPlaylist = await _resolveMediaPlaylist(source, manifest);
    final String media = mediaPlaylist == source
        ? manifest
        : (await _dio.get<String>(mediaPlaylist.toString())).data ?? '';
    if (media.contains('#EXT-X-KEY')) {
      throw StateError('暂不支持加密 m3u8，请使用未加密媒体链接。');
    }
    final List<Uri> segments = media
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty && !line.startsWith('#'))
        .map(mediaPlaylist.resolve)
        .toList(growable: false);
    if (segments.isEmpty) throw StateError('m3u8 中没有可下载的视频片段。');
    if (output.existsSync()) return;
    final Directory segmentDirectory = Directory('${output.path}.segments');
    await segmentDirectory.create(recursive: true);
    try {
      for (int index = 0; index < segments.length; index++) {
        final Uri segment = segments[index];
        final File segmentFile = File(
          '${segmentDirectory.path}${Platform.pathSeparator}$index.part',
        );
        if (!segmentFile.existsSync()) {
          final Response<List<int>> response = await _dio.get<List<int>>(
            segment.toString(),
            options: Options(responseType: ResponseType.bytes),
          );
          await segmentFile.writeAsBytes(response.data ?? const <int>[]);
        }
        onProgress?.call(
          OnlineVideoImportProgress(
            label: '正在下载视频分片 ${index + 1} / ${segments.length}',
            value: (index + 1) / segments.length,
          ),
        );
      }
      final File staging = File('${output.path}.part');
      final IOSink sink = staging.openWrite();
      try {
        for (int index = 0; index < segments.length; index++) {
          await sink.addStream(
            File(
              '${segmentDirectory.path}${Platform.pathSeparator}$index.part',
            ).openRead(),
          );
        }
      } finally {
        await sink.close();
      }
      await staging.rename(output.path);
    } finally {
      if (output.existsSync() && segmentDirectory.existsSync()) {
        await segmentDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _downloadHttp(
    Uri source,
    File output, {
    int? expectedTotalBytes,
    OnlineVideoDownloadProgress? onProgress,
  }) async {
    if (output.existsSync()) return;
    final File staging = File('${output.path}.part');
    int downloadedBytes = staging.existsSync() ? staging.lengthSync() : 0;
    Response<ResponseBody> response = await _streamResponse(
      source,
      downloadedBytes,
    );
    if (downloadedBytes > 0 &&
        response.statusCode != HttpStatus.partialContent) {
      downloadedBytes = 0;
      await staging.writeAsBytes(const <int>[]);
      response = await _streamResponse(source, 0);
    }
    final int incomingBytes =
        int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;
    final int totalBytes =
        expectedTotalBytes ?? incomingBytes + downloadedBytes;
    final IOSink sink = staging.openWrite(
      mode: downloadedBytes > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final List<int> bytes in response.data!.stream) {
        downloadedBytes += bytes.length;
        sink.add(bytes);
        onProgress?.call(
          OnlineVideoImportProgress(
            label: totalBytes <= 0
                ? '正在下载视频 ${_formatBytes(downloadedBytes)}'
                : '正在下载视频 ${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}',
            value: totalBytes <= 0 ? null : downloadedBytes / totalBytes,
          ),
        );
      }
    } finally {
      await sink.close();
    }
    await staging.rename(output.path);
  }

  Future<Response<ResponseBody>> _streamResponse(Uri source, int start) {
    return _dio.getUri<ResponseBody>(
      source,
      options: Options(
        responseType: ResponseType.stream,
        headers: start == 0
            ? null
            : <String, String>{HttpHeaders.rangeHeader: 'bytes=$start-'},
      ),
    );
  }

  Future<Uri> _resolveMediaPlaylist(Uri source, String manifest) async {
    final List<String> lines = manifest.split(RegExp(r'\r?\n'));
    for (int index = 0; index < lines.length - 1; index++) {
      if (!lines[index].startsWith('#EXT-X-STREAM-INF')) continue;
      final String next = lines[index + 1].trim();
      if (next.isNotEmpty && !next.startsWith('#')) return source.resolve(next);
    }
    return source;
  }

  Future<Directory> _newDirectory(String name, String source) async {
    // Portable desktop builds store imported videos under `<exe目录>/data/
    // imported_sources`, so courses travel with the app folder.
    final Directory root = await AppPaths.dataDirectory();
    final String key = sha1
        .convert(utf8.encode(source))
        .toString()
        .substring(0, 12);
    final Directory directory = Directory(
      '${root.path}${Platform.pathSeparator}imported_sources${Platform.pathSeparator}${key}_$name',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _safeName(String value) {
    final String safe = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return safe.isEmpty ? '在线视频' : safe;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
