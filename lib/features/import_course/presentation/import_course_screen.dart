import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'widgets/import_course_flow.dart';

Future<void> openImportCourseExperience(BuildContext context) {
  final bool showPadModal = MediaQuery.sizeOf(context).width >= 900;
  if (!showPadModal) {
    context.go(SGRoute.importCourse.route);
    return Future<void>.value();
  }

  final ImportCourseFlowController flowController =
      ImportCourseFlowController();

  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Import course',
    barrierColor: Colors.transparent,
    pageBuilder: (BuildContext dialogContext, _, __) {
      return ImportCourseModal(
        controller: flowController,
        onClose: () => Navigator.of(dialogContext).pop(),
        child: ImportCourseFlow(
          controller: flowController,
          showHeader: false,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onImportCompleted: () => Navigator.of(dialogContext).pop(),
        ),
      );
    },
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
  ).whenComplete(flowController.dispose);
}

class ImportCourseScreen extends StatefulWidget {
  const ImportCourseScreen({super.key});

  @override
  State<ImportCourseScreen> createState() => _ImportCourseScreenState();
}

class _ImportCourseScreenState extends State<ImportCourseScreen> {
  final ImportCourseFlowController flowController =
      ImportCourseFlowController();

  @override
  void dispose() {
    flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PadScaffold(
      currentDestination: AppNavDestination.library,
      topBar: AnimatedBuilder(
        animation: flowController,
        builder: (BuildContext context, _) {
          return PadTopBar(
            title: '导入影视',
            subtitle: '影视库',
            description: context.isPadCompact ? null : '把本地视频和字幕整理成新的学习片库。',
            leading: _IconAction(
              tooltip: flowController.canGoBack ? '返回上一步' : '返回影视库',
              icon: Icons.arrow_back_rounded,
              onTap: flowController.canGoBack
                  ? flowController.goBack
                  : () => context.go(SGRoute.library.route),
            ),
          );
        },
      ),
      body: ImportCourseFlow(
        controller: flowController,
        showHeader: false,
        onCancel: () => context.go(SGRoute.library.route),
        onImportCompleted: () => context.go(SGRoute.library.route),
      ),
    );
  }
}

class ImportCourseModal extends StatelessWidget {
  const ImportCourseModal({
    required this.controller,
    required this.onClose,
    required this.child,
    super.key,
  });

  final ImportCourseFlowController controller;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFFEDF2F7).withValues(alpha: 0.56),
            ),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1080,
                  maxHeight: 800,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppDesignTokens.appWhite.withValues(alpha: 0.98),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: const Color(0xFFF0ECE6)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 42,
                          offset: Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Column(
                        children: <Widget>[
                          _ModalHeader(
                            controller: controller,
                            onClose: onClose,
                          ),
                          const Divider(height: 1, color: Color(0xFFF0ECE6)),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.controller, required this.onClose});

  final ImportCourseFlowController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Row(
            children: <Widget>[
              _IconAction(
                tooltip: controller.canGoBack ? '返回上一步' : '关闭导入弹窗',
                icon: Icons.arrow_back_rounded,
                onTap: controller.canGoBack ? controller.goBack : onClose,
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppDesignTokens.skyLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '影视库',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.primaryBlueDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '导入影视',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ),
              _IconAction(
                tooltip: '关闭导入弹窗',
                icon: Icons.close_rounded,
                onTap: onClose,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: AppDesignTokens.appWhite,
          foregroundColor: AppDesignTokens.brandGreenDark,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          side: const BorderSide(color: AppDesignTokens.borderGray),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}
