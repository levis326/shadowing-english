import 'dart:io';
import 'dart:typed_data';

import 'package:common_learn_english/features/models/data/local_model_downloader.dart';
import 'package:common_learn_english/features/models/data/local_model_store.dart';
import 'package:common_learn_english/features/models/domain/local_model.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个小的测试模型（真实下载/校验逻辑用，避免下载 GB 级文件）。
LocalModelInfo _testModel({
  required String id,
  required String fileName,
  required List<int> bytes,
  required String url,
  String? wrongSha256,
}) {
  return LocalModelInfo(
    id: id,
    kind: LocalModelKind.whisper,
    name: '测试模型',
    description: '测试用',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: fileName,
        repoPath: '',
        absoluteUrl: url,
        sha256: wrongSha256 ?? sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
      ),
    ],
  );
}

void main() {
  // 纯 Dart 测试（不含 testWidgets），因此可以访问真实的本地 HTTP 服务器。
  HttpOverrides.global = null;

  group('local model downloader', () {
    late HttpServer server;
    late String baseUrl;
    late List<int> payload;

    setUp(() async {
      payload = List<int>.generate(60000, (int index) => index % 251);
      baseUrl = '';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((HttpRequest request) async {
        final List<int> body = payload;
        final String? range = request.headers.value(HttpHeaders.rangeHeader);
        if (range != null && range.startsWith('bytes=')) {
          final int start = int.parse(range.substring(6).split('-').first);
          final List<int> slice = body.sublist(start);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-${body.length - 1}/${body.length}',
            )
            ..headers.contentLength = slice.length
            ..add(slice);
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = body.length
          ..add(body);
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('downloads, verifies and stores the file', () async {
      final LocalModelInfo model = _testModel(
        id: 'downloader-ok',
        fileName: 'model.bin',
        bytes: payload,
        url: '$baseUrl/model.bin',
      );
      final Directory dir = LocalModelStore.modelDirectory(model)!;
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final List<double> progress = <double>[];
      await LocalModelDownloader(dio: Dio()).download(
        model,
        onProgress: (int received, int total) {
          if (total > 0) {
            progress.add(received / total);
          }
        },
      );

      final File saved = File(localModelFilePath(dir, model.files.single));
      expect(saved.existsSync(), isTrue);
      expect(saved.lengthSync(), payload.length);
      expect(saved.readAsBytesSync(), payload);
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      expect(LocalModelStore.isInstalled(model), isTrue);
    });

    test('resumes a partial download instead of restarting', () async {
      final LocalModelInfo model = _testModel(
        id: 'downloader-resume',
        fileName: 'model.bin',
        bytes: payload,
        url: '$baseUrl/model.bin',
      );
      final Directory dir = LocalModelStore.modelDirectory(model)!;
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final File part = File(
        '${localModelFilePath(dir, model.files.single)}.part',
      );
      part.parent.createSync(recursive: true);
      part.writeAsBytesSync(payload.sublist(0, 20000));

      await LocalModelDownloader(dio: Dio()).download(model);

      final File saved = File(localModelFilePath(dir, model.files.single));
      expect(saved.readAsBytesSync(), payload);
    });

    test('rejects a file whose checksum does not match', () async {
      final LocalModelInfo model = _testModel(
        id: 'downloader-bad-hash',
        fileName: 'model.bin',
        bytes: payload,
        url: '$baseUrl/model.bin',
        wrongSha256: '0' * 64,
      );
      final Directory dir = LocalModelStore.modelDirectory(model)!;
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      await expectLater(
        LocalModelDownloader(dio: Dio()).download(model),
        throwsA(isA<StateError>()),
      );
      expect(LocalModelStore.isInstalled(model), isFalse);
      // 校验失败后不留下半成品。
      expect(
        File('${localModelFilePath(dir, model.files.single)}.part').existsSync(),
        isFalse,
      );
    });

    test('download notifier reports progress and errors', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final LocalModelInfo model = _testModel(
        id: 'downloader-notifier',
        fileName: 'model.bin',
        bytes: payload,
        url: '$baseUrl/model.bin',
      );
      final Directory dir = LocalModelStore.modelDirectory(model)!;
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final bool ok = await container
          .read(localModelDownloadsProvider.notifier)
          .download(model);
      expect(ok, isTrue);
      final LocalModelDownloadState state =
          container.read(localModelDownloadsProvider)[model.id]!;
      expect(state.completed, isTrue);
      expect(state.error, isNull);
      expect(state.progress, 1.0);

      // 下载失败的模型会记录错误信息。
      final LocalModelInfo broken = _testModel(
        id: 'downloader-notifier-bad',
        fileName: 'model.bin',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        url: 'http://127.0.0.1:1/missing.bin',
      );
      final bool failed = await container
          .read(localModelDownloadsProvider.notifier)
          .download(broken);
      expect(failed, isFalse);
      expect(
        container.read(localModelDownloadsProvider)[broken.id]!.error,
        isNotNull,
      );
    });
  });

}
