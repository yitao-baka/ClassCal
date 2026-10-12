import 'package:classcal/data/model/resolve.dart';
import 'package:classcal/core/time/periods.dart';
import 'package:flutter_test/flutter_test.dart';

/// 三层叠加是整个 App 最容易出错的地方，这里逐条钉死。
///
/// 锚点：2026-09-07 是周一，也就是学期第 1 周的周一（已核对）。
/// 于是第 5 周周一是 2026-10-05 —— 正好是验收时要跟教务系统逐格比对的那一周。
final DateTime kWeek1 = DateTime(2026, 9, 7);

/// `DateTime` 不是 const 类型，所以 `SetShifts` 没法写成编译期常量，
/// 只能这样持有一份复用。
final SetShifts kNoShift = SetShifts(week1Monday: kWeek1);

void main() {
  group('锚点自检', () {
    test('2026-09-07 确实是周一，第 5 周周一是 2026-10-05', () {
      expect(kWeek1.weekday, DateTime.monday);
      expect(
        dateFor(week1Monday: kWeek1, week: 5, weekday: 1),
        DateTime(2026, 10, 5),
      );
    });
  });

  group('第一层：模板 × 周次', () {
    test('每个周次各生成一次，日期按 weekday 落位', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(
            id: 1,
            title: '高等数学',
            weekday: 3, // 周三
            startPeriod: 1,
            endPeriod: 2,
            weeks: [1, 2],
          ),
        ],
        oneOffs: const [],
        overrides: const [],
      );

      expect(r.warnings, isEmpty);
      expect(r.sessions.length, 2);
      expect(r.sessions[0].date, DateTime(2026, 9, 9));
      expect(r.sessions[0].week, 1);
      expect(r.sessions[1].date, DateTime(2026, 9, 16));
      expect(r.sessions[1].week, 2);

      // 第一二节 = 08:00–09:40
      expect(r.sessions[0].startMinute, 8 * 60);
      expect(r.sessions[0].endMinute, 9 * 60 + 40);
      expect(r.sessions[0].startPeriod, 1);
    });

    test('作息表里没有的节次会被跳过并记警告，而不是抛异常', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(
            id: 1,
            title: '外校课程',
            weekday: 1,
            startPeriod: 11, // 本作息表最大只到第 10 节
            endPeriod: 12,
            weeks: [1],
          ),
        ],
        oneOffs: const [],
        overrides: const [],
      );

      expect(r.sessions, isEmpty);
      expect(r.warnings.single, contains('外校课程'));
    });

    test('week <= 0 的脏数据被忽略', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(
            id: 1,
            title: 'X',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: [0, -3, 1],
          ),
        ],
        oneOffs: const [],
        overrides: const [],
      );
      expect(r.sessions.length, 1);
    });
  });

  group('第二层：单次覆盖', () {
    test('停课一次 —— 只停这一周，其他周不受影响', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(
            id: 7,
            title: '大学物理',
            weekday: 1,
            startPeriod: 3,
            endPeriod: 4,
            weeks: [1, 2, 3],
          ),
        ],
        oneOffs: const [],
        overrides: [
          OverrideData(
            ruleId: 7,
            originalDate: DateTime(2026, 9, 14), // 第 2 周周一
            cancelled: true,
          ),
        ],
      );

      // 停课的那次**仍然在结果里**，只是带 cancelled 标记 —— 剔除掉的话
      // 网格上就没有这个块了，「撤销停课」再没有入口可点。
      // 谁要「真的没有这节课」，谁自己过滤（导出、提醒、日程列表）。
      expect(r.sessions.map((s) => s.date).toList(), [
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 21),
      ]);
      expect(r.sessions.map((s) => s.cancelled).toList(), [false, true, false]);
      expect(r.sessions.every((s) => s.title == '大学物理'), isTrue);
      // 停课的块得能点开「撤销停课」，所以它必须被认为「被调整过」
      expect(r.sessions[1].adjusted, isTrue);
    });

    test('改期到另一天 —— 日期与星期同时变，并打上已调整标记', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(
            id: 7,
            title: '大学物理',
            weekday: 1,
            startPeriod: 3,
            endPeriod: 4,
            weeks: [1],
          ),
        ],
        oneOffs: const [],
        overrides: [
          OverrideData(
            ruleId: 7,
            originalDate: DateTime(2026, 9, 7),
            newDate: DateTime(2026, 9, 10), // 挪到周四
          ),
        ],
      );

      expect(r.sessions.single.date, DateTime(2026, 9, 10));
      expect(r.sessions.single.weekday, DateTime.thursday);
      expect(r.sessions.single.adjusted, isTrue);
      // 原始日期要保留下来，撤销覆盖时靠它反查
      expect(r.sessions.single.originalDate, DateTime(2026, 9, 7));
    });

    test('覆盖可以只改分钟，不改日期', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(
            id: 7,
            title: '大学物理',
            weekday: 1,
            startPeriod: 3,
            endPeriod: 4,
            weeks: [1],
          ),
        ],
        oneOffs: const [],
        overrides: [
          OverrideData(
            ruleId: 7,
            originalDate: DateTime(2026, 9, 7),
            newStartMinute: 10 * 60 + 30,
            newEndMinute: 11 * 60 + 50,
          ),
        ],
      );

      expect(r.sessions.single.startMinute, 10 * 60 + 30);
      expect(r.sessions.single.date, DateTime(2026, 9, 7));
      // 节次不受覆盖影响 —— 网格行仍定位在第 3-4 节
      expect(r.sessions.single.startPeriod, 3);
    });

    test('覆盖只对它自己那条规则生效，不串台', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
          CourseTemplate(id: 2, title: 'B', weekday: 1, startPeriod: 3, endPeriod: 4, weeks: [1]),
        ],
        oneOffs: const [],
        overrides: [
          OverrideData(ruleId: 1, originalDate: DateTime(2026, 9, 7), cancelled: true),
        ],
      );

      // B 完全没被碰到
      expect(r.sessions.map((s) => s.title).toList(), ['A', 'B']);
      expect(r.sessions.map((s) => s.cancelled).toList(), [true, false]);
    });
  });

  group('第三层：套级平移', () {
    test('后移一周 —— 日期整体 +7 天，周次 +1', () {
      final r = resolveSessions(
        shifts: SetShifts(week1Monday: kWeek1, weekShift: 1),
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
        ],
        oneOffs: const [],
        overrides: const [],
      );

      expect(r.sessions.single.date, DateTime(2026, 9, 14));
      expect(r.sessions.single.week, 2);
    });

    test('后移一周再前移一周，精确回到原状（不累积误差）', () {
      List<DateTime> datesWith(int shift) => resolveSessions(
            shifts: SetShifts(week1Monday: kWeek1, weekShift: shift),
            templates: const [
              CourseTemplate(id: 1, title: 'A', weekday: 5, startPeriod: 1, endPeriod: 2, weeks: [3, 4]),
            ],
            oneOffs: const [],
            overrides: const [],
          ).sessions.map((s) => s.date).toList();

      expect(datesWith(0), datesWith(1 + -1));
      expect(datesWith(0), isNot(datesWith(1)));
    });

    test('分钟级平移只改钟点，不把课推离所在节次', () {
      final r = resolveSessions(
        shifts: SetShifts(week1Monday: kWeek1, timeShiftMinutes: 30),
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
        ],
        oneOffs: const [],
        overrides: const [],
      );

      expect(r.sessions.single.startMinute, 8 * 60 + 30);
      expect(r.sessions.single.endMinute, 9 * 60 + 70);
      // 网格行不变
      expect(r.sessions.single.startPeriod, 1);
    });

    test('分钟级平移为负也正常', () {
      final r = resolveSessions(
        shifts: SetShifts(week1Monday: kWeek1, timeShiftMinutes: -15),
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 5, endPeriod: 6, weeks: [1]),
        ],
        oneOffs: const [],
        overrides: const [],
      );
      expect(r.sessions.single.startMinute, 14 * 60 - 15);
    });

    test('平移不改变覆盖的匹配 —— 覆盖按原始日期匹配，再一起被平移', () {
      final r = resolveSessions(
        shifts: SetShifts(week1Monday: kWeek1, weekShift: 2),
        templates: const [
          CourseTemplate(id: 7, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
        ],
        oneOffs: const [],
        overrides: [
          // 覆盖写的是套内本地日期（第 1 周周一），不含平移
          OverrideData(ruleId: 7, originalDate: DateTime(2026, 9, 7), cancelled: true),
        ],
      );
      // 关键在**匹配上了**：覆盖写的是未平移的 9/7，平移若先于覆盖生效，
      // 键就会变成 9/21，这条停课会无声地失效。
      expect(r.sessions.single.cancelled, isTrue);
      expect(r.sessions.single.date, DateTime(2026, 9, 21)); // 平移照旧作用于它
    });

    test('单次事件同样跟着整套平移', () {
      final r = resolveSessions(
        shifts: SetShifts(week1Monday: kWeek1, weekShift: 1, timeShiftMinutes: 10),
        templates: const [],
        oneOffs: [
          OneOffData(
            id: 1,
            title: '讲座',
            date: DateTime(2026, 9, 10),
            startMinute: 19 * 60,
            endMinute: 21 * 60,
          ),
        ],
        overrides: const [],
      );

      final s = r.sessions.single;
      expect(s.date, DateTime(2026, 9, 17));
      expect(s.startMinute, 19 * 60 + 10);
      expect(s.oneOffId, 1);
      expect(s.ruleId, isNull);
      // 单次事件没有节次定位
      expect(s.startPeriod, isNull);
    });
  });

  group('查询辅助', () {
    test('按周筛选', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1, 2, 3, 4, 5]),
        ],
        oneOffs: const [],
        overrides: const [],
      );
      expect(sessionsInWeek(r.sessions, 5).single.date, DateTime(2026, 10, 5));
    });

    test('按天筛选按开始时间排序', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(id: 1, title: '下午课', weekday: 1, startPeriod: 5, endPeriod: 6, weeks: [1]),
          CourseTemplate(id: 2, title: '上午课', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
        ],
        oneOffs: const [],
        overrides: const [],
      );
      expect(
        sessionsOnDay(r.sessions, DateTime(2026, 9, 7)).map((s) => s.title).toList(),
        ['上午课', '下午课'],
      );
    });

    test('周次范围', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [3, 9]),
        ],
        oneOffs: const [],
        overrides: const [],
      );
      expect(weekRange(r.sessions), (first: 3, last: 9));
      expect(weekRange(const []), (first: 1, last: 1));
    });
  });

  group('setId：每条事件都要知道自己属于哪个日程', () {
    test('会盖到模板和单次事件**两种**产出上', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
        ],
        oneOffs: [
          OneOffData(
            id: 9,
            title: 'B',
            date: DateTime(2026, 9, 8),
            startMinute: 10 * 60,
            endMinute: 11 * 60,
          ),
        ],
        overrides: const [],
        setId: 7,
      );

      // 两条产出路径各写了一次 `setId:`，少写一处这里就会红 ——
      // 这正是这个断言的价值所在。
      expect(r.sessions.length, 2);
      expect(r.sessions.map((s) => s.setId).toSet(), {7});
    });

    test('不给就是 kNoSetId，而且它不等于任何一个真实日程 id', () {
      final r = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(id: 1, title: 'A', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [1]),
        ],
        oneOffs: const [],
        overrides: const [],
      );
      // 默认值只为测试夹具和「还没落库的临时会话」存在。drift 的 id 从 1 开始，
      // 所以 0 当哨兵不会和真值撞车 —— 这是那几条 setId 探针能成立的前提。
      expect(r.sessions.single.setId, kNoSetId);
      expect(kNoSetId, 0);
    });
  });

  group('排序必须确定 —— 小组件的同格分栏靠它', () {
    ResolvedSession at(int setId) => ResolvedSession(
          setId: setId,
          date: DateTime(2026, 10, 5),
          startMinute: 8 * 60,
          endMinute: 9 * 60 + 40,
          title: '课$setId',
        );

    test('同一时刻的六条事件，怎么喂进去都排出同一个顺序', () {
      // `List.sort` 在 Dart 里**不是稳定排序**，所以「同一天同一分钟」的几条事件
      // 相对顺序本来是任意的 —— 而小组件的周网格靠这个顺序决定同格谁左谁右，
      // 于是桌面上那两栏可能每次刷新翻个面。
      //
      // 六条同刻事件、两个方向各排一次，钉住 `compare` 末尾那一级 setId tiebreak。
      final forward =
          [for (var i = 1; i <= 6; i++) at(i)]..sort(ResolvedSession.compare);
      final backward =
          [for (var i = 6; i >= 1; i--) at(i)]..sort(ResolvedSession.compare);

      const want = [1, 2, 3, 4, 5, 6];
      expect(forward.map((s) => s.setId).toList(), want);
      expect(backward.map((s) => s.setId).toList(), want);
    });
  });

  group('跨日程取一周：按日期，不按周号', () {
    // A 的锚点就是 kWeek1（2026-09-07），B 的锚点比它晚一周。
    // 于是同一个 2026-10-05 在 A 里是第 5 周、在 B 里是第 4 周。
    final bWeek1 = DateTime(2026, 9, 14);

    List<ResolvedSession> merged() => [
          ...resolveSessions(
            shifts: kNoShift,
            templates: const [
              CourseTemplate(id: 1, title: 'A课', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [5]),
            ],
            oneOffs: const [],
            overrides: const [],
            setId: 1,
          ).sessions,
          ...resolveSessions(
            shifts: SetShifts(week1Monday: bWeek1),
            templates: const [
              CourseTemplate(id: 1, title: 'B课', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [4]),
            ],
            oneOffs: const [],
            overrides: const [],
            setId: 2,
          ).sessions,
        ]..sort(ResolvedSession.compare);

    test('两个日程的课都落在 2026-10-05，但它们的 week 号并不相同', () {
      final all = merged();
      expect(all.map((s) => s.date).toSet(), {DateTime(2026, 10, 5)});
      expect(all.map((s) => s.week).toSet(), {4, 5});
    });

    test('按 week 字段筛会漏掉另一个日程 —— 这就是不能用它的原因', () {
      // 这一条是**反例**，写出来是为了让「为什么总览不能用 sessionsInWeek」
      // 有据可查：它只捞得到 A 那一条，B 的那节课凭空消失
      // （在总览页上看起来就是「B 这周没课」）。
      expect(sessionsInWeek(merged(), 5).map((s) => s.setId), [1]);
    });

    test('按日期区间筛，两个日程各自贡献自己真实落在这一周的那节课', () {
      final byDate = sessionsInWeekRange(merged(), week1Monday: kWeek1, week: 5);
      expect(byDate.map((s) => s.setId).toList(), [1, 2]);
    });

    test('区间是左闭右开：下一周的周一不在里面', () {
      final r = weekDateRange(week1Monday: kWeek1, week: 5);
      expect(r.start, DateTime(2026, 10, 5));
      expect(r.end, DateTime(2026, 10, 12));

      // 第 6 周的那节课（10/12）不该被第 5 周捞走。
      final s = resolveSessions(
        shifts: kNoShift,
        templates: const [
          CourseTemplate(id: 1, title: '下周', weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [6]),
        ],
        oneOffs: const [],
        overrides: const [],
      ).sessions;
      expect(sessionsInWeekRange(s, week1Monday: kWeek1, week: 5), isEmpty);
      expect(sessionsInWeekRange(s, week1Monday: kWeek1, week: 6).length, 1);
    });
  });
}
