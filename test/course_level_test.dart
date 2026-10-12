import 'package:classcal/data/db/database.dart';
import 'package:classcal/data/model/resolve.dart';
import 'package:classcal/data/repository/calendar_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「整门课」级操作的测试 —— 改色与删除。
///
/// 数据模型里的粒度是**一次排课**（`CourseRules` 一行 = 星期几的第几节），
/// 而用户脑子里的粒度是**一门课**。同一门课一周上三次就是三条规则，能不能
/// 把它们当成一件事来操作，全看这两个方法。
///
/// 这两条都曾经是错的，而且错得看不出来：
/// * 改色只写点进来的那条规则 → 周二红了周五还是紫的；
/// * 删除只删点进来的那条规则 → 确认框上写着「这门课的全部周次一起删掉」，
///   周五的课却还在。
///
/// 所以这里的断言是「三条规则一起变」，而不是「点的那条变了」。

CourseTemplate tpl({
  required String title,
  required int weekday,
  int id = 0,
  int startPeriod = 3,
  int endPeriod = 4,
  String? colorHex,
}) =>
    CourseTemplate(
      id: id,
      title: title,
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: const [5, 6],
      colorHex: colorHex,
    );

Future<int> seed(CalendarRepository repo, List<CourseTemplate> templates) =>
    repo.createSet(CalendarSetData(
      id: CalendarSetData.unsavedId,
      name: '测试',
      shifts: SetShifts(week1Monday: DateTime(2026, 9, 7)),
      templates: templates,
    ));

void main() {
  late AppDatabase db;
  late CalendarRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CalendarRepository(db);
  });

  tearDown(() => db.close());

  group('整门改色', () {
    test('一门课横跨三条规则时，三条一起变', () async {
      final setId = await seed(repo, [
        tpl(title: '高等数学A(1)', weekday: 2),
        tpl(title: '高等数学A(1)', weekday: 3),
        tpl(title: '高等数学A(1)', weekday: 5),
        tpl(title: '大学外语(1)', weekday: 5),
      ]);

      await repo.setCourseColor(setId, '高等数学A(1)', '#EF5350');

      final rules = await db.rulesOfSet(setId);
      for (final r in rules.where((r) => r.title == '高等数学A(1)')) {
        expect(r.colorOverrideHex, '#EF5350', reason: '星期${r.weekday} 没跟着变');
      }
      // 别的课不能受牵连 —— 按名字分组，不是「整套课表一起改」。
      final other = rules.singleWhere((r) => r.title == '大学外语(1)');
      expect(other.colorOverrideHex, isNull);
    });

    test('写回 null 就是整门课恢复自动配色', () async {
      final setId = await seed(repo, [
        tpl(title: '高等数学A(1)', weekday: 2, colorHex: '#EF5350'),
        tpl(title: '高等数学A(1)', weekday: 5, colorHex: '#EF5350'),
      ]);

      await repo.setCourseColor(setId, '高等数学A(1)', null);

      final rules = await db.rulesOfSet(setId);
      expect(rules.map((r) => r.colorOverrideHex), everyElement(isNull));
    });

    test('改的是同名的那一组，不是「所有规则」', () async {
      final setId = await seed(repo, [
        tpl(title: 'A', weekday: 1),
        tpl(title: 'B', weekday: 1),
      ]);

      await repo.setCourseColor(setId, 'A', '#26A69A');

      final rules = await db.rulesOfSet(setId);
      expect(rules.singleWhere((r) => r.title == 'A').colorOverrideHex, '#26A69A');
      expect(rules.singleWhere((r) => r.title == 'B').colorOverrideHex, isNull);
    });
  });

  group('整门删除', () {
    test('删掉的是这门课的全部排课，不是点进来的那一条', () async {
      final setId = await seed(repo, [
        tpl(title: '高等数学A(1)', weekday: 2),
        tpl(title: '高等数学A(1)', weekday: 3),
        tpl(title: '高等数学A(1)', weekday: 5),
        tpl(title: '大学外语(1)', weekday: 5),
      ]);

      await repo.deleteCourse(setId, '高等数学A(1)');

      final rules = await db.rulesOfSet(setId);
      expect(rules.map((r) => r.title), ['大学外语(1)']);
    });

    test('连同这些规则的改期 / 停课记录一起走，不留孤儿行', () async {
      final setId = await seed(repo, [
        tpl(title: '高等数学A(1)', weekday: 2),
      ]);
      final rule = (await db.rulesOfSet(setId)).single;

      await repo.setOverride(
        rule.id,
        OverrideData(
          ruleId: rule.id,
          originalDate: DateTime(2026, 9, 8),
          cancelled: true,
        ),
      );
      expect(await db.overridesOfSetSync(setId), hasLength(1));

      await repo.deleteCourse(setId, '高等数学A(1)');

      // 外键 cascade。留着孤儿覆盖行，将来同 id 的规则出现时会「继承」一次
      // 莫名其妙的停课。
      expect(await db.overridesOfSetSync(setId), isEmpty);
    });

    test('删一门不存在的课不改动任何东西', () async {
      final setId = await seed(repo, [tpl(title: '大学外语(1)', weekday: 5)]);

      await repo.deleteCourse(setId, '查无此课');

      expect(await db.rulesOfSet(setId), hasLength(1));
    });
  });
}
