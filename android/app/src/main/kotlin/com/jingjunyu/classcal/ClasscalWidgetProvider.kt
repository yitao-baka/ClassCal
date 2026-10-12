package com.jingjunyu.classcal

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.util.Log

/**
 * 小组件的入口。
 *
 * 尺寸自适应**只走一条路**：`onAppWidgetOptionsChanged` + 手动档位。
 *
 * API 31 起有 `RemoteViews(Map<SizeF, RemoteViews>)` 那套「响应式映射」，
 * Google 也推荐它，这里**刻意不用**。理由不是口味而是风险：映射由**启动器**
 * 挑选，而「vivo 的启动器认不认它」是本阶段唯一无法提前验证的事。用了它，
 * 就多一个「代码全对但就是不生效」的可能；不用它，那个风险直接不存在。
 * 代价也不是多写：`minSdk = 24`，API 31 以下本来就得走手动档位，统一成一条
 * 路反而是少维护一条。
 *
 * 顺便，`Map<SizeF, RemoteViews>` 那种写法上「多大算大」的阈值会落在 Kotlin
 * 里；手动档位让那些阈值继续由 Dart 定（快照里的 `layout` 块），只有一处定义。
 */
class ClasscalWidgetProvider : AppWidgetProvider() {

    /**
     * 系统要求的重画（加上、`updatePeriodMillis` 到点、App 更新后恢复）。
     *
     * `updatePeriodMillis` 是**安全网**而不是主力 —— 主力是 `WidgetAlarms`
     * 那条精确边界链。所以这里老老实实全量重画一遍就够了。
     */
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // 每个 id 记一次尺寸：`onUpdate` 之后未必马上来一次
        // `onAppWidgetOptionsChanged`（恢复备份、重新添加时就不会），
        // 而 `auto` 档位要靠尺寸才能定下来。
        for (id in appWidgetIds) {
            manager.getAppWidgetOptions(id)?.let { saveSize(context, id, it) }
        }
        WidgetRenderer.update(context.applicationContext, appWidgetIds)
    }

    /**
     * 用户拖动改了尺寸。
     *
     * 存下来再重画：`auto` 档位是按尺寸推的，尺寸变了显示的内容也该跟着变 ——
     * 从「下一节课」变成「今日课程」正是用户把卡片拉大时期待的事。
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        newOptions?.let { saveSize(context, appWidgetId, it) }
        WidgetRenderer.update(context.applicationContext, intArrayOf(appWidgetId))
    }

    /** 某个实例被从桌面上删掉 —— 清掉它的配置，免得下一个实例继承回来。 */
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) WidgetStore.clearInstance(context.applicationContext, id)
    }

    /** 最后一个实例被删掉了：闹钟一个都不必再排。 */
    override fun onDisabled(context: Context) {
        WidgetAlarms.cancel(context.applicationContext)
    }

    /**
     * 读启动器报的尺寸。
     *
     * 用 `OPTION_APPWIDGET_MAX_*` 而不是 `OPTION_APPWIDGET_MIN_*`：内容的档位
     * 应当按**展开后**的尺寸决定（用户把卡片拉大就是想看到更多），而排版会按
     * 最小尺寸再做一次约束，所以不会裁切。
     */
    private fun saveSize(context: Context, id: Int, options: Bundle) {
        val w = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val h = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        if (w <= 0 || h <= 0) {
            // 老系统或某些启动器不给 options。留 0 会让 `WidgetStore.options`
            // 返回 null，渲染那边自然会退到 `getAppWidgetInfo` 的 minWidth/minHeight。
            Log.i(TAG, "实例 $id 没拿到尺寸，退到 provider 的最小尺寸")
            return
        }
        WidgetStore.saveOptions(context, id, w, h)
    }

    companion object {
        private const val TAG = "ClasscalWidget"

        /**
         * 桌面上现在放着哪些实例。
         *
         * 每次都现查而不是缓存：用户随时可能拖一个上来或者删一个，
         * 而缓存过期会让「删掉最后一个小组件之后闹钟还在排」.
         */
        fun placedIds(context: Context): IntArray =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(widgetComponent(context))
    }
}
