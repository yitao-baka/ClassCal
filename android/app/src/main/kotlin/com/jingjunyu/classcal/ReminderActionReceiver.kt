package com.jingjunyu.classcal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/**
 * 通知上那两个按钮。
 *
 * 单独一个接收器而不是复用 `ReminderReceiver`：那个的身份里带着「闹钟时刻」，
 * 混在一起会让 PendingIntent 的身份判断变得难懂，而 PendingIntent 身份错了
 * 是「点了按钮没反应」这类最难查的问题。
 */
class ReminderActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(ReminderAlarms.EXTRA_ID, 0)
        if (id == 0) return
        val appContext = context.applicationContext

        when (intent.action) {
            ACTION_ARRIVED -> {
                // 降级路径的出口：位置没取到、用户其实已经在教室，一键消掉。
                NotificationManagerCompat.from(appContext).cancel(id)
                // 重复提醒的出口。这一句是那个选项**全部意义**所系：漏掉它按钮
                // 看上去照常工作（通知确实消失了），但下一跳已经在闹钟里排好了，
                // N 分钟后又弹回来 —— 用户看到的是「这个按钮没反应」，而这条
                // 链路在真机上不跑到下一次重复是看不出来的。
                ReminderAlarms.cancelPending(appContext, id)
            }

            ACTION_SNOOZE -> {
                NotificationManagerCompat.from(appContext).cancel(id)
                val spec = ReminderStore.find(appContext, id) ?: return
                ReminderAlarms.snooze(appContext, spec, SNOOZE_MS)
            }
        }
    }

    companion object {
        const val ACTION_ARRIVED = "com.jingjunyu.classcal.action.ARRIVED"
        const val ACTION_SNOOZE = "com.jingjunyu.classcal.action.SNOOZE"

        private const val SNOOZE_MS = 10 * 60 * 1000L
    }
}
