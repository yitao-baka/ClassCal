package com.jingjunyu.classcal

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** 一天的毫秒数。用来把「周日零点」推成「下周一零点」—— 排他区间的右端。 */
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
 * **一个日程一块** —— 这块自己的周次、标题、网格坐标。
 *
 * 为什么按日程各存一份而不是全局一份：一个被钉在某个日程上的实例，标题该显示
 * **那个日程的**「第 5 周」。而两个日程的 `week1Monday` 不同时，「第 5 周」落在
 * 不同的日期上 —— 一个全局值必然对其中一个日程是错的。
 *
 * **总览也是一块**（[id] = [OVERVIEW_ID]）。它不是某个日程，所以 `currentWeek`
 * 是 0、`weekTitle` 里也**没有**「第 N 周」，只有日期区间 —— 它没有自己的周号，
 * 硬写一个就是编的。
 *
 * [gridDayStartsMs] 是「按日期筛而不是按周号筛」能成立的关键：手上有了这一周七个
 * 绝对时刻，判一条事件在不在这一周、落在哪一列全是减法，**一个字都没有重做
 * 日历运算**。
 */
data class WidgetSetBlock(
    val id: Int,
    val name: String,
    val currentWeek: Int,
    val weekTitle: String,
    val gridWeek: Int,
    val gridRows: Int,
    val gridDayStartsMs: List<Long>,
) {
    /** 这一块是不是「把所有日程合起来看」那个虚拟页。 */
    val isOverview: Boolean get() = id == OVERVIEW_ID

    /** 这条事件属不属于这一块。总览收下全部。 */
    fun accepts(s: WidgetSession): Boolean = isOverview || s.setId == id

    /**
     * [ms] 落在这一块那七天的第几天（0=周一 … 6=周日）；更早返回 -1。
     *
     * 逗号那一列就是这么定的 —— 用**绝对日期**而不是事件自己的 `weekday`，
     * 因为总览那一块里混着几个日程的事件，只有日期是它们共有的东西。
     */
    fun dayIndexOf(ms: Long): Int {
        for (i in gridDayStartsMs.indices.reversed()) {
            if (ms >= gridDayStartsMs[i]) return i
        }
        return -1
    }

    /**
     * 这一块所画那一周的半开区间 `[周一零点, 下周一零点)`；零点缺失时 null。
     *
     * 右端是「周日零点 + 24 小时」而不是再发一个下周一零点：多一个整数换来的
     * 只是对夏令时的严格性，而这个 App 面向的时区（中国）1991 年起就没有夏令时了。
     * `WidgetSnapshot.dayRange` 里本来就有同一条写法。
     */
    fun weekRange(): Pair<Long, Long>? {
        if (gridDayStartsMs.isEmpty()) return null
        return gridDayStartsMs.first() to gridDayStartsMs.last() + DAY_MS
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("currentWeek", currentWeek)
        put("weekTitle", weekTitle)
        put("gridWeek", gridWeek)
        put("gridRows", gridRows)
        put("gridDayStartsMs", JSONArray().apply { gridDayStartsMs.forEach { put(it) } })
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
                currentWeek = o.optInt("currentWeek", 0),
                weekTitle = o.optString("weekTitle"),
                gridWeek = o.optInt("gridWeek", 0),
                gridRows = o.optInt("gridRows", 0),
                gridDayStartsMs = longList(o.optJSONArray("gridDayStartsMs")),
            )
        } catch (e: Exception) {
            null
        }

        private fun longList(array: JSONArray?): List<Long> {
            if (array == null) return emptyList()
            return (0 until array.length()).map { array.optLong(it) }
        }
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
    val todayYear: Int,
    val todayMonth: Int,
    val todayDay: Int,
    val todayTitle: String,
    val tomorrowTitle: String,
    /** 今天 / 明天 / 后天 的本地零点，正好 3 个。 */
    val dayStartsMs: List<Long>,
    val todayWeekday: Int,
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
     * 快照里的「今天」和真实的今天对不上 —— 这份已经过期。
     *
     * 这是整个小组件**唯一一种会安静地错**的失败：用户一周没开 App，
     * 快照会照样说「今天是周三」，然后自信地画出**上周三**的课。
     * 看起来完全正常。所以渲染前必须比一次，对不上就画「打开 ClassCal 更新」。
     *
     * 只读时钟的年月日，不做任何日期运算 —— 比的是「三个整数相不相等」，
     * 而这三个整数是 Dart 那边算好的。
     */
    fun isStale(nowMs: Long): Boolean {
        val cal = Calendar.getInstance()
        cal.timeInMillis = nowMs
        return cal.get(Calendar.YEAR) != todayYear ||
            cal.get(Calendar.MONTH) + 1 != todayMonth ||
            cal.get(Calendar.DAY_OF_MONTH) != todayDay
    }

    /**
     * [nowMs] 落在第几天：0 今天、1 明天、2 后天、-1 更远或更早。
     *
     * 纯粹的区间比较 —— 三天零点既然是现成的，「这是哪天的课」就不该在这里
     * 再算一次。
     */
    fun dayIndexOf(nowMs: Long): Int {
        for (i in dayStartsMs.indices.reversed()) {
            if (nowMs >= dayStartsMs[i]) return i
        }
        return -1
    }

    /** 第 [index] 天（0=今天）的区间；越界返回 null。 */
    fun dayRange(index: Int): Pair<Long, Long>? {
        if (index < 0 || index >= dayStartsMs.size) return null
        val from = dayStartsMs[index]
        // 后一天没有零点（第三天之后）时，用「最后一个零点 + 24 小时」兜底：
        // 少了这一条，星期二的课在只有三个零点时会一天都取不到。
        val to = if (index + 1 < dayStartsMs.size) {
            dayStartsMs[index + 1]
        } else {
            from + DAY_MS
        }
        return from to to
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

    /** 第 [index] 天（0=今天）这一块有哪些课。 */
    fun sessionsOnDay(block: WidgetSetBlock, index: Int): List<WidgetSession> {
        val (from, to) = dayRange(index) ?: return emptyList()
        return sessionsBetween(block, from, to)
    }

    /** 这一块所画那一周（周网格用）的全部课。 */
    fun sessionsInWeek(block: WidgetSetBlock): List<WidgetSession> {
        val (from, to) = block.weekRange() ?: return emptyList()
        return sessionsBetween(block, from, to)
    }

    /**
     * 这一块里正在上、或者接下来要上的那一节。
     *
     * `endAtMs > now` 而不是 `startAtMs > now`：**正在上的那节也算** ——
     * 小尺寸小组件要显示「上课中」，用 `startAtMs > now` 会在打铃那一刻
     * 把它跳过，直接显示下一节。
     */
    fun currentOrNext(block: WidgetSetBlock, nowMs: Long): WidgetSession? =
        sessions.firstOrNull { block.accepts(it) && it.endAtMs > nowMs }

    /** 下一个值得重画一次的时刻；没有比 [nowMs] 更晚的边界就返回 null。 */
    fun nextBoundary(nowMs: Long): Long? =
        boundariesMs.firstOrNull { it > nowMs }

    fun toJson(): JSONObject = JSONObject().apply {
        put("version", version)
        put("generatedAtMs", generatedAtMs)
        put("today", JSONObject().apply {
            put("y", todayYear)
            put("m", todayMonth)
            put("d", todayDay)
        })
        put("todayTitle", todayTitle)
        put("tomorrowTitle", tomorrowTitle)
        put("dayStartsMs", JSONArray().apply { dayStartsMs.forEach { put(it) } })
        put("todayWeekday", todayWeekday)
        put("theme", theme.toJson())
        put("layout", layout.toJson())
        put("sessions", JSONArray().apply { sessions.forEach { put(it.toJson()) } })
        put("boundariesMs", JSONArray().apply { boundariesMs.forEach { put(it) } })
        put("activeSetId", activeSetId)
        put("blocks", JSONArray().apply { blocks.forEach { put(it.toJson()) } })
    }

    companion object {
        fun fromJson(o: JSONObject): WidgetSnapshot? = try {
            val today = o.optJSONObject("today") ?: JSONObject()
            WidgetSnapshot(
                version = o.optInt("version", 0),
                generatedAtMs = o.optLong("generatedAtMs", 0L),
                todayYear = today.optInt("y", 0),
                todayMonth = today.optInt("m", 0),
                todayDay = today.optInt("d", 0),
                todayTitle = o.optString("todayTitle"),
                tomorrowTitle = o.optString("tomorrowTitle"),
                dayStartsMs = longList(o.optJSONArray("dayStartsMs")),
                todayWeekday = o.optInt("todayWeekday", 0),
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
