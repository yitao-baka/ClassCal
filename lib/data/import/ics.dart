/// iCalendar (RFC 5545) 解析 —— 只实现课表用得到的子集。
///
/// 为什么自己写而不是用现成的包：Dart 的 ICS 生态很弱 —— `icalendar_parser`
/// 停更两年且**不做递归展开**（只把 RRULE 当字符串给你），`ical` 只能生成不能解析。
/// 而课表需要的子集很小（VEVENT / DTSTART / DTEND / RRULE / EXDATE / SUMMARY /
/// LOCATION），自己写反而更可控，也能顺手支持我们自己的 X-CLASSCAL-* 扩展属性。
///
/// 纯 Dart，不 import Flutter，便于 `dart test` 直接跑。
library;

/// 一个解析出来的日历事件。
class VEvent {
  VEvent({
    required this.summary,
    required this.start,
    required this.end,
    this.uid,
    this.location = '',
    this.description = '',
    this.rrule,
    this.allDay = false,
    this.exdates = const <DateTime>[],
    this.xProps = const <String, String>{},
  });

  final String? uid;

  /// 本地墙上时间。带 `Z` 的 UTC 时间已转换过。
  final DateTime start;
  final DateTime? end;

  final String summary;
  final String location;
  final String description;

  /// 原始 RRULE 字符串，未展开。
  final String? rrule;

  /// 全天事件（只有日期没有时分）。
  final bool allDay;

  /// 被排除的日期（EXDATE）。
  final List<DateTime> exdates;

  /// `X-CLASSCAL-*` 等自定义属性，键已去掉前缀以外的大小写差异。
  final Map<String, String> xProps;
}

class IcsParseResult {
  const IcsParseResult(this.events, this.warnings, {this.props = const {}});

  final List<VEvent> events;
  final List<String> warnings;

  /// 写在 `VCALENDAR` 层级（而不是某个事件里）的 `X-` 属性。
  ///
  /// 有些信息本来就是**整份日历共有的**而非法某个事件所有 ——
  /// 「第 1 周的周一」是整套课表的锚点，把它在每个 VEVENT 里抄一遍
  /// 既啰嗦，又给了同一文件里不同事件互相矛盾的余地。
  final Map<String, String> props;
}

/// 长度超过 75 字节的行会被折行，续行以空格或制表符开头。
///
/// 必须先做这一步再做任何解析 —— 否则中文摘要（一个字 3 字节）几乎必然被折开，
/// 直接按行取值会得到半截字符串。
String unfold(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final out = StringBuffer();
  for (final line in normalized.split('\n')) {
    if (line.isNotEmpty && (line[0] == ' ' || line[0] == '\t')) {
      out.write(line.substring(1));
    } else {
      if (out.isNotEmpty) out.write('\n');
      out.write(line);
    }
  }
  return out.toString();
}

/// 反转义 TEXT 值。顺序要紧：反斜杠必须最后处理，否则 `\\n` 会被先当成换行。
String _unescapeText(String v) {
  final out = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    if (v[i] != r'\' || i + 1 >= v.length) {
      out.write(v[i]);
      continue;
    }
    final next = v[++i];
    switch (next) {
      case 'n':
      case 'N':
        out.write('\n');
      case ',':
        out.write(',');
      case ';':
        out.write(';');
      case r'\':
        out.write(r'\');
      default:
        out.write(next);
    }
  }
  return out.toString();
}

/// `NAME;PARAM=VAL;PARAM2="a,b":VALUE` → (NAME, {PARAM: VAL}, VALUE)
///
/// 冒号和分号的切分必须避开双引号内的内容 —— 参数值里合法地可以带分隔符。
({String name, Map<String, String> params, String value}) _splitProperty(String line) {
  var inQuote = false;
  var colonAt = -1;
  var semiAt = -1;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      inQuote = !inQuote;
    } else if (!inQuote) {
      if (c == ':' && colonAt < 0) {
        colonAt = i;
        break;
      }
      if (c == ';' && semiAt < 0) semiAt = i;
    }
  }

  final name = (semiAt >= 0 ? line.substring(0, semiAt) : line.substring(0, colonAt < 0 ? line.length : colonAt))
      .toUpperCase();
  final params = <String, String>{};
  if (semiAt >= 0 && colonAt > semiAt) {
    for (final p in line.substring(semiAt + 1, colonAt).split(';')) {
      final eq = p.indexOf('=');
      if (eq > 0) {
        params[p.substring(0, eq).toUpperCase()] =
            p.substring(eq + 1).replaceAll('"', '');
      }
    }
  }
  final value = colonAt < 0 ? '' : line.substring(colonAt + 1);
  return (name: name, params: params, value: value);
}

/// 解析 `20261007T080000` / `20261007T080000Z` / `20261007`。
///
/// 不带 `Z` 的按**本地墙上时间**处理，不做时区换算 —— 课表里的
/// 「08:00 上课」指的是墙上时间，跟着时区挪反而是错的。
/// 带 `Z` 的是 UTC，转成本地时区。
DateTime? _parseDateTime(String raw) {
  final v = raw.trim();
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?(Z)?$').firstMatch(v);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final hh = int.parse(m.group(4) ?? '0');
  final mm = int.parse(m.group(5) ?? '0');
  final ss = int.parse(m.group(6) ?? '0');
  final dt = DateTime(y, mo, d, hh, mm, ss);
  if (dt.month != mo || dt.day != d) return null; // 20260231 这类非法日期
  return m.group(7) == 'Z' ? dt.toLocal() : dt;
}

/// 解析 EXDATE / RDATE 这类可能带逗号的多值日期列表。
List<DateTime> _parseDateList(String value) {
  final out = <DateTime>[];
  for (final part in value.split(',')) {
    final d = _parseDateTime(part);
    if (d != null) out.add(d);
  }
  return out;
}

/// 展开 `FREQ=WEEKLY` 的 RRULE，返回 [start] 之后（含）的所有发生时刻。
///
/// 只支持课表实际会遇到的形态：WEEKLY + COUNT 或 UNTIL，可带 BYDAY。
/// 遇到不认识的组合就退化成「只有首次发生」，并把情况记进 warnings，
/// 而不是抛异常 —— 导入外部日历时半截数据也比整个失败强。
List<DateTime> expandWeeklyRrule(
  String rrule,
  DateTime start, {
  List<String>? warnings,
  int maxOccurrences = 200,
}) {
  final parts = <String, String>{};
  for (final seg in rrule.split(';')) {
    final eq = seg.indexOf('=');
    if (eq > 0) parts[seg.substring(0, eq).toUpperCase()] = seg.substring(eq + 1);
  }

  if ((parts['FREQ'] ?? '').toUpperCase() != 'WEEKLY') {
    warnings?.add('暂不支持的 RRULE 频率：${parts['FREQ'] ?? rrule}');
    return <DateTime>[start];
  }

  int? count;
  if (parts['COUNT'] != null) count = int.tryParse(parts['COUNT']!);
  DateTime? until;
  if (parts['UNTIL'] != null) until = _parseDateTime(parts['UNTIL']!);

  final byDay = <int>{};
  if (parts['BYDAY'] != null) {
    const map = <String, int>{
      'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7,
    };
    for (final d in parts['BYDAY']!.split(',')) {
      // 形如 `-1MO` 的序号前缀我们不支持，忽略前缀只取星期
      final day = map[RegExp(r'([A-Z]{2})$').firstMatch(d.trim())?.group(1) ?? ''];
      if (day != null) byDay.add(day);
    }
  }

  // 没有 BYDAY 就按起始日的星期每周重复
  final days = byDay.isEmpty ? <int>{start.weekday} : byDay;

  // 先按周生成候选，再按 BYDAY 在一周内展开
  final result = <DateTime>[];
  final startDate = DateTime(start.year, start.month, start.day);
  var week = 0;
  while (result.length < maxOccurrences && week < 400) {
    var producedThisWeek = 0;
    for (final wd in days.toList()..sort()) {
      final candidateDate = startDate.add(Duration(days: week * 7 + (wd - start.weekday)));
      if (candidateDate.isBefore(startDate)) continue;
      final candidate = DateTime(
        candidateDate.year,
        candidateDate.month,
        candidateDate.day,
        start.hour,
        start.minute,
        start.second,
      );
      if (until != null && candidate.isAfter(until)) return result;
      result.add(candidate);
      producedThisWeek++;
      if (count != null && result.length >= count) return result;
      if (result.length >= maxOccurrences) {
        warnings?.add('RRULE 展开超过 $maxOccurrences 次，已截断');
        return result;
      }
    }
    // 该周一个都没产生（例如 BYDAY 全在起始日之前）且已设 COUNT，避免空转
    if (producedThisWeek == 0 && until == null && count == null && week > 60) break;
    week++;
  }
  return result;
}

/// 解析整个 `.ics` 文本。
IcsParseResult parseIcs(String source) {
  final warnings = <String>[];
  final lines = unfold(source).split('\n');

  final events = <VEvent>[];
  final calendarProps = <String, String>{};
  Map<String, String>? current;
  var inEvent = false;

  void flush() {
    if (current == null) return;
    final props = current!;
    current = null;
    inEvent = false;

    final summary = _unescapeText(props['SUMMARY'] ?? '').trim();
    final dtStartRaw = props['DTSTART'];
    final start = dtStartRaw == null ? null : _parseDateTime(dtStartRaw);
    if (start == null) {
      warnings.add('跳过缺少有效 DTSTART 的事件：${summary.isEmpty ? '(无标题)' : summary}');
      return;
    }

    // 只有日期没有时刻 → 全天事件
    final allDay = !dtStartRaw!.contains('T');
    final endRaw = props['DTEND'];
    final end = endRaw == null ? null : _parseDateTime(endRaw);

    // 展开重复规则
    final rrule = props['RRULE'];
    final occurrences = rrule == null
        ? <DateTime>[start]
        : expandWeeklyRrule(rrule, start, warnings: warnings);

    final exdates = props['EXDATE'] == null
        ? const <DateTime>[]
        : _parseDateList(props['EXDATE']!);

    final xProps = <String, String>{
      for (final e in props.entries)
        if (e.key.startsWith('X-')) e.key: e.value,
    };

    for (final occ in occurrences) {
      if (exdates.any((e) => e.year == occ.year && e.month == occ.month && e.day == occ.day)) {
        continue;
      }
      events.add(
        VEvent(
          uid: props['UID'],
          summary: summary,
          start: occ,
          end: end == null ? null : occ.add(end.difference(start)),
          location: _unescapeText(props['LOCATION'] ?? '').trim(),
          description: _unescapeText(props['DESCRIPTION'] ?? '').trim(),
          rrule: rrule,
          allDay: allDay,
          exdates: exdates,
          xProps: xProps,
        ),
      );
    }
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line == 'BEGIN:VEVENT') {
      inEvent = true;
      current = <String, String>{};
      continue;
    }
    if (line == 'END:VEVENT') {
      flush();
      continue;
    }
    final p = _splitProperty(line);
    if (p.name.isEmpty) continue;

    if (!inEvent || current == null) {
      // 事件之外的 X- 属性归日历层级。`X-WR-CALNAME` 这类通用属性
      // 我们不用，但留着不影响，也可能有别人写的 X-CLASSCAL-*。
      if (p.name.startsWith('X-')) calendarProps.putIfAbsent(p.name, () => p.value);
      continue;
    }

    // 同名属性取首次出现（DTSTART 等不该重复；重复时首值优先）
    current!.putIfAbsent(p.name, () => p.value);
  }
  flush();

  return IcsParseResult(events, warnings, props: calendarProps);
}
