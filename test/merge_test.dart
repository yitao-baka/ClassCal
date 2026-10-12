import 'package:classcal/data/db/database.dart';
import 'package:classcal/data/import/ics_import.dart';
import 'package:classcal/data/model/resolve.dart';
import 'package:classcal/data/repository/calendar_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「合并到已有课表」的测试。
///
/// 合并最容易错的地方不是插入，而是**判重**：同一门课在两周里各出现一次，
/// 并进来时必须补进周次集合，而不是变成两条各占一半周次的规则 ——
/// 后者在界面上看起来像是课变多了，而且往后每次单向操作都要做两遍。

CalendarSetData setWith({
  required List<CourseTemplate> templates,
  DateTime? week1Monday,
}) =>
    CalendarSetData(
      id: CalendarSetData.unsavedId,
      name: '待导入',
      shifts: SetShifts(week1Monday: week1Monday ?? DateTime(2026, 9, 7)),
      templates: templates,
    );

CourseTemplate tpl({
  int id = 1,
  String title = '大学外语(1)',
  int weekday = 3,
  int startPeriod = 1,
  int endPeriod = 2,
  List<int> weeks = const [5],
  String teacher = '',
  String location = '',
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
    );

void main() {
  late AppDatabase db;
  late CalendarRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CalendarRepository(db);
  });

  tearDown(() => db.close());

  test('同标题 / 同星期 / 同起始节 → 并进周次集合，不新增一条', () async {
    final target = await repo.createSet(setWith(templates: [
      tpl(weeks: [5, 6]),
    ]));

    final r = await repo.mergeIntoSet(
      target,
      setWith(templates: [tpl(weeks: [6, 7])]),
    );

    expect(r.added, 0);
    expect(r.merged, 1);
    final rules = await db.rulesOfSet(target);
    expect(rules.single.weeks, [5, 6, 7]); // 并集，不是覆盖也不是相加
  });

  test('起始节不同就是两门课 —— 同一门课周四 1-2 和周五 3-4 不能并成一条', () async {
    final target = await repo.createSet(setWith(templates: [
      tpl(weekday: 4, startPeriod: 1, endPeriod: 2),
    ]));

    final r = await repo.mergeIntoSet(
      target,
      setWith(templates: [tpl(weekday: 5, startPeriod: 3, endPeriod: 4)]),
    );

    expect(r.added, 1);
    expect(r.merged, 0);
    expect((await db.rulesOfSet(target)).length, 2);
  });

  test('全新的课照常新增，与目标里已有的课互不影响', () async {
    final target = await repo.createSet(setWith(templates: [
      tpl(title: '高等数学A(1)', weekday: 1, startPeriod: 3, endPeriod: 4, weeks: [5]),
    ]));

    final r = await repo.mergeIntoSet(
      target,
      setWith(templates: [
        // 已有，只并周次
        tpl(id: 1, title: '高等数学A(1)', weekday: 1, startPeriod: 3, endPeriod: 4, weeks: [5, 6]),
        tpl(id: 2, title: '大学体育(1)', weekday: 4, startPeriod: 5, endPeriod: 6, weeks: [7]),
      ]),
    );

    expect((added: r.added, merged: r.merged), (added: 1, merged: 1));
    final rules = await db.rulesOfSet(target);
    expect(rules.length, 2);
    expect(
      rules.firstWhere((t) => t.title == '高等数学A(1)').weeks,
      [5, 6],
    );
  });

  test('合并进来的单次事件和覆盖记录也落到了目标那一套', () async {
    final target = await repo.createSet(setWith(templates: [tpl(weeks: [5, 6])]));

    final incoming = setWith(templates: [
      tpl(weeks: [7]),
    ]).copyWith(
      oneOffs: [
        OneOffData(
          id: 1,
          title: '临时讲座',
          date: DateTime(2026, 10, 8),
          startMinute: 12 * 60 + 30,
          endMinute: 13 * 60 + 30,
        ),
      ],
      // 覆盖记录用的是文件空间里的局部 ruleId（=1），
      // 落库时必须翻译成目标那一套里的真实主键，否则这条改动会挂空。
      overrides: [
        OverrideData(
          ruleId: 1,
          originalDate: DateTime(2026, 10, 14),
          cancelled: true,
        ),
      ],
    );

    await repo.mergeIntoSet(target, incoming);

    final data = (await repo.watchSetData(target).first)!;
    expect(data.oneOffs.length, 1);
    expect(data.oneOffs.single.title, '临时讲座');
    expect(data.overrides.length, 1);
    expect(data.overrides.single.ruleId, data.templates.single.id);

    // 覆盖记录真的生效了：第 6 周那次被停掉
    final sessions = resolveSessions(
      shifts: data.shifts,
      templates: data.templates,
      oneOffs: data.oneOffs,
      overrides: data.overrides,
    ).sessions;
    expect(sessions.where((s) => s.ruleId != null && !s.cancelled).length, 2); // 第 5、7 周
    expect(sessions.where((s) => s.cancelled).length, 1); // 第 6 周停课
  });

  test('两套锚点不同的课表合并：按目标的锚点重新解析，日期才落在同一根时间轴上', () async {
    // 同一份 ICS，一次按 9/7 解析、一次按 9/14 解析 —— 后者整体晚一周。
    const source = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:a@x
DTSTART:20260930T080000
DTEND:20260930T094000
SUMMARY:大学外语(1)
RRULE:FREQ=WEEKLY;COUNT=1
X-CLASSCAL-PERIODS:1-2
X-CLASSCAL-WEEKS:4
END:VEVENT
END:VCALENDAR
''';

    final anchorA = DateTime(2026, 9, 7); // 第 4 周 = 9/28 ~ 10/4，周三 = 9/30
    final anchorB = DateTime(2026, 9, 14); // 第 4 周 → 周三 = 10/7

    final targetSet = await repo.createSet(
      importIcs(source, week1Monday: anchorA).set,
    );

    // 合并方按**目标**的锚点重新解析（home_page 里就是这么做的）
    final data = importIcs(source, week1Monday: anchorB).set;
    await repo.mergeIntoSet(targetSet, data);

    final rule = (await db.rulesOfSet(targetSet)).single;
    expect(rule.weeks, [4]);

    // 目标那套的锚点没被动过
    final set = (await db.allSets()).single;
    expect(set.week1Monday, anchorA);
  });
}
