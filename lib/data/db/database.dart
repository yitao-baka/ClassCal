import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

/// 本地库。
///
/// 用 drift 而不是键值库（isar / hive）的原因很具体：课表查询几乎全是
/// 「某个日期区间内有哪些课」，这需要带索引的范围查询；而且单次改期、
/// 整体平移都是就地 UPDATE，键值库只能整文件重写。
/// 另外 isar 与 hive 的作者都已停止维护，isar 还卡在 Android 16 KB 页大小要求上。
///
/// 走了 `drift_flutter` 提供的连接工厂：自 drift 2.32 起原生平台零配置，
/// **不需要**再单独加 `sqlite3_flutter_libs`（那是旧写法的遗留）。
@DriftDatabase(tables: [CalendarSets, CourseRules, OneOffEvents, OccurrenceOverrides])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'classcal'));

  /// 测试用：传入内存库或自定义连接。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          // 外键约束默认是关的，必须显式打开，否则级联删除不会生效 ——
          // 删掉一套课表时，它的课程和覆盖记录会变成孤儿行留在库里。
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // -------------------------------------------------------------------------
  // 课表套
  // -------------------------------------------------------------------------

  Stream<List<CalendarSet>> watchSets() => (select(calendarSets)
        ..orderBy([(t) => OrderingTerm(expression: t.tabOrder)]))
      .watch();

  Future<List<CalendarSet>> allSets() => (select(calendarSets)
        ..orderBy([(t) => OrderingTerm(expression: t.tabOrder)]))
      .get();

  Stream<CalendarSet?> watchSet(int id) =>
      (select(calendarSets)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertSet(CalendarSetsCompanion set) =>
      into(calendarSets).insert(set);

  Future<void> updateSet(CalendarSetsCompanion set) =>
      (update(calendarSets)..where((t) => t.id.equals(set.id.value))).write(set);

  Future<void> deleteSet(int id) =>
      (delete(calendarSets)..where((t) => t.id.equals(id))).go();

  /// 某套课表里已有的全部课程标题，导入时用来判重与自动配色。
  Future<List<String>> titlesOfSet(int setId) async {
    final rows = await (select(courseRules)
          ..where((t) => t.setId.equals(setId)))
        .get();
    return rows.map((r) => r.title).toSet().toList()..sort();
  }

  // -------------------------------------------------------------------------
  // 课程规则
  // -------------------------------------------------------------------------

  Stream<List<CourseRule>> watchRulesOfSet(int setId) =>
      (select(courseRules)..where((t) => t.setId.equals(setId))).watch();

  Future<List<CourseRule>> rulesOfSet(int setId) =>
      (select(courseRules)..where((t) => t.setId.equals(setId))).get();

  Future<int> insertRule(CourseRulesCompanion rule) =>
      into(courseRules).insert(rule);

  Future<void> insertRules(List<CourseRulesCompanion> rules) =>
      batch((b) => b.insertAll(courseRules, rules));

  Future<void> updateRule(CourseRulesCompanion rule) =>
      (update(courseRules)..where((t) => t.id.equals(rule.id.value))).write(rule);

  Future<void> deleteRule(int id) =>
      (delete(courseRules)..where((t) => t.id.equals(id))).go();

  /// 删掉某套课表里同名的一门课（可能横跨多条规则）。
  Future<void> deleteCourseByTitle(int setId, String title) =>
      (delete(courseRules)
            ..where((t) => t.setId.equals(setId) & t.title.equals(title)))
          .go();

  /// 把某套课表里同名规则一起改色；[hex] 传 null 就是恢复「按名称自动配色」。
  ///
  /// 一次 UPDATE 搞定整门课，而不是把规则读出来逐条写：同名的几条规则本来就
  /// 该是同一个颜色，中间不该有「改了一半」的状态。
  Future<void> setCourseColor(int setId, String title, String? hex) =>
      (update(courseRules)
            ..where((t) => t.setId.equals(setId) & t.title.equals(title)))
          .write(CourseRulesCompanion(colorOverrideHex: Value(hex)));

  /// 整体平移：一次写入改掉整套课表的偏移量，可撤销、不累积误差。
  Future<void> shiftSet(int setId, {int? addWeeks, int? addMinutes}) async {
    final set = await (select(calendarSets)..where((t) => t.id.equals(setId)))
        .getSingleOrNull();
    if (set == null) return;
    await updateSet(
      CalendarSetsCompanion(
        id: Value(setId),
        weekShift: Value(set.weekShift + (addWeeks ?? 0)),
        timeShiftMinutes: Value(set.timeShiftMinutes + (addMinutes ?? 0)),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 单次事件
  // -------------------------------------------------------------------------

  Stream<List<OneOffEvent>> watchOneOffsOfSet(int setId) =>
      (select(oneOffEvents)..where((t) => t.setId.equals(setId))).watch();

  Future<int> insertOneOff(OneOffEventsCompanion e) =>
      into(oneOffEvents).insert(e);

  Future<void> updateOneOff(OneOffEventsCompanion e) =>
      (update(oneOffEvents)..where((t) => t.id.equals(e.id.value))).write(e);

  Future<void> deleteOneOff(int id) =>
      (delete(oneOffEvents)..where((t) => t.id.equals(id))).go();

  // -------------------------------------------------------------------------
  // 单次覆盖
  // -------------------------------------------------------------------------

  /// 某套课表的全部覆盖记录。
  ///
  /// 覆盖表只存 ruleId，要按「套」取必须 join 回 courseRules ——
  /// 这一点在渲染路径上很容易写成循环里逐条查（N+1），所以这里一次取全。
  Stream<List<OccurrenceOverride>> watchOverridesOfSet(int setId) {
    final query = select(occurrenceOverrides).join([
      innerJoin(courseRules, courseRules.id.equalsExp(occurrenceOverrides.ruleId)),
    ])
      ..where(courseRules.setId.equals(setId));
    return query.watch().map(
          (rows) => rows.map((r) => r.readTable(occurrenceOverrides)).toList(),
        );
  }

  /// 一次性读取（与 [watchOverridesOfSet] 同一条 join，只是不走流）。
  Future<List<OccurrenceOverride>> overridesOfSetSync(int setId) async {
    final query = select(occurrenceOverrides).join([
      innerJoin(courseRules, courseRules.id.equalsExp(occurrenceOverrides.ruleId)),
    ])
      ..where(courseRules.setId.equals(setId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(occurrenceOverrides)).toList();
  }

  Future<int> insertOverride(OccurrenceOverridesCompanion o) =>
      into(occurrenceOverrides).insert(o);

  /// 同一条规则的同一天只应有一条覆盖（导入、改期都靠这个前提做覆盖）。
  Future<int> upsertOverride(OccurrenceOverridesCompanion o) async {
    final existing = await (select(occurrenceOverrides)
          ..where((t) => t.ruleId.equals(o.ruleId.value) & t.originalDate.equals(o.originalDate.value)))
        .getSingleOrNull();
    if (existing == null) return into(occurrenceOverrides).insert(o);
    await (update(occurrenceOverrides)..where((t) => t.id.equals(existing.id)))
        .write(o);
    return existing.id;
  }

  Future<void> deleteOverride(int id) =>
      (delete(occurrenceOverrides)..where((t) => t.id.equals(id))).go();

  Future<void> deleteOverrideFor(int ruleId, DateTime originalDate) =>
      (delete(occurrenceOverrides)
            ..where((t) => t.ruleId.equals(ruleId) & t.originalDate.equals(originalDate)))
          .go();
}
