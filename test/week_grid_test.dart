import 'package:classcal/core/time/periods.dart';
import 'package:classcal/data/import/ics_import.dart';
import 'package:classcal/data/model/resolve.dart';
import 'package:classcal/features/timetable/week_grid.dart';
import 'package:flutter_test/flutter_test.dart';

/// 网格落位的单元测试。
///
/// 断的是「哪一格」而不是像素：像素断言会被 padding、字号、屏幕尺寸牵着走，
/// 一改样式就红，久而久之就没人看了。格子对不对才是真正要钉的东西。

final DateTime kWeek1 = DateTime(2026, 9, 7);

ResolvedSession session({
  required String title,
  required int weekday,
  required int startPeriod,
  required int endPeriod,
  DateTime? date,
}) =>
    ResolvedSession(
      date: date ?? DateTime(2026, 9, 7),
      startMinute: 8 * 60,
      endMinute: 9 * 60 + 40,
      title: title,
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
    );

/// 一条手动添加的单次事件：只有钟点，没有节次。
ResolvedSession oneOff({
  required String title,
  required int weekday,
  required int startMinute,
  required int endMinute,
}) =>
    ResolvedSession(
      date: DateTime(2026, 9, 7),
      startMinute: startMinute,
      endMinute: endMinute,
      title: title,
      weekday: weekday,
      oneOffId: 1,
    );

void main() {
  group('落位', () {
    test('周一的课在第 0 列，第一二节在第 0 行', () {
      final p = layoutWeekGrid([
        session(title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2),
      ]).single;
      expect(p.col, 0);
      expect(p.row, 0);
      expect(p.span, 1);
      expect(p.lanes, 1);
    });

    test('周日第九十节落在第 6 列第 4 行', () {
      final p = layoutWeekGrid([
        session(title: 'A', weekday: 7, startPeriod: 9, endPeriod: 10),
      ]).single;
      expect(p.col, 6);
      expect(p.row, 4);
    });

    test('1-4 节连上的课纵向跨两行', () {
      final p = layoutWeekGrid([
        session(title: '连堂课', weekday: 3, startPeriod: 1, endPeriod: 4),
      ]).single;
      expect(p.row, 0);
      expect(p.span, 2);
    });

    test('单次事件按开始钟点落进所在的大节，不再是「存完就消失」', () {
      // 这里以前断言的是 `isEmpty`，而那份断言正是漏掉的那条路：从网格上
      // 「新增单次事件」（那一步还特意把日期预填成用户正看着的那一周）存完，
      // 屏幕上什么也不多，而且此后没有任何入口能再点开它。
      final p = layoutWeekGrid([
        oneOff(
          title: '讲座',
          weekday: 2,
          startMinute: 14 * 60 + 30,
          endMinute: 14 * 60 + 40,
        ),
      ]).single;

      expect(p.col, 1);
      expect(p.row, 2, reason: '14:30 落在 14:00–15:40 这一大节里');
      expect(p.span, 1, reason: '没有节次就跨不到第二行去');
    });

    test('课间和午休的单次事件归到最近的那一节，而不是消失', () {
      // 12:00 在上午最后一节（11:40 下课）和下午第一节（14:00 上课）之间，
      // 离前者近。12:50 是正中间，取更早的那一节。
      final twelve = layoutWeekGrid([
        oneOff(title: '交作业', weekday: 2, startMinute: 12 * 60, endMinute: 12 * 60 + 10),
      ]).single;
      expect(twelve.row, 1);

      final half = layoutWeekGrid([
        oneOff(title: '正中间', weekday: 2, startMinute: 12 * 60 + 50, endMinute: 13 * 60),
      ]).single;
      expect(half.row, 1);
    });

    test('清早、深夜的单次事件不上网格 —— 网格压根没画到那些钟点', () {
      final p = layoutWeekGrid([
        oneOff(title: '赶火车', weekday: 2, startMinute: 5 * 60, endMinute: 6 * 60),
        oneOff(title: '夜谈', weekday: 2, startMinute: 22 * 60, endMinute: 23 * 60),
      ]);
      expect(p, isEmpty);
    });

    test('单次事件和同格的课分栏，谁也不盖住谁', () {
      final placed = layoutWeekGrid([
        oneOff(
          title: '讲座',
          weekday: 2,
          startMinute: 14 * 60 + 30,
          endMinute: 14 * 60 + 40,
        ),
        session(title: '大学体育(1)', weekday: 2, startPeriod: 5, endPeriod: 6),
      ]);
      expect(placed.map((p) => p.lanes).toSet(), {2});
      expect(placed.map((p) => p.row).toSet(), {2});
    });

    test('没有节次又不是单次事件的条目仍然不上网格', () {
      final p = layoutWeekGrid([
        session(title: '没节次', weekday: 2, startPeriod: 5, endPeriod: 6)
            .copyWith(startPeriod: null, endPeriod: null),
      ]);
      expect(p, isEmpty);
    });

    test('作息表里不存在的节次也不上网格，而不是硬塞进某一行', () {
      final p = layoutWeekGrid([
        session(title: '外校课', weekday: 1, startPeriod: 11, endPeriod: 12),
      ]);
      expect(p, isEmpty);
    });
  });

  group('同格重叠分栏', () {
    test('两门课在同一格时各占一栏', () {
      final placed = layoutWeekGrid([
        session(title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2),
        session(title: 'B', weekday: 1, startPeriod: 1, endPeriod: 2),
      ]);
      expect(placed.length, 2);
      expect(placed.map((p) => p.lanes).toSet(), {2});
      expect(placed.map((p) => p.lane).toSet(), {0, 1});
      // 不能重叠在同一栏里
      for (final p in placed) {
        expect(p.col, 0);
        expect(p.row, 0);
      }
    });

    test('同一格三门课分三栏', () {
      final placed = layoutWeekGrid([
        session(title: 'A', weekday: 4, startPeriod: 3, endPeriod: 4),
        session(title: 'B', weekday: 4, startPeriod: 3, endPeriod: 4),
        session(title: 'C', weekday: 4, startPeriod: 3, endPeriod: 4),
      ]);
      expect(placed.length, 3);
      expect(placed.map((p) => p.lanes).toSet(), {3});
    });

    test('同一列不同行的课互不影响，不触发分栏', () {
      final placed = layoutWeekGrid([
        session(title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2),
        session(title: 'B', weekday: 1, startPeriod: 5, endPeriod: 6),
      ]);
      expect(placed.map((p) => p.lanes).toSet(), {1});
      expect(placed.map((p) => p.row).toSet(), {0, 2});
    });

    test('分栏按开始时间排序，早的排左边 —— 位置稳定，不会每次重建换位', () {
      final placed = layoutWeekGrid([
        session(title: '晚', weekday: 1, startPeriod: 1, endPeriod: 2)
            .copyWith(startMinute: 10 * 60),
        session(title: '早', weekday: 1, startPeriod: 1, endPeriod: 2)
            .copyWith(startMinute: 8 * 60),
      ]);
      final laneOf = {for (final p in placed) p.session.title: p.lane};
      expect(laneOf['早'], 0);
      expect(laneOf['晚'], 1);
    });
  });

  group('停课的幽灵块', () {
    ResolvedSession ghost({int weekday = 1, int startPeriod = 1}) =>
        ResolvedSession(
          date: DateTime(2026, 9, 7),
          startMinute: 8 * 60,
          endMinute: 9 * 60 + 40,
          title: '停掉的课',
          weekday: weekday,
          startPeriod: startPeriod,
          endPeriod: startPeriod + 1,
          cancelled: true,
        );

    test('停课那次仍然落位 —— 块留在网格上才有地方点「撤销停课」', () {
      final placed = layoutWeekGrid([ghost()]);
      expect(placed.length, 1);
      expect(placed.single.session.cancelled, isTrue);
      expect(placed.single.col, 0);
      expect(placed.single.row, 0);
    });

    test('不参与分栏：同格那节真要去上的课照样占满整格', () {
      final placed = layoutWeekGrid([
        ghost(),
        session(title: '照常上', weekday: 1, startPeriod: 1, endPeriod: 2),
      ]);
      final real = placed.singleWhere((p) => !p.session.cancelled);
      expect(real.lanes, 1, reason: '被一节不上的课挤成半栏，等于为了幽灵牺牲实体');
      expect(real.lane, 0);
    });

    test('幽灵排在前面 —— Stack 后画的盖先画的，实体压在上面', () {
      final placed = layoutWeekGrid([
        session(title: '照常上', weekday: 1, startPeriod: 1, endPeriod: 2),
        ghost(),
      ]);
      expect(placed.first.session.cancelled, isTrue);
      expect(placed.last.session.cancelled, isFalse);
    });
  });

  group('空位点击区', () {
    test('没有课时整张网格都可点，共 7 列 × 节次行数', () {
      final free = freeSlots(const []);
      expect(free.length, 7 * kPeriodRowCount);
      expect(free.first.weekday, 1);
      expect(free.first.row, 0);
      expect(free.first.startPeriod, 1);
      expect(free.last.weekday, 7);
      expect(free.last.startPeriod, kPeriodSlots.last.startPeriod);
    });

    test('有课的那一格不再可选', () {
      final placed = layoutWeekGrid([
        session(title: 'A', weekday: 3, startPeriod: 1, endPeriod: 2),
      ]);
      final free = freeSlots(placed);
      expect(
        free.any((s) => s.weekday == 3 && s.row == 0),
        isFalse,
      );
      expect(free.length, 7 * kPeriodRowCount - 1);
    });

    test('连堂课跨的两行都算被占 —— 只看起始行会叠出第二门课', () {
      final placed = layoutWeekGrid([
        session(title: '连堂', weekday: 1, startPeriod: 1, endPeriod: 4),
      ]);
      final free = freeSlots(placed);
      expect(free.any((s) => s.weekday == 1 && s.row == 0), isFalse);
      expect(free.any((s) => s.weekday == 1 && s.row == 1), isFalse);
      expect(free.any((s) => s.weekday == 1 && s.row == 2), isTrue);
    });

    test('停课的幽灵块也算被占 —— 那一格本来就有一门课', () {
      final placed = layoutWeekGrid([
        ResolvedSession(
          date: DateTime(2026, 9, 7),
          startMinute: 8 * 60,
          endMinute: 9 * 60 + 40,
          title: '停掉的课',
          weekday: 5,
          startPeriod: 1,
          endPeriod: 2,
          cancelled: true,
        ),
      ]);
      expect(freeSlots(placed).any((s) => s.weekday == 5 && s.row == 0), isFalse);
    });
  });

  group('尺寸常量', () {
    test('行数等于大节数量', () {
      expect(kPeriodRowCount, 5);
    });
  });

  group('与真实导入结果连起来', () {
    test('第 5 周网格：周一第一节空着，周三第一节是大学外语', () {
      const ics = r'''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:a@x
DTSTART:20261007T080000
DTEND:20261007T094000
SUMMARY:大学外语(1)
LOCATION:第三教学楼413
X-CLASSCAL-WEEKS:5,6,7
X-CLASSCAL-PERIODS:1-2
X-CLASSCAL-WEEK1MONDAY:2026-09-07
END:VEVENT
END:VCALENDAR
''';
      final r = importIcs(ics);
      final all = resolveSessions(
        shifts: r.set.shifts,
        templates: r.set.templates,
        oneOffs: r.set.oneOffs,
        overrides: const [],
      ).sessions;

      final placed = layoutWeekGrid(sessionsInWeek(all, 5));
      expect(placed.length, 1);
      expect(placed.single.col, 2); // 周三
      expect(placed.single.row, 0); // 第一二节
      expect(placed.single.session.title, '大学外语(1)');
    });

    test('第 5 周与第 7 周各自独立 —— 筛周之后互不串场', () {
      const ics = r'''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:a@x
DTSTART:20261007T080000
DTEND:20261007T094000
SUMMARY:大学外语(1)
X-CLASSCAL-WEEKS:5,7
X-CLASSCAL-PERIODS:1-2
X-CLASSCAL-WEEK1MONDAY:2026-09-07
END:VEVENT
END:VCALENDAR
''';
      final r = importIcs(ics);
      final all = resolveSessions(
        shifts: r.set.shifts,
        templates: r.set.templates,
        oneOffs: r.set.oneOffs,
        overrides: const [],
      ).sessions;

      expect(sessionsInWeek(all, 5).length, 1);
      expect(sessionsInWeek(all, 6), isEmpty); // 单双周之间那周确实没课
      expect(sessionsInWeek(all, 7).length, 1);
    });
  });
}
