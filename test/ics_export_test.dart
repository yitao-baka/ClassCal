import 'dart:convert';
import 'dart:io';

import 'package:classcal/data/exchange/ics_export.dart';
import 'package:classcal/data/import/ics.dart';
import 'package:classcal/data/import/ics_import.dart';
import 'package:classcal/data/model/resolve.dart';
import 'package:flutter_test/flutter_test.dart';

/// ICS 导出的测试。
///
/// 核心是**往返**：导出再导入，解析出来的上课时刻必须逐条相同。
/// 这比断言导出的文本长什么样稳定得多 —— 文本格式可以改（加属性、调折行），
/// 但只要用户看到的课表没变，测试就不该红。

/// 「拿真实课表验一遍」那一组用的文件。
///
/// **这个文件不在仓库里** —— 它是从教务系统导出的真实课表（真实教室、
/// 真实老师姓名），进公开仓库不合适，所以在 `.gitignore` 里。本地有就跑，
/// 没有就整组跳过。
const String _realTimetablePath = 'test/fixtures/timetable_2026-2027-1.ics';

/// 在**收集测试的时候**（不是执行的时候）判一次，`group` 的 `skip` 参数要的
/// 就是这样一颗在收集期就定下来的值。
final bool _hasRealTimetable = File(_realTimetablePath).existsSync();

/// 跳过时打出来的理由。
const String _skipRealTimetable = '真实课表不在仓库里（见 test/fixtures/README.md）';

CalendarSetData setOf({
  String name = '测试课表',
  DateTime? week1Monday,
  int weekShift = 0,
  int timeShiftMinutes = 0,
  List<CourseTemplate> templates = const [],
  List<OneOffData> oneOffs = const [],
  List<OverrideData> overrides = const [],
}) =>
    CalendarSetData(
      id: 1,
      name: name,
      shifts: SetShifts(
        week1Monday: week1Monday ?? DateTime(2026, 9, 7),
        weekShift: weekShift,
        timeShiftMinutes: timeShiftMinutes,
      ),
      templates: templates,
      oneOffs: oneOffs,
      overrides: overrides,
    );

CourseTemplate tpl({
  int id = 1,
  String title = '大学外语(1)',
  int weekday = 3,
  int startPeriod = 1,
  int endPeriod = 2,
  List<int> weeks = const [5, 6, 7],
  String teacher = '张三',
  String location = '第三教学楼413',
  String note = '',
  String? colorHex,
}) =>
    CourseTemplate(
      id: id,
      title: title,
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: weeks,
      teacher: teacher,
      location: location,
      note: note,
      colorHex: colorHex,
    );

List<ResolvedSession> resolve(CalendarSetData set) => resolveSessions(
      shifts: set.shifts,
      templates: set.templates,
      oneOffs: set.oneOffs,
      overrides: set.overrides,
    ).sessions;

/// 把一次上课压成可比较的元组 —— 用 `toString` 比对会把 `DateTime` 的具体
/// 实现细节扯进来，逐字段列出来才知道到底哪里不一样。
List<String> signature(List<ResolvedSession> ss) => ss
    .map((s) => '${_d(s.date)}|${s.startMinute}-${s.endMinute}|${s.title}'
        '|${s.teacher}|${s.location}|${s.weekday}|${s.startPeriod}-${s.endPeriod}')
    .toList()
  ..sort();

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 只比对用户看得见的东西：哪天、几点到几点、什么课、在哪。
///
/// 平移过或被改期的课在 ICS 里只能保住这些。原因是**格式的信息量上限**，
/// 不是实现没做到：ICS 里没有「第几大节」这个概念，节次是我们自己的网格行号。
/// 一门被挪到 14:00 的课导出后就是「那天 14:00 有节课」，重新导入时只能按
/// 钟点反推节次 —— 而它本来就不在课表的节次网格上了。要连结构一起保住，
/// 得用 JSON 备份。
List<String> visual(List<ResolvedSession> ss) => ss
    .map((s) => '${_d(s.date)}|${s.startMinute}-${s.endMinute}|${s.title}|${s.location}')
    .toList()
  ..sort();

/// 导出再导入，返回第二次解析出的课表。
CalendarSetData roundTrip(CalendarSetData set) {
  final ics = exportIcs([set]);
  return importIcs(ics).set;
}

void main() {
  group('往返无损', () {
    test('一门课导出再导入，日期 / 时间 / 节次逐条相同', () {
      final before = setOf(templates: [tpl()]);
      final after = roundTrip(before);
      expect(signature(resolve(after)), signature(resolve(before)));
    });

    test('多门课、不连续周次（单双周）也保持', () {
      final before = setOf(
        templates: [
          tpl(id: 1, title: '大学外语(1)', weeks: [5, 7, 9]),
          tpl(id: 2, title: '高等数学A(1)', weekday: 1, startPeriod: 3, endPeriod: 4, weeks: [5, 6, 7, 8]),
          tpl(id: 3, title: '大学体育(1)', weekday: 4, startPeriod: 5, endPeriod: 6, weeks: [6]),
        ],
      );
      final after = roundTrip(before);
      expect(signature(resolve(after)), signature(resolve(before)));
      // 单双周不能因为归并而被填成连续周
      final weeks = resolve(after).map((s) => s.week).toSet();
      expect(weeks.contains(6) || weeks.contains(8), isTrue);
      expect(resolve(after).where((s) => s.title == '大学外语(1)').length, 3);
    });

    test('手动添加的单次事件也往返', () {
      final before = setOf(
        oneOffs: [
          OneOffData(
            id: 1,
            title: '临时讲座',
            date: DateTime(2026, 10, 8),
            startMinute: 12 * 60 + 30,
            endMinute: 13 * 60 + 30,
            location: '图书馆报告厅',
          ),
        ],
      );
      final after = roundTrip(before);
      expect(signature(resolve(after)), signature(resolve(before)));
    });

    test('单次改期后导出的就是新时间，不是原时间', () {
      final before = setOf(
        week1Monday: DateTime(2026, 9, 7),
        templates: [tpl(weeks: [5])],
        overrides: [
          OverrideData(
            ruleId: 1,
            originalDate: DateTime(2026, 10, 7), // 第 5 周周三
            newDate: DateTime(2026, 10, 8),
            newStartMinute: 14 * 60,
            newEndMinute: 15 * 60 + 40,
          ),
        ],
      );
      final after = roundTrip(before);
      expect(visual(resolve(after)), visual(resolve(before)));
      expect(resolve(after).single.date, DateTime(2026, 10, 8));
      expect(resolve(after).single.startMinute, 14 * 60);
    });

    test('被停掉的那一次不导出 —— 导出的是「实际会发生的样子」', () {
      final before = setOf(
        templates: [tpl(weeks: [5, 6, 7])],
        overrides: [
          OverrideData(
            ruleId: 1,
            originalDate: DateTime(2026, 10, 7), // 第 6 周
            cancelled: true,
          ),
        ],
      );
      // 解析结果里有 3 条（停课那条带着 cancelled 留着，好让 UI 能撤销），
      // 但导出的文件里只应有 2 条。
      expect(resolve(before).length, 3);
      expect(resolve(before).where((s) => s.cancelled).length, 1);

      final after = roundTrip(before);
      expect(resolve(after).length, 2);
      expect(resolve(after).any((s) => s.cancelled), isFalse);
      expect(signature(resolve(after)),
          signature(resolve(before).where((s) => !s.cancelled).toList()));
    });
  });

  group('套级平移被烘焙进日期', () {
    test('后移一周后导出的日期就晚 7 天，再导入是「没平移但日期一致」', () {
      final before = setOf(templates: [tpl(weeks: [5])], weekShift: 1);
      final target = resolve(before).single.date;

      final after = roundTrip(before);
      expect(after.shifts.weekShift, 0); // 偏移量不写进 ICS
      expect(resolve(after).single.date, target); // 但看得到的日期一样
      expect(target, DateTime(2026, 10, 14)); // 9/30 + 7 天
    });

    test('分钟级平移后钟点保住，偏移量本身不写进 ICS', () {
      final before = setOf(templates: [tpl(weeks: [5])], timeShiftMinutes: 20);
      final after = roundTrip(before);
      expect(after.shifts.timeShiftMinutes, 0);
      expect(resolve(after).single.startMinute, 8 * 60 + 20);
      expect(resolve(after).single.endMinute, 10 * 60);
    });

    test('平移后不再落在节次的钟点上，就不再声称它是那一节', () {
      // 08:20 不是「第 1-2 节」的 08:00。若导出时照旧写
      // X-CLASSCAL-PERIODS:1-2，导入方会把它拉回 08:00，平移量被悄悄抹掉。
      final ics = exportIcs([
        setOf(templates: [tpl(weeks: [5])], timeShiftMinutes: 20),
      ]);
      expect(ics.contains('X-CLASSCAL-PERIODS'), isFalse);
    });

    test('平移到跨天：第 5 节后移 10 小时后落回次日凌晨，日期要跟着走', () {
      // 14:00 后移 700 分钟 → 次日 01:40。若只改时分不改日期，
      // 会导出 `T2540` 这种时间戳，导入方直接解析失败。
      final ics = exportIcs([
        setOf(
          templates: [tpl(weekday: 3, startPeriod: 5, endPeriod: 6, weeks: [5])],
          timeShiftMinutes: 700,
        ),
      ]);
      expect(ics.contains('T254000'), isFalse); // 没有非法时间戳

      final s = resolve(importIcs(ics).set).single;
      expect(s.startMinute, 100); // 01:40
      expect(s.endMinute, 200); // 03:20
      expect(s.date, DateTime(2026, 10, 8)); // 10/7 → 10/8
    });
  });

  group('文件格式', () {
    test('每个物理行不超过 75 字节，且不切断多字节字符', () {
      final ics = exportIcs([
        setOf(templates: [tpl(title: '毛泽东思想和中国特色社会主义理论体系概论专题研讨课', location: '第四教学楼多媒体阶梯教室')]),
      ]);

      for (final line in const LineSplitter().convert(ics)) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: '行超长：$line');
        // 折行若切在多字节字符中间，解出来必是 U+FFFD
        expect(line.contains('�'), isFalse, reason: '折行切断了字符：$line');
      }
    });

    test('折行后的文本展开回去和原值一致', () {
      const title = '毛泽东思想和中国特色社会主义理论体系概论专题研讨课';
      final ics = exportIcs([
        setOf(templates: [tpl(title: title, note: '')]),
      ]);
      final parsed = parseIcs(ics);
      expect(parsed.events.first.summary, title);
    });

    test('逗号 / 分号 / 反斜杠 / 换行都按 RFC 5545 转义且能还原', () {
      const nasty = r'甲,乙;丙\d';
      const withNewline = '第一行\n第二行';
      final ics = exportIcs([
        setOf(templates: [tpl(title: nasty, note: withNewline)]),
      ]);
      final parsed = parseIcs(ics);
      expect(parsed.events.first.summary, nasty);
      expect(parsed.events.first.xProps.containsKey('X-CLASSCAL-PERIODS'), isTrue);
    });

    test('用 CRLF 换行 —— RFC 5545 的硬性要求', () {
      final ics = exportIcs([setOf(templates: [tpl()])]);
      expect(ics.contains('\r\n'), isTrue);
      expect(ics.replaceAll('\r\n', '').contains('\n'), isFalse);
    });

    test('空课表也能导出一个结构合法的文件', () {
      final ics = exportIcs([setOf(templates: const [])]);
      expect(ics.contains('BEGIN:VCALENDAR'), isTrue);
      expect(ics.contains('END:VCALENDAR'), isTrue);
      expect(ics.contains('BEGIN:VEVENT'), isFalse);
      expect(importIcs(ics).set.templates, isEmpty);
    });

    test('UID 稳定：同样的内容导出两次得到同样的 UID', () {
      final a = exportIcs([setOf(templates: [tpl()], name: '甲')]);
      final b = exportIcs([setOf(templates: [tpl()], name: '甲')]);
      String uidOf(String s) =>
          s.split('\r\n').firstWhere((l) => l.startsWith('UID:'));
      expect(uidOf(a), uidOf(b));
    });
  });

  group('拿真实课表验一遍', () {
    late String source;
    late CalendarSetData fromSchool;

    setUpAll(() {
      source = File(_realTimetablePath).readAsStringSync();
      fromSchool = importIcs(source, sourceName: '教务系统').set;
    });

    test('教务系统那份（23 门课）导出再导入，全部上课时刻不变', () {
      final exported = exportIcs([fromSchool]);
      final back = importIcs(exported).set;

      expect(fromSchool.templates.length, 23);
      expect(signature(resolve(back)), signature(resolve(fromSchool)));
    });

    test('导出后的文件不再需要靠猜锚点 —— X-CLASSCAL-WEEK1MONDAY 直接给出', () {
      final back = importIcs(exportIcs([fromSchool]));
      expect(back.week1Inferred, isFalse);
      expect(back.week1Monday, DateTime(2026, 9, 7));
    });

    test('真实课表的导出文件同样满足 75 字节折行', () {
      final ics = exportIcs([fromSchool]);
      for (final line in const LineSplitter().convert(ics)) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: '行超长：$line');
      }
    });

    test('教师和教室没有在往返中丢失', () {
      // 同一门课可能在不同时段有不同教室（`C语言程序设计` 就有好几处），
      // 所以不能用标题当键 —— 那样只会比到最后一条。按「标题+星期+节次」比。
      String key(CourseTemplate t) =>
          '${t.title}|${t.weekday}|${t.startPeriod}-${t.endPeriod}';
      List<String> detail(List<CourseTemplate> ts) => ts
          .map((t) => '${key(t)}|${t.teacher}|${t.location}')
          .toList()
        ..sort();

      final back = importIcs(exportIcs([fromSchool])).set;
      expect(detail(back.templates), detail(fromSchool.templates));
    });

    test('1-4 节连堂的课：结束时间取第 3-4 大节的末尾，不是第 1-2 节的', () {
      final before = setOf(
        templates: [tpl(weekday: 4, startPeriod: 1, endPeriod: 4, weeks: [5])],
      );
      final s = resolve(before).single;
      expect(s.startMinute, 8 * 60);
      expect(s.endMinute, 11 * 60 + 40);
      expect(signature(resolve(roundTrip(before))), signature(resolve(before)));
    });
  },
      // 有真实课表就跑，没有就整组跳过而不是红 —— 一条因为缺数据而红的测试
      // 会训练人开始忽略红色，那比少跑几条贵得多。
      skip: _hasRealTimetable ? null : _skipRealTimetable);
}
