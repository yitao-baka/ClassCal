package com.jingjunyu.classcal

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 壁纸取色的原生侧。
 *
 * 自 Android 12（API 31）起，系统本来就按壁纸算好了一整套 Material You 调色板，
 * 并且通过 `android.R.color.system_accent1_*` 这批 **public 资源**暴露出来 ——
 * 读它们不需要任何权限，也读不到壁纸原图。
 *
 * 这一点很关键：官方那个 `palette_generator` 已经被标记 discontinued，而任何
 * 「自己解码壁纸图片、量化取色」的做法，在 Android 13+ 上会被 `READ_MEDIA_IMAGES`
 * 挡死 —— 用户不可能为了换个主题色同意交出相册权限。读系统调色板是唯一
 * 既不要权限、又能跟着壁纸实时变的路子。
 *
 * 取色只取 `_500` 那一档当**种子**，交给 Flutter 那边的 `ColorScheme.fromSeed`
 * 去展开成整套色阶。不逐档搬运系统色，是因为 Material 的角色→色调映射表
 * （哪个角色用 accent1 的第几档）版本之间会变，自己抄一份必然跟系统的实际观感
 * 走偏；而「种子对了，整套就跟壁纸一个调」这件事，HCT 算法已经保证了。
 *
 * 注意 `ContextCompat.getColor` 返回的是**有符号** Int，`0xFFFF0000` 这类值
 * 过来是负数。Dart 侧要按 32 位掩码还原，不能直接 `Color(value)`。
 */
class ThemeBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        const val CHANNEL = "com.jingjunyu.classcal/theme"
        private const val TAG = "ThemeBridge"

        /**
         * 通道上用的键 → 系统资源名。
         *
         * 键写成 `accent1` 而不是把资源名去掉 `system_` 前缀了事：那样剩下的是
         * `accent1_500`，Dart 侧按 `accent1` 取值就会永远是 null —— 而这个失败
         * 是静默的，界面只会说「本设备没给出壁纸主题色」，看着像 ROM 不支持。
         * 映射表把两侧的名字写死在一处，比事后拼字符串靠得住。
         */
        private val ACCENT_KEYS = mapOf(
            "accent1" to "system_accent1_500",
            "accent2" to "system_accent2_500",
            "accent3" to "system_accent3_500",
        )
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "wallpaperPalette" -> result.success(readPalette())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 返回 `{"accent1": 0xFFxxxxxx, ...}`；拿不到（API < 31，或这个 ROM 没实现
     * 这批资源）就返回 null —— 让 Dart 侧退回预设主题，而不是给一个假颜色。
     */
    private fun readPalette(): Map<String, Int>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null

        val resources = context.resources
        val out = LinkedHashMap<String, Int>()
        for ((key, resourceName) in ACCENT_KEYS) {
            // 按名字查，而不是用 `android.R.color.system_accent*` 那批编译期常量。
            // 常量是构建时从 compileSdk 的 android.jar 里烘死的 id，而 android 包
            // 的资源 id **跨平台版本不保证稳定** —— 拿 compileSdk 36 编出来的 id
            // 去 API 31 的设备上取，完全可能取到另一个颜色，而且不报错，主题只是
            // 悄悄地变错。按名字查是运行时解析的，官方文档给的路子也是它。
            val id = runCatching {
                resources.getIdentifier(resourceName, "color", "android")
            }.getOrDefault(0)
            if (id == 0) continue // 这个 ROM 没暴露该资源

            runCatching { ContextCompat.getColor(context, id) }
                .onSuccess { out[key] = it }
                // 拿不到单个色不该让整批失败 —— 少一个 accent3 照样能出主题。
                .onFailure { Log.w(TAG, "读取 $resourceName 失败", it) }
        }
        // 只在「一个都没取到」时出声：那是唯一需要排查的情况（用户报「壁纸取色
        // 不生效」），而且它大概率意味着这个 ROM 没实现这批资源。有这行日志才
        // 分得清是「没取到」还是「取到了但别处没生效」。
        if (out.isEmpty()) Log.w(TAG, "没取到任何 system_accent* 资源")
        return out.ifEmpty { null }
    }
}
