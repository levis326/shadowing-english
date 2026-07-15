import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../library/presentation/library_mock_data.dart';

class PlayerEpisodeStrip extends StatefulWidget {
  const PlayerEpisodeStrip({
    required this.episodes,
    required this.activeEpisodeId,
    required this.onOpenEpisode,
    super.key,
  });

  final List<LibraryEpisodeItem> episodes;
  final String activeEpisodeId;
  final ValueChanged<LibraryEpisodeItem> onOpenEpisode;

  @override
  State<PlayerEpisodeStrip> createState() => _PlayerEpisodeStripState();
}

class _PlayerEpisodeStripState extends State<PlayerEpisodeStrip> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _activeEpisodeOffset(),
    );
  }

  @override
  void didUpdateWidget(covariant PlayerEpisodeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeEpisodeId != widget.activeEpisodeId) {
      _scrollController.jumpTo(_activeEpisodeOffset());
    }
  }

  double _activeEpisodeOffset() {
    final int index = widget.episodes.indexWhere(
      (LibraryEpisodeItem episode) => episode.id == widget.activeEpisodeId,
    );
    return index < 0 ? 0 : index * 242.0;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '课程目录',
              style: TextStyle(
                color: Color(0xFF172033),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _showEpisodePicker(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '查看全部',
                style: TextStyle(
                  color: Color(0xFF047857),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: <PointerDeviceKind>{
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: ListView.separated(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              scrollDirection: Axis.horizontal,
              itemBuilder: (BuildContext context, int index) {
                final LibraryEpisodeItem episode = widget.episodes[index];
                final bool isActive = episode.id == widget.activeEpisodeId;

                return GestureDetector(
                  onTap: () => widget.onOpenEpisode(episode),
                  child: _EpisodeCard(episode: episode, isActive: isActive),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemCount: widget.episodes.length,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showEpisodePicker(BuildContext context) async {
    final LibraryEpisodeItem? selected = await showDialog<LibraryEpisodeItem>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择剧集'),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.episodes.length,
              itemBuilder: (BuildContext context, int index) {
                final LibraryEpisodeItem episode = widget.episodes[index];
                final bool active = episode.id == widget.activeEpisodeId;
                return ListTile(
                  leading: Icon(
                    active
                        ? Icons.play_circle_filled_rounded
                        : Icons.play_circle_outline_rounded,
                    color: active
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                  ),
                  title: Text('第 ${episode.numberStr} 集'),
                  subtitle: Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: active ? const Text('当前') : null,
                  onTap: () => Navigator.of(context).pop(episode),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      widget.onOpenEpisode(selected);
    }
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.isActive,
    super.key,
  });

  final LibraryEpisodeItem episode;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final String statusText = isActive
        ? '继续学习'
        : episode.progressPercent == 100
        ? '已完成'
        : '准备开始';
    return SizedBox(
      width: 230,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFECFDF5) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? const Color(0xFF34D399) : const Color(0xFFE2E8F0),
            width: isActive ? 2 : 1,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x0F0F172A),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isActive
                      ? Icons.play_arrow_rounded
                      : Icons.menu_book_outlined,
                  color: isActive ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isActive
                            ? const Color(0xFF047857)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      episode.title,
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '第${episode.numberStr}集 · ${episode.totalTimeStr ?? '${episode.durationMinutes}:00'} · 完成度 ${episode.progressPercent}%',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
