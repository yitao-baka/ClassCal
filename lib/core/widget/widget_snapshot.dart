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
/// ## 一条摊平的逐日时间轴
///
/// 整份快照围着[一条从本周一起、连续 35 天的逐日表][WidgetSnapshot.dayStartsMs]
/// 转。原生侧要回答「今天是第几天」只需一次区间比较得到下标，于是**过零点之后
/// 它自己就会翻页**，不需要用户打开 App。
///
/// 在这之前不是这样：那一版把「今天」钉成三个整数（年月日），过了零点原生侧
/// 一比就判定快照过期，只能画一句「打开 ClassCal 更新」—— 桌面上那张卡片
/// **每天都要靠打开一次 App 才能活**。根因不是漏做，是那份快照在结构上就只能
/// 表示它被生成的那一天。
///
/// ## 每个日程一块（[WidgetSetBlock]）
///
/// 一个实例可以显示**某一个日程**（而不是把所有日程合起来）。所以周次标题
/// **不能是一个全局值**：两个日程的 `week1Monday` 不同时，「第 5 周」落在
/// 不同的日期上，而它们又落在同一个日历周里。
///
/// 于是每块自带领先算好的[每周标题][WidgetSetBlock.weekTitles]，以及
/// **今天不在学期里时**才画的那一周[七天的零点][WidgetSetBlock.fallbackWeekMs]。
/// 原生侧据此按日期区间筛事件、算列号 —— 全是减法，一个字都没有重新做
/// 日历运算。「按周号筛」在总览那件事上必然错，理由和 App 里总览页那一处逐字相同。
library;

import 'package:flutter/material.dart';

import '../../data/model/resolve.dart';
import '../text/course_abbr.dart';
import '../theme/course_colors.dart';
import '../time/periods.dart';

/// 快照的结构版本。原生侧读不懂的版本要当作「没有快照」，而不是硬解析。
///
/// **2** 把周次 / 标题 / 网格坐标从顶层搬进了 `blocks`（每个日程一块），
/// 并给每条事件加了 `setId`。
///
/// **3** 换掉了「今天」的表达方式：不再发 `today`（年月日三个整数）和拼好的
/// `todayTitle` / `tomorrowTitle` / `todayWeekday`，改成发一条**从本周一起、
/// 连续 35 天的逐日零点表**外加等长的星期标签，`dayStartsMs` 也从 3 格变成
/// 36 格。理由见文件头：固定在某一天上的快照，过零点就只能画「打开 ClassCal
/// 更新」，而那让桌面上的卡片每天都要靠打开一次 App 才活。
///
/// v2 和 v1 的快照一律当过期，桌面上短暂显示「打开 ClassCal 更新」，
/// 打开一次 App 就恢复 —— 比写一段迁移诚实：旧结构里根本没有「窗口」这个
/// 维度，补不出来。
const int kWidgetSnapshotVersion = 3;

/// 总览块在 [WidgetSnapshot.blocks] 里的 id。
///
/// **不是 -1**：`-1` 已经被 `CalendarSetData.unsavedId` 占用表示「还没落库」，
/// 两个概念共用一个哨兵迟早出事。drift 的自增 id 从 1 开始，负数撞不上。
/// Kotlin 侧 `WidgetSetBlock.OVERVIEW_ID` 必须和它一致（契约测试钉着）。
const int kOverviewBlockId = -2;

/// 快照往前铺几天。从**本周一**起算，所以它是 7 的倍数 —— 尽头正好是
/// 一个周日的末尾，周网格不会画到半张。
///
/// **它的新含义是「一次打开能顶多少天」。** 在此之前「今天」在快照里是钉死的
/// 三个整数，窗口多长都只对生成那一天有效，所以 9 天只是个「够画本周 + 明天」
/// 的尺寸。现在原生侧能自己在窗口里定位今天了，窗口多长就直接等于「多久不用
/// 打开 App」—— 9 天能盖住用户报的「第二天」，但一个长假就把它耗尽了。
///
/// 35 天（5 整周）的代价是快照 JSON 从约 15 KB 长到约 60–90 KB：事件是一周
/// 约 35 条 × 5 周，`boundariesMs` 从约 70 条到约 390 条。两者都不影响唤醒
/// 次数 —— [WidgetSnapshot.boundariesMs] 的读者每次**只排下一个**边界。
///
/// 不更长是因为它同时是「快照能有多旧」：那份数据里最久远的一节课也只在
/// 35 天内可信，而放假的学期末本来就会打开 App 改东西。
const int kWidgetHorizonDays = 35;

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

/// **一个日程一块** —— 这块自己的每周标题和兜底周。
///
/// 为什么这一组要按日程各算一份，而不是像从前那样顶层算一份：一个被钉在某个
/// 日程上的实例，标题该显示**那个日程的**「第 5 周」。而两个日程的 `week1Monday`
/// 不同时，「第 5 周」落在不同的日期上 —— 一个全局值必然对其中一个日程是错的。
///
/// **总览也是一块**（[id] = [kOverviewBlockId]）。它不是某个日程，所以它的
/// [weekTitles] 里**没有**「第 N 周」，只有日期区间 —— 它没有自己的周号，
/// 硬写一个就是编的。
///
/// ## 这里没有「现在是第几周」
///
/// 曾经有一个 `currentWeek` / `gridWeek` 字段。它们现在没了，因为**原生侧
/// 不再需要知道周号**：今天落在窗口的第几天是一个下标（`dayIndexOf`），
/// 那个下标除以 7 就是「窗口里的第几周」，而标题直接从 [weekTitles] 取。
///
/// 删掉而不是留着，是因为本项目已经有一条同类的教训：**留着一个没人读的字段，
/// 迟早会被谁当成依据用起来**（`WidgetSession.week` 就是这么被换掉的）。
/// 一个「第 5 周」的整数摆在块上，下一次改渲染的人很容易拿它去筛事件，而
/// 两个日程的周号本来是**不可比**的。
class WidgetSetBlock {
  const WidgetSetBlock({
    required this.id,
    required this.name,
    required this.weekTitles,
    required this.gridRows,
    required this.fallbackWeekMs,
  });

  /// 日程 id；总览块是 [kOverviewBlockId]。
  final int id;

  /// 日程名；总览块是「总览」。小组件上那条日程名信息条直接读它 ——
  /// 空串等于那一栏凭空消失，所以这里不允许为空（测试钉着）。
  final String name;

  /// 窗口里每一周的标题，**下标 = 今天在窗口里的第几周**（`dayIndexOf(now) ~/ 7`）。
  ///
  /// 长度是 `kWidgetHorizonDays ~/ 7`。每一项按**这一块自己的编号体系**算：
  /// `第 5 周 · 10/5–10/11`。今天不在这个日程的学期里时是**空串** ——
  /// 那不是「没有标题」，见 [fallbackWeekMs]。
  ///
  /// 总览块的每一项只有日期区间（`10/5–10/11`），**永远不会是空串**：
  /// 它不是某个日程，没有学期可不在。
  final List<String> weekTitles;

  /// 周网格有几行 = 一天有几个大节（`kPeriodRowCount`）。
  /// 和 [WidgetSession.gridRow] 配套，两边共用 `periods.dart` 那一张作息表。
  final int gridRows;

  /// **今天不在这个日程的学期里时才画的那一周**的七个本地零点（周一 … 周日）。
  ///
  /// 判据是 `weekTitles[weekIdx].isEmpty` —— 今天早于第 1 周（放假、或者锚点
  /// 还没到）时，按窗口算出来的那一周是一张**空格子**，而往前翻到「第一节课
  /// 所在的那一周」至少画的是真课。这是**保留**旧行为，不是新加的：旧的
  /// `gridWeek = week > 0 ? week : fallbackWeek` 就是这件事，只是那时候
  /// 这个字段还是「画的那一周」本身，两种含义挤在一个名字里。
  ///
  /// 改名是必须的。旧名字（`gridDayStartsMs`）一旦被当成「画的那一周」去读，
  /// 表现就是**开学前那张网格永远停在第 1 周**，而且只在放假期间看得出来。
  ///
  /// 一个日程一节课都没有时退到它自己的第 1 周；总览退到**全部日程里最早的
  /// 那一节课**所在的一周（没有课、也没有日程时退到本周）。
  final List<int> fallbackWeekMs;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'weekTitles': weekTitles,
        'gridRows': gridRows,
        'fallbackWeekMs': fallbackWeekMs,
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
    required this.dayStartsMs,
    required this.dayLabels,
    required this.tzOffsetMinutes,
    required this.theme,
    required this.layout,
    required this.sessions,
    required this.boundariesMs,
    required this.activeSetId,
    required this.blocks,
  });

  final int version;
  final int generatedAtMs;

  /// **窗口里每一天的本地零点**（epoch 毫秒），从本周一起，共
  /// `kWidgetHorizonDays + 1` 个。最后一个不是一天，是**排他上界**。
  ///
  /// 原生侧要回答「今天是第几天」只做一次区间比较：从后往前找第一个
  /// `<= now` 的下标。**这就是「过零点自己翻页」的全部机制** —— 它不需要知道
  /// 今天是几月几号，只需要知道 `now` 落在这条轴的第几格。
  ///
  /// 曾经这里是**三个**零点（今天/明天/后天），另配 `todayYear/Month/Day`
  /// 三个整数供原生比对 —— 那一版过了零点就判定整份快照过期，桌面上那张卡片
  /// 于是**每天都要靠打开一次 App 才活**。长度从 3 变成 36 不是「多备几天」，
  /// 是换了一种表达方式。
  ///
  /// 不让原生自己去算本地零点，是「不做日历运算」这条原则最直接的体现：
  /// 那要用到时区数据库，而 `minSdk = 24` 又用不了 `java.time`。
  final List<int> dayStartsMs;

  /// 每一天的 `周三`，和 [dayStartsMs] 的**前 `kWidgetHorizonDays` 项**
  /// 一一对应（长度 `kWidgetHorizonDays`，比 [dayStartsMs] 少那个排他上界）。
  ///
  /// 是**绝对的**星期标签，不是「今天/明天」那种相对措辞 —— 后者一过零点
  /// 就是错的，而那正是这一版要修的毛病。「今天 · 」/「明天 · 」那两个前缀
  /// 由原生侧在下标 0 / 1 上现拼，因为它是唯一知道「哪个下标是今天」的一侧。
  final List<String> dayLabels;

  /// 生成这份快照时，本机的 UTC 偏移（分钟）。
  ///
  /// **一道跨时区的保险。** 老版本比的是本机年月日，所以飞一趟时区之后第二天
  /// 必定过期、强制重开，顺手就把偏移纠正了。换成 35 天的窗口之后这个纠正要
  /// 等到窗口用尽才发生，而那期间「哪节课算今天」会偏几小时 —— 一班早八可能
  /// 整个上午都标错。
  ///
  /// 对不上就当过期。两边都只是**读一次当前偏移**，不是日期运算：偏移是个
  /// 整数，比它和比两个整数没有区别。
  final int tzOffsetMinutes;

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
        'dayStartsMs': dayStartsMs,
        'dayLabels': dayLabels,
        'tzOffsetMinutes': tzOffsetMinutes,
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
/// 「刚过零点」「刚好压在窗口最后一格」「掉到窗口外一天」这些边界钉死。
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
    // `<= horizonDays`：最后一格不是第 36 天，是**排他上界**。
    // 少这一格的话，最后一天夜里到次日零点之间没人把卡片翻过去。
    dayStartsMs: [
      for (var i = 0; i <= horizonDays; i++)
        windowStart.add(Duration(days: i)).millisecondsSinceEpoch,
    ],
    dayLabels: [
      for (var i = 0; i < horizonDays; i++)
        _weekdayCn(windowStart.add(Duration(days: i)).weekday),
    ],
    // 从 `now` 而不是 `today` 取：`today` 已经被抹成当天零点，那时区偏移
    // 在夏令时切换的那一天会差一小时。
    tzOffsetMinutes: now.timeZoneOffset.inMinutes,
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
      windowStart: windowStart,
      horizonDays: horizonDays,
    ),
  );
}

/// 每个日程一块，末尾跟一个总览块。
///
/// 用**输入那份** `ResolvedSession`（不是 [WidgetSession]）来找「这套课表第一节课
/// 在哪一周」：`WidgetSession` 刻意不带 `week`（原生侧改按日期筛之后，那个字段
/// 没有任何读者了），而「最早那一节课」是一个**日期**上的事，两者都可以；
/// 这里用输入那份只是因为它还没有被窗口裁过。
List<WidgetSetBlock> _blocks({
  required List<WidgetSetInfo> sets,
  required int activeSetId,
  required List<ResolvedSession> sessions,
  required DateTime windowStart,
  required int horizonDays,
}) {
  /// 一块的标题表和兜底周。
  ///
  /// [anchor] 只用来把**日期**翻译成这块自己的周号（`weekOf`）—— 两个日程的
  /// `week1Monday` 不同时，同一个 `windowStart + 7k` 落在不同的周号上，而
  /// **日期区间是同一个**。这正是「各算各的、但别搞错那个是编号不是日期」。
  ///
  /// [mine] 是这块自己的事件，只用来找兜底周（最早那节课在哪一周）。
  WidgetSetBlock block({
    required int id,
    required String name,
    required DateTime anchor,
    required List<ResolvedSession> mine,
    required bool overview,
  }) {
    return WidgetSetBlock(
      id: id,
      name: name,
      weekTitles: [
        for (var k = 0; k * 7 < horizonDays; k++)
          if (overview)
            // 总览**没有自己的周号**，所以这里只有日期区间。硬写一个
            // 「第 N 周」就是编的，而桌面上没有任何东西能看出它是编的。
            _rangeOf(windowStart.add(Duration(days: k * 7)))
          else
            _weekTitle(
              anchor,
              weekOf(
                week1Monday: anchor,
                date: windowStart.add(Duration(days: k * 7)),
              ),
            ),
      ],
      gridRows: kPeriodRowCount,
      fallbackWeekMs: _fallbackWeek(anchor, mine),
    );
  }

  final bySet = <int, List<ResolvedSession>>{};
  for (final s in sessions) {
    (bySet[s.setId] ??= <ResolvedSession>[]).add(s);
  }

  final out = <WidgetSetBlock>[
    for (final s in sets)
      block(
        id: s.id,
        name: s.name,
        anchor: s.week1Monday,
        mine: bySet[s.id] ?? const <ResolvedSession>[],
        overview: false,
      ),
  ];

  // 总览借**当前这一套**的锚点。它自己不构成一个学期，所以「今天不在学期里」
  // 对它无从判断（它的 `weekTitles` 永远是日期区间，不会是空串），于是它的
  // 兜底周只能按「全部日程里最早的那一节课」算。一个日程都没有时退到
  // 本周 —— 桌面上那张卡片该显示「今天没有课」，而不是「打开 ClassCal 更新」。
  final focus = _focusSet(sets, activeSetId);
  out.add(
    block(
      id: kOverviewBlockId,
      name: _overviewName,
      anchor: focus?.week1Monday ?? _mondayOf(windowStart),
      mine: sessions,
      overview: true,
    ),
  );

  return out;
}

/// 总览块显示的名字 —— 也就是小组件上那条日程名信息条在总览下的文案。
const String _overviewName = '总览';

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

/// 「今天不在这个日程的学期里时画哪一周」的七个本地零点（周一 … 周日）。
///
/// 判据（在原生侧）是这一周的标题为空串，也就是今天早于第 1 周 —— 那时候按
/// 窗口算出来的那一周是一张**空格子**，而往前翻到第一节课所在的那一周至少
/// 画的是真课。**这是保留旧行为**，不是新加的。
///
/// 取**最早**而不是「第一条」：输入顺序不保证（`buildWidgetSnapshot` 的两个
/// 生产调用方各自排过序，但夹具不一定），而「最早的日期」和顺序无关。
///
/// [mine] 一节课都没有时退到 [anchor] 的第 1 周 —— 那是这个日程该有的样子，
/// 而不是「本周」（那会去画一张属于别的日程的网格）。
List<int> _fallbackWeek(DateTime anchor, List<ResolvedSession> mine) {
  DateTime? earliest;
  for (final s in mine) {
    if (s.cancelled) continue;
    final d = dateOnly(s.date);
    if (earliest == null || d.isBefore(earliest)) earliest = d;
  }
  final monday = earliest != null
      ? _mondayOf(earliest)
      : dateFor(week1Monday: anchor, week: 1, weekday: 1);
  return [
    for (var d = 0; d <= 6; d++)
      monday.add(Duration(days: d)).millisecondsSinceEpoch,
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

/// `第 5 周 · 10/5–10/11`；[week] 不在学期内时返回**空串**。
///
/// 那个空串是 [WidgetSetBlock.fallbackWeekMs] 的**唯一判据** —— 原生侧据此
/// 决定「这一周该画窗口里那一周，还是画兜底那一周」。空串不是「没有标题」
/// 那个意思，改这里的返回值就是在改渲染行为。
String _weekTitle(DateTime week1Monday, int week) =>
    week <= 0 ? '' : '第 $week 周 · ${_rangeOf(
          dateFor(week1Monday: week1Monday, week: week, weekday: 1),
        )}';

/// `10/5–10/11` —— 从 [monday] 起的那一周。总览块的标题用它：它没有自己的周号。
String _rangeOf(DateTime monday) {
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
