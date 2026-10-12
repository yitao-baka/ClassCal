import 'package:classcal/data/import/ics_import.dart';
import 'package:classcal/data/model/resolve.dart';
import 'package:flutter_test/flutter_test.dart';

/// 样例刻意复刻本机那份教务系统导出文件的形态：
/// * `DTSTART;TZID=Asia/Shanghai:...` —— 带时区参数，值里没有 `Z`
/// * `DESCRIPTION` 里既有 `教师：` 又有 `周次：`，且**被折行**
///   （中文一个字 3 字节，摘要稍长就必然触发 75 字节折行）
/// * 同一门课每次上课各占一个 VEVENT
const String sampleIcs = r'''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//HNUST//课表转换器//CN
BEGIN:VTIMEZONE
TZID:Asia/Shanghai
BEGIN:STANDARD
DTSTART:19700101T000000
TZOFFSETFROM:+0800
TZOFFSETTO:+0800
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
UID:c0ac1ef0da7e4b29@hnust.local
DTSTAMP:20261009T093528Z
DTSTART;TZID=Asia/Shanghai:20261116T080000
DTEND;TZID=Asia/Shanghai:20261116T094000
SUMMARY:C语言程序设计实验
LOCATION:逸夫楼535(操作系统实验室)
DESCRIPTION:教师：陈燕晖\n周次：11-14([周])[01-02节]\n节次：第
 一二节
END:VEVENT
BEGIN:VEVENT
UID:376fe48380555cf9@hnust.local
DTSTAMP:20261009T093528Z
DTSTART;TZID=Asia/Shanghai:20261123T080000
DTEND;TZID=Asia/Shanghai:20261123T094000
SUMMARY:C语言程序设计实验
LOCATION:逸夫楼535(操作系统实验室)
DESCRIPTION:教师：陈燕晖\n周次：11-14([周])[01-02节]\n节次：第
 一二节
END:VEVENT
BEGIN:VEVENT
UID:aaa@hnust.local
DTSTAMP:20261009T093528Z
DTSTART;TZID=Asia/Shanghai:20261118T100000
DTEND;TZID=Asia/Shanghai:20261118T114000
SUMMARY:大学外语(3)
LOCATION:外语楼201
DESCRIPTION:教师：王五\n周次：11-14([周])[03-04节]\n节次：第三四节
END:VEVENT
BEGIN:VEVENT
UID:bbb@hnust.local
DTSTAMP:20261009T093528Z
DTSTART;TZID=Asia/Shanghai:20261119T123000
DTEND;TZID=Asia/Shanghai:20261119T133000
SUMMARY:临时讲座
LOCATION:图书馆
DESCRIPTION:不在任何节次上
END:VEVENT
END:VCALENDAR
''';

void main() {
  group('从教务系统 ICS 重建课程规则', () {
    final r = importIcs(sampleIcs, sourceName: '学生个人课表_.xls');

    test('同一门课的多次上课被归并成一条规则，周次合并', () {
      final c = r.set.templates.where((t) => t.title == 'C语言程序设计实验').single;
      expect(c.weeks, [11, 12]);
      expect(c.weekday, DateTime.monday);
      expect(c.startPeriod, 1);
      expect(c.endPeriod, 2);
      expect(c.location, '逸夫楼535(操作系统实验室)');
    });

    test('教师从折行后的 DESCRIPTION 里正确取出', () {
      final c = r.set.templates.where((t) => t.title == 'C语言程序设计实验').single;
      // 折行发生在「节次：第」和「一二节」之间，教师那行在折行之前
      expect(c.teacher, '陈燕晖');
      expect(r.set.templates.where((t) => t.title == '大学外语(3)').single.teacher, '王五');
    });

    test('不同课程各自成组，互不串台', () {
      expect(r.set.templates.length, 2);
      final w = r.set.templates.where((t) => t.title == '大学外语(3)').single;
      expect(w.weekday, DateTime.wednesday);
      expect(w.startPeriod, 3);
      expect(w.endPeriod, 4);
      expect(w.weeks, [11]);
    });

    test('第 1 周周一由「事件日期 + 描述里的周次」交叉推算得出', () {
      // 2026-11-16 是第 11 周周一 → 第 1 周周一 = 2026-09-07
      expect(r.week1Monday, DateTime(2026, 9, 7));
      expect(r.week1Inferred, isTrue); // 文件里没写，是推算的，向导要让用户确认
    });

    test('交叉推算命中时的提示，措辞必须区别于「硬猜最早事件」那条', () {
      // 两条路径都会让 week1Inferred 为真、都要弹确认框，但可信度差着量级：
      // 一条是几十条事件投票一致的交叉验证，一条是纯猜。
      // 提示语如果混用，用户就分不出「大概没问题」和「大概率是错的」。
      final w = r.warnings.singleWhere((s) => s.contains('第 1 周周一'));
      expect(w, contains('交叉推算'));
      expect(w, isNot(contains('无法从文件推算周次起点')));
    });

    test('对不上任何节次的事件降级成单次事件，不丢数据', () {
      expect(r.unmatchedCount, 1);
      final o = r.set.oneOffs.single;
      expect(o.title, '临时讲座');
      expect(o.startMinute, 12 * 60 + 30);
      expect(o.endMinute, 13 * 60 + 30);
    });

    test('事件总数统计正确', () {
      expect(r.eventCount, 4);
    });

    test('重建出来的课表能直接解析 —— 第 11 周网格有三节课', () {
      final out = resolveSessions(
        shifts: r.set.shifts,
        templates: r.set.templates,
        oneOffs: const [],
        overrides: const [],
      );
      final w11Monday = DateTime(2026, 11, 16);
      final inWeek = out.sessions.where((s) => s.week == 11).toList();
      // 周一 C语言、周三 大学外语
      expect(inWeek.length, 2);
      expect(
        inWeek.map((s) => s.title).toList()..sort(),
        ['C语言程序设计实验', '大学外语(3)'],
      );
      expect(inWeek.first.date.isAfter(w11Monday.subtract(const Duration(days: 1))), isTrue);
    });
  });

  group('X-CLASSCAL 属性优先（我们自己的导出）', () {
    const ours = r'''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:x@classcal
DTSTART:20261005T100000
DTEND:20261005T114000
SUMMARY:数据结构
LOCATION:三教301
X-CLASSCAL-WEEKS:5,7,9
X-CLASSCAL-PERIODS:3-4
X-CLASSCAL-TEACHER:李四
X-CLASSCAL-WEEK1MONDAY:2026-09-07
END:VEVENT
END:VCALENDAR
''';

    test('周次直接取属性里的完整集合，不必逐次累加', () {
      final r = importIcs(ours);
      final t = r.set.templates.single;
      // 单双周这种不连续周次，靠日期反推是拼不出来的
      expect(t.weeks, [5, 7, 9]);
      expect(t.title, '数据结构');
      expect(t.teacher, '李四');
      expect(t.startPeriod, 3);
      expect(t.endPeriod, 4);
    });

    test('锚点取自属性，不再推算', () {
      final r = importIcs(ours);
      expect(r.week1Monday, DateTime(2026, 9, 7));
      expect(r.week1Inferred, isFalse);
    });

    test('调用方指定的锚点优先级最高', () {
      final r = importIcs(ours, week1Monday: DateTime(2026, 9, 14));
      expect(r.week1Monday, DateTime(2026, 9, 14));
      expect(r.week1Inferred, isFalse);
    });

    test('自己导出的 ICS 往返后周次结构不变', () {
      final a = importIcs(ours);
      expect(a.set.templates.single.weeks, [5, 7, 9]);
      expect(a.warnings.where((w) => w.contains('周次')), isEmpty);
    });
  });

  group('边界情形', () {
    test('空日历不炸，返回空课表', () {
      final r = importIcs('BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n');
      expect(r.set.templates, isEmpty);
      expect(r.set.oneOffs, isEmpty);
      expect(r.eventCount, 0);
    });

    test('全天事件留成单次事件，不参与节次匹配', () {
      const allDay = r'''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:d@x
DTSTART;VALUE=DATE:20261116
SUMMARY:校运会
END:VEVENT
END:VCALENDAR
''';
      final r = importIcs(allDay);
      expect(r.set.templates, isEmpty);
      expect(r.set.oneOffs.single.title, '校运会');
      expect(r.set.oneOffs.single.startMinute, 0);
      expect(r.set.oneOffs.single.endMinute, 24 * 60);
    });

    test('既无属性也无周次描述时，退回最早事件并明确告警', () {
      const bare = r'''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:e@x
DTSTART:20261005T080000
SUMMARY:未知来源课程
END:VEVENT
END:VCALENDAR
''';
      final r = importIcs(bare);
      expect(r.week1Inferred, isTrue);
      expect(
        r.warnings.any((w) => w.contains('无法从文件推算周次起点')),
        isTrue,
      );
      // 兜底锚点 = 最早事件所在周的周一
      expect(r.week1Monday, DateTime(2026, 10, 5));
    });
  });
}
