package com.jingjunyu.classcal

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 小组件的刷新链。
 *
 * 「小组件在 App 已经死掉的时候还得是对的」—— 这条决定了整个机制。桌面上那张
 * 卡片归启动器进程管，我们唯一能做的就是在**每个有意义的时刻**醒一次、重画一遍。
 *
 * 和 [ReminderAlarms] 的**结构一样，做法相反**：
 *
 * - 那边是**每条提醒一个闹钟**，因为漏一条就少响一次，链子不能断。
 * - 这边是**只排下一个**：每次醒都从当前的 `now` 重新算下一个边界，**自己纠正**。
 *   手机睡过头、被 ROM 掐掉一次，下一次照样对 —— 而重画一张卡片失败一次，
 *   代价只是内容旧了一会儿，下一个边界就会追上。串行排一个还顺带避开了
 *   「几十个闹钟要一起撤」这类清理逻辑。
 *
 * 边界表（每节课的开始/结束、每个本地零点）由 Dart 算好放进快照
 * （`WidgetSnapshot.boundariesMs`）。这里只做 `firstOrNull { it > now }` ——
 * 不从 sessions 里推导，是因为推导要用到「今天是几号」，那正是小组件这一侧
 * 刻意不做的日历运算。
 */
object WidgetAlarms {
    private const val TAG = "WidgetAlarms"

    /**
     * 闹钟 Intent 的 action。
     *
     * **必须和 `ReminderAlarms.ACTION_FIRE` 不同**：两个模块的 request code
     * 空间是重叠的（提醒那边是哈希出来的任意 31 位整数，这边是固定的 0），
     * 单靠 request code 会互相顶掉。`PendingIntent` 的相等性把 action 算在内，
     * 所以换个 action 就彻底隔开了 —— 代价只是一个常量。
     */
    const val ACTION_TICK = "com.jingjunyu.classcal.WIDGET_TICK"

    private const val REQUEST_CODE = 0

    /**
     * 重新武装：排下一个边界；没有下一个、或者桌面上一个小组件都没有就撤掉。
     *
     * 每次重画之后都要调一次 —— 被叫醒的那一次自己也是这么排下一个的，
     * 所以链子能一直续下去。
     */
    fun rearm(context: Context) {
        val pi = pendingIntent(context)
        val am = alarmManager(context)
        // 先撤再排：同一时刻永远只留一个闹钟。不撤的话，一次全量重画
        // （改设置、开机）会留下几个指向同一件事的闹钟，而它们各自都会
        // 触发一轮重画 + 重排。
        am.cancel(pi)

        if (ClasscalWidgetProvider.placedIds(context).isEmpty()) {
            Log.i(TAG, "桌面上没有小组件，不排刷新闹钟")
            return
        }
        val snapshot = WidgetStore.snapshot(context) ?: return
        val now = System.currentTimeMillis()
        val next = snapshot.nextBoundary(now) ?: return

        setExact(context, next, pi)
        Log.i(TAG, "下一次刷新排在 ${(next - now) / 1000} 秒后")
    }

    /** 撤掉还挂着的刷新闹钟。最后一个小组件被删掉时走这条。 */
    fun cancel(context: Context) {
        val pi = pendingIntent(context)
        alarmManager(context).cancel(pi)
        pi.cancel()
    }

    /**
     * 排一个精确闹钟；拿不到精确权限就退到「大致到点」。
     *
     * 降级路径和提醒那边是同一段（`ReminderAlarms.setExact`）—— 小组件晚几分钟
     * 才翻到「今天」，比永远停在上一天好得多。真到了最坏的情况，还有
     * `updatePeriodMillis` 那条 30 分钟的安全网兜着。
     */
    private fun setExact(context: Context, atMs: Long, pi: PendingIntent) {
        val am = alarmManager(context)
        try {
            if (ReminderAlarms.canExact(context)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "精确闹钟被拒绝，退到不精确", e)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
        }
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, WidgetTickReceiver::class.java).setAction(ACTION_TICK)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
}
