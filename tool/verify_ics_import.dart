/// 开发期核对工具：导入一份 .ics，把指定周的网格打印出来。
///
/// 用法：
///   `dart run tool/verify_ics_import.dart <文件.ics> [周次]`
///   `dart run tool/verify_ics_import.dart <文件.ics> --tsv`   仅输出机器可读的规则表
///
/// 存在的意义是阶段 1 的验收标准 —— 「导入 ICS 后第 N 周网格与教务系统逐格一致」。
/// 单元测试只能保证结构对，格子对不对必须拿真实文件核对。`--tsv` 输出
/// `星期\t起始节\t结束节\t课程\t周次\t教室`，供 `tool/compare_with_scrape.py`
/// 与教务系统页面的抓取结果逐行 diff。
library;

import 'dart:io';

import 'package:classcal/core/time/periods.dart';
import 'package:classcal/data/import/ics_import.dart';
import 'package:classcal/data/model/resolve.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法：dart run tool/verify_ics_import.dart <文件.ics> [周次|--tsv]');
    exit(2);
  }

  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('文件不存在：${args[0]}');
    exit(2);
  }

  final r = importIcs(file.readAsStringSync(), sourceName: file.uri.pathSegments.last);

  if (args.contains('--tsv')) {
    _printTsv(r);
    return;
  }

  stdout
    ..writeln('来源：${args[0]}')
    ..writeln('事件数：${r.eventCount}')
    ..writeln('识别出课程规则：${r.set.templates.length}')
    ..writeln('单次事件：${r.set.oneOffs.length}（其中 ${r.unmatchedCount} 条是节次对不上而降级的）')
    ..writeln('第 1 周周一：${_ymd(r.week1Monday)}${r.week1Inferred ? '  ← 推算，未在文件中声明' : ''}');

  if (r.warnings.isNotEmpty) {
    stdout.writeln('\n警告（${r.warnings.length}）:');
    for (final w in r.warnings.take(20)) {
      stdout.writeln('  · $w');
    }
    if (r.warnings.length > 20) stdout.writeln('  …还有 ${r.warnings.length - 20} 条');
  }

  final out = resolveSessions(
    shifts: r.set.shifts,
    templates: r.set.templates,
    oneOffs: r.set.oneOffs,
    overrides: const [],
  );

  final range = weekRange(out.sessions);
  stdout.writeln('\n数据覆盖第 ${range.first}–${range.last} 周');

  stdout.writeln('\n课程规则一览:');
  final sorted = [...r.set.templates]
    ..sort((a, b) => a.weekday != b.weekday
        ? a.weekday - b.weekday
        : a.startPeriod - b.startPeriod);
  for (final t in sorted) {
    stdout.writeln('  周${t.weekday} ${periodLabel(t.startPeriod, t.endPeriod).padRight(8)}'
        '${t.title}  @${t.location}  '
        '[${_compressWeeks(t.weeks)}]');
  }

  final week = args.length > 1 ? int.tryParse(args[1]) ?? 5 : 5;
  _printWeek(out.sessions, r.week1Monday, week);
}

/// 机器可读输出，供外部脚本 diff。
void _printTsv(IcsImportResult r) {
  for (final t in r.set.templates) {
    stdout.writeln([
      t.weekday,
      t.startPeriod,
      t.endPeriod,
      t.title,
      _compressWeeks(t.weeks),
      t.location,
      t.teacher,
    ].join('\t'));
  }
}

/// 把 `[5,6,7,8,9]` 压成 `5-9`，只影响打印，不涉及存储。
String _compressWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = [...weeks]..sort();
  final parts = <String>[];
  var start = sorted.first;
  var prev = start;
  for (final w in sorted.skip(1)) {
    if (w == prev + 1) {
      prev = w;
      continue;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    start = w;
    prev = w;
  }
  parts.add(start == prev ? '$start' : '$start-$prev');
  return parts.join(',');
}

void _printWeek(List<ResolvedSession> all, DateTime week1Monday, int week) {
  final sessions = sessionsInWeek(all, week);
  stdout.writeln('\n===== 第 $week 周 =====');
  if (sessions.isEmpty) {
    stdout.writeln('  （无课）');
    return;
  }

  const names = ['一', '二', '三', '四', '五', '六', '日'];
  for (var wd = 1; wd <= 7; wd++) {
    final day = sessions.where((s) => s.weekday == wd).toList()
      ..sort(ResolvedSession.compare);
    if (day.isEmpty) continue;
    stdout.writeln('  周${names[wd - 1]}  ${_ymd(day.first.date)}');
    for (final s in day) {
      final row = rowForStartPeriod(s.startPeriod ?? -1);
      final rowTag = row == null ? '—' : '第${row + 1}行';
      stdout.writeln('    $rowTag  ${formatMinutes(s.startMinute)}-${formatMinutes(s.endMinute)}  '
          '${s.title}  @${s.location}');
    }
  }
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
