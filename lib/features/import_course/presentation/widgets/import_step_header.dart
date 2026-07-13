import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/pad_compact.dart';

class ImportStepHeader extends StatelessWidget {
  const ImportStepHeader({
    required this.currentStep,
    super.key,
  });

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const List<String> labels = <String>['选择文件夹', '智能解析', '匹配结果'];
    final bool compact = context.isPadCompact;
    final double railInset = compact ? 52 : 70;

    return SizedBox(
      height: compact ? 90 : 102,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Positioned(
            left: railInset,
            right: railInset,
            top: compact ? 20 : 24,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFFE3E0DB),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            left: railInset,
            right: railInset,
            top: compact ? 20 : 24,
            child: FractionallySizedBox(
              widthFactor: currentStep <= 1 ? 0 : currentStep == 2 ? 0.5 : 1,
              alignment: Alignment.centerLeft,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: AppDesignTokens.brandGreenDark,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(labels.length, (int index) {
              final int step = index + 1;
              final bool done = step < currentStep;
              final bool active = step == currentStep;

              return Expanded(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: compact ? 38 : 42,
                      height: compact ? 38 : 42,
                      decoration: BoxDecoration(
                        color: done
                            ? AppDesignTokens.brandGreenDark
                            : active
                            ? AppDesignTokens.appWhite
                            : const Color(0xFFF0EEEC),
                        shape: BoxShape.circle,
                        border: active
                            ? Border.all(
                                color: AppDesignTokens.brandGreenDark,
                                width: 2,
                              )
                            : null,
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: done
                            ? Icon(
                                Icons.check_rounded,
                                size: compact ? 18 : 20,
                                color: AppDesignTokens.appWhite,
                              )
                            : Text(
                                '$step',
                                style: TextStyle(
                                  fontSize: compact ? 13 : 14,
                                  fontWeight: FontWeight.w800,
                                  color: active
                                      ? AppDesignTokens.brandGreenDark
                                      : const Color(0xFF8B8782),
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 12),
                    Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                        color: active || done
                            ? AppDesignTokens.brandGreenDark
                            : const Color(0xFF8B8782),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
