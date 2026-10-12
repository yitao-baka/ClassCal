package com.jingjunyu.classcal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 把闹钟重新排上。
 *
 * **所有闹钟在重启后都会消失**，这是 `AlarmManager` 的设计：进程和它排的闹钟
 * 一起死。开机不重排的话，最典型的表现是「重启一次手机，之后一周都没有提醒」，
 * 而用户完全不会把这两件事联系起来。
 *
 * 时区变更同样要重排：`RTC_WAKEUP` 存的是 UTC 毫秒数，而提醒说的是墙上时间。
 * 从一个时区飞到另一个时区之后，不重排的闹钟会按原来的 UTC 时刻响 ——
 * 也就是在新时区里偏了好几个小时。
 */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> ReminderAlarms.rearm(context.applicationContext)
        }
    }
}
