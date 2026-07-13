import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/pad_compact.dart';
import '../../domain/import_match.dart';

class ImportMatchTable extends StatelessWidget {
  const ImportMatchTable({
    required this.rows,
    required this.onRowChanged,
    super.key,
  });

  final List<ImportMatchRow> rows;
  final void Function(int index, ImportMatchRow row) onRowChanged;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    final List<String> languageCodes = _languageCodes(rows);
    final double tableWidth =
        52 + 180 + 240 + (languageCodes.length * 240) + 96;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '匹配结果',
          style: TextStyle(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '智能解析匹配剧集 (${rows.length} 组)，确认导入前再检查一次字幕配置。',
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        SizedBox(height: compact ? 22 : 26),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDFC),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE8E2DB)),
          ),
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(30, 36, 30, 36),
                  child: Text(
                    '未检测到可匹配的视频或字幕文件',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: <Widget>[
                        _TableHeader(languageCodes: languageCodes),
                        ...rows.asMap().entries.map(
                          (MapEntry<int, ImportMatchRow> entry) => _ImportRow(
                            index: entry.key,
                            row: entry.value,
                            languageCodes: languageCodes,
                            onRowChanged: onRowChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  List<String> _languageCodes(List<ImportMatchRow> values) {
    final Set<String> codes = <String>{'en'};
    for (final ImportMatchRow row in values) {
      codes.addAll(row.visibleLanguageCodes);
    }

    final List<String> ordered = codes.where((String code) => code != 'en').toList(
      growable: false,
    )..sort(
        (String a, String b) => ImportMatcher.languageLabelFor(
          a,
        ).compareTo(ImportMatcher.languageLabelFor(b)),
      );
    return <String>['en', ...ordered];
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.languageCodes});

  final List<String> languageCodes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8E2DB))),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 180,
            child: _HeaderText('匹配集数名称'),
          ),
          const SizedBox(
            width: 240,
            child: _HeaderText('视频文件'),
          ),
          for (final String code in languageCodes)
            SizedBox(
              width: 240,
              child: _HeaderText(ImportMatcher.languageLabelFor(code)),
            ),
          const SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: _HeaderText('状态'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportRow extends StatelessWidget {
  const _ImportRow({
    required this.index,
    required this.row,
    required this.languageCodes,
    required this.onRowChanged,
  });

  final int index;
  final ImportMatchRow row;
  final List<String> languageCodes;
  final void Function(int index, ImportMatchRow row) onRowChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: row.matched ? Colors.transparent : const Color(0xFFFFFBF5),
        border: const Border(top: BorderSide(color: Color(0xFFE8E2DB))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 180,
              child: Text(
                row.episodeName,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: _FileCell(icon: Icons.movie_outlined, text: row.videoFile),
            ),
            for (final String code in languageCodes)
              SizedBox(
                width: 240,
                child: _SubtitleCell(
                  icon: Icons.subtitles_outlined,
                  value: row.subtitleTracks[code]?.path ?? '',
                  placeholder: code == 'en' ? '未指定英文' : '未指定',
                  options: row.optionsForLanguage(code),
                  onChanged: (String value) {
                    onRowChanged(
                      index,
                      row.assignSubtitle(
                        languageCode: code,
                        languageLabel: row.languageLabel(code),
                        path: value,
                      ),
                    );
                  },
                ),
              ),
            SizedBox(
              width: 96,
              child: Align(
                alignment: Alignment.centerRight,
                child: _StatusBadge(ok: row.matched, text: row.statusText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppDesignTokens.textSecondary,
      ),
    );
  }
}

class _FileCell extends StatelessWidget {
  const _FileCell({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: AppDesignTokens.primaryBlueDark),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SubtitleCell extends StatelessWidget {
  const _SubtitleCell({
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String value;
  final String placeholder;
  final List<ImportSubtitleCandidate> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty && value.isEmpty) {
      return const Text(
        '— 未找到',
        style: TextStyle(fontSize: 14, color: Color(0xFF9A938E)),
      );
    }

    final Set<String> optionPaths = options
        .map((ImportSubtitleCandidate item) => item.path)
        .toSet();
    final String dropdownValue = optionPaths.contains(value) ? value : '';

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: AppDesignTokens.primaryBlueDark),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: dropdownValue,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: true,
              fillColor: AppDesignTokens.appWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE0D9D1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE0D9D1)),
              ),
            ),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: '',
                child: Text(
                  placeholder,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9A938E),
                  ),
                ),
              ),
              ...options.map(
                (ImportSubtitleCandidate item) => DropdownMenuItem<String>(
                  value: item.path,
                  child: Text(
                    ImportMatchRow.subtitleLabel(item.path),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
            onChanged: (String? nextValue) => onChanged(nextValue ?? ''),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFEAF5EE) : const Color(0xFFFFF0CC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            ok
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 18,
            color: ok ? AppDesignTokens.brandGreenDark : const Color(0xFFB56A00),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: ok ? AppDesignTokens.brandGreenDark : const Color(0xFFB56A00),
            ),
          ),
        ],
      ),
    );
  }
}
