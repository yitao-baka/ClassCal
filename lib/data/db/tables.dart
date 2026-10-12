import 'package:drift/drift.dart';

/// 把 `[5,6,7]` 这样的周次集合存成逗号分隔字符串。
///
/// 存展开的周集合而不是 `5-16` 这样的区间：教务课表的周次本来就可能不连续
/// （单双周、调课、临时加课），区间表示会逼着渲染层做区间合并与交并运算，
/// 而那正是这类 App 最容易出边界 bug 的地方。展开后渲染只剩一句 `contains`。
/// 量级上 23 门课 × 20 周 ≈ 500 个整数，代价可忽略。
class IntListConverter extends TypeConverter<List<int>, String> {
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <int>[];
    return fromDb
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList()
      ..sort();
  }

  @override
  String toSql(List<int> value) => (value.toList()..sort()).join(',');
}

/// 一套课表 = 一个标签页。
///
/// 整体平移（[weekShift] / [timeShiftMinutes]）存在这里而不是逐条改事件：
/// 平移是一次字段写入，可一键撤销，反复平移也不会累积舍入误差。
class CalendarSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get colorSeedHex => text().withDefault(const Constant('#6750A4'))();
  IntColumn get tabOrder => integer().withDefault(const Constant(0))();

  /// 该套课表第 1 周的周一 —— 全部日期换算的锚点。
  ///
  /// 导入时由用户确认（ICS 里的周次信息本身不含年份），存下来避免每次渲染重算。
  DateTimeColumn get week1Monday => dateTime()();

  BoolColumn get visible => boolean().withDefault(const Constant(true))();

  /// 整体前后移动的周数，可负。
  IntColumn get weekShift => integer().withDefault(const Constant(0))();

  /// 整体前后移动的分钟数，可负。与 [weekShift] 是两条正交的时间轴。
  IntColumn get timeShiftMinutes => integer().withDefault(const Constant(0))();

  /// 导入来源文件名，便于追溯「这套课表是哪来的」。
  TextColumn get sourceName => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 一条规律性课程排课 —— 即「某门课在星期几的第几节、上哪些周」。
///
/// 粒度是「一次排课」而不是「一门课」：教务系统里同一门课（如大学外语）
/// 在周三和周五各出现一次，就是两条规则。课程级的操作（改色、整门删除）
/// 按 [title] 分组进行，不额外建表。
class CourseRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get setId =>
      integer().references(CalendarSets, #id, onDelete: KeyAction.cascade)();

  TextColumn get title => text()();
  TextColumn get teacher => text().withDefault(const Constant(''))();
  TextColumn get location => text().withDefault(const Constant(''))();

  /// 手动指定的课程颜色；null 表示按 [title] 哈希自动分配。
  TextColumn get colorOverrideHex => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// 1=周一 … 7=周日。
  IntColumn get weekday => integer()();

  /// 起始 / 结束节次（1-based，含）。「第一二节」是 1..2。
  IntColumn get startPeriod => integer()();
  IntColumn get endPeriod => integer()();

  /// 上课周次，展开集合。
  TextColumn get weeks => text().map(const IntListConverter())();

  BoolColumn get remindersEnabled => boolean().withDefault(const Constant(true))();

  /// 提前多少分钟提醒；null 表示沿用全局默认。
  IntColumn get leadMinutes => integer().nullable()();
}

/// 手动添加的单次事件（不在任何周次规律里）。
class OneOffEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get setId =>
      integer().references(CalendarSets, #id, onDelete: KeyAction.cascade)();

  TextColumn get title => text()();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get colorHex => text().nullable()();

  DateTimeColumn get date => dateTime()();

  /// 距当日 00:00 的分钟数。与节次解耦 —— 单次事件不必落在整节上。
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
}

/// 对某条规则在某个具体日期的改动（单次改期、停课一次、临时换教室）。
///
/// 不改 [CourseRules]，只在渲染时叠加 —— 这样「这节课调走了」不会污染
/// 整学期的规律，撤销也只是删掉这一行。
class OccurrenceOverrides extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ruleId =>
      integer().references(CourseRules, #id, onDelete: KeyAction.cascade)();

  /// 被覆盖的那一次原本的日期（未经平移的原始日期）。
  DateTimeColumn get originalDate => dateTime()();

  /// 这一次停课。
  BoolColumn get cancelled => boolean().withDefault(const Constant(false))();

  DateTimeColumn get newDate => dateTime().nullable()();
  IntColumn get newStartMinute => integer().nullable()();
  IntColumn get newEndMinute => integer().nullable()();
  TextColumn get newLocation => text().nullable()();
  TextColumn get newTitle => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
