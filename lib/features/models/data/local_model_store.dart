import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../../utils/app_paths.dart';
import '../domain/local_model.dart';

/// 已下载本地模型的存放位置与选择状态。
///
/// 模型统一保存在应用数据目录下的 `models/<类别>/<模型ID>/`，因此随程序
/// 文件夹一起移动（便携），不再打进安装包。
class LocalModelStore {
  LocalModelStore._();

  static const String selectionStorageKey = 'local_model_selection_v1';

  /// `<数据目录>/models`，数据目录未解析时返回 null。
  static Directory? modelsRootDirectory() {
    final String? dataRoot = AppPaths.dataDirectoryPathSync();
    if (dataRoot == null || dataRoot.isEmpty) {
      return null;
    }
    return Directory('$dataRoot${Platform.pathSeparator}models');
  }

  static String kindFolderName(LocalModelKind kind) {
    switch (kind) {
      case LocalModelKind.whisper:
        return 'whisper';
      case LocalModelKind.translation:
        return 'translation';
      case LocalModelKind.pronunciation:
        return 'pronunciation';
    }
  }

  /// 某个模型的目标目录。
  static Directory? modelDirectory(LocalModelInfo model) {
    final Directory? root = modelsRootDirectory();
    if (root == null) {
      return null;
    }
    return Directory(
      '${root.path}${Platform.pathSeparator}'
      '${kindFolderName(model.kind)}${Platform.pathSeparator}${model.id}',
    );
  }

  /// 该模型是否已完整下载（文件存在且大小一致）。
  static bool isInstalled(LocalModelInfo model) {
    final Directory? dir = modelDirectory(model);
    if (dir == null) {
      return false;
    }
    for (final LocalModelFile file in model.files) {
      final File target = File(localModelFilePath(dir, file));
      if (!target.existsSync() || target.lengthSync() != file.sizeBytes) {
        return false;
      }
    }
    return true;
  }

  static List<LocalModelInfo> installedModels(LocalModelKind kind) {
    return localModelsOfKind(
      kind,
    ).where(isInstalled).toList(growable: false);
  }

  /// 当前使用的模型：优先用户选择，其次推荐模型，最后任意已安装模型。
  static LocalModelInfo? selectedModel(LocalModelKind kind) {
    final Map<String, String> selection = _readSelection();
    final String? storedId = selection[kind.name];
    if (storedId != null) {
      final LocalModelInfo? stored = localModelById(storedId);
      if (stored != null && stored.kind == kind && isInstalled(stored)) {
        return stored;
      }
    }
    final List<LocalModelInfo> available = installedModels(kind);
    for (final LocalModelInfo model in available) {
      if (model.recommended) {
        return model;
      }
    }
    return available.isEmpty ? null : available.first;
  }

  /// 记录用户手动选择的模型。
  static Future<void> selectModel(LocalModelInfo model) async {
    final Map<String, String> selection = _readSelection();
    selection[model.kind.name] = model.id;
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    await Hive.box<String>(
      'prefs',
    ).put(selectionStorageKey, jsonEncode(selection));
  }

  /// 删除已下载的模型文件（用户选择会自动回退到其它已安装模型）。
  static Future<void> deleteModel(LocalModelInfo model) async {
    final Directory? dir = modelDirectory(model);
    if (dir == null || !dir.existsSync()) {
      return;
    }
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // 文件被占用时忽略，界面会继续显示为已下载。
    }
  }

  static Map<String, String> _readSelection() {
    if (!Hive.isBoxOpen('prefs')) {
      return <String, String>{};
    }
    final String? raw = Hive.box<String>('prefs').get(selectionStorageKey);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) =>
              MapEntry<String, String>(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      // 存档损坏时按未选择处理。
    }
    return <String, String>{};
  }
}
