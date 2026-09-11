import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/local_model_downloader.dart';
import '../data/local_model_store.dart';
import '../domain/local_model.dart';

/// 本地模型管理：模型不再随安装包分发，按需从这里下载到程序数据目录。
class LocalModelsScreen extends ConsumerStatefulWidget {
  const LocalModelsScreen({this.onSelectionChanged, super.key});

  /// 切换/下载完成后的回调（用于让调用方刷新状态）。
  final VoidCallback? onSelectionChanged;

  @override
  ConsumerState<LocalModelsScreen> createState() => _LocalModelsScreenState();
}

class _LocalModelsScreenState extends ConsumerState<LocalModelsScreen> {
  @override
  Widget build(BuildContext context) {
    final Map<String, LocalModelDownloadState> downloads = ref.watch(
      localModelDownloadsProvider,
    );
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.appWhite,
        foregroundColor: AppDesignTokens.textPrimary,
        elevation: 0,
        title: const Text(
          '本地模型',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const _HintCard(),
          const SizedBox(height: 16),
          for (final LocalModelKind kind in LocalModelKind.values) ...<Widget>[
            _KindHeader(kind: kind),
            const SizedBox(height: 8),
            for (final LocalModelInfo model in localModelsOfKind(kind))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModelCard(
                  model: model,
                  downloadState: downloads[model.id],
                  onDownload: () => _handleDownload(model),
                  onDelete: () => _handleDelete(model),
                  onUse: () => _handleUse(model),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _handleDownload(LocalModelInfo model) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool ok = await ref
        .read(localModelDownloadsProvider.notifier)
        .download(model);
    if (!mounted) {
      return;
    }
    if (ok) {
      // 下载完成后如果还没有选择过模型，直接使用新下载的模型。
      if (LocalModelStore.selectedModel(model.kind) == null) {
        await LocalModelStore.selectModel(model);
      }
      if (!mounted) {
        return;
      }
      widget.onSelectionChanged?.call();
      setState(() {});
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${model.name} 下载完成')));
    } else {
      setState(() {});
    }
  }

  Future<void> _handleDelete(LocalModelInfo model) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除本地模型'),
        content: Text('确定删除「${model.name}」吗？需要时可以重新下载。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await LocalModelStore.deleteModel(model);
    if (!mounted) {
      return;
    }
    ref.read(localModelDownloadsProvider.notifier).clear(model.id);
    widget.onSelectionChanged?.call();
    setState(() {});
  }

  Future<void> _handleUse(LocalModelInfo model) async {
    await LocalModelStore.selectModel(model);
    if (!mounted) {
      return;
    }
    widget.onSelectionChanged?.call();
    setState(() {});
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        '模型不再随安装包分发，首次使用时按需从 Hugging Face 镜像（hf-mirror.com）下载，保存在程序数据目录的 models 文件夹中，可随程序文件夹一起移动。\n带「推荐」标记的是默认建议使用的模型。',
        style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF33507A)),
      ),
    );
  }
}

class _KindHeader extends StatelessWidget {
  const _KindHeader({required this.kind});

  final LocalModelKind kind;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(_iconFor(kind), size: 18, color: AppDesignTokens.brandGreenDark),
        const SizedBox(width: 8),
        Text(
          localModelKindLabel(kind),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.textPrimary,
          ),
        ),
      ],
    );
  }

  IconData _iconFor(LocalModelKind kind) {
    switch (kind) {
      case LocalModelKind.whisper:
        return Icons.graphic_eq_rounded;
      case LocalModelKind.translation:
        return Icons.translate_rounded;
      case LocalModelKind.pronunciation:
        return Icons.record_voice_over_rounded;
    }
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.downloadState,
    required this.onDownload,
    required this.onDelete,
    required this.onUse,
  });

  final LocalModelInfo model;
  final LocalModelDownloadState? downloadState;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final bool installed = LocalModelStore.isInstalled(model);
    final bool inUse =
        installed && LocalModelStore.selectedModel(model.kind)?.id == model.id;
    final bool downloading =
        downloadState != null &&
        !downloadState!.completed &&
        downloadState!.error == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: inUse ? AppDesignTokens.brandGreen : const Color(0xFFE3E8E3),
          width: inUse ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      model.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    if (model.recommended) const _Badge(text: '推荐'),
                    if (inUse) const _Badge(text: '使用中', highlight: true),
                    if (installed && !inUse) const _Badge(text: '已下载'),
                  ],
                ),
              ),
              Text(
                model.sizeLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${model.description}\n下载源：${model.sourceNote}',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          if (downloading) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: downloadState!.progress),
            const SizedBox(height: 4),
            Text(
              downloadState!.statusLabel,
              style: const TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
          if (downloadState?.error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              downloadState!.statusLabel,
              style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (!installed)
                FilledButton.icon(
                  onPressed: downloading ? null : onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(downloading ? '下载中…' : '下载'),
                )
              else ...<Widget>[
                if (!inUse)
                  FilledButton.tonalIcon(
                    onPressed: onUse,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('使用此模型'),
                  ),
                if (!inUse) const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: downloading ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除'),
                ),
              ],
              if (downloadState?.error != null) ...<Widget>[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onDownload,
                  child: const Text('重试'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFDFF8C8) : const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: highlight
              ? AppDesignTokens.brandGreenDark
              : const Color(0xFF8A6D1B),
        ),
      ),
    );
  }
}
