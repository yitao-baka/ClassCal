package com.jingjunyu.classcal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 「到了下一个有意义的时刻」—— 重画，然后再排下一个。
 *
 * 和 `ReminderReceiver` 并列，互不影响：提醒那条链管的是「弹出通知」，
 * 这条链管的是「把桌面上的卡片改成对的」。两者的 action 不同
 * （[WidgetAlarms.ACTION_TICK] vs `ReminderAlarms.ACTION_FIRE`），
 * 所以共享的 request code 空间不会让它们互相顶掉。
 *
 * 这里**不看 Intent 里带了什么**：要画什么完全由落盘的快照决定，
 * 而「下一个边界是什么」每次都从当前的 `now` 重算（`WidgetAlarms.rearm`
 * 在 `updateAll` 里会被调到）。所以就算某次唤醒被 ROM 吞掉、或者设备睡过头
 * 错过了三个边界，醒来的这一次照样把内容改对 —— 这正是「只排一个、自己纠正」
 * 换来的好处。
 */
class WidgetTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WidgetAlarms.ACTION_TICK) return
        WidgetRenderer.updateAll(context.applicationContext)
    }
}
