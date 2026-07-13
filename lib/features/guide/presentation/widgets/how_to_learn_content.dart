import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';

class GuideLearningResource {
  const GuideLearningResource({
    required this.title,
    required this.searchQuery,
    required this.resourceHint,
  });

  final String title;
  final String searchQuery;
  final String resourceHint;
}

class HowToLearnContent extends StatelessWidget {
  const HowToLearnContent({
    required this.onStart,
    required this.onPlayMethod,
    required this.onOpenResource,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onPlayMethod;
  final ValueChanged<GuideLearningResource> onOpenResource;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _LearningHero(onStart: onStart, onPlayMethod: onPlayMethod),
      const SizedBox(height: 40),
      _MethodVideoCard(onPlay: onPlayMethod),
      const SizedBox(height: 48),
      const _SectionTitle(
        title: '一集视频，只练这三件事',
        subtitle: '每一遍只完成一个目标，不需要同时兼顾所有内容。',
      ),
      const SizedBox(height: 20),
      const _ThreePassLearningFlow(),
      const SizedBox(height: 48),
      const _WhyItWorksSection(),
      const SizedBox(height: 48),
      const _LearningExampleSection(),
      const SizedBox(height: 40),
      const _PreparationChecklist(),
      const SizedBox(height: 48),
      _LevelRecommendationSection(onOpenResource: onOpenResource),
      const SizedBox(height: 48),
      _BottomLearningCta(onStart: onStart),
    ],
  );
}

class _LearningHero extends StatelessWidget {
  const _LearningHero({required this.onStart, required this.onPlayMethod});

  final VoidCallback onStart;
  final VoidCallback onPlayMethod;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: _cardDecoration(
      color: AppDesignTokens.appWhite,
      shadow: AppDesignTokens.toyCardShadow,
    ),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 720;
        final Widget copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '每天 20 分钟，用一部剧练会真实英语',
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontSize: 30,
                height: 1.18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '先看懂剧情，再听清表达，最后开口模仿。\n不要求一次全部听懂，只需要比昨天多听懂一点。',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _InfoPill(icon: Icons.schedule_rounded, label: '每次约 20 分钟'),
                _InfoPill(icon: Icons.replay_rounded, label: '同一集练 3 遍'),
                _InfoPill(icon: Icons.calendar_today_rounded, label: '7 天完成一轮'),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('guide-start-learning'),
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始第一次学习'),
              style: _primaryButtonStyle(),
            ),
            TextButton.icon(
              onPressed: onPlayMethod,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 19),
              label: const Text('查看 3 分钟方法视频'),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.primaryBlueDark,
              ),
            ),
          ],
        );
        if (!wide) return copy;
        return Row(
          children: <Widget>[
            Expanded(flex: 6, child: copy),
            const SizedBox(width: 32),
            const Expanded(flex: 4, child: _HeroProgressPreview()),
          ],
        );
      },
    ),
  );
}

class _HeroProgressPreview extends StatelessWidget {
  const _HeroProgressPreview();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppDesignTokens.skyLight,
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '今天的第一小步',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.primaryBlueDark,
          ),
        ),
        SizedBox(height: 14),
        Icon(
          Icons.movie_creation_outlined,
          size: 46,
          color: AppDesignTokens.primaryBlue,
        ),
        SizedBox(height: 14),
        Text(
          '先看懂一小段剧情',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 8),
        Text(
          '完成 5 分钟，就已经在进步。',
          style: TextStyle(color: AppDesignTokens.textSecondary),
        ),
      ],
    ),
  );
}

class _MethodVideoCard extends StatelessWidget {
  const _MethodVideoCard({required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: _cardDecoration(color: AppDesignTokens.appWhite),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 700;
        final Widget details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '3 分钟了解完整学习方法',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const Text(
              '看完你会知道：',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const _Bullet(text: '为什么同一集要看三遍'),
            const _Bullet(text: '每一遍分别做什么'),
            const _Bullet(text: '什么时候可以进入下一集'),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('guide-play-method'),
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放学习方法'),
              style: _primaryButtonStyle(),
            ),
            TextButton(onPressed: onPlay, child: const Text('在抖音中打开')),
          ],
        );
        const Widget preview = _VideoPreview();
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[preview, const SizedBox(height: 20), details],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: details),
            const SizedBox(width: 28),
            const SizedBox(width: 310, child: _VideoPreview()),
          ],
        );
      },
    ),
  );
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 10,
    child: Stack(
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  AppDesignTokens.primaryBlueDark,
                  AppDesignTokens.primaryBlue,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Center(
              child: Icon(
                Icons.movie_filter_rounded,
                size: 76,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const Positioned(top: 12, left: 12, child: _VideoTag(label: '新手必看')),
        const Positioned(
          right: 12,
          bottom: 12,
          child: _VideoTag(label: '03:20'),
        ),
        Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 38,
              color: AppDesignTokens.primaryBlueDark,
            ),
          ),
        ),
      ],
    ),
  );
}

class _VideoTag extends StatelessWidget {
  const _VideoTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _ThreePassLearningFlow extends StatelessWidget {
  const _ThreePassLearningFlow();

  static const List<_LearningStep> _steps = <_LearningStep>[
    _LearningStep(
      number: '1',
      icon: Icons.visibility_outlined,
      title: '第 1 遍：看懂剧情',
      body: '开启双语字幕完整看一遍。不暂停，不查词，先理解人物、情节和语气。',
      duration: '建议时长：8 分钟',
      subtitleMode: '字幕模式：双语字幕',
      goal: '完成标准：能说清这一段发生了什么',
    ),
    _LearningStep(
      number: '2',
      icon: Icons.hearing_outlined,
      title: '第 2 遍：听清表达',
      body: '切换英文字幕，逐句精听。听不清的句子可以重复播放，并收藏常用表达。',
      duration: '建议时长：8 分钟',
      subtitleMode: '字幕模式：英文字幕',
      goal: '完成标准：能听出大部分关键词',
    ),
    _LearningStep(
      number: '3',
      icon: Icons.record_voice_over_outlined,
      title: '第 3 遍：开口模仿',
      body: '关闭中文字幕，跟着人物的语气逐句朗读。每次模仿 3～5 个完整句子即可。',
      duration: '建议时长：5 分钟',
      subtitleMode: '字幕模式：英文字幕或无字幕',
      goal: '完成标准：能完整跟读重点句子',
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool wide = constraints.maxWidth >= 860;
      if (!wide) {
        return Column(
          children: <Widget>[
            for (int index = 0; index < _steps.length; index++) ...<Widget>[
              _LearningStepCard(step: _steps[index], current: index == 1),
              if (index < _steps.length - 1)
                const SizedBox(
                  height: 28,
                  child: Center(
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      color: AppDesignTokens.primaryBlue,
                    ),
                  ),
                ),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int index = 0; index < _steps.length; index++) ...<Widget>[
            Expanded(
              child: _LearningStepCard(
                step: _steps[index],
                current: index == 1,
              ),
            ),
            if (index < _steps.length - 1)
              const SizedBox(
                width: 28,
                child: Padding(
                  padding: EdgeInsets.only(top: 36),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: AppDesignTokens.primaryBlue,
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _LearningStep {
  const _LearningStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.duration,
    required this.subtitleMode,
    required this.goal,
  });

  final String number;
  final IconData icon;
  final String title;
  final String body;
  final String duration;
  final String subtitleMode;
  final String goal;
}

class _LearningStepCard extends StatelessWidget {
  const _LearningStepCard({required this.step, required this.current});

  final _LearningStep step;
  final bool current;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: _cardDecoration(
      color: current ? AppDesignTokens.skyLight : AppDesignTokens.appWhite,
      border: current
          ? AppDesignTokens.primaryBlue
          : AppDesignTokens.borderGray,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: AppDesignTokens.primaryBlue,
              foregroundColor: Colors.white,
              child: Text(
                step.number,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 10),
            Icon(step.icon, color: AppDesignTokens.primaryBlueDark),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          step.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          step.body,
          style: const TextStyle(
            color: AppDesignTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        _StepMeta(text: step.duration),
        _StepMeta(text: step.subtitleMode),
        _StepMeta(text: step.goal),
      ],
    ),
  );
}

class _StepMeta extends StatelessWidget {
  const _StepMeta({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: AppDesignTokens.textSecondary,
      ),
    ),
  );
}

class _WhyItWorksSection extends StatelessWidget {
  const _WhyItWorksSection();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppDesignTokens.skyLight,
      borderRadius: BorderRadius.circular(26),
    ),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const List<Widget> reasons = <Widget>[
          _ReasonItem(title: '剧情已经熟悉', body: '大脑不再忙着猜故事，可以把注意力放到语言本身。'),
          _ReasonItem(title: '表达反复出现', body: '单词会和人物、动作、情绪及具体场景建立联系。'),
          _ReasonItem(title: '模仿真实语气', body: '不仅记住句子意思，也能学习停顿、重音和语调。'),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '为什么要重复同一集？',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            if (constraints.maxWidth >= 760)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: reasons
                    .map((Widget item) => Expanded(child: item))
                    .toList(growable: false),
              )
            else
              const Column(children: reasons),
          ],
        );
      },
    ),
  );
}

class _ReasonItem extends StatelessWidget {
  const _ReasonItem({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.check_circle_rounded,
          color: AppDesignTokens.primaryBlueDark,
          size: 22,
        ),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text(
          body,
          style: const TextStyle(
            color: AppDesignTokens.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _LearningExampleSection extends StatelessWidget {
  const _LearningExampleSection();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: _cardDecoration(
      color: AppDesignTokens.appWhite,
      border: AppDesignTokens.primaryBlue,
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(title: '一句台词，具体应该怎么学？'),
        SizedBox(height: 24),
        Text(
          '“You’ve got to be kidding me.”',
          style: TextStyle(
            fontSize: 26,
            height: 1.3,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.primaryBlueDark,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '你在开玩笑吧。',
          style: TextStyle(fontSize: 17, color: AppDesignTokens.textSecondary),
        ),
        SizedBox(height: 22),
        _ExampleAction(label: '第 1 遍', text: '结合剧情和中文字幕，理解人物为什么说这句话。'),
        _ExampleAction(label: '第 2 遍', text: '注意 “got to” 在自然口语中的弱读和连读。'),
        _ExampleAction(label: '第 3 遍', text: '模仿人物惊讶或不敢相信的语气，跟读 3 次。'),
        SizedBox(height: 14),
        _ExampleResult(),
      ],
    ),
  );
}

class _ExampleAction extends StatelessWidget {
  const _ExampleAction({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppDesignTokens.skyLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppDesignTokens.primaryBlueDark,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
      ],
    ),
  );
}

class _ExampleResult extends StatelessWidget {
  const _ExampleResult();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEFFFF5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      children: <Widget>[
        Icon(
          Icons.bookmark_added_outlined,
          color: AppDesignTokens.brandGreenDark,
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            '收藏到短语库，第二天再复习一次。',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _PreparationChecklist extends StatelessWidget {
  const _PreparationChecklist();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _SectionTitle(title: '开始前，准备好这 4 项'),
      SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          _PreparationItem(icon: Icons.graphic_eq_rounded, label: '音标基础'),
          _PreparationItem(icon: Icons.account_tree_outlined, label: '基础语法'),
          _PreparationItem(icon: Icons.hearing_outlined, label: '连读和弱读意识'),
          _PreparationItem(icon: Icons.headphones_rounded, label: '一副耳机'),
        ],
      ),
      SizedBox(height: 12),
      Text(
        '不用全部掌握后才能开始，边看边补也可以。',
        style: TextStyle(color: AppDesignTokens.textSecondary),
      ),
    ],
  );
}

class _PreparationItem extends StatelessWidget {
  const _PreparationItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: AppDesignTokens.softWhite,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: AppDesignTokens.primaryBlueDark),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _LevelRecommendationSection extends StatelessWidget {
  const _LevelRecommendationSection({required this.onOpenResource});

  final ValueChanged<GuideLearningResource> onOpenResource;

  static const List<GuideLearningResource> _levels = <GuideLearningResource>[
    GuideLearningResource(
      title: '刚起步 · 《Muzzy》《小猪佩奇》',
      searchQuery: 'Muzzy Peppa Pig',
      resourceHint: '适合只能听懂少量基础词的学习者。优先选择短小、生活化的英文片段。',
    ),
    GuideLearningResource(
      title: '有一些基础 · 《走遍美国》',
      searchQuery: 'Family Album USA',
      resourceHint: '适合能理解简单日常表达的学习者，练习完整的家庭生活对话。',
    ),
    GuideLearningResource(
      title: '日常对话进阶 · 《Modern Family》',
      searchQuery: 'Modern Family',
      resourceHint: '适合可以理解部分自然对话的学习者，继续积累真实日常表达。',
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const _SectionTitle(
        title: '选择适合你的第一部剧',
        subtitle: '先选一个难度合适的内容，坚持完成一轮，比频繁换剧更有效。',
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool threeColumns = constraints.maxWidth >= 920;
          final bool twoColumns = constraints.maxWidth >= 620;
          final int count = threeColumns ? 3 : (twoColumns ? 2 : 1);
          final double width =
              (constraints.maxWidth - (count - 1) * 16) / count;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _levels
                .asMap()
                .entries
                .map(
                  (MapEntry<int, GuideLearningResource> entry) => SizedBox(
                    width: width,
                    child: _LevelCard(
                      resource: entry.value,
                      highlighted: entry.key == 1,
                      onPressed: () => onOpenResource(entry.value),
                    ),
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
      const SizedBox(height: 16),
      _AdvancedTopicCard(
        onPressed: () => onOpenResource(
          const GuideLearningResource(
            title: '进阶专题 · 律政或医疗剧',
            searchQuery: 'English legal medical drama',
            resourceHint: '适合已经能听懂日常对话、希望积累专业表达的学习者。',
          ),
        ),
      ),
    ],
  );
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.resource,
    required this.highlighted,
    required this.onPressed,
  });

  final GuideLearningResource resource;
  final bool highlighted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final List<String> pieces = resource.title.split(' · ');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(
        color: highlighted
            ? AppDesignTokens.skyLight
            : AppDesignTokens.appWhite,
        border: highlighted
            ? AppDesignTokens.primaryBlue
            : AppDesignTokens.borderGray,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DifficultyTag(label: pieces.first, highlighted: highlighted),
          const SizedBox(height: 14),
          Text(
            pieces.last,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            resource.resourceHint,
            style: const TextStyle(
              color: AppDesignTokens.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppDesignTokens.primaryBlueDark,
              side: const BorderSide(color: AppDesignTokens.primaryBlue),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            child: const Text('查看学习资源'),
          ),
        ],
      ),
    );
  }
}

class _DifficultyTag extends StatelessWidget {
  const _DifficultyTag({required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: highlighted
          ? AppDesignTokens.primaryBlue
          : AppDesignTokens.softGray,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: highlighted ? Colors.white : AppDesignTokens.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _AdvancedTopicCard extends StatelessWidget {
  const _AdvancedTopicCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(color: AppDesignTokens.softWhite),
    child: Row(
      children: <Widget>[
        const Icon(
          Icons.workspace_premium_outlined,
          color: AppDesignTokens.primaryBlueDark,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('进阶专题', style: TextStyle(fontWeight: FontWeight.w900)),
              SizedBox(height: 3),
              Text(
                '能听懂日常对话后，再用律政或医疗剧积累专业表达。',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onPressed, child: const Text('查看资源')),
      ],
    ),
  );
}

class _BottomLearningCta extends StatelessWidget {
  const _BottomLearningCta({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: AppDesignTokens.primaryBlue,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(
      children: <Widget>[
        const Text(
          '不用准备到完美，现在就可以开始',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '第一次只需要完成 5 分钟，看懂一小段剧情就算成功。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, height: 1.45),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('开始第一次学习'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppDesignTokens.primaryBlueDark,
            minimumSize: const Size(220, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(
          onPressed: onStart,
          child: const Text('先选择适合我的影片', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        title,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
      ),
      if (subtitle != null) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          subtitle!,
          style: const TextStyle(
            color: AppDesignTokens.textSecondary,
            fontSize: 16,
          ),
        ),
      ],
    ],
  );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppDesignTokens.skyLight,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: AppDesignTokens.primaryBlueDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: <Widget>[
        const Icon(
          Icons.check_rounded,
          size: 18,
          color: AppDesignTokens.primaryBlueDark,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

BoxDecoration _cardDecoration({
  required Color color,
  Color border = AppDesignTokens.borderGray,
  List<BoxShadow> shadow = const <BoxShadow>[],
}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(26),
  border: Border.all(color: border),
  boxShadow: shadow,
);

ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
  backgroundColor: AppDesignTokens.primaryBlue,
  foregroundColor: Colors.white,
  minimumSize: const Size(0, 54),
  padding: const EdgeInsets.symmetric(horizontal: 22),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
);
