import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'growth_provider.dart';

class GrowthScreen extends ConsumerWidget {
  const GrowthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserGrowth growth = ref.watch(userGrowthProvider);
    return PadScaffold(
      currentDestination: AppNavDestination.growth,
      topBar: const PadTopBar(title: '英语成长之旅', description: '你的英语身份，正在持续升级。'),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 760;
          final double horizontalPadding = compact ? 20 : 32;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              40,
            ),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _LevelMembershipCarousel(growth: growth),
                      const SizedBox(height: 34),
                      _SectionHeader(
                        title: '今日成长值',
                        actionLabel: growth.today.checkedIn ? '今日已点亮' : '去学习',
                        onAction: growth.today.checkedIn
                            ? null
                            : () => context.go(AppNavDestination.library.route),
                      ),
                      const SizedBox(height: 12),
                      _TodayGrowthValue(growth: growth),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LevelMembershipCarousel extends StatefulWidget {
  const _LevelMembershipCarousel({required this.growth});
  final UserGrowth growth;

  @override
  State<_LevelMembershipCarousel> createState() =>
      _LevelMembershipCarouselState();
}

class _LevelMembershipCarouselState extends State<_LevelMembershipCarousel> {
  late final PageController _controller;
  late int _activeLevel;
  double? _dragStartX;

  @override
  void initState() {
    super.initState();
    _activeLevel = widget.growth.level;
    _controller = PageController(
      initialPage: _activeLevel - 1,
      viewportFraction: .86,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showLevel(int level) {
    final int targetLevel = level.clamp(1, 10);
    if (targetLevel == _activeLevel) {
      return;
    }
    _controller.animateToPage(
      targetLevel - 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleDragEnd(double endX) {
    final double? startX = _dragStartX;
    _dragStartX = null;
    if (startX == null || (endX - startX).abs() < 36) {
      return;
    }
    _showLevel(_activeLevel + (endX < startX ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 760;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Listener(
          key: const Key('growth-level-carousel'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: (PointerDownEvent event) =>
              _dragStartX = event.position.dx,
          onPointerUp: (PointerUpEvent event) =>
              _handleDragEnd(event.position.dx),
          onPointerCancel: (_) => _dragStartX = null,
          child: SizedBox(
            height: compact ? 294 : 286,
            child: PageView.builder(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 10,
              onPageChanged: (int index) =>
                  setState(() => _activeLevel = index + 1),
              itemBuilder: (_, int index) => Padding(
                padding: EdgeInsets.only(right: index == 9 ? 0 : 12),
                child: _LevelMembershipCard(
                  profile: growthLevelProfile(index + 1),
                  growth: widget.growth,
                  isCurrent: index + 1 == widget.growth.level,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int level = 1; level <= 10; level++)
                InkWell(
                  key: Key('growth-level-carousel-dot-$level'),
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => _showLevel(level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: level == _activeLevel ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: level == _activeLevel
                          ? const Color(0xFF68349F)
                          : const Color(0xFFD9D0E1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (_, BoxConstraints constraints) {
            final bool stack = constraints.maxWidth < 760;
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _HowToLearn(growth: widget.growth),
                  const SizedBox(height: 22),
                  _LevelLearningRoute(
                    growth: widget.growth,
                    displayedLevel: _activeLevel,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 6, child: _HowToLearn(growth: widget.growth)),
                const SizedBox(width: 28),
                Expanded(
                  flex: 6,
                  child: _LevelLearningRoute(
                    growth: widget.growth,
                    displayedLevel: _activeLevel,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 34),
        _Badges(growth: widget.growth),
      ],
    );
  }
}

class _LevelMembershipCard extends StatelessWidget {
  const _LevelMembershipCard({
    required this.profile,
    required this.growth,
    required this.isCurrent,
  });
  final GrowthLevelProfile profile;
  final UserGrowth growth;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 760;
    final List<Color> skyColors = _adventureSkyColors(profile.level);
    final bool isUnlocked = profile.level < growth.level;
    final int unlockXp = UserGrowth.experienceToReachLevel(profile.level);
    final int totalTargetXp = isCurrent
        ? growth.nextLevelTotalXP ?? growth.experience
        : unlockXp;
    final double progress = isCurrent
        ? (growth.experience / totalTargetXp).clamp(0, 1).toDouble()
        : (isUnlocked || unlockXp == 0 ? 1 : growth.experience / unlockXp)
              .clamp(0, 1)
              .toDouble();
    final int remainingXp = isCurrent
        ? growth.remainingXPToNextLevel
        : (unlockXp - growth.experience).clamp(0, unlockXp);
    final String statusLabel = isCurrent
        ? 'CURRENT JOURNEY'
        : isUnlocked
        ? 'UNLOCKED'
        : 'LOCKED';
    final String stageLabel = isCurrent
        ? '英语成长冒险 · 当前阶段'
        : isUnlocked
        ? '英语成长冒险 · 已解锁等级'
        : '英语成长冒险 · 待解锁等级';
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 28,
        22,
        compact ? 12 : 20,
        18,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: skyColors,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: skyColors.last.withValues(alpha: .38),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: CustomPaint(painter: _AdventureRoutePainter()),
          ),
          Positioned(
            right: -32,
            top: -60,
            child: Icon(
              Icons.public_rounded,
              size: 224,
              color: Colors.white.withValues(alpha: .1),
            ),
          ),
          const Positioned(
            left: 24,
            top: 20,
            child: Icon(Icons.star_rounded, color: Color(0xFFFFE09A), size: 15),
          ),
          const Positioned(
            right: 124,
            top: 42,
            child: Icon(Icons.star_rounded, color: Color(0xB3FFFFFF), size: 10),
          ),
          const Positioned(right: -48, top: -70, child: _GlowOrb(size: 180)),
          if (isCurrent)
            Positioned(
              top: 18,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE09A),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x88FFCF5A), blurRadius: 12),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 16,
                      color: Color(0xFF6C3C00),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '当前等级',
                      style: TextStyle(
                        color: Color(0xFF6C3C00),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: compact ? 72 : 136,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withValues(alpha: .2)),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  fontSize: 9,
                  letterSpacing: .7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      stageLabel,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: .5,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFFFD77C).withValues(alpha: .95),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lv. ${profile.level}',
                      style: const TextStyle(
                        fontSize: 42,
                        height: .95,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.englishTitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: .68),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      profile.ability,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: .84),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      isCurrent
                          ? growth.hasReachedTopLevel
                                ? '当前总积分 ${growth.experience} XP'
                                : '当前总积分 ${growth.experience} / $totalTargetXp XP'
                          : '当前累计 ${growth.experience} XP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: .75),
                      ),
                    ),
                    const SizedBox(height: 7),
                    _GrowthProgressBar(
                      progress: progress,
                      colors: const <Color>[
                        Color(0xFFFFF0A9),
                        Color(0xFFFFB45F),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      isCurrent
                          ? growth.hasReachedTopLevel
                                ? '已达到最高等级 · 累计 ${growth.experience} XP'
                                : '本等级总积分 $totalTargetXp XP · 还差 $remainingXp XP'
                          : isUnlocked
                          ? '已解锁：门槛 $unlockXp XP'
                          : '本等级总积分 $totalTargetXp XP · 还差 $remainingXp XP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: .78),
                      ),
                    ),
                    const SizedBox(height: 9),
                    _CardStatistics(growth: growth),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Image.asset(
                  'assets/img/growth-level-${profile.level}.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GrowthProgressBar extends StatelessWidget {
  const _GrowthProgressBar({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF102846).withValues(alpha: .38),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: .2)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        height: 8,
        child: LayoutBuilder(
          builder: (_, BoxConstraints constraints) => Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: constraints.maxWidth * progress,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CardStatistics extends StatelessWidget {
  const _CardStatistics({required this.growth});
  final UserGrowth growth;

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> statistics = <(String, String)>[
      ('${growth.totalStudyMinutes}', '分钟'),
      ('${growth.learnedSentenceCount}', '句子'),
      ('${growth.savedPhraseCount}', '表达'),
      ('${growth.completedVideoCount}', '影片'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: statistics
          .map(
            ((String, String) item) => Text(
              '${item.$1} ${item.$2}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: .76),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

List<Color> _adventureSkyColors(int level) {
  if (level <= 3) {
    return const <Color>[
      Color(0xFF173F7B),
      Color(0xFF326BC8),
      Color(0xFF52B7D9),
    ];
  }
  if (level <= 6) {
    return const <Color>[
      Color(0xFF155B67),
      Color(0xFF268E9C),
      Color(0xFF67BFC4),
    ];
  }
  if (level <= 9) {
    return const <Color>[
      Color(0xFF263F85),
      Color(0xFF6259B8),
      Color(0xFF7EAFD1),
    ];
  }
  return const <Color>[Color(0xFF5C4824), Color(0xFFAC7537), Color(0xFFE0B05B)];
}

class _AdventureRoutePainter extends CustomPainter {
  const _AdventureRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint routePaint = Paint()
      ..color = Colors.white.withValues(alpha: .28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Path route = Path()
      ..moveTo(size.width * .04, size.height * .65)
      ..cubicTo(
        size.width * .3,
        size.height * .42,
        size.width * .56,
        size.height * .92,
        size.width * .92,
        size.height * .3,
      );
    final Paint markerPaint = Paint()..color = const Color(0xFFFFE09A);
    canvas
      ..drawPath(route, routePaint)
      ..drawCircle(Offset(size.width * .04, size.height * .65), 3, markerPaint)
      ..drawCircle(Offset(size.width * .92, size.height * .3), 3, markerPaint)
      ..drawArc(
        Rect.fromLTWH(
          size.width * .46,
          -size.height * .22,
          size.width * .46,
          size.height * .72,
        ),
        .4,
        2.1,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
  }

  @override
  bool shouldRepaint(covariant _AdventureRoutePainter oldDelegate) => false;
}

class _LevelLearningRoute extends StatelessWidget {
  const _LevelLearningRoute({
    required this.growth,
    required this.displayedLevel,
  });
  final UserGrowth growth;
  final int displayedLevel;

  @override
  Widget build(BuildContext context) {
    final GrowthLevelProfile profile = growthLevelProfile(displayedLevel);
    final String? courseTitle = growth.activeCourseTitle;
    final bool isCurrent = displayedLevel == growth.level;
    final bool isUnlocked = displayedLevel < growth.level;
    final int unlockXp = UserGrowth.experienceToReachLevel(displayedLevel);
    final int remainingXp = (unlockXp - growth.experience).clamp(0, unlockXp);
    final List<String> steps = isCurrent
        ? courseTitle == null
              ? const <String>[
                  '先在课程库导入一个本地视频与英文字幕',
                  '打开第一集，从一个短片段开始精听',
                  '完成听写、查词与跟读，成长值会自动累计',
                ]
              : <String>[
                  '继续学习《$courseTitle》',
                  '当前已完成 ${growth.activeCourseCompletedEpisodes}/${growth.activeCourseTotalEpisodes} 集，课程进度 ${growth.activeCourseProgressPercent}%',
                  '从上次进度继续，完成听写、查词与跟读',
                ]
        : isUnlocked
        ? <String>[
            '该等级已经由你的真实学习记录解锁',
            '解锁时累计成长值达到 $unlockXp XP',
            '继续当前课程，积累下一阶段的成长值',
          ]
        : <String>[
            '解锁该等级需要累计 $unlockXp XP',
            '你当前累计 ${growth.experience} XP，还差 $remainingXp XP',
            '完成精听、学习句子或收藏表达即可自动累计',
          ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFF7F4FF), Color(0xFFEEF7FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x142C3570),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Lv.$displayedLevel 学习路线',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF28183A),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            profile.ability,
            style: const TextStyle(
              fontSize: 13,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          for (int index = 0; index < steps.length; index++)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 23,
                    height: 23,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: <Color>[Color(0xFF8070DA), Color(0xFF5B9DDB)],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color(0x335D82CE),
                          blurRadius: 7,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        steps[index],
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4A3A58),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _MembershipHero extends StatelessWidget {
  const _MembershipHero({required this.growth});
  final UserGrowth growth;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 760;
    final int remainingXp = growth.remainingXPToNextLevel;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        compact ? 24 : 34,
        30,
        compact ? 18 : 30,
        28,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF19052F),
            Color(0xFF44117A),
            Color(0xFF210740),
          ],
          stops: <double>[0, .56, 1],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x45230A48),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -82,
            right: compact ? -60 : 120,
            child: _GlowOrb(size: compact ? 210 : 250),
          ),
          Positioned(
            bottom: -120,
            left: compact ? -80 : 260,
            child: const _GlowOrb(size: 220),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                flex: compact ? 7 : 6,
                child: _HeroDetails(growth: growth, remainingXp: remainingXp),
              ),
              SizedBox(width: compact ? 2 : 22),
              Expanded(
                flex: compact ? 3 : 4,
                child: _CompanionArt(compact: compact),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFB172FF).withValues(alpha: .18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFC28CFF).withValues(alpha: .3),
            blurRadius: 42,
          ),
        ],
      ),
    ),
  );
}

class _HeroDetails extends StatelessWidget {
  const _HeroDetails({required this.growth, required this.remainingXp});
  final UserGrowth growth;
  final int remainingXp;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        'ENGLISH GROWTH MEMBER',
        style: TextStyle(
          letterSpacing: 1.2,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: const Color(0xFFFFD77C).withValues(alpha: .88),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Lv.${growth.level}',
        style: const TextStyle(
          fontSize: 46,
          height: .9,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        growth.title,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        growth.englishTitle,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: .64),
        ),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _MemberTag(
            icon: LucideIcons.flame,
            text: '连续学习 ${growth.streakDays} 天',
          ),
          _MemberTag(icon: LucideIcons.star, text: '${growth.experience} XP'),
        ],
      ),
      const SizedBox(height: 25),
      _HeroProgress(
        total: growth.experience,
        totalTarget: growth.nextLevelTotalXP,
        remaining: remainingXp,
        hasReachedTopLevel: growth.hasReachedTopLevel,
      ),
    ],
  );
}

class _MemberTag extends StatelessWidget {
  const _MemberTag({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .11)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: const Color(0xFFFFD77C)),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

class _HeroProgress extends StatelessWidget {
  const _HeroProgress({
    required this.total,
    required this.totalTarget,
    required this.remaining,
    required this.hasReachedTopLevel,
  });
  final int total;
  final int? totalTarget;
  final int remaining;
  final bool hasReachedTopLevel;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Text(
            hasReachedTopLevel
                ? '当前总积分 $total XP'
                : '当前总积分 $total / $totalTarget XP',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            hasReachedTopLevel
                ? '累计 $total XP'
                : '本等级总积分 $totalTarget XP · 还差 $remaining XP',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: .65),
            ),
          ),
        ],
      ),
      const SizedBox(height: 9),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: 0,
            end: hasReachedTopLevel ? 1 : (total / totalTarget!).clamp(0, 1),
          ),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, double value, __) => LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: const Color(0xFFFFD77C),
            backgroundColor: Colors.white.withValues(alpha: .18),
          ),
        ),
      ),
    ],
  );
}

class _CompanionArt extends StatelessWidget {
  const _CompanionArt({required this.compact});
  final bool compact;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 244 : 278,
    child: Align(
      alignment: Alignment.bottomRight,
      child: Image.asset(
        'assets/img/growth-companion.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

class _HowToLearn extends StatelessWidget {
  const _HowToLearn({required this.growth});
  final UserGrowth growth;

  @override
  Widget build(BuildContext context) {
    final List<(IconData, String, String, String)> actions =
        <(IconData, String, String, String)>[
          (
            LucideIcons.play,
            growth.today.checkedIn ? '继续今天的学习' : '完成今天的一次练习',
            growth.today.checkedIn ? '今天已点亮，趁节奏还在继续一小段。' : '从一集、一句或五分钟开始，也算完成。',
            AppNavDestination.library.route,
          ),
          (
            LucideIcons.repeat2,
            '回顾收藏过的表达',
            '${growth.savedPhraseCount} 条表达等着重新进入你的记忆。',
            AppNavDestination.phrases.route,
          ),
          (
            LucideIcons.medal,
            '收集真实的学习印记',
            '完成影片、精听时长和收藏都会沉淀为勋章。',
            AppNavDestination.growth.route,
          ),
        ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFDF5FF), Color(0xFFF0F6FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x142C3570),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '怎么学习',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF28183A),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '每次只做一个小动作，让学习自然接到下一次。',
            style: TextStyle(
              fontSize: 13,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          for (int index = 0; index < actions.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == actions.length - 1 ? 0 : 12,
              ),
              child: _LearningLoopAction(
                icon: actions[index].$1,
                title: actions[index].$2,
                description: actions[index].$3,
                route: actions[index].$4,
                showDivider: false,
              ),
            ),
        ],
      ),
    );
  }
}

class _LearningLoopAction extends StatelessWidget {
  const _LearningLoopAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.route,
    required this.showDivider,
  });
  final IconData icon;
  final String title;
  final String description;
  final String route;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      if (showDivider)
        const Positioned(
          left: -9,
          top: 2,
          bottom: 2,
          child: VerticalDivider(width: 1, color: Color(0xFFDCCFE6)),
        ),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: Row(
            children: <Widget>[
              Container(
                width: 33,
                height: 33,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7DEFF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 17, color: const Color(0xFF66339C)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF39254D),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF776C82),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Text(
        title,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w900,
          color: Color(0xFF20152E),
        ),
      ),
      const Spacer(),
      if (actionLabel != null)
        TextButton.icon(
          onPressed: onAction,
          icon: Icon(
            onAction == null ? LucideIcons.badgeCheck : LucideIcons.arrowRight,
            size: 16,
          ),
          label: Text(actionLabel!),
          style: TextButton.styleFrom(
            foregroundColor: onAction == null
                ? const Color(0xFF407B32)
                : const Color(0xFF5E269D),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
    ],
  );
}

class _TodayGrowthValue extends StatelessWidget {
  const _TodayGrowthValue({required this.growth});
  final UserGrowth growth;
  @override
  Widget build(BuildContext context) {
    final List<(IconData, String, int, String)> values =
        <(IconData, String, int, String)>[
          (
            LucideIcons.headphones,
            '精听',
            UserGrowth.studyXPForMinutes(growth.today.studyMinutes),
            AppNavDestination.library.route,
          ),
          (
            LucideIcons.bookOpenCheck,
            '学习句子',
            UserGrowth.sentenceXPForCount(growth.today.sentenceCount),
            AppNavDestination.library.route,
          ),
          (
            LucideIcons.bookmarkCheck,
            '收藏表达',
            UserGrowth.phraseXPForCount(growth.today.phraseCount),
            AppNavDestination.phrases.route,
          ),
        ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFFEFF), Color(0xFFF5F8FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3E7F5)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12263166),
            blurRadius: 18,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < values.length; index++) ...<Widget>[
            Padding(
              padding: EdgeInsets.only(
                bottom: index == values.length - 1 ? 0 : 7,
              ),
              child: _GrowthValueRow(
                icon: values[index].$1,
                label: values[index].$2,
                xp: values[index].$3,
                route: values[index].$4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GrowthValueRow extends StatelessWidget {
  const _GrowthValueRow({
    required this.icon,
    required this.label,
    required this.xp,
    required this.route,
  });
  final IconData icon;
  final String label;
  final int xp;
  final String route;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.go(route),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFECECF5)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFECE2FF), Color(0xFFD9EEFF)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF68409E)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF33263F),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0E5FF),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '+$xp XP',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF6B31B2),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              key: Key('growth-value-action-$label'),
              onPressed: () => context.go(route),
              icon: const Icon(LucideIcons.arrowRight, size: 15),
              label: Text(
                route == AppNavDestination.phrases.route ? '去复习' : '去学习',
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF6A53B8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Badges extends StatelessWidget {
  const _Badges({required this.growth});
  final UserGrowth growth;

  @override
  Widget build(BuildContext context) {
    final List<_Badge> badges = <_Badge>[
      _Badge(
        Icons.local_fire_department_rounded,
        '十日坚持',
        '连续学习 10 天',
        growth.streakDays,
        10,
      ),
      _Badge(
        Icons.calendar_month_rounded,
        '月度习惯',
        '连续学习 30 天',
        growth.streakDays,
        30,
      ),
      _Badge(
        Icons.emoji_events_rounded,
        '百日精进',
        '连续学习 100 天',
        growth.streakDays,
        100,
      ),
      _Badge(
        Icons.workspace_premium_rounded,
        '年度沟通者',
        '连续学习 365 天',
        growth.streakDays,
        365,
      ),
      _Badge(
        LucideIcons.clapperboard,
        '首部影片完成',
        '完成 1 部影片',
        growth.completedVideoCount,
        1,
      ),
      _Badge(
        LucideIcons.film,
        '追剧达人',
        '完成 5 部影片',
        growth.completedVideoCount,
        5,
      ),
      _Badge(
        LucideIcons.headphones,
        '听力突破',
        '累计精听 100 分钟',
        growth.totalStudyMinutes,
        100,
      ),
      _Badge(
        LucideIcons.audioLines,
        '沉浸聆听',
        '累计精听 500 分钟',
        growth.totalStudyMinutes,
        500,
      ),
      _Badge(
        LucideIcons.bookOpenCheck,
        '逐句理解',
        '学习 50 句',
        growth.learnedSentenceCount,
        50,
      ),
      _Badge(
        LucideIcons.messagesSquare,
        '句子收藏家',
        '学习 300 句',
        growth.learnedSentenceCount,
        300,
      ),
      _Badge(
        LucideIcons.bookmarkCheck,
        '表达起步',
        '收藏 20 个表达',
        growth.savedPhraseCount,
        20,
      ),
      _Badge(
        LucideIcons.star,
        '表达收藏家',
        '收藏 100 个表达',
        growth.savedPhraseCount,
        100,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '成长勋章',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                color: Color(0xFF20152E),
              ),
            ),
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0C7),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'ACHIEVEMENTS',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: .55,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF91651B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '点击勋章，查看你为什么获得它，或离它还有多远。',
          style: TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFFFFCF8), Color(0xFFF6F3FF)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x12263166),
                blurRadius: 18,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: Wrap(
            spacing: 13,
            runSpacing: 16,
            children: badges
                .map((_Badge badge) => _BadgeView(badge: badge))
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _Badge {
  const _Badge(
    this.icon,
    this.title,
    this.condition,
    this.current,
    this.target,
  );
  final IconData icon;
  final String title;
  final String condition;
  final int current;
  final int target;

  bool get unlocked => current >= target;
  String get progress => '$current / $target';
  bool get isPhraseBadge => title.contains('表达');
  bool get isStreakBadge => condition.contains('连续学习');
  String get route => isPhraseBadge
      ? AppNavDestination.phrases.route
      : AppNavDestination.library.route;
  String get actionLabel => isPhraseBadge
      ? '去复习表达'
      : isStreakBadge
      ? '去完成今日学习'
      : '去开始学习';
  String get suggestion {
    if (isPhraseBadge) {
      return '打开短语库，挑 3 个已收藏表达逐句朗读，再用其中 1 个造句。';
    }
    if (isStreakBadge) {
      return '今天完成一次精听或逐句学习，保持连续学习记录不中断。';
    }
    if (title.contains('影片')) {
      return '在学习页选一集你愿意反复练习的影片，从第一段开始完成听写和跟读。';
    }
    if (title.contains('句子')) {
      return '在学习页选一个 30 秒以内的片段，逐句听写并至少跟读 3 句。';
    }
    return '在学习页选一个短片段，先精听 5 分钟，再把听懂的句子标记下来。';
  }
}

class _BadgeView extends StatelessWidget {
  const _BadgeView({required this.badge});
  final _Badge badge;

  @override
  Widget build(BuildContext context) {
    final Color foreground = badge.unlocked
        ? const Color(0xFF9B6812)
        : const Color(0xFF99919E);
    return InkWell(
      key: Key('growth-badge-${badge.title}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(badge.title),
          content: Text(
            badge.unlocked
                ? '你已获得这枚勋章。\n\n获得原因：${badge.condition}\n当前记录：${badge.progress}\n\n建议下一步：${badge.suggestion}'
                : '获得条件：${badge.condition}\n当前进度：${badge.progress}\n\n建议下一步：${badge.suggestion}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.go(badge.route);
              },
              child: Text(badge.actionLabel),
            ),
          ],
        ),
      ),
      child: SizedBox(
        width: 102,
        child: Column(
          children: <Widget>[
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: badge.unlocked
                    ? const LinearGradient(
                        colors: <Color>[Color(0xFFFFE6A0), Color(0xFFC18A25)],
                      )
                    : const LinearGradient(
                        colors: <Color>[Color(0xFFF0EDF2), Color(0xFFD6D0D8)],
                      ),
                border: Border.all(
                  color: badge.unlocked
                      ? const Color(0xFFFFEFBB)
                      : const Color(0xFFE6E0E9),
                  width: 2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color:
                        (badge.unlocked
                                ? const Color(0xFFFFC851)
                                : const Color(0xFFBBB1C1))
                            .withValues(alpha: badge.unlocked ? .32 : .12),
                    blurRadius: badge.unlocked ? 14 : 6,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Icon(
                    badge.unlocked ? badge.icon : LucideIcons.lockKeyhole,
                    color: foreground,
                    size: 23,
                  ),
                  if (!badge.unlocked)
                    Positioned(
                      right: 8,
                      bottom: 7,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFB9AFBF),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              badge.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w900,
                color: badge.unlocked
                    ? const Color(0xFF372747)
                    : const Color(0xFF8E8594),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              badge.unlocked ? '已获得' : badge.progress,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badge.unlocked ? foreground : const Color(0xFFA69FAC),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
