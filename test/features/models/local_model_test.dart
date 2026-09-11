import 'dart:io';

import 'package:common_learn_english/features/models/data/local_model_resolver.dart';
import 'package:common_learn_english/features/models/data/local_model_store.dart';
import 'package:common_learn_english/features/models/domain/local_model.dart';
import 'package:common_learn_english/features/models/presentation/local_models_screen.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
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
  group('local model registry', () {
    test('every model is well formed and each kind has one recommendation', () {
      expect(localModels, isNotEmpty);
      final Set<String> ids = <String>{};
      for (final LocalModelInfo model in localModels) {
        expect(ids.add(model.id), isTrue, reason: 'duplicate id ${model.id}');
        expect(model.files, isNotEmpty);
        expect(model.name.trim(), isNotEmpty);
        expect(model.description.trim(), isNotEmpty);
        for (final LocalModelFile file in model.files) {
          expect(file.fileName.trim(), isNotEmpty);
          expect(file.sha256.length, 64, reason: '${model.id} sha256');
          expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(file.sha256), isTrue,
              reason: '${model.id} sha256 必须是小写十六进制');
          expect(file.sizeBytes, greaterThan(0));
          expect(file.mirrorUrl.startsWith('https://'), isTrue);
        }
      }
      for (final LocalModelKind kind in LocalModelKind.values) {
        final List<LocalModelInfo> models = localModelsOfKind(kind);
        expect(models, isNotEmpty, reason: 'category $kind');
        expect(
          models.where((LocalModelInfo model) => model.recommended),
          hasLength(1),
          reason: 'category $kind should mark exactly one recommendation',
        );
      }
    });

    test('hugging face models use the mirror first and the official site '
        'as fallback', () {
      final LocalModelInfo whisper = localModelById('whisper-small')!;
      final LocalModelFile file = whisper.files.single;
      expect(file.mirrorUrl, startsWith('$hfMirrorBaseUrl/ggerganov/'));
      expect(file.fallbackUrl, startsWith('$hfBaseUrl/ggerganov/'));
    });

    test('models that are not hosted on Hugging Face keep their CDN url', () {
      final LocalModelInfo pronunciation = localModelById(
        'pronunciation-large-960h',
      )!;
      expect(
        pronunciation.files.single.mirrorUrl,
        startsWith('https://download.pytorch.org/'),
      );
      expect(pronunciation.sourceNote, contains('PyTorch'));
    });

    test('size labels are human readable', () {
      expect(formatModelSize(487601967), '约 465 MB');
      expect(formatModelSize(1381827201), '约 1.3 GB');
      expect(formatModelSize(3095033483), '约 2.9 GB');
    });
  });

  group('local model store', () {
    test('installed detection and deletion work for a downloaded model', () async {
      final LocalModelInfo model = _testModel(
        id: 'store-test-model',
        fileName: 'ggml-test.bin',
        bytes: <int>[1, 2, 3, 4, 5],
        url: 'https://example.com/ggml-test.bin',
      );
      final Directory? dir = LocalModelStore.modelDirectory(model);
      expect(dir, isNotNull);
      addTearDown(() {
        if (dir!.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      expect(LocalModelStore.isInstalled(model), isFalse);

      final File target = File(
        localModelFilePath(dir!, model.files.single),
      );
      target.parent.createSync(recursive: true);
      // 大小不一致时视为未完成。
      target.writeAsBytesSync(<int>[1, 2, 3]);
      expect(LocalModelStore.isInstalled(model), isFalse);

      target.writeAsBytesSync(<int>[1, 2, 3, 4, 5]);
      expect(LocalModelStore.isInstalled(model), isTrue);

      await LocalModelStore.deleteModel(model);
      expect(LocalModelStore.isInstalled(model), isFalse);
    });

    test('resolver returns null when no model is downloaded', () {
      // 测试环境不会下载真实模型，因此解析结果为空（服务会回退到打包位置）。
      if (LocalModelStore.installedModels(LocalModelKind.whisper).isEmpty) {
        expect(LocalModelResolver.whisperModelPath(), isNull);
      }
      if (LocalModelStore.installedModels(LocalModelKind.translation).isEmpty) {
        expect(LocalModelResolver.translationModelDir(), isNull);
        expect(LocalModelResolver.translationTokenizerPath(), isNull);
      }
      if (LocalModelStore
          .installedModels(LocalModelKind.pronunciation)
          .isEmpty) {
        expect(LocalModelResolver.pronunciationModelDir(), isNull);
      }
    });
  });

  group('local models screen', () {
    testWidgets('lists every model and marks the recommended one', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LocalModelsScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('本地模型'), findsOneWidget);
      // 首屏显示语音识别分类与推荐模型。
      expect(
        find.text(localModelKindLabel(LocalModelKind.whisper)),
        findsOneWidget,
      );
      expect(find.text('Whisper small（多语言）'), findsOneWidget);
      expect(find.text('推荐'), findsWidgets);

      // 列表懒加载：滚动到后面两个分类，确认模型与推荐标记都在。
      for (final LocalModelKind kind in <LocalModelKind>[
        LocalModelKind.translation,
        LocalModelKind.pronunciation,
      ]) {
        final Finder header = find.text(localModelKindLabel(kind));
        await tester.scrollUntilVisible(
          header,
          320,
          scrollable: find.byType(Scrollable).first,
        );
        expect(header, findsOneWidget);
        final LocalModelInfo recommended = localModelsOfKind(
          kind,
        ).firstWhere((LocalModelInfo model) => model.recommended);
        expect(find.text(recommended.name), findsOneWidget);
        expect(find.text('推荐'), findsWidgets);
      }
      // 每个类别都恰好有一个推荐模型。
      final int recommendedCount = localModels
          .where((LocalModelInfo model) => model.recommended)
          .length;
      expect(recommendedCount, LocalModelKind.values.length);
    });
  });
}
