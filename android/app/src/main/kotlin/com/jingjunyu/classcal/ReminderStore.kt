package com.jingjunyu.classcal

import android.content.Context
import android.location.Location
import org.json.JSONArray
import org.json.JSONObject

/**
 * 一条要排给系统的提醒。
 *
 * 字段和 Dart 侧 `ReminderSpec` 一一对应，`toJson` 的键名也要对得上 ——
 * 这是跨语言的数据契约，对不上不会报错，只会「提醒一条都不响」。
 * `test/reminder_channel_test.dart` 里有一条直接读 Dart 与 Kotlin 源码核对的测试。
 */
data class ReminderSpec(
    val id: Int,
    val key: String,
    val fireAtMs: Long,
    val title: String,
    val body: String,
    val gateLat: Double?,
    val gateLng: Double?,
    val gateRadiusMeters: Int,
    /** 判定为「就在教室里」时怎么办，见 [NEARBY_SKIP] / [NEARBY_SILENT]。 */
    val nearby: String,
    /** 弹出后多久自动消失，毫秒；0 表示不自动清除。 */
    val timeoutMs: Long,
    /** 重复提醒的间隔，毫秒；0 表示只响一次。 */
    val repeatIntervalMs: Long,
    /** 这节课的开始时刻（epoch 毫秒）。重复提醒到这一刻必须停 —— 见 [repeats]。 */
    val classStartMs: Long,
) {
    /** 这条要不要在响之前先看一眼位置。 */
    val gated: Boolean get() = gateLat != null && gateLng != null

    /** 这条要不要每隔 [repeatIntervalMs] 再弹一次，直到用户按按钮或上课。 */
    val repeats: Boolean get() = repeatIntervalMs > 0 && classStartMs > 0

    /**
     * 已经在教室里时是「照常弹但不出声」还是「干脆不弹」。
     *
     * 认不出来的值一律当作 [NEARBY_SKIP]：这是老行为，而门控的错误方向应当
     * 偏安静 —— 一个拼错的模式名不该让本该静音的提醒突然响起来。
     */
    val silentWhenNear: Boolean get() = gated && nearby == NEARBY_SILENT

    /** [loc] 是否落在门控半径内。 */
    fun contains(loc: Location): Boolean {
        val lat = gateLat ?: return false
        val lng = gateLng ?: return false
        val out = FloatArray(1)
        Location.distanceBetween(lat, lng, loc.latitude, loc.longitude, out)
        return out[0] <= gateRadiusMeters
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("key", key)
        put("fireAtMs", fireAtMs)
        put("title", title)
        put("body", body)
        gateLat?.let { put("gateLat", it) }
        gateLng?.let { put("gateLng", it) }
        put("gateRadiusMeters", gateRadiusMeters)
        put("nearby", nearby)
        put("timeoutMs", timeoutMs)
        put("repeatIntervalMs", repeatIntervalMs)
        put("classStartMs", classStartMs)
    }

    companion object {
        const val NEARBY_SKIP = "skip"
        const val NEARBY_SILENT = "silent"

        /** 解析失败返回 null 而不是抛 —— 一条坏数据不该让整份提醒表都排不上。 */
        fun fromJson(o: JSONObject): ReminderSpec? = try {
            ReminderSpec(
                id = o.getInt("id"),
                key = o.optString("key"),
                fireAtMs = o.getLong("fireAtMs"),
                title = o.optString("title"),
                body = o.optString("body"),
                gateLat = if (o.has("gateLat")) o.getDouble("gateLat") else null,
                gateLng = if (o.has("gateLng")) o.getDouble("gateLng") else null,
                gateRadiusMeters = o.optInt("gateRadiusMeters", 0),
                // 默认值是老行为。盘里存的那张表可能是上一个版本的 App 写的，
                // 那时候还没有这两个字段。
                nearby = o.optString("nearby", NEARBY_SKIP),
                timeoutMs = o.optLong("timeoutMs", 0L),
                // 0 是「不重复」，也正是老版本的行为：盘里那份表可能是上一个
                // 版本的 App 写的，那时候还没有这两个字段。
                repeatIntervalMs = o.optLong("repeatIntervalMs", 0L),
                classStartMs = o.optLong("classStartMs", 0L),
            )
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * 提醒表落盘。
 *
 * 存下来是为了**开机后不用等 Dart 起来**就能把闹钟重新排上：开机广播只给
 * 几秒钟，那时候没有 Flutter engine，能依靠的只有这份 JSON。
 */
object ReminderStore {
    private const val PREFS = "classcal_reminders"
    private const val KEY_PLAN = "plan"
    private const val KEY_ARMED = "armed_ids"
    private const val KEY_PENDING = "pending_ids"
    private const val KEY_TEST = "test_spec"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun savePlan(context: Context, specs: List<ReminderSpec>) {
        val array = JSONArray()
        for (s in specs) array.put(s.toJson())
        prefs(context).edit().putString(KEY_PLAN, array.toString()).apply()
    }

    fun plan(context: Context): List<ReminderSpec> {
        val raw = prefs(context).getString(KEY_PLAN, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { i ->
                array.optJSONObject(i)?.let { ReminderSpec.fromJson(it) }
            }
        } catch (e: Exception) {
            // 文件坏了就当没有提醒，而不是让开机广播崩掉。
            emptyList()
        }
    }

    /** 按 id 找一条 —— 闹钟响的时候只有 id，其余信息都得从这里捞回来。 */
    fun find(context: Context, id: Int): ReminderSpec? =
        plan(context).firstOrNull { it.id == id } ?: testSpec(context)?.takeIf { it.id == id }

    /** 已排的闹钟 id，用于「先取消全部再重排」。 */
    fun armedIds(context: Context): Set<Int> = intSet(context, KEY_ARMED)

    fun saveArmedIds(context: Context, ids: Set<Int>) = saveIntSet(context, KEY_ARMED, ids)

    /**
     * 响过之后又追加上去的一次性跳（snooze、重复提醒的下一跳）。
     *
     * 和 [armedIds] 分开存，理由见 `ReminderAlarms.snooze` 的注释：这两个集合
     * 撤销的时机一样，但**用途不一样** —— 一个要报给界面当「排了几条」，
     * 另一个不能进去。
     */
    fun pendingIds(context: Context): Set<Int> = intSet(context, KEY_PENDING)

    fun savePendingIds(context: Context, ids: Set<Int>) =
        saveIntSet(context, KEY_PENDING, ids)

    private fun intSet(context: Context, key: String): Set<Int> {
        val raw = prefs(context).getString(key, null) ?: return emptySet()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { array.getInt(it) }.toSet()
        } catch (e: Exception) {
            // 存坏了就当没有 —— 这里返回 null 或抛异常都会让闹钟响了之后
            // 连带把整条链路打断，代价比丢几个 id 大得多。
            emptySet()
        }
    }

    private fun saveIntSet(context: Context, key: String, ids: Set<Int>) {
        val array = JSONArray()
        for (id in ids) array.put(id)
        prefs(context).edit().putString(key, array.toString()).apply()
    }

    // -------------------------------------------------------------------------
    // 试提醒
    // -------------------------------------------------------------------------

    /**
     * 「试一条提醒」用的临时条目。
     *
     * 单独一格而不是塞进 plan：它是 5 秒后就会消失的一次性东西，混进正表里
     * 会让下一次 `sync` 的差量看起来像是「用户删了一条提醒」。
     */
    fun saveTestSpec(context: Context, spec: ReminderSpec) {
        prefs(context).edit().putString(KEY_TEST, spec.toJson().toString()).apply()
    }

    fun testSpec(context: Context): ReminderSpec? {
        val raw = prefs(context).getString(KEY_TEST, null) ?: return null
        return try {
            ReminderSpec.fromJson(JSONObject(raw))
        } catch (e: Exception) {
            null
        }
    }

    fun clearTestSpec(context: Context) {
        prefs(context).edit().remove(KEY_TEST).apply()
    }
}
