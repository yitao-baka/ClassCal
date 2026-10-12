package com.jingjunyu.classcal

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 闹钟的排与撤。
 *
 * 每条提醒一个独立闹钟（而不是「只排最近的一条，响了再排下一条」）：
 * 后者一旦某次唤醒失败（被 ROM 杀掉、电量优化拦下），整条链就断了，
 * 而且是静默断掉 —— 直到用户错过好几节课才会发现。
 */
object ReminderAlarms {
    private const val TAG = "ReminderAlarms"

    /** 闹钟 Intent 的 action。它和 requestCode、组件名一起构成 PendingIntent 的身份。
     *  身份不稳就会出现「取消不掉的幽灵闹钟」，所以这是个常量。 */
    const val ACTION_FIRE = "com.jingjunyu.classcal.action.REMINDER"

    const val EXTRA_ID = "spec_id"
    const val EXTRA_FORCE = "force"

    /** 迟到的提醒超过这么久就丢掉。 */
    private const val STALE_AFTER_MS = 15 * 60 * 1000L

    /**
     * 全量替换。
     *
     * 先撤掉上一批再排新的：课表改一处（整体平移、删一门课）会牵动很多条提醒，
     * 算差量本身就是一类容易出错的逻辑，而全量重排的成本只是几十次系统调用。
     */
    fun sync(context: Context, specs: List<ReminderSpec>) {
        cancelAll(context)
        ReminderStore.savePlan(context, specs)
        ReminderStore.saveArmedIds(context, armAll(context, specs))
    }

    /** 按已落盘的表重新排一遍 —— 开机、时区变更、App 升级之后走这条。 */
    fun rearm(context: Context) {
        val armed = armAll(context, ReminderStore.plan(context))
        ReminderStore.saveArmedIds(context, armed)
        Log.i(TAG, "重新排上 ${armed.size} 条提醒")
    }

    fun cancelAll(context: Context) {
        val am = alarmManager(context)
        // 两类 id 都要撤：`armedIds` 是这张表排出去的，`pendingIds` 是响过之后
        // 又追加上去的一次性跳（snooze / 重复提醒的下一跳）。
        // 只撤前一类的话，改完设置几分钟后还会冒出一条按**旧时刻**排的通知。
        val ids = ReminderStore.armedIds(context) + ReminderStore.pendingIds(context)
        for (id in ids) {
            val pi = pendingIntent(context, id)
            am.cancel(pi)
            pi.cancel()
        }
        ReminderStore.saveArmedIds(context, emptySet())
        ReminderStore.savePendingIds(context, emptySet())
    }

    /**
     * 响了之后追加的一次性闹钟：「10 分钟后再提醒」，以及重复提醒的下一跳。
     *
     * 单独记进 `pendingIds` 而不是 `armedIds`：后者会被当作「系统里现在排着几条」
     * 报给设置页，拿去和提醒表对数目 —— 混进这些临时跳会让那个数字对不上，
     * 而那条对不上的提示是用户自查「设置到底生效没有」的唯一手段。
     */
    fun snooze(context: Context, spec: ReminderSpec, delayMs: Long) {
        val id = spec.id
        val pi = pendingIntent(context, id, force = true)
        setExact(context, System.currentTimeMillis() + delayMs, pi)
        ReminderStore.savePendingIds(context, ReminderStore.pendingIds(context) + id)
    }

    /**
     * 撤掉某个 id 上还挂着的一次性闹钟。
     *
     * 「我已到教室」按下去时走这条 —— 重复提醒的下一跳挂在同一个 id 上，
     * 不撤掉的话按钮按完 N 分钟后提醒又自己弹回来了，而用户只会觉得
     * 按钮是坏的。
     */
    fun cancelPending(context: Context, id: Int) {
        val pi = pendingIntent(context, id)
        alarmManager(context).cancel(pi)
        pi.cancel()
        ReminderStore.savePendingIds(context, ReminderStore.pendingIds(context) - id)
    }

    /** 「试一条提醒」用的一次性条目。 */
    fun armTest(context: Context, atMs: Long, seconds: Long) {
        val spec = ReminderSpec(
            id = TEST_ID,
            key = "test",
            fireAtMs = atMs,
            title = "试一条提醒",
            body = "这条能弹出来，真的课前提醒就能弹出来（${seconds} 秒后）",
            gateLat = null,
            gateLng = null,
            gateRadiusMeters = 0,
            // 演示条目不门控（gateLat/gateLng 都是 null，下面两个字段根本不会被读），
            // 让它**能原样走过真实的那条路**：两秒后就弹，正常响、不自动消失。
            nearby = ReminderSpec.NEARBY_SKIP,
            timeoutMs = 0L,
            // 演示条目不重复。它 10 秒后才弹，而演示的人多半正盯着屏幕等 ——
            // 让它按默认间隔再弹几次纯属打扰。
            repeatIntervalMs = 0L,
            classStartMs = 0L,
        )
        ReminderStore.saveTestSpec(context, spec)
        setExact(context, atMs, pendingIntent(context, spec.id))
    }

    /**
     * 演示提醒的固定 id。
     *
     * 挑一个不会被 FNV-1a 撞上的值不成问题（哈希值遍布 31 位，撞上就是两条
     * 提醒互相顶掉，概率可忽略）。真正要保证的是它**每次一样** ——
     * 否则连点两下会留下两个都取消不掉的闹钟。
     */
    const val TEST_ID = 0x7E57

    private fun armAll(context: Context, specs: List<ReminderSpec>): Set<Int> {
        val now = System.currentTimeMillis()
        val armed = mutableSetOf<Int>()
        for (spec in specs) {
            // 已经过点的直接跳过：补一条「上课前 15 分钟」的提醒发生在课后，
            // 是纯噪音。真的错过了就是错过了。
            if (spec.fireAtMs <= now) continue
            setExact(context, spec.fireAtMs, pendingIntent(context, spec.id))
            armed.add(spec.id)
        }
        return armed
    }

    /**
     * 排一个精确闹钟；拿不到精确权限就退到「大致到点」。
     *
     * 降级路径必须写：`USE_EXACT_ALARM` 在安装时就授予，但用户可以在系统设置里
     * 收回，某些 ROM 也不认这个权限。退到 `setAndAllowWhileIdle` 意味着提醒可能
     * 晚几分钟 —— 比不响好，但要在设置页说清楚，否则「晚了 3 分钟」会被当成 bug。
     */
    private fun setExact(context: Context, atMs: Long, pi: PendingIntent) {
        val am = alarmManager(context)
        try {
            if (canExact(context)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            }
        } catch (e: SecurityException) {
            // 权限在检查之后、设置之前被收回，或者 ROM 直接拒绝。退一步再来。
            Log.w(TAG, "精确闹钟被拒绝，退到不精确", e)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
        }
    }

    fun canExact(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager(context).canScheduleExactAlarms()
        } else {
            // API 31 之前没有「精确闹钟权限」这回事，一直都是精确的。
            true
        }

    /**
     * 同一个 id 拿到同一个 PendingIntent。
     *
     * `FLAG_IMMUTABLE` 是 API 31 起强制的：可变 PendingIntent 会被系统直接拒绝。
     * 我们本来也不需要接收方改 extras。
     */
    private fun pendingIntent(context: Context, id: Int, force: Boolean = false): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_FORCE, force)
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /** 闹钟响了之后的「迟到容忍度」，给 Receiver 用。 */
    fun isStale(spec: ReminderSpec): Boolean =
        System.currentTimeMillis() - spec.fireAtMs > STALE_AFTER_MS
}
