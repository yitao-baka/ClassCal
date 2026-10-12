/// 领域层的纯数据模型与叠加解析。
///
/// 这一层**刻意不依赖 drift、也不依赖 Flutter**，原因有两个：
/// 一是三层叠加顺序（模板 → 单次覆盖 → 套级平移）是整套设计里最容易出
/// 边界错误的地方，必须能用 `dart test` 直接钉死，不该被数据库或 widget
/// 环境拖累；二是 drift 生成的行类（`CourseRule` 等）是持久化细节，
/// 让 UI 直接吃它会使得「换个存储」变成全量重写。
library;

/// 节次 ↔ 时间换算；复用 `core/time/periods.dart`，这里再导出一次方便调用方。
export '../../core/time/periods.dart' show slotForStartPeriod, kPeriodSlots, PeriodSlot;

/// `copyWith` 的「未提供」哨兵。
///
/// 直接用 `null` 当默认值是个陷阱：`copyWith(colorHex: null)` 会算成
/// `null ?? this.colorHex`，也就是**什么都没做**。于是「清除自定义颜色」
/// 「取消单次改期」「把某节课从网格上摘掉」这类操作全都静默失效，
/// 而且编译期不报错、测试不覆盖就发现不了。
///
/// 因此**可空字段一律用它当默认值**：不传 = 保持不变，显式传 `null` = 真的置空。
const Object kUnset = Object();

/// 「这条事件不属于任何一个日程」。
///
/// 值是 0，因为 drift 的 `INTEGER PRIMARY KEY AUTOINCREMENT` 从 **1** 开始 ——
/// 0 永远不会是某个日程的真实 id，当哨兵不会和真值撞车。
///
/// 存在的理由：测试夹具和「还没落库的临时会话」需要一条不指向任何日程的事件。
/// **生产路径上不该出现它** —— `allSessionsProvider` 里有一条探针测试盯着
/// 每一条事件的 `setId >= 1`。
const int kNoSetId = 0;

/// 一条规律性排课。「大学外语周三第 3-4 节，第 5-16 周」就是一条。
class CourseTemplate {
  const CourseTemplate({
    required this.id,
    required this.title,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    this.teacher = '',
    this.location = '',
    this.note = '',
    this.colorHex,
    this.remindersEnabled = true,
    this.leadMinutes,
  });

  final int id;
  final String title;

  /// 1=周一 … 7=周日。
  final int weekday;

  /// 1-based，含。
  final int startPeriod;
  final int endPeriod;

  /// 展开的周次集合（不是区间），渲染时只剩一句 `contains`。
  final List<int> weeks;

  final String teacher;
  final String location;
  final String note;

  /// 手动指定的颜色；null 表示按标题哈希自动分配。
  final String? colorHex;

  final bool remindersEnabled;

  /// 提前多少分钟提醒；null 表示沿用全局默认。
  final int? leadMinutes;

  CourseTemplate copyWith({
    int? id,
    String? title,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    List<int>? weeks,
    String? teacher,
    String? location,
    String? note,
    Object? colorHex = kUnset,
    bool? remindersEnabled,
    Object? leadMinutes = kUnset,
  }) =>
      CourseTemplate(
        id: id ?? this.id,
        title: title ?? this.title,
        weekday: weekday ?? this.weekday,
        startPeriod: startPeriod ?? this.startPeriod,
        endPeriod: endPeriod ?? this.endPeriod,
        weeks: weeks ?? this.weeks,
        teacher: teacher ?? this.teacher,
        location: location ?? this.location,
        note: note ?? this.note,
        colorHex: identical(colorHex, kUnset) ? this.colorHex : colorHex as String?,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        leadMinutes:
            identical(leadMinutes, kUnset) ? this.leadMinutes : leadMinutes as int?,
      );
}

/// 手动添加的单次事件，不参与周次规律。
class OneOffData {
  const OneOffData({
    required this.id,
    required this.title,
    required this.date,
    required this.startMinute,
    required this.endMinute,
    this.location = '',
    this.note = '',
    this.colorHex,
  });

  final int id;
  final String title;
  final DateTime date;

  /// 距当日 00:00 的分钟数。与节次解耦 —— 单次事件不必落在整节上。
  final int startMinute;
  final int endMinute;

  final String location;
  final String note;
  final String? colorHex;

  OneOffData copyWith({
    int? id,
    String? title,
    DateTime? date,
    int? startMinute,
    int? endMinute,
    String? location,
    String? note,
    Object? colorHex = kUnset,
  }) =>
      OneOffData(
        id: id ?? this.id,
        title: title ?? this.title,
        date: date ?? this.date,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        location: location ?? this.location,
        note: note ?? this.note,
        colorHex: identical(colorHex, kUnset) ? this.colorHex : colorHex as String?,
      );
}

/// 对某条模板在**某一个原始日期**上的改动。
///
/// 不改模板本身，只在渲染时叠加 —— 这样「这节课调走了」不会污染整学期的规律，
/// 撤销就是删掉这一行。
class OverrideData {
  const OverrideData({
    required this.ruleId,
    required this.originalDate,
    this.cancelled = false,
    this.newDate,
    this.newStartMinute,
    this.newEndMinute,
    this.newLocation,
    this.newTitle,
  });

  final int ruleId;

  /// 被覆盖的那一次**未经任何平移**的原始日期 —— 匹配键。
  final DateTime originalDate;

  /// 这一次停课。
  final bool cancelled;

  /// 改期到的日期。语义上是「套内本地日期」，因此之后仍会被套级 [SetShifts.weekShift] 平移。
  final DateTime? newDate;

  final int? newStartMinute;
  final int? newEndMinute;
  final String? newLocation;
  final String? newTitle;

  /// 这次覆盖是否真的改变了什么（用于 UI 上打「已调整」角标）。
  bool get hasChange => cancelled || newDate != null || newStartMinute != null || newEndMinute != null;
}

/// 一整套课表 —— 一个标签页的完整内容。
///
/// 这是导入/导出的传输单位，也是仓库层对外的聚合根：UI 拿到它就能渲染，
/// 不必再去拼三张表。
class CalendarSetData {
  const CalendarSetData({
    required this.id,
    required this.name,
    required this.shifts,
    this.colorSeedHex = '#6750A4',
    this.tabOrder = 0,
    this.visible = true,
    this.sourceName,
    this.templates = const [],
    this.oneOffs = const [],
    this.overrides = const [],
  });

  /// 尚未落库的新课表用 [unsavedId]。
  static const int unsavedId = -1;

  final int id;
  final String name;
  final SetShifts shifts;
  final String colorSeedHex;
  final int tabOrder;
  final bool visible;

  /// 导入来源文件名，便于追溯「这套课表是哪来的」。
  final String? sourceName;

  final List<CourseTemplate> templates;
  final List<OneOffData> oneOffs;
  final List<OverrideData> overrides;

  CalendarSetData copyWith({
    int? id,
    String? name,
    SetShifts? shifts,
    String? colorSeedHex,
    int? tabOrder,
    bool? visible,
    Object? sourceName = kUnset,
    List<CourseTemplate>? templates,
    List<OneOffData>? oneOffs,
    List<OverrideData>? overrides,
  }) =>
      CalendarSetData(
        id: id ?? this.id,
        name: name ?? this.name,
        shifts: shifts ?? this.shifts,
        colorSeedHex: colorSeedHex ?? this.colorSeedHex,
        tabOrder: tabOrder ?? this.tabOrder,
        visible: visible ?? this.visible,
        sourceName:
            identical(sourceName, kUnset) ? this.sourceName : sourceName as String?,
        templates: templates ?? this.templates,
        oneOffs: oneOffs ?? this.oneOffs,
        overrides: overrides ?? this.overrides,
      );
}

/// 一套课表的两个套级偏移量。
class SetShifts {
  const SetShifts({
    required this.week1Monday,
    this.weekShift = 0,
    this.timeShiftMinutes = 0,
  });

  /// 该套课表第 1 周的周一 —— 全部日期换算的锚点。
  final DateTime week1Monday;

  /// 整体前后移动的周数，可负。
  final int weekShift;

  /// 整体前后移动的分钟数，可负。与 [weekShift] 是两条正交的时间轴。
  final int timeShiftMinutes;
}

/// 一次**已经解析完**的具体上课时刻 —— 三层叠加之后的最终结果。
///
/// UI 只消费这个类型，不再自己算偏移。
class ResolvedSession {
  const ResolvedSession({
    required this.date,
    required this.startMinute,
    required this.endMinute,
    required this.title,
    this.setId = kNoSetId,
    this.weekday = 0,
    this.week = 0,
    this.teacher = '',
    this.location = '',
    this.note = '',
    this.colorHex,
    this.ruleId,
    this.oneOffId,
    this.startPeriod,
    this.endPeriod,
    this.originalDate,
    this.adjusted = false,
    this.cancelled = false,
    this.leadMinutes,
    this.remindersEnabled = true,
  });

  /// 这条事件属于哪个日程。
  ///
  /// **不给默认值就没法构造测试夹具**，所以默认 [kNoSetId]；但生产路径上每条都应当
  /// 由 `resolveSessions(setId:)` 盖上真实的 id —— 提醒要按它取那套参数，
  /// 总览页要按它打开正确的那个日程，小组件要按它筛。
  final int setId;

  /// 最终日期（已应用 [SetShifts.weekShift]）。
  final DateTime date;

  /// 最终时钟时间（已应用 [SetShifts.timeShiftMinutes]）。
  final int startMinute;
  final int endMinute;

  /// 冗余出来的日期派生量 —— 渲染时按天/按周分桶要用，放在这里避免每帧重算。
  final int weekday;
  final int week;

  final String title;
  final String teacher;
  final String location;
  final String note;
  final String? colorHex;

  /// 来源：模板规则的 id；单次事件为 null。
  final int? ruleId;
  final int? oneOffId;

  /// 网格行定位用的节次。
  ///
  /// **故意不受 [SetShifts.timeShiftMinutes] 影响**：课表网格的行是「第几大节」，
  /// 分钟级平移只改实际钟点（和提醒时刻），若让它把课程推离所在行，
  /// 网格就再也对不上课表了。单次事件没有节次，为 null。
  final int? startPeriod;
  final int? endPeriod;

  /// 模板推出的原始日期（未平移），用于反查覆盖记录 / 撤销。
  final DateTime? originalDate;

  /// 被单次覆盖改动过。
  final bool adjusted;

  /// 这一次被停掉了（只影响这一天）。
  ///
  /// **停课的条目仍然留在解析结果里**，而不是直接剔除。剔除看着更干净，
  /// 但会让「停课一次」变成一个不可逆操作：那节课从网格上消失之后，
  /// 就再没有任何入口能点开它、把它恢复回来。留一条画成灰色的幽灵块，
  /// 「撤销停课」才有地方可点。
  ///
  /// 需要「真的没有这节课」的地方要显式过滤 —— 导出、提醒、日程列表都算。
  final bool cancelled;

  final int? leadMinutes;
  final bool remindersEnabled;

  ResolvedSession copyWith({
    DateTime? date,
    int? startMinute,
    int? endMinute,
    String? title,
    int? setId,
    int? weekday,
    int? week,
    String? teacher,
    String? location,
    String? note,
    Object? colorHex = kUnset,
    Object? ruleId = kUnset,
    Object? oneOffId = kUnset,
    Object? startPeriod = kUnset,
    Object? endPeriod = kUnset,
    Object? originalDate = kUnset,
    bool? adjusted,
    bool? cancelled,
    Object? leadMinutes = kUnset,
    bool? remindersEnabled,
  }) =>
      ResolvedSession(
        date: date ?? this.date,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        title: title ?? this.title,
        setId: setId ?? this.setId,
        weekday: weekday ?? this.weekday,
        week: week ?? this.week,
        teacher: teacher ?? this.teacher,
        location: location ?? this.location,
        note: note ?? this.note,
        colorHex: identical(colorHex, kUnset) ? this.colorHex : colorHex as String?,
        ruleId: identical(ruleId, kUnset) ? this.ruleId : ruleId as int?,
        oneOffId: identical(oneOffId, kUnset) ? this.oneOffId : oneOffId as int?,
        startPeriod:
            identical(startPeriod, kUnset) ? this.startPeriod : startPeriod as int?,
        endPeriod: identical(endPeriod, kUnset) ? this.endPeriod : endPeriod as int?,
        originalDate: identical(originalDate, kUnset)
            ? this.originalDate
            : originalDate as DateTime?,
        adjusted: adjusted ?? this.adjusted,
        cancelled: cancelled ?? this.cancelled,
        leadMinutes:
            identical(leadMinutes, kUnset) ? this.leadMinutes : leadMinutes as int?,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      );

  /// 排序列用：同一天内按开始时间排，最后按日程 id 兜底。
  ///
  /// **最后那一级不是装饰**：`List.sort` 在 Dart 里**不是稳定排序**，所以
  /// 「同一天同一分钟」的两条事件相对顺序是任意的，同一次运行的两次排序都可能不同。
  /// 而小组件的周网格**靠这个顺序决定同格分栏谁左谁右** —— 于是桌面上那两栏
  /// 可能每次刷新翻个面。
  ///
  /// 加 `setId` 兜底之后，同一个日程内部 setId 是常量，**网格观感完全不变**，
  /// 只是把不确定变成了确定。跨日程撞在同一时刻时，轮到的那个顺序是「id 小的在左」，
  /// 这条本身就是个说得清、可复现的规则。
  static int compare(ResolvedSession a, ResolvedSession b) {
    final d = a.date.compareTo(b.date);
    if (d != 0) return d;
    final m = a.startMinute.compareTo(b.startMinute);
    return m != 0 ? m : a.setId.compareTo(b.setId);
  }

  @override
  String toString() => 'ResolvedSession($title @ $date $startMinute-$endMinute)';
}
