/// 仓库层 —— UI 只碰这一层，不直接看到 drift 的行类。
///
/// 这一层唯一的实质工作就是**在两个 id 空间之间搬运**：
///
/// * 数据库空间：`CourseRules.id` / `OneOffEvents.id` 是自增主键，
///   导入到另一个库就完全变样。
/// * 文件空间：导入的 JSON / ICS 里用的是下标之类的局部编号。
///
/// 其余都是直白的读写。之所以值得单独一层，是因为这个映射是「导入一份备份却
/// 得到一堆错位的单次改期」这类 bug 的唯一滋生地，集中在一处才好审。
library;

import 'package:drift/drift.dart';

import '../../core/settings/schedule_ref.dart';
import '../db/database.dart';
import '../model/domain.dart';

class CalendarRepository {
  CalendarRepository(this._db);

  final AppDatabase _db;

  // -------------------------------------------------------------------------
  // 读取
  // -------------------------------------------------------------------------

  /// 标签页列表（只要元信息，不含课程内容）。
  Stream<List<CalendarSet>> watchTabRows() => _db.watchSets();

  Future<List<CalendarSet>> allTabRows() => _db.allSets();

  /// 一整套课表 —— 标签页 + 全部课程 + 单次事件 + 覆盖记录。
  ///
  /// 四张表里任何一张变动都要重新拉，否则会在 UI 上出现「改了课程但网格没变」
  /// 这类灵异现象。drift 只会为它「声明读过」的表重新触发查询，所以这里用一条
  /// 只取 id 的小查询当触发器，把四张表都登记进去，再整份重读。
  Stream<CalendarSetData?> watchSetData(int setId) {
    final trigger = _db.customSelect(
      'SELECT id FROM calendar_sets WHERE id = ?',
      variables: [Variable.withInt(setId)],
      readsFrom: {
        _db.calendarSets,
        _db.courseRules,
        _db.oneOffEvents,
        _db.occurrenceOverrides,
      },
    );
    return trigger.watch().asyncMap((_) => loadSetData(setId));
  }

  /// 一次性读取。
  Future<CalendarSetData?> loadSetData(int setId) async {
    final row = await (_db.select(_db.calendarSets)..where((t) => t.id.equals(setId)))
        .getSingleOrNull();
    if (row == null) return null;

    final rules = await _db.rulesOfSet(setId);
    final oneOffs = await (_db.select(_db.oneOffEvents)..where((t) => t.setId.equals(setId))).get();
    final overrides = await _db.overridesOfSetSync(setId);

    return CalendarSetData(
      id: row.id,
      name: row.name,
      colorSeedHex: row.colorSeedHex,
      tabOrder: row.tabOrder,
      visible: row.visible,
      sourceName: row.sourceName,
      shifts: SetShifts(
        week1Monday: row.week1Monday,
        weekShift: row.weekShift,
        timeShiftMinutes: row.timeShiftMinutes,
      ),
      templates: rules.map(_toTemplate).toList(),
      oneOffs: oneOffs.map(_toOneOff).toList(),
      overrides: overrides.map(_toOverride).toList(),
    );
  }

  /// 全部套的完整内容，**任何一张表变动都重拉**。
  ///
  /// 和 [watchSetData] 是同一套触发器+整份重读的写法，区别只是范围 ——
  /// 提醒要跨标签页排（在另一套课表里的课也得提醒），所以不能只盯当前这一套。
  Stream<List<CalendarSetData>> watchAllSets() {
    final trigger = _db.customSelect(
      'SELECT COUNT(*) AS n FROM calendar_sets',
      readsFrom: {
        _db.calendarSets,
        _db.courseRules,
        _db.oneOffEvents,
        _db.occurrenceOverrides,
      },
    );
    return trigger.watch().asyncMap((_) => loadAllSets());
  }

  /// 全部套，供「叠加视图」和导出使用。
  Future<List<CalendarSetData>> loadAllSets() async {
    final rows = await _db.allSets();
    final out = <CalendarSetData>[];
    for (final r in rows) {
      final d = await loadSetData(r.id);
      if (d != null) out.add(d);
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // 写入：套
  // -------------------------------------------------------------------------

  /// 新建一套课表，连同它的课程、单次事件与覆盖记录。
  ///
  /// [data] 里的 id 视为**文件空间的局部编号**，落库时整体重编；覆盖记录指向
  /// 的 ruleId 也会同步翻译。返回新套的真实主键。
  Future<int> createSet(CalendarSetData data) {
    return _db.transaction(() async {
      final setId = await _db.insertSet(
        CalendarSetsCompanion.insert(
          name: data.name,
          week1Monday: data.shifts.week1Monday,
          colorSeedHex: Value(data.colorSeedHex),
          tabOrder: Value(data.tabOrder),
          visible: Value(data.visible),
          weekShift: Value(data.shifts.weekShift),
          timeShiftMinutes: Value(data.shifts.timeShiftMinutes),
          sourceName: Value(data.sourceName),
        ),
      );

      // 局部编号 → 真实主键
      final remap = <int, int>{};
      for (final tpl in data.templates) {
        remap[tpl.id] = await _db.insertRule(_ruleCompanion(setId, tpl));
      }
      for (final e in data.oneOffs) {
        await _db.insertOneOff(_oneOffCompanion(setId, e));
      }
      for (final o in data.overrides) {
        final realRuleId = remap[o.ruleId];
        // 指向不存在规则的覆盖记录直接丢弃 —— 规则都没了，这条改动无从附着
        if (realRuleId == null) continue;
        await _db.insertOverride(_overrideCompanion(realRuleId, o));
      }
      return setId;
    });
  }

  /// 把 [data] 的内容**追加**到已有的 [targetSetId]（导入时选「合并到某套」）。
  ///
  /// 按「标题 + 星期 + 起始节」判重：已存在的规则只把周次并进去，不新建一条，
  /// 否则同一门课会变成两条各占一半周次的规则。返回 (新增, 合并) 的条数。
  Future<({int added, int merged})> mergeIntoSet(
    int targetSetId,
    CalendarSetData data,
  ) async {
    return _db.transaction(() async {
      final existing = await _db.rulesOfSet(targetSetId);
      final byKey = <String, CourseRule>{};
      for (final r in existing) {
        byKey['${r.title}\u0000${r.weekday}\u0000${r.startPeriod}'] = r;
      }

      var added = 0;
      var merged = 0;
      final remap = <int, int>{};

      for (final tpl in data.templates) {
        final key = '${tpl.title}\u0000${tpl.weekday}\u0000${tpl.startPeriod}';
        final hit = byKey[key];
        if (hit == null) {
          final id = await _db.insertRule(_ruleCompanion(targetSetId, tpl));
          remap[tpl.id] = id;
          added++;
          continue;
        }
        final union = <int>{...hit.weeks, ...tpl.weeks}.toList()..sort();
        await _db.updateRule(CourseRulesCompanion(
          id: Value(hit.id),
          weeks: Value(union),
        ));
        remap[tpl.id] = hit.id;
        merged++;
      }

      for (final e in data.oneOffs) {
        await _db.insertOneOff(_oneOffCompanion(targetSetId, e));
      }
      for (final o in data.overrides) {
        final realRuleId = remap[o.ruleId];
        if (realRuleId == null) continue;
        await _db.insertOverride(_overrideCompanion(realRuleId, o));
      }

      return (added: added, merged: merged);
    });
  }

  Future<void> renameSet(int setId, String name) => _db.updateSet(
        CalendarSetsCompanion(id: Value(setId), name: Value(name)),
      );

  Future<void> setVisible(int setId, bool visible) => _db.updateSet(
        CalendarSetsCompanion(id: Value(setId), visible: Value(visible)),
      );

  Future<void> setColorSeed(int setId, String hex) => _db.updateSet(
        CalendarSetsCompanion(id: Value(setId), colorSeedHex: Value(hex)),
      );

  /// 把界面上的标签顺序**顺手写回数据库那一列**。
  ///
  /// `CalendarSets.tabOrder` 已经不是权威顺序了 —— 权威那份在
  /// `AppSettings.tabOrder`，因为**一行一个整数表达不了「总览插在第二和第三个
  /// 日程之间」**（总览没有 id，也就没有那一列）。但这一列不能就此烂掉：
  /// 导出 JSON 备份时会带上它，而**设置文件不会跟着备份一起走**。恢复到一台
  /// 新机器上时顺序就只剩这一列，不写回的话导出的备份里那一列是陈旧值 ——
  /// 「看起来有顺序、恢复出来却是乱的」。
  ///
  /// [order] 是 [ScheduleRef] 的 key 列表，`'overview'` 这类没有 id 的项跳过。
  /// 名次按**在列表里的位置**编号，所以总览占的那一号会被跳过 —— 这不是问题，
  /// 这一列只用来排序，中间缺号无所谓。
  Future<void> writeTabOrder(List<String> order) async {
    for (var i = 0; i < order.length; i++) {
      final id = ScheduleRef.setIdOf(order[i]);
      if (id == null) continue;
      await _db.updateSet(
        CalendarSetsCompanion(id: Value(id), tabOrder: Value(i)),
      );
    }
  }

  Future<void> deleteSet(int setId) => _db.deleteSet(setId);

  /// 整体平移（周级 / 分钟级），累加到套上的偏移量。
  Future<void> shiftSet(int setId, {int addWeeks = 0, int addMinutes = 0}) =>
      _db.shiftSet(setId, addWeeks: addWeeks, addMinutes: addMinutes);

  /// 把平移量清零 —— 「撤销整体移动」。
  Future<void> resetShift(int setId) => _db.updateSet(
        CalendarSetsCompanion(
          id: Value(setId),
          weekShift: const Value(0),
          timeShiftMinutes: const Value(0),
        ),
      );

  // -------------------------------------------------------------------------
  // 写入：课程 / 单次事件 / 覆盖
  // -------------------------------------------------------------------------

  Future<int> addRule(int setId, CourseTemplate tpl) =>
      _db.insertRule(_ruleCompanion(setId, tpl));

  Future<void> updateRule(int setId, CourseTemplate tpl) => _db.updateRule(
        _ruleCompanion(setId, tpl).copyWith(id: Value(tpl.id)),
      );

  Future<void> deleteRule(int ruleId) => _db.deleteRule(ruleId);

  /// 整门删除：把这门课名下的全部排课规则一起删掉（连同它们的单次覆盖，
  /// 靠外键的 cascade）。一门课在教务课表里常常一周上两三次，那是几条规则。
  Future<void> deleteCourse(int setId, String title) =>
      _db.deleteCourseByTitle(setId, title);

  /// 整门改色；[hex] 为 null 表示恢复「按课程名自动配色」。
  ///
  /// 按 [title] 分组写，而不是只写点进来的那条规则：同一门课分在几条规则里，
  /// 逐条改必然出现「周三红了周五还紫着」的中间状态，而没人想要一门课两种颜色。
  Future<void> setCourseColor(int setId, String title, String? hex) =>
      _db.setCourseColor(setId, title, hex);

  Future<int> addOneOff(int setId, OneOffData e) =>
      _db.insertOneOff(_oneOffCompanion(setId, e));

  Future<void> updateOneOff(int setId, OneOffData e) => _db.updateOneOff(
        _oneOffCompanion(setId, e).copyWith(id: Value(e.id)),
      );

  Future<void> deleteOneOff(int id) => _db.deleteOneOff(id);

  /// 记录「这一次课被改了/停了」。同一条规则的同一天重复调用会覆盖前一次。
  Future<void> setOverride(int ruleId, OverrideData o) =>
      _db.upsertOverride(_overrideCompanion(ruleId, o));

  Future<void> clearOverride(int ruleId, DateTime originalDate) =>
      _db.deleteOverrideFor(ruleId, originalDate);

  // -------------------------------------------------------------------------
  // 行 ↔ 领域对象
  // -------------------------------------------------------------------------

  CourseTemplate _toTemplate(CourseRule r) => CourseTemplate(
        id: r.id,
        title: r.title,
        weekday: r.weekday,
        startPeriod: r.startPeriod,
        endPeriod: r.endPeriod,
        weeks: r.weeks,
        teacher: r.teacher,
        location: r.location,
        note: r.note,
        colorHex: r.colorOverrideHex,
        remindersEnabled: r.remindersEnabled,
        leadMinutes: r.leadMinutes,
      );

  OneOffData _toOneOff(OneOffEvent e) => OneOffData(
        id: e.id,
        title: e.title,
        date: e.date,
        startMinute: e.startMinute,
        endMinute: e.endMinute,
        location: e.location,
        note: e.note,
        colorHex: e.colorHex,
      );

  OverrideData _toOverride(OccurrenceOverride o) => OverrideData(
        ruleId: o.ruleId,
        originalDate: o.originalDate,
        cancelled: o.cancelled,
        newDate: o.newDate,
        newStartMinute: o.newStartMinute,
        newEndMinute: o.newEndMinute,
        newLocation: o.newLocation,
        newTitle: o.newTitle,
      );

  CourseRulesCompanion _ruleCompanion(int setId, CourseTemplate t) =>
      CourseRulesCompanion.insert(
        setId: setId,
        title: t.title,
        weekday: t.weekday,
        startPeriod: t.startPeriod,
        endPeriod: t.endPeriod,
        weeks: t.weeks,
        teacher: Value(t.teacher),
        location: Value(t.location),
        note: Value(t.note),
        colorOverrideHex: Value(t.colorHex),
        remindersEnabled: Value(t.remindersEnabled),
        leadMinutes: Value(t.leadMinutes),
      );

  OneOffEventsCompanion _oneOffCompanion(int setId, OneOffData e) =>
      OneOffEventsCompanion.insert(
        setId: setId,
        title: e.title,
        date: e.date,
        startMinute: e.startMinute,
        endMinute: e.endMinute,
        location: Value(e.location),
        note: Value(e.note),
        colorHex: Value(e.colorHex),
      );

  OccurrenceOverridesCompanion _overrideCompanion(int ruleId, OverrideData o) =>
      OccurrenceOverridesCompanion.insert(
        ruleId: ruleId,
        originalDate: o.originalDate,
        cancelled: Value(o.cancelled),
        newDate: Value(o.newDate),
        newStartMinute: Value(o.newStartMinute),
        newEndMinute: Value(o.newEndMinute),
        newLocation: Value(o.newLocation),
        newTitle: Value(o.newTitle),
      );
}
