import '../../core/time/periods.dart';
import 'domain.dart';

// 解析函数与它消费/产出的类型是同一套 API，调用方不该被逼着 import 两个文件。
export 'domain.dart';

/// 三层叠加解析。
///
/// 叠加顺序**固定**为：
///
/// ```
/// 模板 CourseTemplate  →  单次覆盖 OverrideData  →  套级平移 SetShifts
/// ```
///
/// 这个顺序不是随手定的，换任何一步都会出错：
///
/// * 覆盖必须**先于**平移 —— 覆盖记录的匹配键是「未经平移的原始日期」。
///   若先平移，学期中途调整 weekShift 会让已存在的覆盖记录全部错位一天都算不上、
///   而是差好几周，且无法恢复。
/// * 平移必须**最后**且只作用一次 —— 它是纯显示层的偏移量，写入数据库的
///   日期永远是不含平移的「套内本地日期」。这样反复平移不会累积误差，
///   归零就精确回到原状。
///
/// **推论（写编辑器时务必遵守）**：任何由用户输入的日期在落库前都要**减去**
/// 当前平移量换算回套内本地日期；只有渲染和提醒调度才应用平移。
///
/// 另一个刻意的决定：**平移对单次事件同样生效**。「整体后移一周」的含义是
/// 整套日程一起挪，手动加的事件留在原地反而是意外行为。
class ResolveOutcome {
  const ResolveOutcome(this.sessions, this.warnings);

  final List<ResolvedSession> sessions;

  /// 无法解析的条目（例如模板用了本作息表里不存在的节次）。
  /// 记下来而不是抛异常 —— 导入别的学校的 ICS 时，跳过坏条目比整个失败好。
  final List<String> warnings;
}

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// 把 [templates] / [oneOffs] 按 [shifts] 展开成具体的上课时刻。
///
/// 解析结果的周次由**平移后**的日期反推，因此 weekShift = +1 会让全部课程
/// 出现在下一周 —— 这正是「整体后移一周」的直觉含义。
///
/// [setId] 会原样盖到每条产出的事件上，用来回答「这条事件属于哪个日程」。
/// **做成可选具名参数**（默认 [kNoSetId]）而不是必填：这个函数有二十多处调用点，
/// 而其中绝大多数（导出、单次详情、几十处测试夹具）根本不关心归属，
/// 逼它们各写一个 `setId: 0` 只会训练人无脑粘一个魔数。真正需要它的两处
/// （`resolvedSessionsProvider` / `allSessionsProvider`）在
/// `native_sync_test.dart` 里有一条探针测试盯着。
ResolveOutcome resolveSessions({
  required SetShifts shifts,
  required List<CourseTemplate> templates,
  required List<OneOffData> oneOffs,
  required List<OverrideData> overrides,
  int setId = kNoSetId,
}) {
  final warnings = <String>[];
  final out = <ResolvedSession>[];

  // (ruleId, 原始日期) → 覆盖。用复合键而不是嵌套 Map，
  // 因为同一规则在同一日期只可能有一条覆盖（upsertOverride 保证了这点）。
  final overrideIndex = <String, OverrideData>{};
  for (final o in overrides) {
    overrideIndex['${o.ruleId}@${_dayKey(o.originalDate)}'] = o;
  }

  final dateShift = Duration(days: shifts.weekShift * 7);
  final minuteShift = shifts.timeShiftMinutes;

  // ---- 第一层 + 第二层：模板 × 周次，逐次叠加覆盖 ----
  for (final t in templates) {
    // 起始看「以第几节开头」的大节，结束看「包含第几节」的大节。
    // 两者不是一回事：1-4 节连堂的课起始是第 1 大节、结束是第 3-4 节那个大节，
    // 结束时间必须是 11:40 而不是 09:40。
    final startSlot = slotForStartPeriod(t.startPeriod);
    final endSlot = slotForPeriod(t.endPeriod);

    for (final week in t.weeks) {
      // 锚点可能在别的年份，dateFor 会做归一化；week <= 0 是脏数据，跳过。
      if (week <= 0) continue;
      final originalDate = dateFor(
        week1Monday: shifts.week1Monday,
        week: week,
        weekday: t.weekday,
      );

      final ov = overrideIndex['${t.id}@${_dayKey(originalDate)}'];
      // 停课的条目**照样产出**，只是打上 cancelled。剔除看着更干净，但会让
      // 「停课一次」变成不可逆操作 —— 块从网格上消失之后，就再没有入口能
      // 点开它、把它恢复回来。留一条画成灰色的幽灵块，撤销才有地方可点。
      final cancelled = ov?.cancelled ?? false;

      final baseDate = ov?.newDate ?? originalDate;

      // 分钟级的来源优先级：单次覆盖 > 节次作息表。
      // 两个都没有（既没覆盖、节次又不在作息表里）才算无法解析。
      final baseStart = ov?.newStartMinute ?? startSlot?.startMinute;
      final baseEnd = ov?.newEndMinute ?? endSlot?.endMinute;
      if (baseStart == null || baseEnd == null) {
        warnings.add('「${t.title}」第 $week 周用了作息表中不存在的节次 ${t.startPeriod}-${t.endPeriod}，已跳过');
        continue;
      }

      // ---- 第三层：套级平移，最后应用且只应用一次 ----
      final date = baseDate.add(dateShift);
      out.add(
        ResolvedSession(
          setId: setId,
          date: dateOnly(date),
          weekday: date.weekday,
          week: weekOf(week1Monday: shifts.week1Monday, date: date),
          startMinute: baseStart + minuteShift,
          endMinute: baseEnd + minuteShift,
          title: ov?.newTitle ?? t.title,
          teacher: t.teacher,
          location: ov?.newLocation ?? t.location,
          note: t.note,
          colorHex: t.colorHex,
          ruleId: t.id,
          startPeriod: t.startPeriod,
          endPeriod: t.endPeriod,
          originalDate: originalDate,
          // 停课也算「被调整过」—— 面板要据此把「撤销停课」置成可点。
          adjusted: ov != null && (ov.hasChange || cancelled),
          cancelled: cancelled,
          leadMinutes: t.leadMinutes,
          remindersEnabled: t.remindersEnabled,
        ),
      );
    }
  }

  // ---- 单次事件 ----
  for (final e in oneOffs) {
    final date = dateOnly(e.date.add(dateShift));
    out.add(
      ResolvedSession(
        setId: setId,
        date: date,
        weekday: date.weekday,
        week: weekOf(week1Monday: shifts.week1Monday, date: date),
        startMinute: e.startMinute + minuteShift,
        endMinute: e.endMinute + minuteShift,
        title: e.title,
        location: e.location,
        note: e.note,
        colorHex: e.colorHex,
        oneOffId: e.id,
      ),
    );
  }

  out.sort(ResolvedSession.compare);
  return ResolveOutcome(out, warnings);
}

/// 界面上显示的日期 → **套内本地日期**（落库用）。
///
/// 每一个由用户输入的日期都必须先过这一道。平移是纯渲染层的偏移量，
/// 数据库里存的永远是不含平移的日期；直接把用户看到的日期存进去，
/// 它会在渲染时被再平移一次，「后移一周」就变成了后移两周。
DateTime toLocalSetDate(DateTime shown, SetShifts shifts) =>
    dateOnly(shown.subtract(Duration(days: shifts.weekShift * 7)));

/// 套内本地日期 → 界面上应当显示的日期。[toLocalSetDate] 的反函数。
DateTime fromLocalSetDate(DateTime local, SetShifts shifts) =>
    dateOnly(local.add(Duration(days: shifts.weekShift * 7)));

/// 取落在 [week] 周内的全部课程 —— 课表网格一屏就取这一次。
///
/// **只对同一个日程成立。** 它比的是事件自带的 `week` 字段，而那个字段是各日程
/// 按自己的 `week1Monday` 和 `weekShift` 算出来的 —— 两个日程的「第 5 周」可能
/// 根本不是同一个星期。跨日程一律用 [sessionsInWeekRange]。
List<ResolvedSession> sessionsInWeek(List<ResolvedSession> all, int week) =>
    all.where((s) => s.week == week).toList();

/// [week1Monday] 的第 [week] 周覆盖的日期区间：`[周一, 下周一)`。
({DateTime start, DateTime end}) weekDateRange({
  required DateTime week1Monday,
  required int week,
}) {
  final start = dateOnly(week1Monday).add(Duration(days: (week - 1) * 7));
  return (start: start, end: start.add(const Duration(days: 7)));
}

/// 取**日期**落在 [week1Monday] 的第 [week] 周里的全部事件。
///
/// **和 [sessionsInWeek] 是两件事，混用会静默出错。** 差别只在筛选键：
/// 那边比 `week` 字段，这边比 `date`。
///
/// 跨日程的视图（总览页、小组件的总览块）**必须**用这个：总览借的是某一个日程的
/// 坐标系（它自己没有周号），拿那个坐标系换出日期区间之后，让所有日程的事件按
/// **日期**落进来 —— 于是每个日程贡献的都是**它自己真实落在这一周**的那些课。
/// 换成比 `week` 字段的话，`week1Monday` 与锚点不同的那个日程会整周错位。
///
/// 代价写在明处：锚点日程的第 N 周，对另一个日程来说可能是它的第 N±k 周。
/// 这不是没修好，是「把两个不同起点的周次合并」本来就没有唯一正确答案
/// —— 所以总览的标题只写日期区间，不写「第 N 周」。
List<ResolvedSession> sessionsInWeekRange(
  List<ResolvedSession> all, {
  required DateTime week1Monday,
  required int week,
}) {
  final r = weekDateRange(week1Monday: week1Monday, week: week);
  return all
      .where((s) {
        final d = dateOnly(s.date);
        return !d.isBefore(r.start) && d.isBefore(r.end);
      })
      .toList();
}

/// 取某一天的全部课程，按时间排序。
List<ResolvedSession> sessionsOnDay(List<ResolvedSession> all, DateTime day) =>
    all.where((s) => isSameDay(s.date, day)).toList()
      ..sort(ResolvedSession.compare);

/// 全部数据覆盖到的周次范围（含），用于周次选择器的上下界。
/// 空数据返回 `(1, 1)`。
({int first, int last}) weekRange(List<ResolvedSession> all) {
  if (all.isEmpty) return (first: 1, last: 1);
  var lo = all.first.week;
  var hi = lo;
  for (final s in all) {
    if (s.week < lo) lo = s.week;
    if (s.week > hi) hi = s.week;
  }
  return (first: lo, last: hi);
}
