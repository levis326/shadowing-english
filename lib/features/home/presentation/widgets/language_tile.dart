import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../utils/app_locale.dart';

/// 语言开关：在中/英之间切换，并把选择保存到程序数据目录
/// （`data/prefs.hive`）。不使用 `shared_preferences`，避免写入 `%APPDATA%`。
class LanguageTile extends StatelessWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      onChanged: (bool newValue) {
        final Locale locale = newValue
            ? const Locale('tr')
            : const Locale('en');
        unawaited(saveAppLocale(locale));
        unawaited(context.setLocale(locale));
      },
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      value: context.locale.languageCode == 'tr',
      title: Text(
        tr('toggle_language'),
        style: Theme.of(
          context,
        ).textTheme.titleMedium!.apply(fontWeightDelta: 2),
      ),
    );
  }
}
