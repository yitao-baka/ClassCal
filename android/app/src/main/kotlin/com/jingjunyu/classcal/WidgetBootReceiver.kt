package com.jingjunyu.classcal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 重启 / App 升级 / 改时间改时区之后，把桌面上的卡片重画一遍。
 *
 * 和 `ReminderBootReceiver` **并列而不是合并**：两者的触发集看起来一样，
 * 但做的事不同（那边重排提醒闹钟，这边重画卡片），而且这一条**顺带会重新
 * 武装刷新链**（`WidgetRenderer.updateAll` 结尾调 `WidgetAlarms.rearm`）。
 * 合起来写会让「改了提醒那边的东西把小组件搞坏」变成可能，而它们本来就
 * 没有任何共享状态。
 *
 * 三个触发点各自的道理：
 *
 * - `BOOT_COMPLETED`：**所有闹钟在重启后都会消失**，这是 `AlarmManager` 的
 *   设计。不重排的话，最典型的表现是「重启一次手机，桌面上的课表就永远停在
 *   重启前那一刻」—— 用户完全不会把这两件事联系起来。
 * - `MY_PACKAGE_REPLACED`：升级会清掉闹钟，也会让落盘的快照变成上一个版本
 *   写的。后者由 `WidgetStore.SUPPORTED_VERSION` 兜着（读不懂就画「打开
 *   ClassCal 更新」），但至少要把卡片刷新一遍，别让它停在旧内容上。
 * - `TIME_SET` / `TIMEZONE_CHANGED`：`RTC_WAKEUP` 存的是 UTC 毫秒数，而快照
 *   里的「今天」是**本地**日期。改了时间或飞了时区之后，两边就对不上了 ——
 *   重画一次会走到 `isStale` 那条判断，于是卡片诚实地显示「课表已过期」，
 *   而不是继续拿昨天的数据装作今天。
 */
class WidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> WidgetRenderer.updateAll(context.applicationContext)
        }
    }
}
