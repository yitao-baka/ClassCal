/// 桌面小组件要显示的一切 —— 纯计算，不碰平台、不碰 Android。
///
/// 单独成一层，理由和 `core/reminder/reminder_plan.dart` 完全同构：小组件渲染
/// 发生在 **App 已经死掉的时候**（桌面上那张卡片归启动器进程管），所以原生侧
/// 只能拿一份预先算好、落了盘的快照自己画。算错的代价是「桌面上摆着一份看着
/// 正常、其实和 App 里对不上的课表」，而那种错误不会有任何报错。
///
/// 因此这里定下一条原则，整份文件都在执行它：
///
/// > **Kotlin 侧不做任何日历运算。**
///
/// 「今天几号」「这是第几周」「现在是 08:00」全部在这里算完，用绝对毫秒和
/// 现成的字符串发过去。原生侧只做两件事：`now` 与 `startAtMs` 的大小比较、
/// 以及按日期区间把事件分到某一列。理由不是洁癖 —— 颜色、周次这些逻辑在 App 里
/// 已经有一份了（[courseColor] / `weekOf`），在 Kotlin 里再写一份，两份就会
/// 慢慢走偏，而走偏的表现是「同一门课在 App 里是蓝的、在桌面上是绿的」。
///
/// ## 每个日程一块（[WidgetSetBlock]）
///
/// 一个实例可以显示**某一个日程**（而不是把所有日程合起来）。所以周次、标题、
/// 网格这一组坐标**不能是一个全局值**：两个日程的 `week1Monday` 不同时，
/// 「第 5 周」落在不同的日期上。
///
/// 于是每块自带[七天的本地零点][WidgetSetBlock.gridDayStartsMs]，原生侧据此
/// **按日期区间**筛事件、算列号 —— 全是减法，一个字都没有重新做日历运算。
/// 「按周号筛」在总览那件事上必然错，理由和 App 里总览页那一处逐字相同。
library;

import 'package:flutter/material.dart';

import '../../data/model/resolve.dart';
import '../text/course_abbr.dart';
import '../theme/course_colors.dart';
import '../time/periods.dart';

/// 快照的结构版本。原生侧读不懂的版本要当作「没有快照」，而不是硬解析。
///
/// **2** 把周次 / 标题 / 网格坐标从顶层搬进了 `blocks`（每个日程一块），
/// 并给每条事件加了 `setId`。老快照（v1）一律当过期，桌面上短暂显示
/// 「打开 ClassCal 更新」，打开一次 App 就恢复 —— 比写一段迁移诚实：
/// v1 里根本没有「这条事件属于哪个日程」这个维度，补不出来。
const int kWidgetSnapshotVersion = 2;

/// 总览块在 [WidgetSnapshot.blocks] 里的 id。
///
/// **不是 -1**：`-1` 已经被 `CalendarSetData.unsavedId` 占用表示「还没落库」，
/// 两个概念共用一个哨兵迟早出事。drift 的自增 id 从 1 开始，负数撞不上。
/// Kotlin 侧 `WidgetSetBlock.OVERVIEW_ID` 必须和它一致（契约测试钉着）。
const int kOverviewBlockId = -2;

/// 快照往前铺几天。
///
/// **比提醒的 30 天短得多，理由正好相反**：漏掉一条提醒是「没看到」，
/// 而桌面上一张过期的课表是「看到错的」—— 后者更坏。窗口只要盖住
/// 「本周 + 明天」就够了，再往后的日子用户本来就要打开 App 才看得见。
const int kWidgetHorizonDays = 9;

/// 桌面小组件的一套配色。
///
/// 四个值都是从 `ColorScheme` 里取好的具体颜色，**不是 Material 角色名** ——
/// 原生侧不参与「surface 该配哪个色阶」这种映射，那是会随 Flutter 版本变的东西。
class WidgetTheme {
  const WidgetTheme({
    required this.surface,
    required this.onSurface,
    required this.secondary,
    required this.accent,
    required this.onAccent,
  });

  /// 卡片底色。
  final int surface;

  /// 主要文字色（课名）。
  final int onSurface;

  /// 次要文字色（时间、教室）。比 [onSurface] 淡一档，
  /// 否则满屏同一种黑，信息层级就没了。
  final int secondary;

  /// 强调色。用在「正在上课」的竖条、今天的日期列这些地方。
  final int accent;

  /// 压在 [accent] 上的前景色。
  final int onAccent;

  Map<String, Object?> toJson() => {
        'surface': surface,
        'onSurface': onSurface,
        'secondary': secondary,
        'accent': accent,
        'onAccent': onAccent,
      };
}

/// 一次课在小组件里的样子。全是现成的数字和字符串，原生侧拿来就能画。
class WidgetSession {
  const WidgetSession({
    required this.startAtMs,
    required this.endAtMs,
    required this.weekday,
    required this.title,
    required this.location,
    required this.startLabel,
    required this.endLabel,
    required this.dayLabel,
    required this.dateLabel,
    required this.periodLabel,
    required this.color,
    required this.onColor,
    this.setId = kNoSetId,
    this.abbr = '',
    this.gridRow = 0,
    this.gridRowSpan = 1,
  });

  /// 上课/下课时刻，**绝对本地时刻**的 epoch 毫秒。
  ///
  /// 刻意不发「日期 + 分钟数」两件套：那样原生侧要自己做时区、跨日那些算术，
  /// 而 `now` 与它比的又是一次减法 —— 少一件要算的东西就少一处会算错的地方。
  /// 这套约定在 `ReminderSpec.classStartMs` 上已经用过一轮了。
  final int startAtMs;
  final int endAtMs;

  /// 这条事件属于哪个日程。原生侧拿它跟块的 id 比 —— 「这个实例配的是哪个
  /// 日程」就落在这一次整数比较上。
  ///
  /// 默认 [kNoSetId] 只为测试夹具存在；生产路径上每条都经过 `resolveSessions`，
  /// 而它一定会盖上真实的 setId（`native_sync_test.dart` 里有一条探针盯着）。
  final int setId;

  /// 星期几（1=周一）。列号由块按**绝对日期**算，但列表那两种布局要拿它拼
  /// 「周三」这类现成的标签，所以照样发。
  final int weekday;

  final String title;
  final String location;

  /// 已经格式化好的 `08:00` / `09:40`。原生侧不碰时间格式化。
  final String startLabel;
  final String endLabel;

  /// `周三`、`10/8`。「今天是几号」是日历运算，所以在这一侧做完。
  final String dayLabel;
  final String dateLabel;

  /// `第一二节`；单次事件（没有节次）为空串。
  final String periodLabel;

  /// 已经解析好的课程色与它的前景色（有符号 32 位 ARGB）。
  final int color;
  final int onColor;

  /// 周网格格子里画的那个缩写（`高数` / `离散`）。
  ///
  /// 在这一侧算，理由和 [color] 一样：它是「标题 → 缩写」的映射，在
  /// `core/text/course_abbr.dart` 里只有一份（预置表 + 用户覆盖）。
  /// 原生侧拿到就用，不认识也不需要认识——它只是画一行字。
  ///
  /// 这条链子上最容易出错的是**两边各写一份规则**：那样预置表改了、
  /// 用户在设置里自定义了，桌面上的格子纹丝不动，而且不报错。
  final String abbr;

  /// 周缩略网格里的行号（0-based，一行 = 一个大节）与跨行数。
  ///
  /// **这不是「日历运算」，但同样是原生侧不该自己算的东西**：行号来自
  /// `periods.dart` 的 `kPeriodSlots`，那样一张作息表在 Kotlin 里再抄一份，
  /// 改版时必然只改一边 —— 而表现是「桌面上那张网格里，课全挤在第一行」。
  ///
  /// [-1][gridRow] 表示这节**不在网格里**：单次事件在作息时间之外（清早、深夜）。
  /// 它照样出现在列表里，只是周网格里没有它的位置。
  final int gridRow;
  final int gridRowSpan;

  Map<String, Object?> toJson() => {
        'startAtMs': startAtMs,
        'endAtMs': endAtMs,
        'setId': setId,
        'weekday': weekday,
        'title': title,
        'location': location,
        'startLabel': startLabel,
        'endLabel': endLabel,
        'dayLabel': dayLabel,
        'dateLabel': dateLabel,
        'periodLabel': periodLabel,
        'color': color,
        'onColor': onColor,
        'abbr': abbr,
        'gridRow': gridRow,
        'gridRowSpan': gridRowSpan,
      };
}

/// **一个日程一块** —— 这块自己的周次、标题、网格坐标。
///
/// 为什么这一组要按日程各算一份，而不是像从前那样顶层算一份：一个被钉在某个
/// 日程上的实例，标题该显示**那个日程的**「第 5 周」。而两个日程的 `week1Monday`
/// 不同时，「第 5 周」落在不同的日期上 —— 一个全局值必然对其中一个日程是错的。
///
/// **总览也是一块**（[id] = [kOverviewBlockId]）。它不是某个日程，所以
/// [currentWeek] 是 0、[weekTitle] 里也**没有**「第 N 周」，只有日期区间 ——
/// 它没有自己的周号，硬写一个就是编的。
class WidgetSetBlock {
  const WidgetSetBlock({
    required this.id,
    required this.name,
    required this.currentWeek,
    required this.weekTitle,
    required this.gridWeek,
    required this.gridRows,
    required this.gridDayStartsMs,
  });

  /// 日程 id；总览块是 [kOverviewBlockId]。
  final int id;

  /// 日程名；总览块是「总览」。小组件上那条日程名信息条直接读它 ——
  /// 空串等于那一栏凭空消失，所以这里不允许为空（测试钉着）。
  final String name;

  /// 这个日程自己的「现在第几周」；算不出来（不在学期内）时为 0。
  final int currentWeek;

  /// `第 5 周 · 10/5–10/11`；不在学期内时为空串。总览块是 `10/5–10/11`。
  final String weekTitle;

  /// 周网格画哪一周（**这个日程编号体系里的**第几周）。
  final int gridWeek;

  /// 周网格有几行 = 一天有几个大节（`kPeriodRowCount`）。
  /// 和 [WidgetSession.gridRow] 配套，两边共用 `periods.dart` 那一张作息表。
  final int gridRows;

  /// **[gridWeek] 那一周的七个本地零点**（周一 … 周日，正好 7 个）。
  ///
  /// 这是「按日期筛而不是按周号筛」成立的关键：原生侧手上就有了绝对时刻，
  /// 判一条事件在不在这一周、落在哪一列，全是减法 —— **一个字都没有重做
  /// 日历运算**，「Kotlin 不做日历运算」那条约束仍然成立。
  ///
  /// 总览块的这七个零点**借用当前日程那一周的日期**（总览必须有个坐标系）。
  final List<int> gridDayStartsMs;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'currentWeek': currentWeek,
        'weekTitle': weekTitle,
        'gridWeek': gridWeek,
        'gridRows': gridRows,
        'gridDayStartsMs': gridDayStartsMs,
      };
}

/// 「多大算大」这件事的定义。
///
/// 放进快照而不是写死在 Kotlin 的 `when` 里，是为了让它**只有一处定义**，
/// 而且能在 `dart test` 里把边界钉死。原生侧读这几个数字跑同一段阶梯。
class WidgetLayout {
  const WidgetLayout({
    this.smallMaxHeightDp = 110,
    this.largeMinWidthDp = 250,
    this.largeMinHeightDp = 180,
    this.maxListRows = 8,
  });

  /// 高度小于这个值算「小」（画下一节课）。
  ///
  /// 判据是**高**不是宽。一开始写的是宽度，那是个错：一条「下一节课」放不下
  /// 三行，卡住它的是竖直空间，跟有多宽没关系。而启动器报回来的宽度是**格数
  /// 乘格子宽**（4 列网格上一个 2×1 大约 190dp），180 这条线正好落在它下面 ——
  /// 于是「小」这一档在 4 列网格上**永远不会命中**，2×1 的小组件会去画
  /// 今天的课单，然后挤成一团。换成高度之后，1 格高（约 84dp）和 2 格高
  /// （约 170dp）之间有个很宽的缝，110 落在正中间。
  final int smallMaxHeightDp;

  /// 宽和高**同时**达到这两个值才算「大」（画本周缩略网格）。
  /// 只看宽度的话，一个 4×2 的扁条也会被当成大的，而 5 行网格塞不进 110dp 高。
  final int largeMinWidthDp;
  final int largeMinHeightDp;

  /// 列表最多画几行 —— 是个**上限**，不是实际行数。
  ///
  /// 真正画几行由原生侧按卡片高度算（`WidgetRenderer.rowsThatFit`），
  /// 放不下的折成「还有 N 节」。这里只兜一个「再高也别画成几十行」的底。
  /// 8 这个值是照着最高的那一档取的：4×4 大约 380dp 高，一行 34dp，
  /// 减掉标题和页脚差不多正好八行。
  final int maxListRows;

  Map<String, Object?> toJson() => {
        'smallMaxHeightDp': smallMaxHeightDp,
        'largeMinWidthDp': largeMinWidthDp,
        'largeMinHeightDp': largeMinHeightDp,
        'maxListRows': maxListRows,
      };
}

/// 推给原生并落盘的那份东西。
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.version,
    required this.generatedAtMs,
    required this.todayYear,
    required this.todayMonth,
    required this.todayDay,
    required this.todayTitle,
    required this.tomorrowTitle,
    required this.dayStartsMs,
    required this.todayWeekday,
    required this.theme,
    required this.layout,
    required this.sessions,
    required this.boundariesMs,
    required this.activeSetId,
    required this.blocks,
  });

  final int version;
  final int generatedAtMs;

  /// 生成这份快照时，「今天」是哪一天。
  ///
  /// 这是整个小组件**唯一一种「安静地错」**的防线：用户一周没开 App，快照会
  /// 照样说「今天是周三」，然后自信地画出**上周三**的课 —— 看起来完全正常。
  /// 所以原生侧渲染前必须拿本机的年月日和这三个数比一次，对不上就画一句
  /// 「打开 ClassCal 更新」，而不是把上周的课当成今天的。
  ///
  /// 发三个整数而不是「epoch 天数」：后者要 Dart 和 Kotlin **各写一份一样的
  /// 天数换算算法**，而 `minSdk = 24` 又用不了 `java.time`（没开 core library
  /// desugaring），只能手搓 `Calendar`。三个整数一个算法都不需要。
  final int todayYear;
  final int todayMonth;
  final int todayDay;

  /// `今天 · 周三` / `明天 · 周四`。列表两组的标题。
  ///
  /// 留在顶层而不是搬进块里：**「今天是几号」和哪个日程无关**，每个块抄一份
  /// 只是把同一个事实存 N 遍。
  final String todayTitle;
  final String tomorrowTitle;

  /// **今天 / 明天 / 后天** 三天的本地零点（epoch 毫秒），正好 3 个。
  ///
  /// 「这两节课分别是哪天的」在原生侧是纯粹的大小比较：落在
  /// `[dayStartsMs[0], dayStartsMs[1])` 里就是今天的。不让原生自己去算本地零点，
  /// 是「不做日历运算」这条原则最直接的体现 —— 那要用到时区数据库，
  /// 而在两个语言里各算一遍就是两处会走偏的地方。
  ///
  /// **它和块上的 [WidgetSetBlock.gridDayStartsMs] 是两个东西**，名字不同就是
  /// 为了不让人看混：这里是「今天起连续三天的零点」（列表布局用它分今天/明天），
  /// 那里是「某一块画的那一周的七个零点」（周网格用它筛事件、算列号）。
  final List<int> dayStartsMs;

  /// 今天星期几（1=周一 … 7=周日）。
  ///
  /// 周网格要把它那一列标出来。原生当然也能从 `Calendar` 读到 —— 但那又是一次
  /// 「读时钟」，而读时钟和「算日历」之间只差一点点，边界一旦模糊，下一个人
  /// 就会顺手在那里做一次日期减法。这边已经有了这个值（`todayTitle` 就是用它
  /// 拼的），顺手发过去更省事。
  final int todayWeekday;

  final WidgetTheme theme;
  final WidgetLayout layout;

  /// 窗口内（本周一往后 [kWidgetHorizonDays] 天）的全部课，按开始时刻升序。
  /// **停课的条目已经被滤掉**（`ResolvedSession.cancelled`）。
  ///
  /// 仍然是一份**所有日程混在一起**的列表：分块是 [blocks] 的事，这里再按日程
  /// 拆成一堆数组的话，Kotlin 侧就要在「按块取数」和「全局取下一节」之间做两套。
  /// 每条带着 [WidgetSession.setId]，一次 filter 就分好了。
  final List<WidgetSession> sessions;

  /// 值得重画一次的绝对时刻，升序去重。
  ///
  /// 每节课的**开始**、每节课的**结束**、以及窗口内每个**本地零点**。
  /// 原生侧只做 `firstOrNull { it > now }`，自己纠正、串行排一个闹钟就够了。
  ///
  /// 不让原生从 `sessions` 里推导这些，是「不做日历运算」的直接推论 ——
  /// 推导要用到「今天是几号」，那正是要避免的东西。
  ///
  /// **推论**：小组件因此只显示绝对时刻（`14:00`），永远不显示倒计时
  /// （「还有 95 分钟」）—— 倒计时需要每分钟一跳的闹钟，而这里没有这种东西。
  final List<int> boundariesMs;

  /// App 里**当前选中的**那个日程 —— 小组件选了「跟随当前」时指的是它。
  ///
  /// 一个日程都没有时为 [kNoSetId]。用它而不是 `null`：JSON 里的 null 和
  /// 「键不存在」在容错读取时是一回事，而 0 在 drift 的自增 id 里永远不可能是
  /// 一个真实日程，语义比 null 更硬。
  final int activeSetId;

  /// 每个日程一块，**末尾永远是总览块**。
  ///
  /// 一个日程都没有时也有一块（就是总览块，日期落在今天那一周），所以原生侧
  /// 不需要写「没有块」那条支路 —— 空课表该显示的是「今天没有课」，不是
  /// 「打开 ClassCal 更新」。
  final List<WidgetSetBlock> blocks;

  Map<String, Object?> toJson() => {
        'version': version,
        'generatedAtMs': generatedAtMs,
        'today': {'y': todayYear, 'm': todayMonth, 'd': todayDay},
        'todayTitle': todayTitle,
        'tomorrowTitle': tomorrowTitle,
        'dayStartsMs': dayStartsMs,
        'todayWeekday': todayWeekday,
        'theme': theme.toJson(),
        'layout': layout.toJson(),
        'sessions': [for (final s in sessions) s.toJson()],
        'boundariesMs': boundariesMs,
        'activeSetId': activeSetId,
        'blocks': [for (final b in blocks) b.toJson()],
      };
}

/// 构建快照时需要的、**每个日程一份**的输入。
///
/// 只装快照真正用得上的三项 —— 把整份 `CalendarSetData` 递进来会让「快照依赖
/// 课表的哪些字段」变得看不出来，而那正是下次改数据模型时最容易漏的地方。
@immutable
class WidgetSetInfo {
  const WidgetSetInfo({
    required this.id,
    required this.name,
    required this.week1Monday,
  });

  final int id;
  final String name;

  /// 第 1 周的周一 —— 这个日程自己的日期锚点。**两个日程的它可以不一样。**
  final DateTime week1Monday;
}

/// 把解析后的上课时刻折成一份小组件快照。
///
/// [now] 由调用方传入 —— 时间是这里唯一的隐含输入，显式化才能在测试里把
/// 「刚过零点」「正好第 9 天」这些边界钉死。
///
/// [sets] 是全部日程（顺序即数据库顺序）；[activeSetId] 指明 App 当前停在哪一套，
/// 总览块借用的就是它的坐标系。两者都为空时照样有一块总览块，
/// 它的日期落在今天那一周 —— 桌面上的卡片不该因为「还没导入课表」而变成一句
/// 「打开 ClassCal 更新」。
WidgetSnapshot buildWidgetSnapshot({
  required List<ResolvedSession> sessions,
  required ColorScheme theme,
  required DateTime now,
  List<WidgetSetInfo> sets = const [],
  int activeSetId = kNoSetId,
  int horizonDays = kWidgetHorizonDays,
  WidgetLayout layout = const WidgetLayout(),
  Map<String, String> abbrOverrides = const {},
}) {
  final today = dateOnly(now);

  // 窗口 = 本周一 起、往后 horizonDays 天。锚在**周一**而不是「今天」：
  // 周网格要画整周，从今天起算会把已经过去的那几天漏掉，网格左边缺半张。
  final windowStart = today.subtract(Duration(days: today.weekday - 1));
  final windowEnd = windowStart.add(Duration(days: horizonDays));

  final out = <WidgetSession>[];
  for (final s in sessions) {
    // 停课的条目在解析结果里是**保留**的（为了能点开撤销），所以这里必须显式
    // 滤掉 —— 和 `buildReminderPlan` 里那处是同一个坑，也是这套设计里最容易漏的。
    if (s.cancelled) continue;

    final startAt = _startAt(s);
    if (startAt.isBefore(windowStart)) continue;
    if (!startAt.isBefore(windowEnd)) continue;

    out.add(
      WidgetSession(
        startAtMs: startAt.millisecondsSinceEpoch,
        endAtMs: _endAt(s).millisecondsSinceEpoch,
        setId: s.setId,
        weekday: s.weekday,
        title: s.title,
        location: s.location.trim(),
        startLabel: formatMinutes(s.startMinute),
        endLabel: formatMinutes(s.endMinute),
        dayLabel: _weekdayCn(s.weekday),
        dateLabel: '${s.date.month}/${s.date.day}',
        // 单次事件没有节次，`periodLabel` 会是空串 —— 布局侧据此少画一行。
        periodLabel: (s.startPeriod == null || s.endPeriod == null)
            ? ''
            : periodLabel(s.startPeriod!, s.endPeriod!),
        color: _argb(courseColor(s.title, overrideHex: s.colorHex)),
        onColor: _argb(onCourseColor(courseColor(s.title, overrideHex: s.colorHex))),
        abbr: abbrFor(s.title, overrides: abbrOverrides),
        gridRow: _gridRow(s),
        gridRowSpan: _gridSpan(s),
      ),
    );
  }
  out.sort((a, b) {
    final byStart = a.startAtMs.compareTo(b.startAtMs);
    if (byStart != 0) return byStart;
    // 同一时刻的两节课要有**确定**的先后：Dart 的 `List.sort` 不是稳定排序，
    // 而「谁在前」决定了小尺寸卡片上画的是哪一节。不加这一级的话，两个日程里
    // 撞在同一时间的课会让卡片每次刷新翻一次面。
    final bySet = a.setId.compareTo(b.setId);
    if (bySet != 0) return bySet;
    return a.title.compareTo(b.title);
  });

  return WidgetSnapshot(
    version: kWidgetSnapshotVersion,
    generatedAtMs: now.millisecondsSinceEpoch,
    todayYear: today.year,
    todayMonth: today.month,
    todayDay: today.day,
    todayTitle: '今天 · ${_weekdayCn(today.weekday)}',
    tomorrowTitle:
        '明天 · ${_weekdayCn(today.add(const Duration(days: 1)).weekday)}',
    dayStartsMs: [
      for (var i = 0; i <= 2; i++)
        today.add(Duration(days: i)).millisecondsSinceEpoch,
    ],
    todayWeekday: today.weekday,
    theme: WidgetTheme(
      surface: _argb(theme.surface),
      onSurface: _argb(theme.onSurface),
      secondary: _argb(theme.onSurfaceVariant),
      accent: _argb(theme.primary),
      onAccent: _argb(theme.onPrimary),
    ),
    layout: layout,
    sessions: out,
    boundariesMs: _boundaries(out, windowStart, horizonDays),
    activeSetId: activeSetId,
    blocks: _blocks(
      sets: sets,
      activeSetId: activeSetId,
      sessions: sessions,
      today: today,
    ),
  );
}

/// 每个日程一块，末尾跟一个总览块。
///
/// 用**输入那份** `ResolvedSession`（不是 [WidgetSession]）来找「这套课表第一节在
/// 第几周」：它带着每节课在**自己那套编号体系**里的 `week`，而 `WidgetSession`
/// 刻意不带（原生侧改按日期筛之后，那个字段没有任何读者了）。
List<WidgetSetBlock> _blocks({
  required List<WidgetSetInfo> sets,
  required int activeSetId,
  required List<ResolvedSession> sessions,
  required DateTime today,
}) {
  final firstWeek = _firstWeeksBySet(sessions);

  /// 一块的网格坐标 = 锚点 + 画第几周。
  ///
  /// [anchor] 是这块用来算「今天第几周」的锚点。今天不在学期内时（放假、或者
  /// 锚点还没设）退到 [fallbackWeek]：一张空格子比「往前翻几周的真课」难看得多，
  /// 而这正是 fallback 存在的意义。
  WidgetSetBlock block({
    required int id,
    required String name,
    required DateTime anchor,
    required int? fallbackWeek,
    required bool overview,
  }) {
    final week = weekOf(week1Monday: anchor, date: today);
    final gridWeek = week > 0 ? week : (fallbackWeek ?? 1);
    return WidgetSetBlock(
      id: id,
      name: name,
      // 总览块**没有自己的周号**，所以这里是 0 而不是借来的那个数。
      // 它借当前那一套的只是**日期区间**；把周号也一起带过来就变成「编一个」，
      // 而桌面上没有任何东西能看出它是编的。
      currentWeek: overview ? 0 : (week > 0 ? week : 0),
      // 同理，总览的标题**只有日期区间、没有「第 N 周」**。
      weekTitle:
          overview ? _rangeTitle(anchor, gridWeek) : _weekTitle(anchor, week),
      gridWeek: gridWeek,
      gridRows: kPeriodRowCount,
      gridDayStartsMs: _gridDayStarts(anchor, gridWeek),
    );
  }

  final out = <WidgetSetBlock>[
    for (final s in sets)
      block(
        id: s.id,
        name: s.name,
        anchor: s.week1Monday,
        fallbackWeek: firstWeek[s.id],
        overview: false,
      ),
  ];

  // 总览借**当前这一套**的周次与日期。总览没有自己的周号，而把几个起点不同的
  // 周次合起来本来就没有唯一正确答案 —— 按当前日程的日期对齐是唯一自洽的选择
  // （和 App 里总览页同一条）。一个日程都没有时坐标系退到「今天所在的那一周」：
  // 桌面上那张卡片该显示「今天没有课」，而不是「打开 ClassCal 更新」。
  final focus = _focusSet(sets, activeSetId);
  out.add(
    block(
      id: kOverviewBlockId,
      name: _overviewName,
      anchor: focus?.week1Monday ?? _mondayOf(today),
      fallbackWeek: focus == null ? null : firstWeek[focus.id],
      overview: true,
    ),
  );

  return out;
}

/// 总览块显示的名字 —— 也就是小组件上那条日程名信息条在总览下的文案。
const String _overviewName = '总览';

/// 每个日程「最早的那一周是第几周」。没有课的日程不在表里。
///
/// 取**最小**而不是「第一条」：输入顺序不保证（`buildWidgetSnapshot` 的两个
/// 生产调用方各自排过序，但夹具不一定），而「最早的周」和顺序无关。
Map<int, int> _firstWeeksBySet(List<ResolvedSession> sessions) {
  final out = <int, int>{};
  for (final s in sessions) {
    if (s.cancelled) continue;
    final cur = out[s.setId];
    if (cur == null || s.week < cur) out[s.setId] = s.week;
  }
  return out;
}

/// 「跟随当前」和「认不出来的 key」都落到这里。
///
/// 刻意**不返回 null**（除非一个日程都没有）：用户删掉一个日程之后，桌面上
/// 那几个实例应该继续显示别的东西，而不是一起变成「打开 ClassCal 同步课表」。
WidgetSetInfo? _focusSet(List<WidgetSetInfo> sets, int activeSetId) {
  if (sets.isEmpty) return null;
  for (final s in sets) {
    if (s.id == activeSetId) return s;
  }
  return sets.first;
}

/// [week] 那一周的七个本地零点（周一 … 周日）。
List<int> _gridDayStarts(DateTime week1Monday, int week) {
  final w = week < 1 ? 1 : week;
  return [
    for (var d = 1; d <= 7; d++)
      dateFor(week1Monday: week1Monday, week: w, weekday: d)
          .millisecondsSinceEpoch,
  ];
}

DateTime _mondayOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// 上课时刻。**和 `reminder_plan.dart` 的 `_startAtFor` 必须逐字一致** ——
/// 两边算的是同一节课的同一个时刻，算法分叉了小组件和提醒就会差几分钟。
DateTime _startAt(ResolvedSession s) =>
    DateTime(s.date.year, s.date.month, s.date.day)
        .add(Duration(minutes: s.startMinute));

DateTime _endAt(ResolvedSession s) =>
    DateTime(s.date.year, s.date.month, s.date.day)
        .add(Duration(minutes: s.endMinute));

/// 这节在周网格里的行号；不在网格里返回 -1。
///
/// 模板课按 `startPeriod` 查作息表；单次事件（没有节次）按开始钟点落到最接近的
/// 大节。两者都不在（清早 06:00 的补课、晚上 22:00 的自习）就是 -1 ——
/// 网格里没有它的位置，但它照样出现在列表里。
int _gridRow(ResolvedSession s) {
  final p = s.startPeriod;
  if (p != null) return rowForStartPeriod(p) ?? -1;
  return rowForMinute(s.startMinute) ?? -1;
}

/// 跨几个大节。1-4 节连堂要占两行，否则网格上会缺一块。
///
/// 单次事件恒为 1：它没有节次，跨行数只能靠开始和结束的钟点去凑，而那要按
/// 作息表逐行比对 —— 为一张缩略图做这件事不值得，画一个格子已经说明问题了。
int _gridSpan(ResolvedSession s) {
  final a = s.startPeriod;
  final b = s.endPeriod;
  if (a == null || b == null) return 1;
  final span = rowsSpanned(a, b);
  return span < 1 ? 1 : span;
}

/// 边界表 = 每节课的开始 + 结束 + 窗口内每个本地零点，升序去重。
List<int> _boundaries(
  List<WidgetSession> sessions,
  DateTime windowStart,
  int horizonDays,
) {
  final set = <int>{};
  for (final s in sessions) {
    set.add(s.startAtMs);
    set.add(s.endAtMs);
  }
  // 含 windowEnd 那一天：最后一节下课后到次日零点之间，也要有人把小组件
  // 从「今天」翻到「明天」。
  for (var i = 0; i <= horizonDays; i++) {
    set.add(windowStart.add(Duration(days: i)).millisecondsSinceEpoch);
  }
  return set.toList()..sort();
}

/// `第 5 周 · 10/5–10/11`；[week] 不在学期内时返回空串。
String _weekTitle(DateTime week1Monday, int week) =>
    week <= 0 ? '' : '第 $week 周 · ${_rangeTitle(week1Monday, week)}';

/// `10/5–10/11`。总览块的标题 —— 它没有自己的周号。
String _rangeTitle(DateTime week1Monday, int week) {
  final w = week < 1 ? 1 : week;
  final monday = dateFor(week1Monday: week1Monday, week: w, weekday: 1);
  final sunday = monday.add(const Duration(days: 6));
  return '${monday.month}/${monday.day}–${sunday.month}/${sunday.day}';
}

const List<String> _weekdayNames = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

/// 1=周一 … 7=周日 → `周三`。越界返回空串（脏数据不该让渲染崩掉）。
String _weekdayCn(int weekday) =>
    (weekday >= 1 && weekday <= 7) ? _weekdayNames[weekday - 1] : '';

/// `Color` → **有符号** 32 位 ARGB。
///
/// `Color.toARGB32()` 给的是无符号值（`0xFF5C6BC0` = 4284769216），而 JSON 要
/// 跨到 Kotlin 的 `Int`（有符号 32 位）上去 —— 不减这个 `2^32` 的话，
/// 原生侧会拿到一个溢出的数字，颜色直接错掉。
///
/// 不用 `Color.value`：它在 Flutter 3.47 上已经 `@Deprecated`，而本项目的
/// 标准是 `flutter analyze` 零警告。
int _argb(Color c) {
  final v = c.toARGB32();
  return v > 0x7FFFFFFF ? v - 0x100000000 : v;
}
