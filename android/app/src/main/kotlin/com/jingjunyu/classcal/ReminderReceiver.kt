package com.jingjunyu.classcal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/**
 * 闹钟到点了。
 *
 * 这是整个提醒链路的落点，也是唯一一个**在 App 已经死掉的时候运行**的组件 ——
 * 所以这里不能碰任何 Flutter 侧的东西，能依靠的只有落盘的那张提醒表。
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(ReminderAlarms.EXTRA_ID, 0)
        if (id == 0) return

        val appContext = context.applicationContext
        val spec = ReminderStore.find(appContext, id)
        if (spec == null) {
            // 表里没有这一条：多半是排完之后又同步过一次（课时改了、课被删了），
            // 而这次闹钟是上一轮的残留。什么都不做才是对的。
            Log.i(TAG, "闹钟 $id 找不到对应的提醒，忽略")
            return
        }

        // 「10 分钟后再提醒」和重复提醒的下一跳都是一次性补发，不受迟到容忍度约束。
        val force = intent.getBooleanExtra(ReminderAlarms.EXTRA_FORCE, false)

        // 重复提醒的收尾。上课之后这一跳只是来撤通知的，不再弹。
        //
        // 这条判断是整条重复链**唯一的终点**（另一个终点是用户按按钮）。下一跳
        // 的排法见 `repeatNext`：最后一跳正好落在 `classStartMs` 上，于是这条链
        // 一定会走到这里，不会留下一个悬着的闹钟在课后随机弹一条。
        //
        // 两处 `force` 都不是装饰：
        //
        // 一是**只拦补发的那几跳，不拦第一次**。把提前量设成 0 的人（提醒时刻
        // 正好等于上课时刻）第一次响时 `now` 已经 >= 上课时刻了，一起拦掉的话
        // 他一条提醒都收不到 —— 而设置页只会说「已开启」，什么异常都看不到。
        //
        // 二是**不能靠上面那条「迟到太久就丢弃」来收尾**：它比的是 `fireAtMs`
        // （第一次提醒的时刻），而重复提醒从第二跳起就把那个时刻甩开十几分钟了，
        // 拿它当终点会把本该响的重复提醒全部丢掉。
        if (force && spec.repeats && System.currentTimeMillis() >= spec.classStartMs) {
            Log.i(TAG, "${spec.key} 已经上课，重复提醒结束")
            NotificationManagerCompat.from(appContext).cancel(spec.id)
            ReminderAlarms.cancelPending(appContext, spec.id)
            return
        }

        if (!force && ReminderAlarms.isStale(spec)) {
            // 手机没电关机、被 ROM 压到几小时后才醒……这时候课上到一半了，
            // 弹出来只有害处。
            Log.i(TAG, "提醒 ${spec.key} 迟到太久，丢弃")
            if (id == ReminderAlarms.TEST_ID) ReminderStore.clearTestSpec(appContext)
            return
        }

        if (!spec.gated) {
            post(appContext, spec)
            return
        }

        // 有门控：要取一次位置，那是个几秒钟的操作，不能在 onReceive 里同步做。
        // goAsync() 让系统知道我们还要接着干，但**必须**在超时前 finish()，
        // 否则进程会被判为 ANR。
        val pending = goAsync()
        LocationProbe.best(appContext, LocationProbe.DEFAULT_TIMEOUT_MS) { fix ->
            try {
                // 注意这三种结果的区别，整个门控的价值就在这个区分上：
                //   在教室里      → 按用户选的模式：静音地弹一条，或者干脆不弹
                //   明确不在教室  → 正常提醒
                //   不知道/拿不准 → 正常提醒，并挂「我已到教室」按钮
                // 把「不知道」当成「不在教室」也能跑，但那样按钮永远不出现，
                // 而降级路径正是这块功能最需要的部分。
                //
                // `fresh` 那道坎是同一道理的另一面：**跳过提醒必须由新位置来支撑**。
                // 拿几小时前的缓存位置判「在教室」会把该响的提醒吞掉，而用户只会
                // 觉得「这提醒时灵时不灵」—— 他没法知道是位置旧了。判不准就照常
                // 提醒：多响一次的代价远小于漏掉一次。
                val inside = fix != null && fix.fresh && spec.contains(fix.location)
                when {
                    !inside -> post(appContext, spec, locationUnknown = fix == null || !fix.fresh)
                    // 静音模式的日志要**和跳过分开**。这两条在用户眼里都表现为
                    // 「没响」，而区分它们是这个模式存在的全部意义 —— 排查时看到的
                    // 如果都是「跳过提醒」，就又回到了「分不清是设计还是坏了」。
                    spec.silentWhenNear -> {
                        Log.i(TAG, "${spec.key} 已在教室附近，静音提醒")
                        post(appContext, spec, silent = true)
                    }
                    else -> Log.i(TAG, "${spec.key} 已在教室附近，跳过提醒")
                }
            } catch (e: Exception) {
                Log.w(TAG, "门控判断出错，照常提醒", e)
                post(appContext, spec)
            } finally {
                pending.finish()
            }
        }
    }

    private fun post(
        context: Context,
        spec: ReminderSpec,
        locationUnknown: Boolean = false,
        silent: Boolean = false,
    ) {
        NotificationHelper.post(context, spec, locationUnknown, silent)
        // 演示提醒用完即弃，留在表里会让「下次同步排了几条」多出个幽灵。
        if (spec.id == ReminderAlarms.TEST_ID) ReminderStore.clearTestSpec(context)
        // 只在**真的弹了**之后才排下一跳：门控判定「人已经在教室里」而跳过的那条
        // 不该继续追着人响，那正好是用户选那个模式想避免的事。
        if (spec.repeats) repeatNext(context, spec)
    }

    /**
     * 排重复提醒的下一跳。
     *
     * 夹到 `classStartMs`：最后一跳正好落在上课那一刻，那时的 `onReceive` 会走
     * 上面那个「已经上课」的分支，把通知撤掉然后停下。这样这条链**一定会自己
     * 终结** —— 否则最后一次重复会排在课后，而那时候弹出来的提醒已经只是在说
     * 「上课了」，和用户按下按钮想达到的效果完全一样，却还得多按一次。
     *
     * 已经在课上就不排了。这条拦的是**提前量为 0** 那种配置：它第一次响时
     * `now` 就等于上课时刻，夹出来的下一跳是「立刻」，于是刚弹出来的通知会被
     * 紧跟的一次收尾跳撤掉 —— 用户看到的是一条一闪而过的横幅。
     */
    private fun repeatNext(context: Context, spec: ReminderSpec) {
        val now = System.currentTimeMillis()
        if (now >= spec.classStartMs) return
        val at = minOf(now + spec.repeatIntervalMs, spec.classStartMs)
        ReminderAlarms.snooze(context, spec, at - now)
    }

    private companion object {
        const val TAG = "ReminderReceiver"
    }
}
