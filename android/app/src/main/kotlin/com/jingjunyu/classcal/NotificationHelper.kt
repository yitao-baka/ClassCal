package com.jingjunyu.classcal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 课前提醒的通知。
 *
 * 自己写而不是引 `flutter_local_notifications`：提醒的触发时刻要**先看一眼定位**
 * 再决定弹不弹，而那个判断发生在 App 已经死掉、Flutter engine 不在的时候。
 * 用插件就得为这几秒钟起一个后台 Dart isolate，还得解决「后台 isolate 里
 * 通道能不能用、插件注册表在不在」这一串问题；直接写原生反而更短、更可控。
 */
object NotificationHelper {
    const val CHANNEL_ID = "classcal_reminders"

    /**
     * 「人已经在教室附近」时用的渠道：照常弹，但不出声。
     *
     * **只能是另一个渠道，不能是同一个渠道换个 Builder 参数。** 从 Android 8
     * 起声音和振动都归渠道管，在 `Builder` 上 `setSilent(true)` 对已建好的渠道
     * 毫无作用 —— 改完看着像生效了，实际照样响。
     */
    const val SILENT_CHANNEL_ID = "classcal_reminders_silent"

    /** 动作按钮的 action —— 也是 `PendingIntent` 身份的一部分，必须各不相同。 */
    private const val ACTION_ARRIVED = "com.jingjunyu.classcal.action.ARRIVED"
    private const val ACTION_SNOOZE = "com.jingjunyu.classcal.action.SNOOZE"

    /**
     * 建通知渠道。**必须在 App 启动时就建**，不能等到第一次提醒 ——
     * 那时候 App 是死的，`createNotificationChannel` 在接收器里调用虽然也能成，
     * 但渠道的「重要程度」由首次创建时的值定下，之后改了不生效；
     * 放在 App 启动时建，至少用户改过一次之后行为是稳定的。
     */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel(nm, CHANNEL_ID, "课前提醒", "按设定的提前量提醒下一节课", silent = false)
        createChannel(
            nm,
            SILENT_CHANNEL_ID,
            "课前提醒（静音）",
            "人已经在教室附近时的提醒：照常弹出来，但没有铃声和振动",
            silent = true,
        )
    }

    private fun createChannel(
        nm: NotificationManager,
        id: String,
        name: String,
        description: String,
        silent: Boolean,
    ) {
        if (nm.getNotificationChannel(id) != null) return
        val channel = NotificationChannel(
            id,
            name,
            // IMPORTANCE_HIGH 才会以横幅形式弹出。课前提醒晚看到就等于没看到，
            // 压低到默认级别会让它在通知栏里默默躺着。
            //
            // **静音渠道也用 HIGH**：「不响起闹铃」要的是不出声，不是看不见。
            // 降到 LOW 连横幅都不弹，那就退化成「什么也没收到」了 ——
            // 而这个选项存在的全部理由就是「到了教室也想扫一眼确认」。
            // 重要程度和声音是两件事：HIGH + 无声音 = 安静地弹个横幅。
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            this.description = description
            if (silent) {
                setSound(null, null)
                enableVibration(false)
            } else {
                enableVibration(true)
            }
        }
        nm.createNotificationChannel(channel)
    }

    /**
     * 弹一条提醒。
     *
     * [locationUnknown] 为 true 表示**这次门控没做成**（拿不到位置），
     * 那不是「不在教室」，所以照常提醒，只是额外挂一个「我已到教室」的按钮，
     * 让被误提醒的用户一键消掉。
     *
     * [silent] 走静音渠道。**换渠道而不是给同一渠道换参数** —— 见
     * [SILENT_CHANNEL_ID] 的注释。
     */
    fun post(
        context: Context,
        spec: ReminderSpec,
        locationUnknown: Boolean = false,
        silent: Boolean = false,
    ) {
        ensureChannel(context)
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return

        // 提示语得把「这条会重复响」说出来。否则用户按掉之后又来一条，会以为
        // 是 App 出错了 —— 而这是他自己打开的一个选项，只是过了几节课忘了。
        val repeatHint = if (spec.repeats) {
            "\n（每 ${spec.repeatIntervalMs / 60_000} 分钟再提醒一次，"
            "点「我已到教室」或上课即停）"
        } else {
            ""
        }
        val hint = repeatHint + if (locationUnknown) {
            "\n（没能取到位置，已经在教室的话点「我已到教室」）"
        } else {
            ""
        }

        val builder = NotificationCompat.Builder(
            context,
            if (silent) SILENT_CHANNEL_ID else CHANNEL_ID,
        )
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(spec.title)
            .setContentText(spec.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(spec.body + hint))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openApp(context, spec.id))

        // 到点自动消失。用户设了才用 —— 0 就是「不自动清除」。
        //
        // 用 `setTimeoutAfter` 而不是自己排一个延迟广播去 cancel：后者要另开一个
        // 闹钟，还得在用户手动划掉通知之后把这个闹钟也撤掉，不撤的话到点会对一个
        // 已经不存在的通知做一次 cancel（无害，但「已经处理过的事再处理一次」
        // 是 bug 的温床）。系统给的这个就是干这件事的。
        if (spec.timeoutMs > 0) builder.setTimeoutAfter(spec.timeoutMs)

        if (spec.repeats) {
            // 重复模式下「我已到教室」是**唯一**停得掉这条链的按钮，所以无条件
            // 带上，不再看 [locationUnknown] —— 那个参数说的是「位置没取到」，
            // 而这里需要它是因为它同时是**开关**。
            builder.addAction(
                0,
                "我已到教室",
                action(context, spec.id, ACTION_ARRIVED),
            )
            // 重复模式下不给「10 分钟后再提醒」：它和重复本身是同一件事
            // （都是「过一会儿再响」），两个按钮按同一个 id 排闹钟只会互相顶掉，
            // 而用户会以为其中一个坏了。想要晚点再提醒的人可以直接改重复间隔。
        } else {
            if (locationUnknown) {
                builder.addAction(
                    0,
                    "我已到教室",
                    action(context, spec.id, ACTION_ARRIVED),
                )
            }
            // 「再等 10 分钟」对两种情况都有用：还没出门，和这条其实是噪音但不想
            // 现在就处理掉。只给降级路径加按钮的话，正常路径的误报就没有出口了。
            builder.addAction(
                0,
                "10 分钟后再提醒",
                action(context, spec.id, ACTION_SNOOZE),
            )
        }

        try {
            nm.notify(spec.id, builder.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS 被收回。设置页的状态卡片会显示出来，这里不再出声。
        }
    }

    /** 点通知正文 → 打开 App。 */
    private fun openApp(context: Context, id: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun action(context: Context, id: Int, action: String): PendingIntent {
        val intent = Intent(context, ReminderActionReceiver::class.java).apply {
            this.action = action
            putExtra(ReminderAlarms.EXTRA_ID, id)
        }
        // requestCode 用 id + action 的哈希，而不是只取 id —— 两个按钮
        // requestCode 相同、只有 action 不同，靠 action 也能区分身份，
        // 但把 requestCode 也分开可以让 PendingIntent 池里的碰撞无从发生。
        return PendingIntent.getBroadcast(
            context,
            id * 31 + action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

}
