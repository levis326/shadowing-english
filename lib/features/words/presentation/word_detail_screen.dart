import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../player/presentation/player_course_lookup.dart';
import '../../player/presentation/player_media_source.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/domain/word_lookup_entry.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/offline_word_dictionary.dart';
import 'word_book_provider.dart';

class WordDetailDialog extends ConsumerStatefulWidget {
  const WordDetailDialog({required this.word, super.key});

  final String word;

  @override
  ConsumerState<WordDetailDialog> createState() => _WordDetailDialogState();
}

class _WordDetailDialogState extends ConsumerState<WordDetailDialog> {
  OfflineWordDefinition? _offlineDefinition;
  bool _loadingOfflineDefinition = true;
  bool _translatingWithApi = false;
  String? _speakingText;
  final Set<String> _translatingContextKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _loadOfflineDefinition();
  }

  Future<void> _loadOfflineDefinition() async {
    final OfflineWordDefinition? definition = await ref
        .read(offlineWordDictionaryProvider)
        .lookup(widget.word);
    if (mounted) {
      setState(() {
        _offlineDefinition = definition;
        _loadingOfflineDefinition = false;
      });
    }
  }

  Future<void> _translateWithApi(WordEntry entry) async {
    if (_translatingWithApi) return;
    setState(() => _translatingWithApi = true);
    final WordLookupEntry result = await ref
        .read(wordLookupServiceProvider)
        .lookupWord(
          rawWord: entry.word,
          contextSentence: entry.occurrences.first.sentence,
          settings: ref.read(learningSettingsProvider),
        );
    if (!mounted) return;
    if (result.sourceLabel == '未配置' || result.definitionCn.trim().isEmpty) {
      _showMessage(result.definitionCn);
    } else {
      ref
          .read(wordBookProvider.notifier)
          .setDefinition(entry.word, result.definitionCn);
    }
    setState(() => _translatingWithApi = false);
  }

  Future<void> _speak(String text) async {
    if (_speakingText != null) return;
    setState(() => _speakingText = text);
    try {
      await ref.read(wordPronunciationServiceProvider).speak(text);
    } on WordPronunciationException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage(const WordPronunciationException().message);
    } finally {
      if (mounted) setState(() => _speakingText = null);
    }
  }

  Future<void> _translateContext(
    WordEntry entry,
    WordOccurrence occurrence,
    WordContext contextItem,
  ) async {
    final String key = '${occurrence.episodeId}:${contextItem.lineKey}';
    if (_translatingContextKeys.contains(key)) return;
    setState(() => _translatingContextKeys.add(key));
    final String? translation = await ref
        .read(wordLookupServiceProvider)
        .translateSentence(
          sentence: contextItem.sentence,
          settings: ref.read(learningSettingsProvider),
        );
    if (!mounted) return;
    if (translation == null) {
      _showMessage('短语翻译失败，请检查翻译 API 设置后重试。');
    } else {
      ref
          .read(wordBookProvider.notifier)
          .setContextTranslation(
            rawWord: entry.word,
            episodeId: occurrence.episodeId,
            lineKey: contextItem.lineKey,
            translation: translation,
          );
    }
    setState(() => _translatingContextKeys.remove(key));
  }

  Future<void> _openVideo(
    WordOccurrence occurrence,
    WordContext contextItem,
  ) async {
    final PlayerCourseLookupResult result = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: occurrence.episodeId,
    );
    final String? video = result.videoAsset;
    if (!result.hasEpisode ||
        video == null ||
        video.isEmpty ||
        !playerMediaAvailable(video)) {
      if (mounted) _showMessage('该视频资源已不在设备中，请重新导入课程。');
      return;
    }
    if (mounted) {
      final GoRouter router = GoRouter.of(context);
      Navigator.of(context, rootNavigator: true).pop();
      unawaited(
        router.push(
          '/episodes/${occurrence.episodeId}?startTime=${Uri.encodeComponent(contextItem.time)}&autoplay=1',
        ),
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final WordEntry? entry = ref
        .watch(wordBookProvider)
        .where((WordEntry item) => item.word == widget.word)
        .firstOrNull;
    if (entry == null) {
      return const Dialog(
        child: Padding(padding: EdgeInsets.all(24), child: Text('该单词已不在单词本中。')),
      );
    }
    final OfflineWordDefinition? offline = _offlineDefinition;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '单词详情',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: <Widget>[
                  _WordHeader(
                    entry: entry,
                    definition: offline,
                    loading: _loadingOfflineDefinition,
                    speaking: _speakingText == entry.word,
                    onSpeak: () => _speak(entry.word),
                    onFavorite: () => ref
                        .read(wordBookProvider.notifier)
                        .toggleFavorite(entry.word),
                  ),
                  const SizedBox(height: 16),
                  _DefinitionCard(
                    offlineDefinition: offline,
                    offlineTranslation: entry.offlineDefinitionCn,
                    apiDefinition: entry.definitionCn,
                    translating: _translatingWithApi,
                    onTranslate: () => _translateWithApi(entry),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '影片语境 · ${entry.occurrenceCount} 次出现',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final WordOccurrence occurrence in entry.occurrences)
                    for (final WordContext contextItem in occurrence.contexts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _OccurrenceCard(
                          occurrence: occurrence,
                          contextItem: contextItem,
                          speaking: _speakingText == contextItem.sentence,
                          onSpeak: () => _speak(contextItem.sentence),
                          onOpenVideo: () =>
                              _openVideo(occurrence, contextItem),
                          translating: _translatingContextKeys.contains(
                            '${occurrence.episodeId}:${contextItem.lineKey}',
                          ),
                          onTranslate: () =>
                              _translateContext(entry, occurrence, contextItem),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordHeader extends StatelessWidget {
  const _WordHeader({
    required this.entry,
    required this.definition,
    required this.loading,
    required this.speaking,
    required this.onSpeak,
    required this.onFavorite,
  });

  final WordEntry entry;
  final OfflineWordDefinition? definition;
  final bool loading;
  final bool speaking;
  final VoidCallback onSpeak;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.word,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('正在加载离线词典…'),
                )
              else if (definition != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    <String>[
                      definition!.phonetic,
                      definition!.partOfSpeech,
                    ].where((String item) => item.isNotEmpty).join(' · '),
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: '播放单词发音',
          onPressed: speaking ? null : onSpeak,
          icon: Icon(
            speaking ? Icons.volume_up_rounded : Icons.volume_up_outlined,
          ),
        ),
        IconButton(
          tooltip: entry.favorite ? '取消收藏' : '收藏单词',
          onPressed: onFavorite,
          icon: Icon(
            entry.favorite
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
          ),
        ),
      ],
    ),
  );
}

class _DefinitionCard extends StatelessWidget {
  const _DefinitionCard({
    required this.offlineDefinition,
    required this.offlineTranslation,
    required this.apiDefinition,
    required this.translating,
    required this.onTranslate,
  });

  final OfflineWordDefinition? offlineDefinition;
  final String? offlineTranslation;
  final String? apiDefinition;
  final bool translating;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFF2FBEA),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('中文释义', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          offlineTranslation ??
              offlineDefinition?.translation ??
              '离线词典未收录，可查看影片语境或使用 API 补充。',
        ),
        const SizedBox(height: 14),
        if (apiDefinition != null && apiDefinition!.isNotEmpty) ...<Widget>[
          const Text('API 语境释义', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(apiDefinition!),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: translating ? null : onTranslate,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(translating ? '翻译中…' : '使用 API 获取语境释义'),
        ),
      ],
    ),
  );
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({
    required this.occurrence,
    required this.contextItem,
    required this.speaking,
    required this.onSpeak,
    required this.onOpenVideo,
    required this.translating,
    required this.onTranslate,
  });

  final WordOccurrence occurrence;
  final WordContext contextItem;
  final bool speaking;
  final VoidCallback onSpeak;
  final VoidCallback onOpenVideo;
  final bool translating;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${occurrence.course} · ${occurrence.episode} · ${contextItem.time}',
        ),
        const SizedBox(height: 8),
        Text(
          contextItem.sentence,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        if (contextItem.chinese.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            contextItem.chinese,
            style: const TextStyle(color: AppDesignTokens.textSecondary),
          ),
        ],
        if (contextItem.apiTranslationCn != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'API：${contextItem.apiTranslationCn}',
            style: const TextStyle(color: AppDesignTokens.primaryBlueDark),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Text(
              '此句出现 ${contextItem.count} 次',
              style: const TextStyle(fontSize: 12),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: speaking ? null : onSpeak,
              icon: const Icon(Icons.volume_up_outlined, size: 18),
              label: const Text('播放短语'),
            ),
            TextButton.icon(
              onPressed: translating ? null : onTranslate,
              icon: const Icon(Icons.translate_rounded, size: 18),
              label: Text(translating ? '翻译中…' : 'API 翻译'),
            ),
            TextButton.icon(
              onPressed: onOpenVideo,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text('跳到影片'),
            ),
          ],
        ),
      ],
    ),
  );
}
