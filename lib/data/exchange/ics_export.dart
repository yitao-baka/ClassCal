/// ICS 导出 —— 导出的是**实际会发生的样子**，不是「怎么算出来的」。
///
/// 这是和 JSON 备份刻意分道扬镳的地方，值得说清楚：
///
/// * **JSON 备份**保存三层结构本身（模板 / 单次覆盖 / 套级平移），导入回来
///   连「哪几次课被调过」都还在，因为它的目的是**完整还原这个 App 的状态**。
/// * **ICS 导出**先把三层叠加解析完，再逐次写出最终日期与钟点，因为它的目的是
///   **把课表交给别的日历软件**。Google Calendar 不认识 `weekShift`，
///   给它一份带着偏移量的模板毫无意义；它只认「10 月 7 日 8:00 有一节课」。
///
/// 换算下来 ICS 必定是有损的（撤销不了某次改期、找不回被停掉的那一节），
/// 但那正是 JSON 的活。两份文件都导出，才既互通又不丢东西。
///
/// 附带的好处是导出的 ICS 再导回本 App 也无损：解析器本来就是按
/// 「标题+教师+教室+星期+节次」把同一门课的多次事件重新归并成一条规律的
/// （见 `ics_import.dart`），所以平铺成一条条事件反而是它能吃的最自然的形态。
library;

import 'dart:convert';

import '../../core/time/periods.dart';
import '../model/resolve.dart';
import 'ics_props.dart';

/// 把若干套课表导出成一个 `.ics` 文本。
///
/// 多套会合并进同一个 VCALENDAR —— ICS 文件里没有「标签页」这个概念，
/// 硬造一个私有属性去承载它，别的软件读不懂，我们自己读回来也只是自娱自乐。
/// 需要保留多套结构的场景请走 JSON 备份。
String exportIcs(
  List<CalendarSetData> sets, {
  DateTime? now,
  String? calendarName,
}) {
  final stamp = _utcStamp(now ?? DateTime.now());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//ClassCal//Timetable//CN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    // X-WR-CALNAME 是各个日历软件约定俗成的日历显示名（非 RFC 标准，但通用）
    _text('X-WR-CALNAME', calendarName ?? _calendarName(sets)),
  ];

  // 锚点是整套共有的，写在日历层级而不是每个事件里。
  // 多套课表各有各的锚点时只能写一个 —— 这种情况下它已经不准，
  // 干脆不写，让导入方按自己的事件日期去推，好过给一个错的。
  final anchors = {for (final s in sets) _ymd(s.shifts.week1Monday)};
  if (anchors.length == 1) {
    lines.add('$kXWeek1Monday:${anchors.single}');
  }
  if (sets.length == 1) {
    lines.add(_text(kXSetName, sets.single.name));
  }

  for (final set in sets) {
    final resolved = resolveSessions(
      shifts: set.shifts,
      templates: set.templates,
      oneOffs: set.oneOffs,
      overrides: set.overrides,
    ).sessions;

    for (final s in resolved) {
      // 停课的那次不导出 —— 导出的是「实际会发生的样子」，
      // 而这节课实际不会发生（ICS 里写成 STATUS:CANCELLED 也只会让
      // 别的日历显示一条划掉的日程，不如干脆不写）。
      if (s.cancelled) continue;
      lines.addAll(_event(s, stamp));
    }
  }

  lines.add('END:VCALENDAR');
  // RFC 5545 要求 CRLF 换行
  return '${_fold(lines).join('\r\n')}\r\n';
}

String _calendarName(List<CalendarSetData> sets) {
  if (sets.isEmpty) return 'ClassCal';
  if (sets.length == 1) return sets.single.name;
  return 'ClassCal（${sets.length} 套课表）';
}

/// 一个 VEVENT 的全部行（未折行）。
List<String> _event(ResolvedSession s, String stamp) {
  // 分钟数可能因为套级平移落到 [-1439, 2879] 这种越界区间：
  // 「整体后移 30 分钟」加在 23:50 的课上就跨到了第二天。
  // 日期必须跟着走，否则会导出 `T2410` 这种非法时间戳。
  final start = _normalize(s.date, s.startMinute);
  final duration = s.endMinute - s.startMinute;
  final end = _normalize(start.date, start.minute + duration);

  final lines = <String>[
    'BEGIN:VEVENT',
    // UID 只取内容的哈希而非数据库 id：同一个课表在换台设备、
    // 重新导入之后应当得到同样的 UID，别的日历才不会当成两节课。
    _text('UID', '${_fnv1a('${s.title}|${_ymd(start.date)}'
        '|${s.startMinute}|${s.teacher}|${s.location}')}@classcal'),
    'DTSTAMP:$stamp',
    'DTSTART:${_stamp(start.date, start.minute)}',
    'DTEND:${_stamp(end.date, end.minute)}',
    _text('SUMMARY', s.title),
  ];

  if (s.location.isNotEmpty) lines.add(_text('LOCATION', s.location));
  if (s.teacher.isNotEmpty) lines.add(_text(kXTeacher, s.teacher));
  if (s.colorHex != null) lines.add(_text(kXColor, s.colorHex!));

  // 节次是网格的行号，别的日历不关心，但少写它我们自己的往返就得多做一次
  // 「按时间反推节次」的 15 分钟容差猜测 —— 能精确就别猜。
  //
  // **但只有在钟点确实落在这个节次的作息时间上时才写。** 被套级平移推走
  // 20 分钟的课已经不在「第 1-2 节」那个钟点上了，硬写等于撒谎：
  // 导入方会以为它 08:00 才开始，把平移量悄悄抹掉。
  if (_matchesNominalSlot(s)) {
    lines.add('$kXPeriods:${s.startPeriod}-${s.endPeriod}');
  }

  // 这里的周次措辞刻意不带 `周次：` 前缀 —— 那个前缀是教务系统的格式，
  // 也是我们自己解析器的匹配串（`_weeksFromDescription`）。写成
  // `周次：5` 会让整份导出文件在重新导入时走上「交叉推算锚点」那条路，
  // 而锚点明明已经写在日历层级了。
  final desc = <String>[
    if (s.teacher.isNotEmpty) '教师：${s.teacher}',
    if (s.week > 0) '第 ${s.week} 周',
    if (s.note.isNotEmpty) s.note,
  ];
  if (desc.isNotEmpty) lines.add(_text('DESCRIPTION', desc.join('\n')));

  lines.add('END:VEVENT');
  return lines;
}

/// 上课钟点是否正好是该节次作息表里的起止时刻。
bool _matchesNominalSlot(ResolvedSession s) {
  if (s.startPeriod == null || s.endPeriod == null) return false;
  final startSlot = slotForStartPeriod(s.startPeriod!);
  final endSlot = slotForPeriod(s.endPeriod!);
  if (startSlot == null || endSlot == null) return false;
  return s.startMinute == startSlot.startMinute && s.endMinute == endSlot.endMinute;
}

({DateTime date, int minute}) _normalize(DateTime date, int minute) {
  var d = dateOnly(date);
  var m = minute;
  while (m < 0) {
    m += 1440;
    d = d.subtract(const Duration(days: 1));
  }
  while (m >= 1440) {
    m -= 1440;
    d = d.add(const Duration(days: 1));
  }
  return (date: d, minute: m);
}

/// `NAME:VALUE` 或 `NAME;PARAM=V:VALUE`，值按 RFC 5545 转义。
String _text(String name, String value, {Map<String, String>? params}) {
  final buf = StringBuffer(name);
  params?.forEach((k, v) => buf.write(';$k=$v'));
  buf.write(':${_escape(value)}');
  return buf.toString();
}

/// TEXT 值的转义。**反斜杠必须最先替换**，否则后面替换出来的反斜杠
/// （比如 `\,` 的 `\`）会被再转义一次，变成 `\\,`。
String _escape(String v) => v
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll(',', r'\,')
    .replaceAll(';', r'\;');

String _stamp(DateTime d, int minute) =>
    '${d.year}${_pad(d.month)}${_pad(d.day)}T${_pad(minute ~/ 60)}${_pad(minute % 60)}00';

String _utcStamp(DateTime d) {
  final u = d.toUtc();
  return '${u.year}${_pad(u.month)}${_pad(u.day)}T'
      '${_pad(u.hour)}${_pad(u.minute)}${_pad(u.second)}Z';
}

String _pad(int n) => n.toString().padLeft(2, '0');

String _ymd(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

/// 折行到每行 **75 个八位组**以内，续行以单个空格开头。
///
/// 必须按字节而不是按字符数折：中文一个字 3 字节，按字符数折会写出
/// 长达 225 字节的「行」，有些解析器直接拒收整个文件。折点也不能落在
/// 多字节字符中间，否则解出来就是乱码。
List<String> _fold(List<String> lines) {
  final out = <String>[];
  for (final line in lines) {
    if (utf8.encode(line).length <= 75) {
      out.add(line);
      continue;
    }
    var buf = StringBuffer();
    var bytes = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final n = utf8.encode(ch).length;
      if (bytes + n > 75) {
        out.add(buf.toString());
        // 续行的行首空格本身占一个字节，也要算进这 75 里
        buf = StringBuffer(' ');
        bytes = 1;
      }
      buf.write(ch);
      bytes += n;
    }
    if (buf.isNotEmpty) out.add(buf.toString());
  }
  return out;
}

/// FNV-1a 32 位。用哈希而不是拼接原文，是为了让 UID 短且不含需要转义的字符。
String _fnv1a(String input) {
  var hash = 0x811c9dc5;
  for (final b in utf8.encode(input)) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
