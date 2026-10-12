/// 把解析出的 ICS 事件还原成「课程规则」结构。
///
/// ICS 是**逐次**的（每次上课一个事件），我们的模型是**规律**的（一门课 = 星期 +
/// 节次 + 周次集合）。所以导入的核心动作是反向归并：把属于同一门课的若干次
/// 事件重新聚成一条规则，并把各自的日期折回周次。
///
/// 两条识别路径，优先级从高到低：
///
/// 1. `X-CLASSCAL-*` 属性 —— 我们自己的导出，周次与节次是原生字段，无损。
/// 2. 从 DTSTART/DTEND 反推 —— 兼容标准 ICS 和教务系统直接导出的文件：
///    星期取 DTSTART 的星期，节次按开始时间匹配作息表，周次按日期与锚点算。
///
/// 纯 Dart，可直接单元测试。
library;

import '../../core/time/periods.dart';
import '../exchange/ics_props.dart';
import '../model/domain.dart';
import 'ics.dart';

class IcsImportResult {
  const IcsImportResult({
    required this.set,
    required this.warnings,
    required this.week1Monday,
    required this.week1Inferred,
    required this.eventCount,
    required this.unmatchedCount,
  });

  final CalendarSetData set;
  final List<String> warnings;

  /// 最终采用的第 1 周周一。
  final DateTime week1Monday;

  /// 该锚点是我们猜的（文件里没写、用户也没指定），导入向导必须让用户确认。
  final bool week1Inferred;

  final int eventCount;

  /// 开始时间对不上任何节次、被降级成单次事件的数量。
  final int unmatchedCount;
}

/// 解析并归并。 [week1Monday] 由调用方（导入向导）确认后传入时最可靠。
IcsImportResult importIcs(
  String source, {
  DateTime? week1Monday,
  String? setName,
  String? sourceName,
}) {
  final parsed = parseIcs(source);
  final warnings = <String>[...parsed.warnings];

  final fromProps = _week1FromProps(parsed);
  final explicit = week1Monday ?? fromProps;
  // 提示语由推算函数自己写 —— 只有它知道这次是「交叉验证命中」还是
  // 「退回最早事件硬猜」，这两种的可信度差着量级，措辞不该一样。
  final inferred = explicit == null ? _inferWeek1Monday(parsed.events, warnings) : null;
  final anchor = explicit ?? inferred!;
  final week1Inferred = explicit == null;

  // 先按 X-CLASSCAL-WEEKS 声明的整体周次建索引 —— 同一门课的每次事件都会
  // 带上完整的周次集合，因此取第一次见到的即可，不必逐次并集。
  final templates = <String, _RuleGroup>{};
  final oneOffs = <OneOffData>[];
  var unmatched = 0;

  for (final e in parsed.events) {
    if (e.allDay) {
      // 全天事件不是课，原样留成单次事件
      oneOffs.add(_oneOffFrom(e));
      continue;
    }

    final startMinute = e.start.hour * 60 + e.start.minute;
    final declaredPeriods = _parsePeriods(e.xProps[kXPeriods]);
    final slot = declaredPeriods != null
        ? slotForStartPeriod(declaredPeriods.$1)
        : slotForMinute(startMinute);

    if (slot == null) {
      // 时间对不上任何大节 —— 降级成单次事件而不是丢弃，宁可多出一条也不要少一条
      unmatched++;
      oneOffs.add(_oneOffFrom(e));
      continue;
    }

    final endPeriod = declaredPeriods?.$2 ?? slot.endPeriod;
    final weeks = _weeksOf(e, anchor);
    if (weeks.isEmpty) {
      warnings.add('「${e.summary}」(${_date(e.start)}) 算不出有效周次，已跳过');
      continue;
    }

    final teacher = e.xProps[kXTeacher] ?? _teacherFromDescription(e.description);
    final key = '${e.summary}\u0000$teacher\u0000${e.location}'
        '\u0000${e.start.weekday}\u0000${slot.startPeriod}\u0000$endPeriod';

    final group = templates.putIfAbsent(
      key,
      () => _RuleGroup(
        title: e.summary,
        teacher: teacher,
        location: e.location,
        weekday: e.start.weekday,
        startPeriod: slot.startPeriod,
        endPeriod: endPeriod,
        colorHex: e.xProps[kXColor],
      ),
    );
    group.weeks.addAll(weeks);
  }

  // 空标题的事件归成「未命名」会很难看，但比丢掉强；这里给它一个显式名字。
  final rules = <CourseTemplate>[];
  for (final g in templates.values) {
    rules.add(
      CourseTemplate(
        id: rules.length + 1,
        title: g.title.isEmpty ? '未命名课程' : g.title,
        teacher: g.teacher,
        location: g.location,
        weekday: g.weekday,
        startPeriod: g.startPeriod,
        endPeriod: g.endPeriod,
        weeks: g.weeks.toList()..sort(),
        colorHex: g.colorHex,
      ),
    );
  }

  final normalizedOneOffs = <OneOffData>[
    for (var i = 0; i < oneOffs.length; i++) oneOffs[i].copyWith(id: i + 1),
  ];

  return IcsImportResult(
    set: CalendarSetData(
      id: CalendarSetData.unsavedId,
      name: setName ?? _setNameFromEvents(parsed) ?? '导入的课表',
      shifts: SetShifts(week1Monday: dateOnly(anchor)),
      sourceName: sourceName,
    )
      .copyWith(templates: rules, oneOffs: normalizedOneOffs),
    warnings: warnings,
    week1Monday: dateOnly(anchor),
    week1Inferred: week1Inferred,
    eventCount: parsed.events.length,
    unmatchedCount: unmatched,
  );
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _RuleGroup {
  _RuleGroup({
    required this.title,
    required this.teacher,
    required this.location,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.colorHex,
  });

  final String title;
  final String teacher;
  final String location;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  final String? colorHex;
  final Set<int> weeks = <int>{};
}

OneOffData _oneOffFrom(VEvent e) {
  final start = e.start.hour * 60 + e.start.minute;
  final end = e.end == null
      ? (e.allDay ? 24 * 60 : start + 45)
      : (e.allDay ? 24 * 60 : e.end!.hour * 60 + e.end!.minute);
  // 全天事件的起止都是 0:00，直接当 0..1440 处理
  final s = e.allDay ? 0 : start;
  final en = e.allDay ? 24 * 60 : (end <= s ? s + 45 : end);
  return OneOffData(
    id: 0, // 调用方统一重编号
    title: e.summary.isEmpty ? '未命名事件' : e.summary,
    location: e.location,
    note: e.description,
    date: dateOnly(e.start),
    startMinute: s,
    endMinute: en,
  );
}

// ---------------------------------------------------------------------------
// 周次与锚点
// ---------------------------------------------------------------------------

/// 该事件属于哪些周。
///
/// 优先读 `X-CLASSCAL-WEEKS`：那里存的是**这门课的全部周次**，一次就能拿到完整
/// 集合；否则按事件日期相对锚点反推，此时每个事件只贡献自己那一周，靠归并补齐。
/// 后者正是标准 ICS 的处境 —— 所以同一门课必须逐次累加才拼得出周次集合。
List<int> _weeksOf(VEvent e, DateTime anchor) {
  final declared = e.xProps[kXWeeks];
  if (declared != null) {
    final out = <int>[];
    // 逗号在 ICS 的 TEXT 值里本应转义成 `\,`，但别的工具重写文件时转不转义不一定，
    // 两种都接受。
    for (final part in declared.replaceAll(r'\,', ',').split(',')) {
      final n = int.tryParse(part.trim());
      if (n != null && n > 0) out.add(n);
    }
    if (out.isNotEmpty) return out;
  }

  final w = weekOf(week1Monday: anchor, date: e.start);
  return w > 0 ? <int>[w] : const <int>[];
}

/// 锚点优先取**日历层级**的属性，退化时再找事件层级。
///
/// 两种都要认：日历层级是我们自己现在写的形态（一个套级的值不该在每个事件里
/// 抄一遍），事件层级是早期版本和别的工具写出来的形态。只认其中一种，
/// 就会出现「同一份文件在一台机器上正常、在另一台上要重猜」的分裂行为。
DateTime? _week1FromProps(IcsParseResult parsed) =>
    _ymdProp(parsed.props[kXWeek1Monday]) ??
    parsed.events
        .map((e) => _ymdProp(e.xProps[kXWeek1Monday]))
        .firstWhere((d) => d != null, orElse: () => null);

DateTime? _ymdProp(String? raw) {
  if (raw == null) return null;
  final d = _parseYmd(raw.trim());
  return d == null ? null : _mondayOf(d);
}

String? _setNameFromEvents(IcsParseResult parsed) {
  for (final n in [parsed.props[kXSetName], ...parsed.events.map((e) => e.xProps[kXSetName])]) {
    if (n != null && n.trim().isNotEmpty) return n.trim();
  }
  return null;
}

/// 没有现成锚点时，靠「事件日期」和「描述里写的周次」交叉推算。
///
/// 做法：对每个带 `周次：A-B` 的事件，其日期所在周的周一往前推 k 周都能得到
/// 一个候选锚点（k ∈ [A-1, B-1]）。真实锚点会被绝大多数事件同时命中，
/// 取票数最高的即可。这比「拿最早的事件当第 1 周」可靠得多 ——
/// 本机这份课表最早的事件在第 5 周，那样推出来的锚点会整体偏 4 周。
DateTime _inferWeek1Monday(
  List<VEvent> events,
  List<String> warnings,
) {
  final votes = <String, ({DateTime anchor, int count})>{};

  for (final e in events) {
    final range = _weeksFromDescription(e.description);
    if (range == null) continue;
    final monday = _mondayOf(e.start);
    for (var w = range.$1; w <= range.$2; w++) {
      if (w < 1) continue;
      final candidate = monday.subtract(Duration(days: (w - 1) * 7));
      final key = _date(candidate);
      final prev = votes[key];
      votes[key] = (anchor: candidate, count: (prev?.count ?? 0) + 1);
    }
  }

  if (votes.isNotEmpty) {
    final best = votes.values.reduce((a, b) => a.count >= b.count ? a : b);
    warnings.add(
      '文件里没有第 1 周周一的记录，已用「描述里的周次」和事件日期交叉推算出 '
      '${_date(best.anchor)}（${best.count} 条事件一致）；如有出入请在导入向导里改正',
    );
    return best.anchor;
  }

  // 空日历没什么可推的：给一个本周一当占位，也不值得为它告警
  // （导入向导那边会直接显示「0 门课」）。
  if (events.isEmpty) return _mondayOf(DateTime.now());

  // 连描述里都没有周次，只能退到「最早事件所在周的周一」。
  // 这是个**会算错周次**的猜测 —— 只要课表不是从第 1 周就开始有课，
  // 结果就一定偏 —— 所以措辞要比上面那条重，且必须让用户确认。
  var earliest = events.first.start;
  for (final e in events) {
    if (e.start.isBefore(earliest)) earliest = e.start;
  }
  warnings.add('无法从文件推算周次起点（既无 X-CLASSCAL 属性，描述里也没有周次信息），'
      '已按最早事件所在周（${_date(_mondayOf(earliest))}）当作第 1 周 —— '
      '若课表不是第 1 周就有课，这个日期偏早，请务必改正');
  return _mondayOf(earliest);
}

DateTime _mondayOf(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 从 `周次：11-14([周])[01-02节]` 里取 `(11, 14)`。
(int, int)? _weeksFromDescription(String description) {
  final m = RegExp(r'周次\s*[：:]\s*(\d+)\s*(?:[-–~]\s*(\d+))?').firstMatch(description);
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = m.group(2) == null ? a : int.parse(m.group(2)!);
  return a <= b ? (a, b) : (b, a);
}

String _teacherFromDescription(String description) {
  final m = RegExp(r'教师\s*[：:]\s*([^\n\r]+)').firstMatch(description);
  return m == null ? '' : m.group(1)!.trim();
}

(int, int)? _parsePeriods(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(raw.trim());
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  if (a < 1 || b < a) return null;
  return (a, b);
}

DateTime? _parseYmd(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final dt = DateTime(y, mo, d);
  // DateTime 会把 2026-02-31 悄悄滚成 3 月 3 日，必须回查
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}
