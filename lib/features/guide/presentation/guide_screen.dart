import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/url_utils.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'widgets/how_to_learn_content.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static final Uri _methodVideo = Uri.parse(
    'https://www.douyin.com/video/7660464132604776038',
  );

  static Future<void> showLearningGuideDialog(BuildContext context) =>
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          '怎么学',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        tooltip: '关闭',
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                    children: <Widget>[
                      HowToLearnContent(
                        onStart: () {
                          Navigator.of(dialogContext).pop();
                          context.go(AppNavDestination.library.route);
                        },
                        onPlayMethod: () => _openUrl(context, _methodVideo),
                        onOpenResource: (GuideLearningResource resource) =>
                            _showResourceSheet(context, resource),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => PadScaffold(
    currentDestination: AppNavDestination.guide,
    topBar: const PadTopBar(
      title: '怎么学',
      subtitle: '三遍学习法',
      trailing: SizedBox.shrink(),
    ),
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        context.padPagePadding,
        12,
        context.padPagePadding,
        40,
      ),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: HowToLearnContent(
              onStart: () => context.go(AppNavDestination.library.route),
              onPlayMethod: () => _openUrl(context, _methodVideo),
              onOpenResource: (GuideLearningResource resource) =>
                  _showResourceSheet(context, resource),
            ),
          ),
        ),
      ],
    ),
  );

  static Future<void> _showResourceSheet(
    BuildContext context,
    GuideLearningResource resource,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              resource.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(resource.resourceHint),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _openUrl(
                context,
                Uri.https('www.google.com', '/search', <String, String>{
                  'q': '${resource.searchQuery} English full episodes',
                }),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('在 Google 搜索资源'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openUrl(BuildContext context, Uri url) async {
    try {
      await openUrl(url);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时打不开链接，请稍后再试。')));
      }
    }
  }
}
