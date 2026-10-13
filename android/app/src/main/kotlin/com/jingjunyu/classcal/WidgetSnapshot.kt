package com.jingjunyu.classcal

import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone

/**
 * 一天的毫秒数。只用来给**兜底周**（[WidgetSetBlock.fallbackWeekMs]，只有七个
 * 零点、没有第八格）推它的右端 —— 窗口里的每一周都有精确的下一格零点，用不上它。
 */
private const val DAY_MS = 24L * 60 * 60 * 1000

/**
 * 桌面小组件要画的一切 —— **反序列化 + 查询，没有一行日历运算**。
 *
 * Dart 侧 `core/widget/widget_snapshot.dart` 把颜色、周次、格式化好的字符串、
 * 本地零点全都算好了；这里只做两件事：`now` 与 `startAtMs` 的大小比较，
 * 以及按**日期区间**把事件分到某一天 / 某一列。
 *
 * 这条分界不是洁癖。颜色在 Dart 那边是「FNV-1a(课名) % 调色板长度」，
 * 周次是套级平移之后的结果，行号来自那张作息表 —— 任何一项在这里重算一份，
 * 两份就会慢慢走偏，而走偏的表现是「同一门课在 App 里是蓝的、在桌面上是绿的」，
 * 或者「网格里课全挤在第一行」。这两种都不会报错，只会看起来像 UI 抽风。
 *
 * ## 「今天」是一个下标，不是一个日期（v3）
 *
 * [WidgetSnapshot.dayStartsMs] 是一条**从本周一起、连续 35 天的逐日零点表**。
 * 「今天是第几天」在这里只做一次区间比较，于是**过了零点这张卡片自己就会翻页**。
 *
 * 在这之前不是这样：那一版把今天钉成三个整数（年月日），过了零点一比就判定
 * 快照过期，只能画一句「打开 ClassCal 更新」—— 桌面上那张卡片每天都要靠用户
 * 打开一次 App 才活。那不是一个漏做的功能，是那份快照在结构上只能表示
 * 它被生成的那一天。
 *
 * 字段名和 Dart 的 `toJson` 一一对应，跨语言对不上不会报错、只会画错，
 * 所以 `test/widget_channel_test.dart` 里有一条直接读两边源码核对的契约测试。
 */
data class WidgetTheme(
    val surface: Int,
    val onSurface: Int,
    val secondary: Int,
    val accent: Int,
    val onAccent: Int,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("surface", surface)
        put("onSurface", onSurface)
        put("secondary", secondary)
        put("accent", accent)
        put("onAccent", onAccent)
    }

    companion object {
        /** 兜底：白底黑字。快照残缺时宁可画得素，也不能画成白底白字。 */
        val FALLBACK = WidgetTheme(
            surface = 0xFFFFFFFF.toInt(),
            onSurface = 0xFF000000.toInt(),
            secondary = 0xFF666666.toInt(),
            accent = 0xFF3F51B5.toInt(),
            onAccent = 0xFFFFFFFF.toInt(),
        )

        fun fromJson(o: JSONObject): WidgetTheme = WidgetTheme(
            surface = o.optInt("surface", FALLBACK.surface),
            onSurface = o.optInt("onSurface", FALLBACK.onSurface),
            secondary = o.optInt("secondary", FALLBACK.secondary),
            accent = o.optInt("accent", FALLBACK.accent),
            onAccent = o.optInt("onAccent", FALLBACK.onAccent),
        )
    }
}

/**
 * 「多大算大」的档位。
 *
 * 数字由 Dart 定、放进快照，Kotlin 只照着跑同一段阶梯 —— 这样阈值只有一处定义，
 * 而且能在 `dart test` 里把边界钉死。默认值必须和 Dart 侧的 `WidgetLayout`
 * 一致：老版本 App 写下的快照里可能没有这一块，那时用的就是这里的默认值。
 */
data class WidgetLayout(
    val smallMaxHeightDp: Int = 110,
    val largeMinWidthDp: Int = 250,
    val largeMinHeightDp: Int = 180,
    val maxListRows: Int = 8,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("smallMaxHeightDp", smallMaxHeightDp)
        put("largeMinWidthDp", largeMinWidthDp)
        put("largeMinHeightDp", largeMinHeightDp)
        put("maxListRows", maxListRows)
    }

    companion object {
        fun fromJson(o: JSONObject?): WidgetLayout {
            if (o == null) return WidgetLayout()
            val d = WidgetLayout()
            return WidgetLayout(
                smallMaxHeightDp = o.optInt("smallMaxHeightDp", d.smallMaxHeightDp),
                largeMinWidthDp = o.optInt("largeMinWidthDp", d.largeMinWidthDp),
                largeMinHeightDp = o.optInt("largeMinHeightDp", d.largeMinHeightDp),
                maxListRows = o.optInt("maxListRows", d.maxListRows),
            )
        }
    }
}

/**
 * **一个日程一块** —— 这块自己的每周标题和兜底周。
 *
 * 为什么按日程各存一份而不是全局一份：一个被钉在某个日程上的实例，标题该显示
 * **那个日程的**「第 5 周」。而两个日程的 `week1Monday` 不同时，「第 5 周」落在
 * 不同的日期上 —— 一个全局值必然对其中一个日程是错的。
 *
 * **总览也是一块**（[id] = [OVERVIEW_ID]）。它不是某个日程，所以 [weekTitles]
 * 里**没有**「第 N 周」，只有日期区间 —— 它没有自己的周号，硬写一个就是编的。
 *
 * ## 这里没有「现在是第几周」
 *
 * 曾经有 `currentWeek` / `gridWeek` 两个整数。它们被删掉了：要画哪一周现在由
 * [WidgetSnapshot.gridFor] 从窗口表里切，标题从 [weekTitles] 里取，**周号在
 * 这边一个读者都没有**。留着会是下一个坑 —— 那两个数字在两个日程之间**不可比**
 * （同一个日历周在 A 是第 5 周、在 B 是第 4 周），而它看起来又很像一个
 * 「筛事件」的好依据。本项目在 `WidgetSession.week` 上已经吃过一次这个亏。
 */
data class WidgetSetBlock(
    val id: Int,
    val name: String,
    /** 窗口里每一周的标题，下标 = 今天在窗口里的第几周。空串见 [fallbackWeekMs]。 */
    val weekTitles: List<String>,
    val gridRows: Int,
    /** 今天不在这个日程的学期里时才画的那一周的七个零点（周一 … 周日）。 */
    val fallbackWeekMs: List<Long>,
) {
    /** 这一块是不是「把所有日程合起来看」那个虚拟页。 */
    val isOverview: Boolean get() = id == OVERVIEW_ID

    /** 这条事件属不属于这一块。总览收下全部。 */
    fun accepts(s: WidgetSession): Boolean = isOverview || s.setId == id

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("weekTitles", JSONArray().apply { weekTitles.forEach { put(it) } })
        put("gridRows", gridRows)
        put("fallbackWeekMs", JSONArray().apply { fallbackWeekMs.forEach { put(it) } })
    }

    companion object {
        /**
         * 总览块的 id，必须和 Dart 侧 `kOverviewBlockId` 一致（契约测试钉着）。
         *
         * **不是 -1**：`-1` 在 dart 那边是 `CalendarSetData.unsavedId`（「还没
         * 落库」）。两个概念共用一个哨兵迟早出事。drift 的自增 id 从 1 开始，
         * 负数撞不上真实日程。
         */
        const val OVERVIEW_ID = -2

        fun fromJson(o: JSONObject): WidgetSetBlock? = try {
            WidgetSetBlock(
                id = o.getInt("id"),
                name = o.optString("name"),
                weekTitles = stringList(o.optJSONArray("weekTitles")),
                gridRows = o.optInt("gridRows", 0),
                fallbackWeekMs = longList(o.optJSONArray("fallbackWeekMs")),
            )
        } catch (e: Exception) {
            null
        }

        private fun longList(array: JSONArray?): List<Long> {
            if (array == null) return emptyList()
            return (0 until array.length()).map { array.optLong(it) }
        }

        private fun stringList(array: JSONArray?): List<String> {
            if (array == null) return emptyList()
            return (0 until array.length()).map { array.optString(it) }
        }
    }
}

/**
 * 周网格**这一次要画的那一周** —— 七天的零点，外加一个排他上界。
 *
 * 单独成一个类，是因为「画哪一周」现在有两个来源：窗口里今天所在的那一周，
 * 或者块上那份兜底周（今天不在这个日程的学期里时）。下游（网格列号、取事件）
 * 只关心「这七格是哪七天」，不该知道它是哪一种 —— 让它去读块上的
 * `fallbackWeekMs` 的话，学期中那张网格会画成兜底周，而那**只在开学前
 * 才看得出来**。
 */
class GridWeek(
    /** 这七天的本地零点（周一 … 周日）。空表 = 这一块没有可画的周。 */
    val days: List<Long>,
    /** 排他上界，也就是下周一零点。 */
    val endMs: Long,
) {
    val fromMs: Long get() = days.firstOrNull() ?: 0L

    /**
     * [ms] 落在这一周的第几天（0=周一 … 6=周日）；**不落在这一周里返回 -1**。
     *
     * 列号就是这么定的 —— 用**绝对日期**而不是事件自己的 `weekday`，
     * 因为总览那一块里混着几个日程的事件，只有日期是它们共有的东西。
     *
     * **上界那一次比较不是多余的**：只判「不早于某一天的零点」的话，一整周都
     * 在 [ms] 之前时会返回 6（周日）—— 而那正是兜底周（今天不在这个日程的
     * 学期里、画的是另外一周）的情形。表现是「放假的某一天，网格把周日涂成了
     * 今天」。所以这个方法判的是**包含**，不是「往前找最近的一天」。
     */
    fun columnOf(ms: Long): Int {
        if (days.isEmpty() || ms < days[0] || ms >= endMs) return -1
        for (i in days.indices.reversed()) {
            if (ms >= days[i]) return i
        }
        return -1
    }
}

/** 一次课。全是现成的数字和字符串 —— 这里一个格式化都不用做。 */
data class WidgetSession(
    val startAtMs: Long,
    val endAtMs: Long,
    /**
     * 这条事件属于哪个日程。和 [WidgetSetBlock.id] 比一次整数就知道这一块
     * 该不该收它 —— 「这个实例配的是哪个日程」全落在这一处。
     */
    val setId: Int,
    /** 星期几（1=周一 … 7=周日）。**列号不用它**，那是块按绝对日期算的。 */
    val weekday: Int,
    val title: String,
    val location: String,
    val startLabel: String,
    val endLabel: String,
    val dayLabel: String,
    val dateLabel: String,
    val periodLabel: String,
    val color: Int,
    val onColor: Int,
    /**
     * 周网格格子里画的那个缩写（`高数` / `离散`）。
     *
     * Dart 那边按「预置表 + 用户覆盖」算好，这里只管画 —— 命名规则在这里
     * 再实现一份的话，用户改了缩写、预置表换了叫法，桌面上的格子都不会动，
     * 而且不会报错。空串就是不画字。
     */
    val abbr: String,
    /** 周网格里的行号，-1 表示不在网格里（作息时间之外的单次事件）。 */
    val gridRow: Int,
    val gridRowSpan: Int,
) {
    /** 这一刻正在上这节。 */
    fun isCurrent(nowMs: Long): Boolean = nowMs >= startAtMs && nowMs < endAtMs

    fun toJson(): JSONObject = JSONObject().apply {
        put("startAtMs", startAtMs)
        put("endAtMs", endAtMs)
        put("setId", setId)
        put("weekday", weekday)
        put("title", title)
        put("location", location)
        put("startLabel", startLabel)
        put("endLabel", endLabel)
        put("dayLabel", dayLabel)
        put("dateLabel", dateLabel)
        put("periodLabel", periodLabel)
        put("color", color)
        put("onColor", onColor)
        put("abbr", abbr)
        put("gridRow", gridRow)
        put("gridRowSpan", gridRowSpan)
    }

    companion object {
        fun fromJson(o: JSONObject): WidgetSession? = try {
            WidgetSession(
                startAtMs = o.getLong("startAtMs"),
                endAtMs = o.getLong("endAtMs"),
                setId = o.optInt("setId", 0),
                weekday = o.optInt("weekday", 0),
                title = o.optString("title"),
                location = o.optString("location"),
                startLabel = o.optString("startLabel"),
                endLabel = o.optString("endLabel"),
                dayLabel = o.optString("dayLabel"),
                dateLabel = o.optString("dateLabel"),
                periodLabel = o.optString("periodLabel"),
                // 白色兜底而不是 0（全透明）：漏了颜色键时画出来是一块看不见的
                // 空白，用户只会觉得「这门课丢了」。
                color = o.optInt("color", 0xFFFFFFFF.toInt()),
                onColor = o.optInt("onColor", 0xFF000000.toInt()),
                // 空串而不是兜底词：漏了这个键时宁可格子里没字，
                // 也不能十二个格子都写着同一个「课程」。
                abbr = o.optString("abbr"),
                gridRow = o.optInt("gridRow", -1),
                gridRowSpan = maxOf(1, o.optInt("gridRowSpan", 1)),
            )
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * 落盘的那份快照。
 *
 * 解析失败返回 null，而不是抛 —— 一份坏掉的快照应当让桌面上那张卡片说
 * 「打开 ClassCal 更新」，而不是让 AppWidgetProvider 崩掉（崩掉的后果是
 * 启动器把这张卡片直接删掉，用户看到的是小组件「自己消失了」）。
 */
data class WidgetSnapshot(
    val version: Int,
    val generatedAtMs: Long,
    /**
     * 窗口里每一天的本地零点，**从锚定那个周一起连续**，最后一格是**排他上界**。
     *
     * 长度是 `horizonDays + 1`（现在 36）：多出来的那一格专门用来给最后一周
     * 一个精确的右端，见 [gridFor]。下标 `0..horizonDays - 1` 才是「一天」。
     */
    val dayStartsMs: List<Long>,
    /** 和 [dayStartsMs] 对齐的**绝对**星期标签（`周三`）。这是「今天」的措辞来源。 */
    val dayLabels: List<String>,
    /**
     * 生成时的本地 UTC 偏移（分钟）。
     *
     * 存它是为了判「换时区了」—— 窗口里的零点是在旧时区算出来的，飞到另一个
     * 时区之后，往后「哪节课算今天」会偏几个小时，而窗口要 35 天才用完。
     * 两边都只是**读一次当前偏移**，不是日期运算，所以这条分界没破。
     */
    val tzOffsetMinutes: Int,
    val theme: WidgetTheme,
    val layout: WidgetLayout,
    /** 窗口内的全部课，已按开始时刻升序。**所有日程混在一起**。 */
    val sessions: List<WidgetSession>,
    /** 值得重画一次的绝对时刻，升序去重。 */
    val boundariesMs: List<Long>,
    /** App 里当前选中的那个日程；0 = 一个日程都没有。 */
    val activeSetId: Int,
    /** 每个日程一块，**末尾永远是总览块**。一个日程都没有时也有一块。 */
    val blocks: List<WidgetSetBlock>,
) {
    /**
     * 这份快照盖不住 [nowMs] 这一刻 —— 它已经过期。
     *
     * ## 判据从「今天是哪一天」换成了「今天在不在窗口里」
     *
     * 老版本比的是本机年月日和快照里钉死的三个整数。那等于宣布「这份快照只在
     * 它被生成的那一天有效」，于是**过了零点的每一次重画都被这道闸门拦下来，
     * 画成一句「打开 ClassCal 更新」**：桌面上那张卡片每天都要靠用户打开一次
     * App 才活。闹钟一直有响，是这里把它判死的。
     *
     * 现在窗口本身就是「35 天」这个维度，判据自然变成一次区间比较。
     *
     * `firstOrNull` / `lastOrNull` 而不是 `first` / `last`：键缺失时
     * [longList] 返回空表，那两个会在这里抛，而 `WidgetRenderer.remotes` 的
     * catch 会把它吞掉 —— 表现是卡片静默冻在上一帧，比画一句提示更难查。
     * 空表一律当过期。
     *
     * `nowMs >= last` 而不是 `> last`：最后一格是**排他上界**（再下一天的零点）。
     * 写成 `> last` 会多算一天，窗口用尽之后的那个第 36 天会显示「今天没有课」，
     * 而那是个真上课的日子。
     */
    fun isStale(nowMs: Long): Boolean {
        val first = dayStartsMs.firstOrNull() ?: return true
        val last = dayStartsMs.lastOrNull() ?: return true
        if (nowMs < first || nowMs >= last) return true
        // 换了时区：窗口里的零点是在旧时区算出来的。不纠正的话，往后「哪节课算
        // 今天」会偏几个小时 —— 而这种错**看起来完全正常**，正是最坏的一种。
        // 两边都只是读一次当前偏移，不是日期运算。
        return TimeZone.getDefault().getOffset(nowMs) / 60_000 != tzOffsetMinutes
    }

    /**
     * [ms] 落在窗口的第几天（0 起）；窗口之前返回 -1。
     *
     * 纯粹的区间比较 —— 逐日零点既然是现成的，「这是哪一天的课」就不该在这里
     * 再算一次。这是**唯一**一处把时刻翻译成「第几天」的地方，渲染器全靠它。
     */
    fun dayIndexOf(ms: Long): Int {
        for (i in dayStartsMs.indices.reversed()) {
            if (ms >= dayStartsMs[i]) return i
        }
        return -1
    }

    /**
     * 第 [index] 天作为分组标题叫什么：`今天 · 周三` / `明天 · 周四` / `周五`。
     *
     * **前缀是措辞，日期是 Dart 给的**：[dayLabels] 里那些字符串在生成时就定死
     * 了（`周三` 这种**绝对**星期，不是「今天」）。反过在这里算星期几，就等于把
     * 日历运算搬进 Kotlin —— 那正是这份快照存在的理由。
     *
     * [todayIndex] 由调用方算好传进来（它已经为了别的事算过一次了）。
     * 更远的日子只给星期：窗口有 5 周，写「第 4 周周三」得先知道那是第几周，
     * 而周号在这边已经没有了（见 [WidgetSetBlock]）。
     */
    fun labelFor(index: Int, todayIndex: Int): String {
        val day = dayLabels.getOrNull(index) ?: return ""
        return when (index) {
            todayIndex -> "今天 · $day"
            todayIndex + 1 -> "明天 · $day"
            else -> day
        }
    }

    /**
     * 今天在窗口里属于第几周（0 起）。窗口外返回 0。
     *
     * 「除 7」能成立是因为窗口**锚在周一**：`dayStartsMs[0]` 是周一零点，于是
     * 每一天的「第几周」就是它的下标除 7。窗口不锚周一的话这里要多一次星期计算，
     * 而那是日历运算，不在这边做。
     */
    fun weekIndexOf(nowMs: Long): Int {
        val t = dayIndexOf(nowMs)
        return if (t < 0) 0 else t / 7
    }

    /**
     * 这一块第 [weekIdx] 周的标题；空串表示**今天不在这个日程的学期里**。
     *
     * 空串不是「没算出来」，是一个**有含义的值**（Dart 侧 `_weekTitle` 在
     * 周号 <= 0 时返回空串）。所以这里不兜底顶替 —— [gridFor] 拿它当判据决定
     * 要不要退回兜底周，渲染器拿它当「退回今天那句」的判据。在这里补一句话，
     * 上面两处就永远看不到那个信号了。
     */
    fun weekTitleOf(block: WidgetSetBlock, weekIdx: Int): String =
        block.weekTitles.getOrNull(weekIdx).orEmpty()

    /**
     * 这一块这一次要画的那一周。
     *
     * 正常情况下是窗口里第 [weekIdx] 周那八个零点（八格给七个区间）。**今天那一周
     * 没有标题**时说明今天不在这个日程的学期里，那就退回块上那份兜底周 ——
     * 那正是「八月份打开 App，大尺寸卡片照旧画第一周有课的网格，而不是一张
     * 空网格」这条现有行为。
     *
     * 判据用「标题是不是空串」而不是「周号 <= 0」：周号在这边**已经没有了**
     * （见 [WidgetSetBlock] 里那段）。
     *
     * 下游只拿到一个 [GridWeek]，**不知道也不该知道**这七个零点来自窗口还是兜底 ——
     * 让它自己去读 `fallbackWeekMs` 的话，学期中那张网格会画成兜底周，而那
     * **只在开学前才看得出来**。
     */
    fun gridFor(block: WidgetSetBlock, weekIdx: Int): GridWeek {
        if (weekTitleOf(block, weekIdx).isNotEmpty()) {
            val from = weekIdx * 7
            val days = (0 until 7).mapNotNull { dayStartsMs.getOrNull(from + it) }
            if (days.size == 7) {
                // 窗口第 36 格就是下一个周一零点 —— 多出那一格正是为了给最后一周
                // 一个**精确的**右端，而不是「周日零点 + 24 小时」那种近似。
                val end = dayStartsMs.getOrNull(from + 7) ?: (days.last() + DAY_MS)
                return GridWeek(days, end)
            }
        }
        val fb = block.fallbackWeekMs
        return GridWeek(fb, fb.lastOrNull()?.plus(DAY_MS) ?: 0L)
    }

    /**
     * 窗口里第 [index] 天的半开区间 `[那天的零点, 下一天的零点)`；越界返回 null。
     *
     * 要求**下一格零点存在**，所以最后一格（排他上界它自己）不是一天、也取不到 ——
     * 那正是它在那儿的意义。旧版本在这里给「第三天之后」留了一条 `+24 小时` 的
     * 近似兜底：那是只有 3 格时不得不做的事，现在每一格都有下一格了。
     */
    fun dayRange(index: Int): Pair<Long, Long>? {
        if (index < 0 || index + 1 >= dayStartsMs.size) return null
        return dayStartsMs[index] to dayStartsMs[index + 1]
    }

    /**
     * 这一块在 `[fromMs, toMs)` 里的课。
     *
     * **「这一块」的判据是两件事**：日程对得上（总览块则全收），而且日期落在
     * 这个区间里。前一件解决「实例配的是哪个日程」，后一件解决「总览里几个
     * 日程的周号不同」—— 后者正是不能按 `week` 数字筛的原因。
     */
    fun sessionsBetween(
        block: WidgetSetBlock,
        fromMs: Long,
        toMs: Long,
    ): List<WidgetSession> = sessions.filter {
        block.accepts(it) && it.startAtMs >= fromMs && it.startAtMs < toMs
    }

    /** 窗口里第 [index] 天这一块有哪些课。 */
    fun sessionsOnDay(block: WidgetSetBlock, index: Int): List<WidgetSession> {
        val (from, to) = dayRange(index) ?: return emptyList()
        return sessionsBetween(block, from, to)
    }

    /**
     * 这一块里正在上、或者接下来要上的那一节。
     *
     * `endAtMs > now` 而不是 `startAtMs > now`：**正在上的那节也算** ——
     * 小尺寸小组件要显示「上课中」，用 `startAtMs > now` 会在打铃那一刻
     * 把它跳过，直接显示下一节。
     *
     * [untilMs] 是**开始时刻**的排他上界。窗口有 5 周，不加这个界就会在放假时
     * 报一节三周后的课 —— 而那不是一个 2×1 的卡片讲得清楚的日子。
     * 缺省值让「只看这一块」的调用方不用传。
     */
    fun currentOrNext(
        block: WidgetSetBlock,
        nowMs: Long,
        untilMs: Long = Long.MAX_VALUE,
    ): WidgetSession? = sessions.firstOrNull {
        block.accepts(it) && it.endAtMs > nowMs && it.startAtMs < untilMs
    }

    /** 下一个值得重画一次的时刻；没有比 [nowMs] 更晚的边界就返回 null。 */
    fun nextBoundary(nowMs: Long): Long? =
        boundariesMs.firstOrNull { it > nowMs }

    fun toJson(): JSONObject = JSONObject().apply {
        put("version", version)
        put("generatedAtMs", generatedAtMs)
        put("dayStartsMs", JSONArray().apply { dayStartsMs.forEach { put(it) } })
        put("dayLabels", JSONArray().apply { dayLabels.forEach { put(it) } })
        put("tzOffsetMinutes", tzOffsetMinutes)
        put("theme", theme.toJson())
        put("layout", layout.toJson())
        put("sessions", JSONArray().apply { sessions.forEach { put(it.toJson()) } })
        put("boundariesMs", JSONArray().apply { boundariesMs.forEach { put(it) } })
        put("activeSetId", activeSetId)
        put("blocks", JSONArray().apply { blocks.forEach { put(it.toJson()) } })
    }

    companion object {
        fun fromJson(o: JSONObject): WidgetSnapshot? = try {
            WidgetSnapshot(
                version = o.optInt("version", 0),
                generatedAtMs = o.optLong("generatedAtMs", 0L),
                dayStartsMs = longList(o.optJSONArray("dayStartsMs")),
                dayLabels = stringList(o.optJSONArray("dayLabels")),
                // 缺键时给一个**不可能等于**真偏移的值（24 小时），于是老快照
                // 一律判过期 —— 和版本号那条闸门同一个方向：宁可让用户重开一次，
                // 也不能拿旧时区的零点当今天。
                tzOffsetMinutes = o.optInt("tzOffsetMinutes", Int.MAX_VALUE),
                theme = WidgetTheme.fromJson(o.optJSONObject("theme") ?: JSONObject()),
                layout = WidgetLayout.fromJson(o.optJSONObject("layout")),
                sessions = sessionList(o.optJSONArray("sessions")),
                boundariesMs = longList(o.optJSONArray("boundariesMs")),
                activeSetId = o.optInt("activeSetId", 0),
                blocks = blockList(o.optJSONArray("blocks")),
            )
        } catch (e: Exception) {
            null
        }

        private fun longList(array: JSONArray?): List<Long> {
            if (array == null) return emptyList()
            return (0 until array.length()).map { array.optLong(it) }
        }

        private fun stringList(array: JSONArray?): List<String> {
            if (array == null) return emptyList()
            return (0 until array.length()).map { array.optString(it) }
        }

        /** 单条解析失败就丢掉那一条 —— 一门课的数据脏了不该让整张课表消失。 */
        private fun sessionList(array: JSONArray?): List<WidgetSession> {
            if (array == null) return emptyList()
            return (0 until array.length()).mapNotNull { i ->
                array.optJSONObject(i)?.let { WidgetSession.fromJson(it) }
            }
        }

        /** 同理：一块日程的数据脏了，剩下的照画。 */
        private fun blockList(array: JSONArray?): List<WidgetSetBlock> {
            if (array == null) return emptyList()
            return (0 until array.length()).mapNotNull { i ->
                array.optJSONObject(i)?.let { WidgetSetBlock.fromJson(it) }
            }
        }
    }
}
