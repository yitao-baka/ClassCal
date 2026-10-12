package com.jingjunyu.classcal

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.function.Consumer

/**
 * 取一次位置就够，不要长期订阅。
 *
 * 这是整个定位门控里唯一真会出错的一块，所以策略写的都是「拿不准怎么办」：
 *
 * * **有上限的时间预算**。广播接收器只有几秒钟（`goAsync` 之后更宽裕，但也不是
 *   无限的），等不到就当作「不知道」继续走 —— 宁可多响一次，也不能因为等位置
 *   把提醒彻底吞掉。
 * * **先问当前位置，再退到缓存位置**。缓存位置快但可能是几小时前的（那时用户
 *   在家里，于是「不在教室」判定成立，提醒照响）；当前位置准但慢。先准后快。
 * * **拿不到就是 null，绝不猜**。null 的含义是「不知道」，调用方据此走降级路径
 *   （照常提醒 + 挂一个「我已到教室」按钮），而不是当成「不在教室」草率处理 ——
 *   这两个的后果不一样，但如果不区分，代码会写成后者。
 */
object LocationProbe {
    private const val TAG = "LocationProbe"

    /** 一次探测的时间预算。 */
    const val DEFAULT_TIMEOUT_MS = 6000L

    /**
     * 缓存位置最多能有多旧，才允许拿它来判「你在教室里」。
     *
     * 为什么必须有这个上限：主动定位失败时（室内收不到星、ROM 拦了、时间预算
     * 用光）会退回缓存位置，而缓存可能是几小时前的 —— 那时用户还在学校。
     * 拿它判「在教室」的结果是**这条提醒被悄悄吞掉**，而「该响的提醒没响」
     * 是这块功能最坏的失败方式：用户不会去查为什么，只会不再相信它。
     *
     * 反过来，一个旧位置说明「不在学校」时照常提醒是安全的（多响一次而已），
     * 所以这个上限只卡「在教室里」这一个判定，见 [Fix.fresh]。
     */
    const val MAX_CACHE_AGE_MS = 10 * 60 * 1000L

    /**
     * 一次探测的结果。
     *
     * 刻意不用裸 `Location?`：**「拿到了位置」和「这个位置新不新」是两件事**，
     * 而它们对应完全不同的用法 —— 旧位置可以用来排除「在教室里」，却不能用来
     * 断定「在教室里」。把这一点丢进类型里，调用方就没法忽略它。
     */
    class Fix(val location: Location, val fresh: Boolean)

    /** 没有权限、或者系统关掉了定位服务。 */
    fun hasPermission(context: Context): Boolean =
        granted(context, Manifest.permission.ACCESS_FINE_LOCATION) ||
            granted(context, Manifest.permission.ACCESS_COARSE_LOCATION)

    /**
     * 异步取一次位置；**保证恰好回调一次**，拿不到给 null。
     *
     * 在后台线程上跑：`getCurrentLocation` 会阻塞到有结果或超时，
     * 放在广播接收器的主线程上会直接 ANR。
     */
    fun best(context: Context, timeoutMs: Long, callback: (Fix?) -> Unit) {
        val appContext = context.applicationContext
        Thread({ callback(probe(appContext, timeoutMs)) }, "classcal-location").start()
    }

    /** 同步版本，给「用当前位置记一个地点」按钮用。 */
    fun bestBlocking(context: Context, timeoutMs: Long): Fix? = probe(context, timeoutMs)

    private fun probe(context: Context, timeoutMs: Long): Fix? {
        if (!hasPermission(context)) {
            Log.i(TAG, "没有定位权限，跳过探测")
            return null
        }
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val fresh = current(lm, timeoutMs)
            if (fresh != null) return Fix(fresh, fresh = true)
        }
        val cached = lastKnown(lm)
        if (cached == null) {
            Log.i(TAG, "当前位置和缓存位置都没拿到")
            return null
        }
        // 缓存位置按年龄分两档，不是一刀切地不信任：
        //   十分钟以内 → 用户多半还在同一个地方，拿来判「在教室里」是可靠的
        //               （这也正是「到教室后手机自动又定位了一次」这种常见情形）
        //   更久       → 只够说明「不在学校」，不够说明「在教室里」
        val ageMs = System.currentTimeMillis() - cached.time
        val recent = ageMs in 0..MAX_CACHE_AGE_MS
        if (!recent) {
            Log.i(
                TAG,
                "只有缓存位置，已过期 ${ageMs / 60000} 分钟 —— 不许用它判「在教室里」",
            )
        }
        return Fix(cached, fresh = recent)
    }

    /**
     * 定位源，按「谁多半先答上来」排序。
     *
     * `fused` 排在第一个是有实际意义的：手机上真正快的是融合定位（靠 WiFi 和基站
     * 先给一个可用结果，GPS 再慢慢修正），而门控问的最多的是「你是否在学校里」
     * 这种几百米精度的问题 —— 室内 GPS 十几秒都未必有结果，网络定位往往一秒内
     * 就答了。只用 GPS + NETWORK 的话，室内场景会稳定地耗光时间预算再退回缓存
     * 位置，而缓存位置可能还是几个小时前在家时的。
     *
     * `fused` 是 API 31 才有的常量（32 才有 `LocationManager.FUSED_PROVIDER`），
     * 低版本上直接传字符串 "fused" 也行 —— 认不出来就当这个源不存在。
     */
    private val fusedName: String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            LocationManager.FUSED_PROVIDER
        } else {
            "fused"
        }

    private val SOURCES: List<String> = listOf(
        fusedName,
        LocationManager.NETWORK_PROVIDER,
        LocationManager.GPS_PROVIDER,
    )

    /** 主动请求一次定位，最多等 [timeoutMs]。 */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun current(lm: LocationManager, timeoutMs: Long): Location? {
        // `fused` 不参与 `enabled` 过滤：它不是一个能被开关的硬件，某些 ROM 上
        // `isProviderEnabled("fused")` 会返回 false 或者干脆抛异常，照它过滤等于
        // 把最好的那个源丢了。真不存在的话下面的调用会抛，被 catch 掉。
        val providers = SOURCES.filter { it == fusedName || enabled(lm, it) }
        if (providers.isEmpty()) return null

        val signal = CancellationSignal()
        val latch = CountDownLatch(1)
        val holder = AtomicReference<Location?>(null)
        // 几个源同时问，谁先给有效的算谁的 —— 串行等会让时间预算变成三倍，
        // 而超时的代价是这次门控直接失效。
        val executor = Executors.newSingleThreadExecutor()
        val consumer = Consumer<Location?> { loc ->
            if (loc != null && holder.compareAndSet(null, loc)) latch.countDown()
        }

        for (provider in providers) {
            try {
                lm.getCurrentLocation(provider, signal, executor, consumer)
            } catch (e: Exception) {
                // 两种情况都在这里：权限在上面查过，报 SecurityException 的是 ROM 的
                // 额外拦截；报别的多半是这个 provider 名不被认。**少一个源不致命**，
                // 所以不能让一个源把整次探测带走。
                Log.w(TAG, "请求 $provider 位置失败", e)
            }
        }

        val got = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        signal.cancel()
        executor.shutdown()
        if (!got && holder.get() == null) Log.i(TAG, "主动定位超时（${timeoutMs}ms）")
        return holder.get()
    }

    /** 最近一次已知位置。可能很旧，所以只当兜底。 */
    private fun lastKnown(lm: LocationManager): Location? {
        for (provider in SOURCES) {
            if (provider != fusedName && !enabled(lm, provider)) continue
            val loc = try {
                lm.getLastKnownLocation(provider)
            } catch (e: Exception) {
                null
            }
            if (loc != null) return loc
        }
        return null
    }

    private fun enabled(lm: LocationManager, provider: String): Boolean =
        try {
            lm.isProviderEnabled(provider)
        } catch (e: Exception) {
            false
        }

    private fun granted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED
}
