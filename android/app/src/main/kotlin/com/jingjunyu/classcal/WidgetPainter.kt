package com.jingjunyu.classcal

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 唯一一处画位图的地方：本周缩略网格。
 *
 * **整个小组件只有这一张位图。** 其余的底色、文字颜色、课程色竖条全部走
 * `setInt(id, "setBackgroundColor", …)` / `setTextColor` —— 那些只传一个整数，
 * 而位图要走 `RemoteViews` 背后那条 **1 MB 的共享事务缓冲区**
 * （`TransactionTooLargeException`），框架侧还有一道 `mMaxWidgetBitmapMemory`
 * 检查。4×4 的小组件在 3x 屏上是 828 × 1368 px，ARGB_8888 就是 4.5 MB，直接超。
 *
 * 所以这一张用 `RGB_565`（2 字节/像素）并把总字节数封在 [MAX_BITMAP_BYTES]，
 * 位图会被 `ImageView` 以 `scaleType="fitXY"` 拉满。
 *
 * ## 格子里画缩写（这条推翻过前一版）
 *
 * 前一版**不画文字**，理由是「位图会被放大，大色块放大两倍没问题、文字放大
 * 两倍就糊了」。那个理由本身没错，但结论下错了：只有色块的网格要求用户记住
 * 十二门课各自是什么颜色，而那是记不住的 —— 一张认不出课的课表等于没有。
 *
 * 改成画**缩写**（`高数` / `离散`，最多三个汉字，由 Dart 侧算好放进快照）。
 * 代价用两件事压住：
 *
 * 1. **预算从「长边 500 px」改成「总共 600 KB」。** 按像素封顶是拿错了尺子 ——
 *    同一个像素数，扁宽的和接近正方形的，放大倍数差得很远。按字节算才是真正
 *    受约束的那个量，而且大尺寸下（真正需要清晰度的那一档）能多拿到 ~25% 的
 *    分辨率，放大倍数从 1.5× 降到 1.2×。
 * 2. **字号自己缩**：先按格子宽度算出一行放得下多大，再按格子高度封一次顶。
 *    缩到底还放不下就不画 —— 一个糊成一团的字比色块更糟。
 *
 * 仍然**不做**的事：网格里不画完整课名（放不下）、不画时间、不画教室。
 * 想认全就点开 App。
 */
object WidgetPainter {
    /**
     * 位图的字节上限。
     *
     * 600 KB 是照 `MAX_SIDE_PX = 500` 换算过来、再往上取的一档：
     * 500 × 500 × 2 字节 = 500 KB 是原来留的余量，而那条 1 MB 的缓冲区
     * **整个进程共享**，同一次事务里还有别的 action 要走。600 KB 留了 400 KB，
     * 换来的那点分辨率全用在让缩写认得出来上。
     *
     * 超过 1 MB 是**必炸**，但不到 1 MB 也不等于安全 —— 所以这里是个保守值，
     * 不是算出来的极限值。
     */
    private const val MAX_BITMAP_BYTES = 600_000

    /** `RGB_565`：2 字节一个像素。 */
    private const val BYTES_PER_PIXEL = 2

    /** 块与块之间的留白占格子边长的比例。 */
    private const val GAP_RATIO = 0.10f

    /** 圆角半径占格子短边的比例。 */
    private const val CORNER_RATIO = 0.22f

    /** 今天那一列的底色浓度（0-255）。很淡，只是给个暗示。 */
    private const val TODAY_TINT_ALPHA = 0x26

    /** 字号占块高的比例上限 —— 再大行距就顶到块边上了。 */
    private const val TEXT_HEIGHT_RATIO = 0.52f

    /** 文字两边各留的比例（占块宽），否则字会贴着块边。 */
    private const val TEXT_PADDING_RATIO = 0.06f

    /**
     * 位图里的最小字号（px）。
     *
     * 比这更小的一行汉字在这个分辨率下已经糊成一条了，画上去只会让人以为是
     * 渲染坏了。放不下就不画。
     */
    private const val MIN_TEXT_PX = 7f

    /**
     * 画 [block] 那一周的缩略网格。
     *
     * [widthPx] / [heightPx] 是 `ImageView` 实际要占的像素；这里只在超过
     * [MAX_BITMAP_BYTES] 时等比缩小，剩下的交给 `fitXY` 拉伸。
     *
     * **收一个块而不是整份快照**：网格的行数和「这条事属不属于这一块」全在块上。
     * 总览块和某个日程块的差别只体现在 `accepts` 和列号算出来的结果里，
     * 画法一模一样 —— 所以这里不该有「是不是总览」这种分支。
     *
     * [grid] 是**这一次要画的那一周**，由 `WidgetSnapshot.gridFor` 切出来。为什么
     * 不在这里自己从块上取七个零点：那个字段（`fallbackWeekMs`）现在只是
     * 「今天不在学期里时的兜底」，学期中直接用它画出来的是**别的一周** ——
     * 而那种错只在开学前才看得见。
     */
    fun weekGrid(
        snapshot: WidgetSnapshot,
        block: WidgetSetBlock,
        grid: GridWeek,
        nowMs: Long,
        widthPx: Int,
        heightPx: Int,
    ): Bitmap {
        val w = widthPx.coerceAtLeast(1)
        val h = heightPx.coerceAtLeast(1)
        val scale = min(1f, sqrt(MAX_BITMAP_BYTES / BYTES_PER_PIXEL.toFloat() / (w.toFloat() * h)))
        val bw = (w * scale).toInt().coerceAtLeast(7)
        val bh = (h * scale).toInt().coerceAtLeast(1)

        val bitmap = Bitmap.createBitmap(bw, bh, Bitmap.Config.RGB_565)
        val canvas = Canvas(bitmap)
        val theme = snapshot.theme

        // 先铺底：`RGB_565` 没有 alpha 通道，不铺的话没画到的地方是黑的。
        canvas.drawColor(theme.surface)

        val rows = block.gridRows.coerceAtLeast(1)
        val cellW = bw.toFloat() / 7f
        val cellH = bh.toFloat() / rows
        val gap = min(cellW, cellH) * GAP_RATIO
        val radius = min(cellW, cellH) * CORNER_RATIO
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // 今天那一列的淡底。放在课块之前画，否则它会盖在课块上把颜色冲淡。
        //
        // **今天落在这一周的哪一列，一次区间比较就问出来了**。今天不在这一周里
        // 时（`columnOf` 判的是包含，两头都管）返回 -1，那一列就不涂 —— 而那正是
        // 「今天不在学期里，画的是兜底周」的情形：在一块不是本周的网格上标出一个
        // 「今天」，用户看到的是「我的课表把周三当今天了」。
        //
        // 改之前这里是 `dayStartsMs.first()`（当时那个字段的意思是「今天的零点」）
        // 加 `todayWeekday - 1`，还要配一道 `todayInGrid` 守卫。那两个字段现在都
        // 不在了：`dayStartsMs[0]` 是**窗口的周一**，留着它就是「字段没改名、
        // 含义变了、谁也没发现」—— 表现是淡底只在窗口的第一周出现。
        val todayCol = grid.columnOf(nowMs)
        if (todayCol in 0..6) {
            paint.color = withAlpha(theme.accent, TODAY_TINT_ALPHA)
            canvas.drawRect(
                todayCol * cellW, 0f, (todayCol + 1) * cellW, bh.toFloat(), paint,
            )
        }

        // 先把块全画完，再回头画字。混在一个循环里也行（块之间不重叠），
        // 但分成两趟之后「后面的块盖住前面的字」这种可能彻底不存在 ——
        // 表现是某一格的字缺一半，看起来像渲染坏了。
        val blocks = mutableListOf<Pair<WidgetSession, RectF>>()
        for (s in snapshot.sessionsBetween(block, grid.fromMs, grid.endMs)) {
            // 列号由**这一周的七个零点**算出来，不用 `s.weekday`：总览那一块里混着
            // 几个日程的事件，而它们的周号各不相同 —— 只有绝对日期是共有的。
            val col = grid.columnOf(s.startAtMs)
            if (col !in 0..6) continue
            val row = s.gridRow
            // 行号 -1 = 作息时间之外的单次事件，网格里没有它的位置。
            if (row < 0 || row >= rows) continue

            val span = s.gridRowSpan.coerceIn(1, rows - row)
            val left = col * cellW + gap
            val top = row * cellH + gap
            val right = (col + 1) * cellW - gap
            val bottom = (row + span) * cellH - gap
            // 极端窄高比下留白可能把矩形挤成负数，那样 drawRoundRect 什么也不画，
            // 表现是「这一周的课一个块都没有」。
            if (right <= left || bottom <= top) continue

            paint.color = s.color
            val rect = RectF(left, top, right, bottom)
            canvas.drawRoundRect(rect, radius, radius, paint)
            blocks += s to rect
        }

        drawAbbrs(canvas, blocks, paint)

        return bitmap
    }

    /**
     * 在每个块里居中画它的缩写。
     *
     * 字号从块宽和块高各算一个上限，取小的那个：**宽度是几乎总是生效的那一个**
     * （一列只有屏宽的七分之一），高度那一条只在块特别扁的时候才起作用
     * （比如把 5 行网格塞进一个矮条里）。
     */
    private fun drawAbbrs(
        canvas: Canvas,
        blocks: List<Pair<WidgetSession, RectF>>,
        paint: Paint,
    ) {
        paint.typeface = Typeface.DEFAULT_BOLD
        paint.textAlign = Paint.Align.CENTER
        paint.isSubpixelText = true

        for ((session, rect) in blocks) {
            val text = session.abbr
            if (text.isEmpty()) continue

            val availW = rect.width() * (1f - 2 * TEXT_PADDING_RATIO)
            val availH = rect.height() * TEXT_HEIGHT_RATIO
            if (availW <= 0f || availH <= 0f) continue

            // 从「一行刚好放得下」的字号起步，再按块高封顶。`measureText`
            // 依赖 `textSize`，所以只能先给一个估计值再校正一次 ——
            // 中英文混排（`C语言`）的实测宽度和字数不成正比，除字数只是个起点。
            var size = min(availH, availW / max(1, text.length) * 1.35f)
            paint.textSize = size
            val measured = paint.measureText(text)
            if (measured > availW && measured > 0f) {
                size *= availW / measured
                paint.textSize = size
            }
            size = min(size, availH)
            paint.textSize = size
            if (size < MIN_TEXT_PX) continue

            paint.color = session.onColor
            // 竖直居中：`drawText` 的 y 是**基线**，直接给中心会整体偏上。
            val centerY = rect.centerY() - (paint.descent() + paint.ascent()) / 2f
            canvas.drawText(text, rect.centerX(), centerY, paint)
        }
    }

    /** 按 [alpha]（0-255）淡化 [color] 的透明度，保留它的 RGB。 */
    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
