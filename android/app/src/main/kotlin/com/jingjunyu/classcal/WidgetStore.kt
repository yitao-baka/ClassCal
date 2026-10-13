package com.jingjunyu.classcal

import android.content.Context
import android.util.Log
import org.json.JSONObject

/**
 * 小组件的落盘。
 *
 * 形状照抄 [ReminderStore]，理由也一样：**App 死掉的时候，这里是唯一的数据来源**。
 * 桌面上那张卡片由启动器进程 inflate，App 可能几周没被打开过，而闹钟到点时
 * 醒来的也只有我们自己的广播接收器 —— 没有 Flutter engine，没有数据库，
 * 能依靠的就是这份 JSON。
 *
 * 因此存的是**整份快照**而不是「原始课表 + 渲染时现算」：现算就要在这里
 * 重做一遍周次、颜色、行号，而那正是 `WidgetSnapshot` 的注释里说的那类重复。
 */
object WidgetStore {
    private const val TAG = "WidgetStore"

    private const val PREFS = "classcal_widget"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_PENDING_LAUNCH = "pending_launch"
    private const val KEY_PENDING_OPEN = "pending_open"
    private const val PREFIX_CONFIG = "config_"
    private const val PREFIX_OPTIONS = "options_"
    private const val PREFIX_SCOPE = "scope_"
    private const val PREFIX_SETNAME = "setname_"

    /** 内容配置的默认值，和 Dart 侧 `WidgetContent.auto` 同名。 */
    const val CONTENT_AUTO = "auto"

    // -------------------------------------------------------------------------
    // 「这个实例显示哪个日程」
    // -------------------------------------------------------------------------
    //
    // 取值是 Dart 侧 `ScheduleRef` 那套词表：`follow` / `overview` / `set:3`。
    // 两边各持一份字符串常量是**故意的**：这份词表要过 shared_preferences
    // 的边界，而那边只能存字符串。契约测试钉着这几个字面量。

    /** 每次重画都看当时 App 里选中的是哪个日程。 */
    const val SCOPE_FOLLOW = "follow"

    /** 把所有日程合起来看。 */
    const val SCOPE_OVERVIEW = "overview"

    private const val SCOPE_SET_PREFIX = "set:"

    /**
     * `set:3` → 3；不是这个形状就返回 null（`follow` / `overview` / 坏串）。
     *
     * 认不出来时返回 null 而**不是**随便挑一个，是因为调用方对这两件事的处理
     * 完全不同：null 表示「不是固定日程」，要去比 `activeSetId` 或者找总览块。
     */
    fun setIdOf(scope: String?): Int? =
        scope?.takeIf { it.startsWith(SCOPE_SET_PREFIX) }
            ?.removePrefix(SCOPE_SET_PREFIX)
            ?.toIntOrNull()

    /**
     * 这一版 Kotlin 认识的快照结构版本，和 Dart 的 `kWidgetSnapshotVersion` 一致。
     *
     * **版本比它新的快照当作「没有快照」**（画「打开 ClassCal 更新」），而不是
     * 硬着头皮解析：比我们新的版本可能改掉了某个字段的含义，而小组件的错误
     * 形态是「看起来完全正常但是错的」。反过来，**比它旧的照读** —— 老版本
     * 写下的快照缺少的字段都能用默认值兜住，那没必要让用户的桌面空一张。
     *
     * v2 改了 `blocks` / `activeSetId`，而 v1 的快照里**根本没有 `blocks`**
     * —— 那不是「缺个字段用默认值兜」，是整张卡片没有坐标系可用。
     *
     * v3（本轮）把「今天」从一个**日期**（`todayYear/Month/Day` + 三格零点）换成
     * 了一条**35 天的逐日时间轴**，删掉了 `todayTitle` / `tomorrowTitle` /
     * `todayWeekday`，块上还换掉了三个字段。同样兜不住：v2 的快照里那几个键
     * 一个都没有，硬读出来的会是「今天是 0 年 0 月 0 日」。
     *
     * 两次的代价都一样：升级后、App 跑一次之前，桌面上会短暂显示
     * 「打开 ClassCal 更新」。**不写迁移**——旧结构里根本没有「窗口」这个维度，
     * 迁移代码是一辈子只跑一次、却要永远维护的东西。这比那两句话贵。
     */
    private const val SUPPORTED_VERSION = 3

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // -------------------------------------------------------------------------
    // 快照
    // -------------------------------------------------------------------------

    fun saveSnapshot(context: Context, snapshot: WidgetSnapshot) {
        prefs(context).edit().putString(KEY_SNAPSHOT, snapshot.toJson().toString()).apply()
    }

    /**
     * 读回快照；没有、坏了、或者版本读不懂都返回 null。
     *
     * 三种情况在调用方看来是同一件事（画「打开 ClassCal 更新」），所以不分开报。
     */
    fun snapshot(context: Context): WidgetSnapshot? {
        val raw = prefs(context).getString(KEY_SNAPSHOT, null) ?: return null
        return try {
            val snap = WidgetSnapshot.fromJson(JSONObject(raw))
            when {
                snap == null -> null
                snap.version <= 0 || snap.version > SUPPORTED_VERSION -> {
                    Log.w(TAG, "快照版本 ${snap.version} 读不懂，当作没有")
                    null
                }
                else -> snap
            }
        } catch (e: Exception) {
            // 文件坏了就当没有快照 —— 抛出去会让 AppWidgetProvider 崩掉，
            // 而崩掉的后果是启动器直接把这张卡片删掉，用户看到的是
            // 小组件「自己消失了」。
            Log.w(TAG, "快照解析失败，当作没有", e)
            null
        }
    }

    fun hasSnapshot(context: Context): Boolean = snapshot(context) != null

    // -------------------------------------------------------------------------
    // 每个实例的配置
    // -------------------------------------------------------------------------

    /**
     * 这个实例要画什么，默认 [CONTENT_AUTO]（跟随尺寸）。
     *
     * 存的是 Dart 侧 `WidgetContent` 的**枚举名**（`next` / `today` / `week` …），
     * 而不是序号：序号会在枚举里插一项时全部错位，而表现是「用户选了今日课程、
     * 桌面上却显示下一节课」。
     */
    fun content(context: Context, id: Int): String =
        prefs(context).getString(PREFIX_CONFIG + id, null) ?: CONTENT_AUTO

    fun saveContent(context: Context, id: Int, content: String) {
        prefs(context).edit().putString(PREFIX_CONFIG + id, content).apply()
    }

    /**
     * 这个实例显示哪个日程，缺省 [SCOPE_OVERVIEW]。
     *
     * **缺省必须是总览，不是跟随当前。** 加这个功能之前，小组件的快照里
     * 事件是**所有日程混在一起**的 —— 也就是「总览」才是那个**行为不变**的
     * 默认值。缺省成 `follow` 会让升级瞬间桌面上那几个实例**悄悄换掉内容**，
     * 而这种回归没有任何东西会报错。
     *
     * 新开一个键而不是把 `config_<id>` 改成 JSON：后者要处理老值，而那段迁移
     * 代码是一辈子只跑一次、却要永远维护的东西。缺 `scope_<id>` 就是「总览」，
     * 正好是想要的默认 —— **零迁移**。
     */
    fun scope(context: Context, id: Int): String =
        prefs(context).getString(PREFIX_SCOPE + id, null) ?: SCOPE_OVERVIEW

    fun saveScope(context: Context, id: Int, scope: String) {
        prefs(context).edit().putString(PREFIX_SCOPE + id, scope).apply()
    }

    /**
     * 要不要在卡片上写一行「这是哪个日程」，缺省显示。
     *
     * **判的是「是不是 `"0"`」而不是「是不是 `"1"`」**：这样缺省和任何认不出的
     * 值都自然落在「显示」那一侧，不必在三个地方各写一次默认值。
     */
    fun showSetName(context: Context, id: Int): Boolean =
        prefs(context).getString(PREFIX_SETNAME + id, null) != "0"

    /** 传布尔而不是裸串：`"0"` / `"1"` 这个编码只该在这个文件里出现一次。 */
    fun saveShowSetName(context: Context, id: Int, show: Boolean) {
        prefs(context).edit().putString(PREFIX_SETNAME + id, if (show) "1" else "0").apply()
    }

    /**
     * 实例被从桌面上删掉时清掉它的配置，免得换了新实例又继承回来。
     *
     * appWidgetId 是**由启动器分配并且会复用**的，所以漏清一个键的后果不是
     * 「多占几字节」，而是「新加的小组件一上来就显示上一个人的日程名」。
     */
    fun clearInstance(context: Context, id: Int) {
        prefs(context).edit()
            .remove(PREFIX_CONFIG + id)
            .remove(PREFIX_OPTIONS + id)
            .remove(PREFIX_SCOPE + id)
            .remove(PREFIX_SETNAME + id)
            .remove(KEY_PENDING_LAUNCH)
            .remove(KEY_PENDING_OPEN)
            .apply()
    }

    // -------------------------------------------------------------------------
    // 尺寸
    // -------------------------------------------------------------------------

    /**
     * 启动器报给我们的当前尺寸（dp）；没记录过返回 null。
     *
     * **存下来而不是每次现问**：`AppWidgetManager.getAppWidgetOptions` 要跨进程
     * 调启动器，而重画可能发生在闹钟到点的广播里 —— 那时候多一次 IPC 就多一次
     * 被 ROM 掐掉的机会。options 变化时存一次就够了。
     */
    fun options(context: Context, id: Int): Pair<Int, Int>? {
        val raw = prefs(context).getString(PREFIX_OPTIONS + id, null) ?: return null
        return try {
            val o = JSONObject(raw)
            val w = o.optInt("w", 0)
            val h = o.optInt("h", 0)
            if (w <= 0 || h <= 0) null else w to h
        } catch (e: Exception) {
            null
        }
    }

    fun saveOptions(context: Context, id: Int, widthDp: Int, heightDp: Int) {
        val o = JSONObject().apply {
            put("w", widthDp)
            put("h", heightDp)
        }
        prefs(context).edit().putString(PREFIX_OPTIONS + id, o.toString()).apply()
    }

    // -------------------------------------------------------------------------
    // 「点齿轮打开了 App」
    // -------------------------------------------------------------------------

    /**
     * 待处理的 appWidgetId：用户点了小组件上的齿轮，App 起来之后要直接落到
     * 那个实例的配置页。
     *
     * **拉而不是推**：这里只把 id 存着，等 Dart 那边主动问
     * （`consumeLaunch`）。反过来让原生在 Activity 一 `onCreate` 就推，会在
     * Dart 还没挂上通道监听时把这次调用丢掉 —— 和 `capabilities()` 是同一个
     * 道理，而表现是「点了齿轮只是打开了 App，什么都没发生」。
     */
    fun savePendingLaunch(context: Context, id: Int) {
        prefs(context).edit().putInt(KEY_PENDING_LAUNCH, id).apply()
    }

    /** 取一次就清掉，免得每次冷启动都弹配置页。返回 0 表示没有。 */
    fun takePendingLaunch(context: Context): Int {
        val id = prefs(context).getInt(KEY_PENDING_LAUNCH, 0)
        if (id != 0) prefs(context).edit().remove(KEY_PENDING_LAUNCH).apply()
        return id
    }

    // -------------------------------------------------------------------------
    // 「点了卡片（不是齿轮）打开了 App」
    // -------------------------------------------------------------------------

    /**
     * 待处理的 appWidgetId：用户点了卡片的**非齿轮区域**，App 起来之后要落到
     * 那个实例配的日程 + 今天那一周。
     *
     * 和 [savePendingLaunch] 是**两条独立的路，各存各的键**。合成一个槽位是错的：
     * 用户完全可能先点齿轮改配置、退出来又点卡片主体，混用一个键就会把后一次
     * 点击变成「打开配置页」—— 而两次点击写在同一个键上，后写的那次覆盖前面，
     * 没有东西会报错。拉而不是推的理由同 [savePendingLaunch]。
     */
    fun savePendingOpen(context: Context, id: Int) {
        prefs(context).edit().putInt(KEY_PENDING_OPEN, id).apply()
    }

    /** 取一次就清掉，免得每次冷启动都跳到课表。返回 0 表示没有。 */
    fun takePendingOpen(context: Context): Int {
        val id = prefs(context).getInt(KEY_PENDING_OPEN, 0)
        if (id != 0) prefs(context).edit().remove(KEY_PENDING_OPEN).apply()
        return id
    }
}
