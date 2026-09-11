import 'dart:io';

import '../domain/local_model.dart';
import 'local_model_store.dart';

/// 把「当前选择且已下载」的本地模型解析成服务需要的路径。
///
/// 三个本地服务（whisper-server / nllb-server / pronunciation-server）在启动时
/// 先问这里要路径，拿不到再回退到随程序打包的旧位置，保证老用户仍可用。
class LocalModelResolver {
  LocalModelResolver._();

  /// 已下载的语音识别模型文件路径（ggml-*.bin）。
  static String? whisperModelPath() {
    final _ResolvedModel? resolved = _resolve(LocalModelKind.whisper);
    if (resolved == null || resolved.model.files.isEmpty) {
      return null;
    }
    return localModelFilePath(resolved.directory, resolved.model.files.first);
  }

  /// 已下载的翻译模型目录（包含 model.bin / sentencepiece.bpe.model 等）。
  static String? translationModelDir() => _resolve(LocalModelKind.translation)?.directory.path;

  /// 已下载的翻译模型 tokenizer 路径。
  static String? translationTokenizerPath() {
    final _ResolvedModel? resolved = _resolve(LocalModelKind.translation);
    if (resolved == null) {
      return null;
    }
    for (final LocalModelFile file in resolved.model.files) {
      if (file.fileName == 'sentencepiece.bpe.model') {
        return localModelFilePath(resolved.directory, file);
      }
    }
    return null;
  }

  /// 已下载的发音评测模型目录（内部为 `hub/checkpoints/<文件>` 布局）。
  static String? pronunciationModelDir() =>
      _resolve(LocalModelKind.pronunciation)?.directory.path;

  static _ResolvedModel? _resolve(LocalModelKind kind) {
    final LocalModelInfo? model = LocalModelStore.selectedModel(kind);
    if (model == null) {
      return null;
    }
    final Directory? dir = LocalModelStore.modelDirectory(model);
    if (dir == null) {
      return null;
    }
    return _ResolvedModel(model: model, directory: dir);
  }
}

class _ResolvedModel {
  const _ResolvedModel({required this.model, required this.directory});

  final LocalModelInfo model;
  final Directory directory;
}
