package com.jingjunyu.classcal

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews

/**
 * 把一份快照变成桌面上的那张卡片。
 *
 * **纯函数**：输入尺寸 + 配置 + 快照，输出 `RemoteViews`，不写任何持久状态。
 * Dart 那边那个 `preview` 通道方法也走它 —— 所以「配置页里的预览」和
 * 「桌面上的实际渲染」是**同一段代码**，不是两份会走偏的实现。
 * （准确地说，预览把 RemoteViews `apply()` 成一个真的 View 再 `draw()` 到
 * 位图上，走的是同一条 action 路径；唯一的差别只在启动器自己那一侧的 inflate。）
 *
 * 每次调用都**新建**一个 `RemoteViews`。复用同一个实例会把每次
 * `setImageViewBitmap` 累积成一条条独立 action，改十次就是十份位图一起过 Binder
 * —— 这是个不撞上就永远不知道的坑。
 *
 * ## 每个实例先挑一块，再照着它画
 *
 * 从本轮起快照里的事件分属不同**日程**，而每个实例可以指定它显示哪一个
 * （[WidgetStore.scope]）。[remotes] 开头那次 [blockFor] 就是这件事的**唯一一处**
 * 实现：挑出块之后，下面三种布局拿到的都是「一块的坐标 + 一块的事件」，
 * 没有一处需要知道这个实例配的是总览还是某个日程。
 */
object WidgetRenderer {
    private const val TAG = "WidgetRenderer"

    // 内容和 Dart 侧 `WidgetContent` 的枚举名一一对应。
    const val CONTENT_AUTO = "auto"
    const val CONTENT_NEXT = "next"
    const val CONTENT_TODAY = "today"
    const val CONTENT_TODAY_TOMORROW = "todayTomorrow"
    const val CONTENT_WEEK = "week"

    /** 点齿轮打到 `MainActivity` 上的那个 action。 */
    const val ACTION_CONFIGURE = "com.jingjunyu.classcal.WIDGET_CONFIGURE"

    /** 点卡片**除齿轮之外**的区域打到 `MainActivity` 上的那个 action。 */
    const val ACTION_OPEN = "com.jingjunyu.classcal.WIDGET_OPEN"

    const val EXTRA_WIDGET_ID = "app_widget_id"

    /**
     * 整卡点击那条 `PendingIntent` 的 request code 起点。
     *
     * 齿轮用的是 appWidgetId 本身，这一条用 `REQUEST_OPEN_BASE + id`。
     * **严格说，撞在同一个 request code 上也不会出事** —— `PendingIntent` 的
     * 相等性是把 action 一起算的（齿轮那句注释里写了这条），两个 action 不同。
     * 分开是**为了别去依赖那条性质**：它埋在 `filterEquals` 的定义里，
     * 而看代码的人只会看到两个 `getActivity` 用着同一个数字。撞上时的表现是
     * 「点齿轮和点卡片主体进了同一个地方」，那不会报错，只会看起来像齿轮坏了。
     *
     * 取 100000 是因为 appWidgetId 由启动器分配、实践上到不了四位数。
     */
    private const val REQUEST_OPEN_BASE = 100_000

    /** 尺寸读不到时的兜底，和 `classcal_widget_info.xml` 的 minWidth/minHeight 一致。 */
    private const val FALLBACK_WIDTH_DP = 110
    private const val FALLBACK_HEIGHT_DP = 40

    // -------------------------------------------------------------------------
    // 列表里各块占的高度（dp）—— 用来算「这几行放不放得下」
    // -------------------------------------------------------------------------
    //
    // **放在 Kotlin 里而不是快照里**，因为它纯粹是排版问题 —— 和日历无关，
    // Dart 那边也不该知道 `widget_row.xml` 有多高。这和「Dart 算，Kotlin 只画」
    // 不冲突：那条原则管的是**日期运算和配色**，不是像素。
    //
    // ## 这几个数是怎么来的（真机实测，不是推算）
    //
    // vivo V2553A / 1080×2400 @ 411dpi（密度 2.571）上摆一个 200dp 宽的中号列表，
    // `adb shell uiautomator dump` 把每个控件的 bounds 打出来，除以 2.571：
    //
    //     根布局上下内边距      8 + 8      = 16dp   ← **没有单独计入下面任何一项**
    //     日程名那条 11sp       14.4 + 3   = 17.4dp
    //     标题栏（26dp 齿轮撑着）           = 26dp
    //     分组标题 11sp         14.8 + 5   = 19.8dp
    //     一行（26dp 色条 + 3+3 内边距）    = 32dp
    //     页脚 11sp             14.8 + 2   = 16.7dp
    //
    // 也就是说：**标题栏那个 26 是准的（它由齿轮的固定 26dp 决定），
    // 另外三个文字项每个都比实测大 3~6dp，根布局那 16dp 则完全没算。**
    // 那不是量错了，是刻意留的：文字项的高度跟着系统字号走，字号调到 1.3 倍时
    // 一行 11sp 就从 14.8 变成 19dp，按实测值算就会**少留**一行、最后一行露出
    // 半个。多留的这点余量正好把根布局那 16dp 也盖住了 —— 所以别为了「算得更准」
    // 把它们改成实测值：要改就得**先把根布局的 16dp 补回来**，否则是净减。
    //
    // 代价是行数算得偏保守：4×4（242dp）的「今天+明天」实际放得下 4 行 + 页脚，
    // 这里算出来是 3 行。宁可这样 —— 估大只是提前折成「还有 N 节」，
    // 估小了是最后一行被顶出卡片露出半个，那看起来就是渲染坏了。
    //
    // （还有一截空白的来源不在这一侧：这台 ROM 的启动器报
    // `OPTION_APPWIDGET_MAX_HEIGHT = 242`，实际却给了 250dp。
    // 我们只能拿到它报的那个数。）
    private const val HEADER_DP = 26
    private const val ROW_DP = 34
    private const val GROUP_DP = 26
    private const val FOOTER_DP = 20

    /**
     * 日程名那一行占的高度（dp）。
     *
     * 本轮新增的 `@id/set_label`（11sp + 3dp 下边距）实测 **17.4dp**，
     * 这里写的 24 和上面四个是同一套尺子 —— 字号一变它就变，所以留同样的余量，
     * 理由和上面那段完全一样（宁可提前一行折成「还有 N 节」，不要露半个）。
     *
     * 它进 `chrome` 这件事本身是硬要求：漏掉的话开着日程名时最后一行会被顶出
     * 卡片，而**单元测试看不见** —— 契约测试只钉得住「它被减掉了」，
     * 钉不住这个数字对不对。所以真机上量过一次，结论就是上面那个 17.4。
     */
    private const val LABEL_DP = 24

    // -------------------------------------------------------------------------
    // 入口
    // -------------------------------------------------------------------------

    /** 重画桌面上全部实例，然后重新武装刷新闹钟。 */
    fun updateAll(context: Context) {
        val ids = ClasscalWidgetProvider.placedIds(context)
        if (ids.isEmpty()) {
            // 一个小组件都没放时**一个闹钟都不排** —— 排了也是白醒。
            WidgetAlarms.cancel(context)
            return
        }
        update(context, ids)
    }

    /** 重画指定的几个实例，然后重新武装刷新闹钟。 */
    fun update(context: Context, ids: IntArray) {
        val now = System.currentTimeMillis()
        val snapshot = WidgetStore.snapshot(context)
        val manager = AppWidgetManager.getInstance(context)
        for (id in ids) {
            try {
                val (w, h) = sizeOf(context, id)
                manager.updateAppWidget(
                    id,
                    remotes(
                        context = context,
                        id = id,
                        content = WidgetStore.content(context, id),
                        scope = WidgetStore.scope(context, id),
                        showSetName = WidgetStore.showSetName(context, id),
                        snapshot = snapshot,
                        nowMs = now,
                        widthDp = w,
                        heightDp = h,
                    ),
                )
            } catch (e: Exception) {
                // 单个实例画不出来不该让其余的也跟着不更新 —— 启动器上那些卡片
                // 是彼此独立的，而这里的循环是共享的。
                Log.w(TAG, "重画实例 $id 失败", e)
            }
        }
        WidgetAlarms.rearm(context)
    }

    /**
     * 渲染成一份 `RemoteViews`，**并把整卡点击挂上去**。
     *
     * 这一步刻意留在最外面、只有一处：四种布局（含两张提示卡）都从这里出去，
     * 漏挂一种的表现是「某个尺寸点不动」—— 而那是四种里最难发现的一种漏。
     * 挂在这里就不用去数底下有几个 `return`。
     *
     * [content] 是**配置里选的值**（可能是 [CONTENT_AUTO]），真正的档位由
     * [effectiveContent] 决定。[scope] 同理由 [blockFor] 决定落到哪一块。
     */
    fun remotes(
        context: Context,
        id: Int,
        content: String,
        scope: String,
        showSetName: Boolean,
        snapshot: WidgetSnapshot?,
        nowMs: Long,
        widthDp: Int,
        heightDp: Int,
    ): RemoteViews = build(
        context, id, content, scope, showSetName, snapshot, nowMs, widthDp, heightDp,
    ).also { attachOpen(context, it, id) }

    private fun build(
        context: Context,
        id: Int,
        content: String,
        scope: String,
        showSetName: Boolean,
        snapshot: WidgetSnapshot?,
        nowMs: Long,
        widthDp: Int,
        heightDp: Int,
    ): RemoteViews {
        // 没有快照 = App 还没跑过；过期 = 用户一周没开 App。两者都只能画一句
        // 提示：过期那份如果照画，会自信地显示**上周的课**，而那看起来完全正常。
        if (snapshot == null || snapshot.isStale(nowMs)) {
            return initialView(context, snapshot != null)
        }

        // 挑不出块就没有坐标系可用（周次、列号、事件全都挂在块上）。
        // 一份 v2 快照至少有一个块，所以这条只在快照残缺时命中。
        val block = blockFor(snapshot, scope)
            ?: return initialView(context, stale = false)

        val layout = snapshot.layout
        return when (effectiveContent(content, widthDp, heightDp, layout)) {
            CONTENT_NEXT -> nextView(context, snapshot, block, nowMs)

            CONTENT_WEEK -> weekView(
                context, snapshot, block, id, showSetName, widthDp, heightDp, nowMs,
            )

            CONTENT_TODAY -> listView(
                context, snapshot, block, id, layout, showSetName, heightDp, nowMs,
                tomorrow = false,
            )

            else -> listView(
                context, snapshot, block, id, layout, showSetName, heightDp, nowMs,
                tomorrow = true,
            )
        }
    }

    /**
     * 这个实例该画哪一块。
     *
     * `follow` / 认不出来的串 / **那个日程已经被删掉** 三种情况都退到
     * 「App 里当前选中的那一块」。退到那儿而不是画空白，是因为用户删掉一个日程
     * 之后，桌面上那几个小组件应该继续显示别的东西 —— 一起变成「打开 ClassCal」
     * 看起来就是这个功能坏了。
     *
     * 顺序不能颠倒：先按 `set:<id>` 精确匹配，再判总览，最后才退到 `activeSetId`。
     * 把总览那一步提前会让「跟随当前、而当前正好是某个日程」在 `activeSetId`
     * 恰好等于 `OVERVIEW_ID` 时永远命中总览 —— 而那个等号**永远不会成立**
     * （drift 的 id 从 1 开始），所以那是条死代码，写错了也看不出来。
     */
    private fun blockFor(snapshot: WidgetSnapshot, scope: String): WidgetSetBlock? {
        val blocks = snapshot.blocks
        if (blocks.isEmpty()) return null

        WidgetStore.setIdOf(scope)?.let { id ->
            blocks.firstOrNull { it.id == id }?.let { return it }
        }
        if (scope == WidgetStore.SCOPE_OVERVIEW) {
            blocks.firstOrNull { it.isOverview }?.let { return it }
        }
        return blocks.firstOrNull { it.id == snapshot.activeSetId }
            ?: blocks.firstOrNull { it.isOverview }
            ?: blocks.first()
    }

    /**
     * 配置里选了什么就画什么；选了 [CONTENT_AUTO] 才按尺寸推导。
     *
     * 用户显式选了「本周缩略」而小组件被缩到 2×1 时**照画不误** —— 画出来会很挤，
     * 但那是用户自己选的。替他改回默认只会让人以为设置没生效，然后再去点一遍。
     */
    fun effectiveContent(
        configured: String,
        widthDp: Int,
        heightDp: Int,
        layout: WidgetLayout,
    ): String = when (configured) {
        CONTENT_NEXT, CONTENT_TODAY, CONTENT_TODAY_TOMORROW, CONTENT_WEEK -> configured

        else -> when {
            // 「大」要宽高同时够：一个 4×2 的扁条宽度够大，但 5 行网格塞不进 170dp。
            widthDp >= layout.largeMinWidthDp && heightDp >= layout.largeMinHeightDp ->
                CONTENT_WEEK

            // 「小」看高度 —— 理由写在 `WidgetLayout.smallMaxHeightDp` 的注释里：
            // 卡住「下一节课」那条布局的是竖直空间，而按宽度判在 4 列网格上
            // 永远不会命中。宽度在这里没用，索性不看。
            heightDp < layout.smallMaxHeightDp -> CONTENT_NEXT
            else -> CONTENT_TODAY
        }
    }

    // -------------------------------------------------------------------------
    // 三种布局
    // -------------------------------------------------------------------------

    private fun initialView(context: Context, stale: Boolean): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_initial).apply {
            setTextViewText(
                R.id.initial_message,
                if (stale) "课表已过期 · 打开 ClassCal 更新" else "打开 ClassCal 同步课表",
            )
        }

    /**
     * 日程名那条信息条 —— 写 [block] 的名字，不写就整条收掉。
     *
     * **不画色点**：总览块的 `color` 借的是当前日程的色，画出来等于给一个
     * 「合并视图」编了一个它没有的颜色。
     *
     * 三种布局里只有 [listView] 和 [weekView] 调它。[nextView]（2×1）**结构上**
     * 就没有这一栏 —— 那是四个控件已经排满的一档，不是「用户关掉了」。所以
     * 配置页那个开关在小尺寸上不生效但不置灰：它要持久化，用户配好之后
     * 改成中/大尺寸时那一栏会自己回来。
     */
    private fun attachSetLabel(
        rv: RemoteViews,
        block: WidgetSetBlock,
        theme: WidgetTheme,
        show: Boolean,
    ) {
        if (show) {
            rv.setViewVisibility(R.id.set_label, View.VISIBLE)
            rv.setTextViewText(R.id.set_label, block.name)
            rv.setTextColor(R.id.set_label, theme.secondary)
        } else {
            rv.setViewVisibility(R.id.set_label, View.GONE)
        }
    }

    /** 小：下一节课（或正在上的那一节）。 */
    private fun nextView(
        context: Context,
        snapshot: WidgetSnapshot,
        block: WidgetSetBlock,
        nowMs: Long,
    ): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_next)
        val theme = snapshot.theme
        rv.setInt(R.id.widget_root, "setBackgroundColor", theme.surface)
        rv.setInt(R.id.next_bar, "setBackgroundColor", theme.accent)
        rv.setTextColor(R.id.next_eyebrow, theme.secondary)
        rv.setTextColor(R.id.next_title, theme.onSurface)
        rv.setTextColor(R.id.next_location, theme.secondary)

        // 「今天是窗口里的第几天」。**这个下标是「这节是不是今天的」的唯一来源** ——
        // 拿它和这一节的 `dayIndexOf` 比。不问这一句的话，恒真的「今天是不是第 0 天」
        // 会让下面那一支永远命中、后面全是死代码，而表现是周六上午的卡片上写着
        // 「第一二节 · 08:00–09:40」，指着一节**周一**的课，读起来就是
        // 「我今天一二节有课」。这是整个小组件里最容易信的假话。
        //
        // `isStale` 已经把「今天不在窗口里」挡在门外了，所以这里 `t` 一定在
        // 0..horizonDays-1 里；真出了窗口也只是退化成「接下来没有课了」。
        val t = snapshot.dayIndexOf(nowMs)

        // **搜索范围夹到一周之内。** 窗口从 9 天变成 35 天之后，`currentOrNext`
        // 会在放假（或者课表后几周是空的）时一路找到三周后的那节课，然后这张
        // 2×1 的卡片写着「周三 08:00–09:40」—— 读起来就是「周三有课」，而它其实
        // 是三周后的周三。一周是能自圆其说的范围：更远的话，与其报一个用户无从
        // 定位是哪个「周三」的日子，不如说「接下来没有课了」。
        val weekEnd = snapshot.dayStartsMs.getOrNull(t + 7) ?: Long.MAX_VALUE

        val session = snapshot.currentOrNext(block, nowMs, untilMs = weekEnd) ?: return rv.apply {
            setTextViewText(R.id.next_title, "接下来没有课了")
            setTextViewText(R.id.next_location, "")
        }

        rv.setInt(R.id.next_bar, "setBackgroundColor", session.color)

        val dayIndex = snapshot.dayIndexOf(session.startAtMs)

        // 「上课中」是唯一一种不需要倒计时的进行态：它只依赖 `nowMs` 落在
        // [startAtMs, endAtMs) 里，而那一刻本来就会有一个边界闹钟把我们叫醒。
        // 真正的倒计时（「还有 23 分钟」）需要每分钟一跳的闹钟，这里没有那种东西。
        val eyebrow = when {
            session.isCurrent(nowMs) -> "上课中 · ${session.endLabel} 下课"

            dayIndex == t -> listOfNotNull(
                session.periodLabel.ifEmpty { null },
                "${session.startLabel}–${session.endLabel}",
            ).joinToString(" · ")

            dayIndex == t + 1 -> "${session.dayLabel} ${session.startLabel}–${session.endLabel}"

            // 一周之内、但不是今明两天：**必须带上日期**。窗口有 5 周，
            // 光写「周三」会是一个无从判断是哪个周三的日期 —— 而这里说的恰恰是
            // 一节几天之后的课。`dateLabel` 每条事件都带着（`10/15` 这种），
            // 空串时退化成只有星期，仍旧比一个光秃秃的「周三 08:00」强。
            else -> listOfNotNull(
                session.dateLabel.ifEmpty { null },
                session.dayLabel.ifEmpty { null },
                "${session.startLabel}–${session.endLabel}",
            ).joinToString(" ")
        }
        rv.setTextViewText(R.id.next_eyebrow, eyebrow)
        rv.setTextViewText(R.id.next_title, session.title)
        rv.setTextViewText(R.id.next_location, session.location)
        return rv
    }

    /**
     * 中/大：今天，或者今天 + 明天。
     *
     * 行是**逐个 addView 塞进去**的：`RemoteViews` 的子视图只能来自布局资源，
     * 没有「用代码建一个 View」这条路 —— 所以 `widget_row.xml` 和
     * `widget_group.xml` 这两个只有几行的文件是必需的，不是啰嗦。
     */
    private fun listView(
        context: Context,
        snapshot: WidgetSnapshot,
        block: WidgetSetBlock,
        id: Int,
        layout: WidgetLayout,
        showSetName: Boolean,
        heightDp: Int,
        nowMs: Long,
        tomorrow: Boolean,
    ): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_list)
        val theme = snapshot.theme
        rv.setInt(R.id.widget_root, "setBackgroundColor", theme.surface)
        rv.setTextColor(R.id.list_header, theme.secondary)
        rv.setTextColor(R.id.footer, theme.secondary)
        attachGear(context, rv, id, theme)
        attachSetLabel(rv, block, theme, showSetName)

        // **今天不再是一个常量 0，而是一个下标。** 「今天 / 明天」这两组以前是
        // 现成的字段（`sessionsOnDay(block, 0/1)`），现在得先问一句今天是窗口里的
        // 第几天 —— 这一句问完，跨天就不再需要 App 跑一次了。
        val t = snapshot.dayIndexOf(nowMs)
        val weekIdx = snapshot.weekIndexOf(nowMs)

        // 「今天 + 明天」时主标题换成周次：两个分组各自带着「今天 · 周三」
        // 「明天 · 周四」，主标题再写一次「今天」就重复了。
        //
        // 周次取自**这一块**而不是快照顶层 —— 被钉在某个日程上的实例该显示
        // 那个日程的「第 N 周」，而总览块的标题只有日期区间（它没有自己的周号），
        // `ifEmpty` 正好兜住。
        rv.setTextViewText(
            R.id.list_header,
            if (tomorrow) snapshot.weekTitleOf(block, weekIdx).ifEmpty { snapshot.labelFor(t, t) }
            else snapshot.labelFor(t, t),
        )

        // **今天落在窗口最后一天时只画「今天」一组。** 那时候 `t + 1` 已经在窗口
        // 外了，画一个必定空的「明天」等于说假话 —— 而它底下会跟着一句
        // 「没有课」，读起来就是「明天没课」。窗口用尽之前 Dart 会推一份新快照，
        // 所以这是最后一天的边界，不是常态。
        val days = if (tomorrow && snapshot.dayRange(t + 1) != null) listOf(t, t + 1) else listOf(t)
        val groups = days.map { snapshot.labelFor(it, t) to snapshot.sessionsOnDay(block, it) }
        val total = groups.sumOf { it.second.size }

        rv.removeAllViews(R.id.rows)
        // 放不下的折成一句「还有 N 节」，而不是硬塞 —— 塞进去的结果是最后一行
        // 只露出一半，看起来像渲染坏了。
        //
        // **行数是按高度算的，不是简单的 `maxListRows`。** 卡片的竖直空间里
        // 标题和分组标题先占掉一块，剩多少才轮到行。按固定行数画的结果是
        // 「今天 + 明天」在 4×2 上比「今天」多一个分组标题，正好把最后一行
        // 和那句「还有 N 节」一起顶出去 —— 而「还有 N 节」正是为了不让用户
        // 以为课就这几节才写的。
        //
        // 分组标题吃的高度按**真会画出来的个数**算（见下 `showTitle`）：只画今天
        // 时一个分组标题都不画（顶部那条 header 已经写着「今天 · 周二」），
        // 「今天 + 明天」时最少画今天那一个。
        val twoDays = days.size > 1
        fun capacity(groupTitles: Int, reserveFooter: Boolean): Int {
            val chrome = (if (showSetName) LABEL_DP else 0) + HEADER_DP +
                GROUP_DP * groupTitles + if (reserveFooter) FOOTER_DP else 0
            return ((heightDp - chrome) / ROW_DP).coerceIn(1, layout.maxListRows)
        }

        // **今天的课先排满，剩下的行才轮到明天。**
        //
        // 以前是「先给后面的组留一行，再按顺序填」。分组标题和数据行吃的是同一份
        // 高度，所以「给明天留一行」实际是拿今天的一节课去换明天的一节课 ——
        // 今天 4 节、只排得下 3 行时，画出来是「今天 2 节 + 明天 1 节」，
        // 读起来就是「我今天少了一节课」，而缺的那节明明还在下面排着队。
        //
        // 明天出场的条件是**今天一节不落地排完、且还剩至少一整行**。行数是整数，
        // 「还剩 1」就是「够一整行」，所以不存在只排半行的情况。
        //
        // 判据用的是**两个分组标题**那份容量，也就是保守的那一份。明天不出场时
        // 它那个标题省下来了（`GROUP_DP = 26 < ROW_DP = 34`，所以这笔高度还给
        // 今天），但**不拿这份多出来的空间回头再问一遍明天能不能出场** —— 那会
        // 让两个决定互相喂食：不出场 → 空间变大 → 能出场 → 空间变小 → 不出场。
        // 宁可少排明天一行，也不能把行数算多一行、末行被裁掉半个。
        //
        // 返回值：[今天几行, 明天几行, 还能拿出几行放「没有课」那句]。
        // 明天「出场」和「排了几行」是两件事：明天一节课都没有时它照样出场，
        // 只是排 0 行、由那句「没有课」占位。
        fun plan(groupTitles: Int, reserveFooter: Boolean): IntArray {
            val wide = capacity(groupTitles, reserveFooter)
            val todayRows = minOf(groups[0].second.size, wide)
            val rest = wide - todayRows
            if (twoDays && rest >= 1) {
                val tomorrowRows = minOf(rest, groups[1].second.size)
                return intArrayOf(todayRows, tomorrowRows, rest - tomorrowRows)
            }
            val narrow = capacity(if (twoDays) 1 else 0, reserveFooter)
            return intArrayOf(minOf(groups[0].second.size, narrow), 0, 0)
        }

        // 先按「不需要页脚」算一次：装得下就一行都不用省，页脚也不用出。
        // 装不下才把页脚那块高度让出来重算一次。
        val wideTitles = if (twoDays) 2 else 0
        val roomy = plan(wideTitles, reserveFooter = false)
        val fitted = if (total - roomy[0] - roomy[1] > 0) {
            plan(wideTitles, reserveFooter = true)
        } else {
            roomy
        }

        val allowance = IntArray(groups.size) { fitted[it] }
        // 明天出场 ⇔ 上面那条分支命中过 ⇔ 今天的课排完之后还剩下了行。
        val tomorrowInPlay = twoDays && fitted[1] + fitted[2] > 0

        // 分组标题画几个。明天不出场时它那个标题跟着省掉：一个底下什么都没有的
        // 「明天 · 周三」比不写更让人困惑，而且省下的高度已经还给今天了。
        val showTitle = BooleanArray(groups.size) { i -> twoDays && (i == 0 || tomorrowInPlay) }

        // 「没有课」那一句**只吃剩下的预算**（`plan` 还回来的第三个数）。
        //
        // 今天已经有三节课把行占满时它会被挤掉，这是有意的：有内容的信息优先，
        // 而「今天有课、明天没有」这件事，明天那一组的分组标题本身就在说了。
        // 反过来把这句话排到课程行前面，就会出现「显示着『明天没有课』、
        // 今天的课却被折成『还有 2 节』」—— 拿有内容的换没内容的。
        //
        // 明天不出场时这个预算是 0，所以这里不会冒出一句「明天没有课」去说明
        // 一件用户根本没在问的事（他看不到明天那一组）。
        //
        // `total > 0` 那一层守卫：今天明天都没课时这里一句话都不给，
        // 让页脚那句「今天和明天都没有课」独自收尾。两句都画会打架。
        val noteShown = BooleanArray(groups.size)
        var left = fitted[2]
        if (total > 0) {
            for (i in groups.indices) {
                if (left <= 0) break
                if (groups[i].second.isEmpty()) {
                    noteShown[i] = true
                    left--
                }
            }
        }

        for ((i, group) in groups.withIndex()) {
            val (title, list) = group
            val shown = list.take(allowance[i])
            // 分组标题在这一组**真要有东西画**时才出现：一个底下什么都没有的
            // 「明天 · 周四」比不写更让人困惑。
            if (shown.isEmpty() && !noteShown[i]) continue
            if (showTitle[i]) rv.addView(R.id.rows, groupView(context, title, theme))
            if (shown.isEmpty()) {
                rv.addView(R.id.rows, noteView(context, "没有课", theme))
            } else {
                for (s in shown) rv.addView(R.id.rows, rowView(context, s, theme))
            }
        }

        // 页脚只数**真画出来的那一组（那两组）**里藏了多少节。明天不出场时它
        // 的课不算在这个数里 —— 屏幕上只有今天的课，而页脚写「还有 6 节」会让人
        // 以为是今天还有 6 节，那比不写更糟。（这是本轮新出现的组合：以前明天
        // 总会分到一行，所以「今天被截断」和「明天不出场」不会同时成立。）
        val shownGroups = if (tomorrowInPlay) groups.size else 1
        val hidden = (0 until shownGroups).sumOf { groups[it].second.size - allowance[it] }
        when {
            total == 0 -> {
                rv.setViewVisibility(R.id.footer, View.VISIBLE)
                // 措辞按**真画了几组**来，不是按用户配了什么：窗口最后一天上
                // 只画了今天那一组，那时候写「这两天都没有课」里的「两天」是假的。
                rv.setTextViewText(
                    R.id.footer,
                    if (tomorrowInPlay) "这两天都没有课" else "今天没有课",
                )
            }

            hidden > 0 -> {
                rv.setViewVisibility(R.id.footer, View.VISIBLE)
                rv.setTextViewText(R.id.footer, "还有 $hidden 节")
            }

            else -> {
                rv.setViewVisibility(R.id.footer, View.GONE)
                rv.setTextViewText(R.id.footer, "")
            }
        }
        return rv
    }

    private fun rowView(
        context: Context,
        session: WidgetSession,
        theme: WidgetTheme,
    ): RemoteViews = RemoteViews(context.packageName, R.layout.widget_row).apply {
        setInt(R.id.row_bar, "setBackgroundColor", session.color)
        setTextViewText(R.id.row_time, session.startLabel)
        setTextViewText(R.id.row_title, session.title)
        setTextViewText(R.id.row_location, session.location)
        setTextColor(R.id.row_title, theme.onSurface)
        setTextColor(R.id.row_time, theme.secondary)
        setTextColor(R.id.row_location, theme.secondary)
        // 教室为空（线上课、没填地点）时把那一段收掉，否则会留一块空白，
        // 看起来像是渲染截断了。
        if (session.location.isBlank()) setViewVisibility(R.id.row_location, View.GONE)
    }

    private fun groupView(
        context: Context,
        title: String,
        theme: WidgetTheme,
    ): RemoteViews = RemoteViews(context.packageName, R.layout.widget_group).apply {
        setTextViewText(R.id.group_title, title)
        setTextColor(R.id.group_title, theme.secondary)
    }

    /** 「没有课」那一行。和分组标题同为 11sp 灰字，观感一致。 */
    private fun noteView(
        context: Context,
        text: String,
        theme: WidgetTheme,
    ): RemoteViews = RemoteViews(context.packageName, R.layout.widget_note).apply {
        setTextViewText(R.id.note_text, text)
        setTextColor(R.id.note_text, theme.secondary)
    }

    /** 大：本周缩略网格。 */
    private fun weekView(
        context: Context,
        snapshot: WidgetSnapshot,
        block: WidgetSetBlock,
        id: Int,
        showSetName: Boolean,
        widthDp: Int,
        heightDp: Int,
        nowMs: Long,
    ): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_week)
        val theme = snapshot.theme
        rv.setInt(R.id.widget_root, "setBackgroundColor", theme.surface)
        rv.setTextColor(R.id.week_header, theme.secondary)
        // 同上：周次取自这一块；总览块没有周号，退回一句「本周课表」。
        //
        // 空串还有第二种含义：**今天不在这个日程的学期里**。那时候画的是兜底周
        // （`gridFor` 决定的），标题退回「本周课表」正好对 —— 兜底周本来就不是
        // 「本周」，而是「有课的那一周」。
        val weekIdx = snapshot.weekIndexOf(nowMs)
        rv.setTextViewText(
            R.id.week_header,
            snapshot.weekTitleOf(block, weekIdx).ifEmpty { "本周课表" },
        )
        attachGear(context, rv, id, theme)
        attachSetLabel(rv, block, theme, showSetName)

        val density = context.resources.displayMetrics.density
        // 网格占的是「卡片高度减去标题栏和上下留白」那一块。这里只是**估**：
        // 位图会被 `fitXY` 拉满，估歪了几个像素看不出差别，而精确测量要么得
        // 走一趟布局（在广播接收器里不合适），要么就得用 API 31 的
        // `setViewLayoutWidth`。
        //
        // 多减的那一份是日程名那条（`LABEL_DP`）：网格是 `layout_weight="1"`，
        // 上面多一行它就自己短一截 —— 在这里减掉才估得准，而**减多了也只是
        // 位图分辨率低一点**，`fitXY` 会拉满，不像列表那边会顶掉一行。
        val extraChrome = if (showSetName) LABEL_DP else 0
        val gridW = (widthDp * density - 24 * density).toInt().coerceAtLeast(7)
        val gridH = ((heightDp - extraChrome) * density - 48 * density)
            .toInt().coerceAtLeast(5)
        rv.setImageViewBitmap(
            R.id.grid,
            WidgetPainter.weekGrid(
                snapshot = snapshot,
                block = block,
                grid = snapshot.gridFor(block, weekIdx),
                nowMs = nowMs,
                widthPx = gridW,
                heightPx = gridH,
            ),
        )
        return rv
    }

    // -------------------------------------------------------------------------
    // 齿轮
    // -------------------------------------------------------------------------

    /**
     * 标题栏右侧那个齿轮：点它打开 App 并直接落到这个实例的配置页。
     *
     * `PendingIntent` 的 request code 用 appWidgetId，action 用
     * [ACTION_CONFIGURE] —— 和提醒那边（`ReminderAlarms`）的 request code 空间
     * 是重叠的，靠 action 区分。`PendingIntent` 的相等性把 action 算在内，
     * 所以两者不会互相顶掉。
     */
    private fun attachGear(
        context: Context,
        rv: RemoteViews,
        id: Int,
        theme: WidgetTheme,
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_CONFIGURE
            putExtra(EXTRA_WIDGET_ID, id)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pi = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        rv.setOnClickPendingIntent(R.id.gear, pi)
        // 齿轮是灰色的矢量图，深色主题下会几乎看不见 —— 而「齿轮看不见」
        // 等于用户找不到配置入口。按主题染一次色。
        rv.setInt(R.id.gear, "setColorFilter", theme.secondary)
    }

    // -------------------------------------------------------------------------
    // 整卡点击
    // -------------------------------------------------------------------------

    /**
     * 卡片上**除齿轮之外**的任何地方：点一下打开 App，落到这个实例配的日程 + 今天那一周。
     *
     * 挂的是每个布局的根（`R.id.widget_root`，四种布局都有）。
     * 「除齿轮之外」是**自动成立**的，不用在这里做减法：齿轮是根的子视图，自己带着
     * 一个 `PendingIntent`，触摸被它吃掉，不会冒泡到根。
     *
     * [id] 传 0 或负数时什么都不挂 —— 那是配置页里那条 `preview` 路径
     * （`id = -1`），它渲出来是一个 PNG，没有人能点它，挂上去只是白造一个
     * `PendingIntent`。
     */
    private fun attachOpen(context: Context, rv: RemoteViews, id: Int) {
        if (id <= 0) return
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN
            putExtra(EXTRA_WIDGET_ID, id)
            // 和齿轮那一条完全一样，理由也一样：`NEW_TASK` 是必须的（从启动器进程
            // 拉起 Activity），`SINGLE_TOP` 让已经在跑的 App 走 `onNewIntent`
            // 而不是再 `onCreate` 一次 —— 后者会重建整个 Flutter engine。
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pi = PendingIntent.getActivity(
            context,
            REQUEST_OPEN_BASE + id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        rv.setOnClickPendingIntent(R.id.widget_root, pi)
    }

    // -------------------------------------------------------------------------
    // 尺寸
    // -------------------------------------------------------------------------

    /**
     * 实际尺寸（dp）。
     *
     * 优先用 `onAppWidgetOptionsChanged` 存下来的那份：那一次是启动器告诉我们的
     * **用户拖动之后**的尺寸。没存过（刚加上还没收到回调）就退到 provider 的
     * `minWidth/minHeight` —— 那是「没被调整过」时的尺寸，够用。
     */
    fun sizeOf(context: Context, id: Int): Pair<Int, Int> {
        WidgetStore.options(context, id)?.let { return it }
        val info = AppWidgetManager.getInstance(context).getAppWidgetInfo(id)
        val w = info?.minWidth ?: 0
        val h = info?.minHeight ?: 0
        return (if (w > 0) w else FALLBACK_WIDTH_DP) to
            (if (h > 0) h else FALLBACK_HEIGHT_DP)
    }

    /**
     * 把某个内容按某个尺寸渲染成 PNG，给配置页做实时预览。
     *
     * 这不是临时脚手架：`adb shell cmd appwidget` 在这台 ROM 上不可用（返回
     * "No shell command implementation."），没有任何命令行办法把小组件绑到
     * 桌面上。这条通道让布局、配色、数据正确性全部可以**在没有桌面小组件的情况下**
     * 用截图验证 —— 而它同时就是用户在配置页里要看的那个预览。
     *
     * 走的是 `RemoteViews.apply()`（不是另写一套 LayoutInflater），所以和桌面上
     * 那条路径几乎重合；唯一的差别是启动器那一侧的 inflate 不在我们手里。
     *
     * [scope] / [showSetName] 和桌面上那条路**走同一个 [blockFor] 和同一段
     * 行数预算** —— 预览要是自己另算一套，配置页里那个图就会指着一个用户在桌面上
     * 看不到的样子，那比没有预览更坏。
     */
    fun previewPng(
        context: Context,
        content: String,
        scope: String,
        showSetName: Boolean,
        widthDp: Int,
        heightDp: Int,
    ): ByteArray? = try {
        val now = System.currentTimeMillis()
        val snapshot = WidgetStore.snapshot(context)
        // id 传 -1：预览不属于任何一个已放置的实例，齿轮的 PendingIntent
        // 在这里没有意义，也不会有人去点它。
        val rv = remotes(
            context = context,
            id = -1,
            content = content,
            scope = scope,
            showSetName = showSetName,
            snapshot = snapshot,
            nowMs = now,
            widthDp = widthDp,
            heightDp = heightDp,
        )

        val density = context.resources.displayMetrics.density
        val wPx = (widthDp * density).toInt().coerceIn(1, 2000)
        val hPx = (heightDp * density).toInt().coerceIn(1, 2000)

        val parent = FrameLayout(context)
        val view = rv.apply(context, parent)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(wPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(hPx, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, wPx, hPx)

        val bitmap = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bitmap))

        java.io.ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    } catch (e: Exception) {
        Log.w(TAG, "预览渲染失败", e)
        null
    }
}

/** 小组件的 `ComponentName`。放在这里而不是散落在各处 —— 写错一个包名
 *  就是「桌面上找不到这个小组件」，而那没有任何报错。 */
internal fun widgetComponent(context: Context): ComponentName =
    ComponentName(context.packageName, ClasscalWidgetProvider::class.java.name)
