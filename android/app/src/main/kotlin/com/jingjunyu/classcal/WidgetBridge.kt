package com.jingjunyu.classcal

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Dart ↔ 原生的小组件通道。
 *
 * 和 `ReminderBridge` 不同，这一个**不需要 Activity**：不弹权限对话框、不读
 * 用户当前的位置，只读写落盘的快照和几张卡片。所以它拿 applicationContext，
 * 生命周期也不必和 engine 绑在一起 —— 少一个持有 Activity 的通道，
 * 就少一处热重载之后会泄漏的东西。
 *
 * 通道名和 Dart 侧 `MethodChannelHomeWidgetBridge.channelName` 必须一致，
 * 方法名和参数名也一样：跨语言对不上不会报错，只会**永远返回 null**
 * （Dart 那边把 `MissingPluginException` 和 `PlatformException` 都收敛成
 * 「这个平台没有这个能力」，所以看起来就像 Windows 上那样「这个功能没做」）。
 * `test/widget_channel_test.dart` 里有一条直接读两边源码核对的契约测试。
 */
class WidgetBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    fun attach() {
        channel.setMethodCallHandler(this)
    }

    fun detach() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sync" -> {
                val raw = call.argument<Map<String, Any?>>("snapshot")
                if (raw == null) {
                    // Dart 那边不该发 null；真发了就当一次空推送，而不是崩掉。
                    Log.w(TAG, "sync 收到空的快照")
                    result.success(null)
                    return
                }
                val snapshot = WidgetSnapshot.fromJson(JSONObject(raw))
                if (snapshot == null) {
                    Log.w(TAG, "快照解析失败，保留盘里那份旧的")
                    result.success(null)
                    return
                }
                WidgetStore.saveSnapshot(context, snapshot)
                // 推完立刻重画，不等下一个边界 —— 用户刚改完课表就切回桌面，
                // 看到的必须已经是新的。
                WidgetRenderer.updateAll(context)
                result.success(null)
            }

            "status" -> result.success(status())

            "instances" -> result.success(instances())

            "setConfig" -> {
                val id = call.argument<Int>("id") ?: -1
                val content = call.argument<String>("content") ?: WidgetStore.CONTENT_AUTO
                WidgetStore.saveContent(context, id, content)
                // 这三项**一起写**，缺一个就用那个键的缺省 —— 而不是「没给就不改」。
                // Dart 那边配置页手上本来就同时有这三个值，一次 `setConfig` 全发过来；
                // 真收到个缺项（老版本 Dart 配上新原生），退回缺省也好过让这个实例
                // 停在一半新一半旧的状态。
                WidgetStore.saveScope(
                    context, id, call.argument<String>("setKey") ?: WidgetStore.SCOPE_OVERVIEW,
                )
                WidgetStore.saveShowSetName(context, id, call.argument<Boolean>("showSetName") != false)
                // 只重画这一个：改的是一个实例的配置，别的卡片不该跟着闪一下。
                WidgetRenderer.update(context, intArrayOf(id))
                result.success(null)
            }

            "clearConfig" -> {
                val id = call.argument<Int>("id") ?: -1
                WidgetStore.clearInstance(context, id)
                WidgetRenderer.update(context, intArrayOf(id))
                result.success(null)
            }

            "refreshAll" -> {
                WidgetRenderer.updateAll(context)
                result.success(null)
            }

            "preview" -> {
                val content = call.argument<String>("content") ?: WidgetStore.CONTENT_AUTO
                val scope = call.argument<String>("setKey") ?: WidgetStore.SCOPE_OVERVIEW
                val showSetName = call.argument<Boolean>("showSetName") != false
                val w = (call.argument<Int>("widthDp") ?: 0).coerceIn(40, 600)
                val h = (call.argument<Int>("heightDp") ?: 0).coerceIn(40, 600)
                result.success(
                    WidgetRenderer.previewPng(context, content, scope, showSetName, w, h),
                )
            }

            "consumeLaunch" -> result.success(WidgetStore.takePendingLaunch(context))

            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------

    private fun status(): Map<String, Any?> {
        val snapshot = WidgetStore.snapshot(context)
        return mapOf(
            "count" to ClasscalWidgetProvider.placedIds(context).size,
            "hasSnapshot" to (snapshot != null),
            "snapshotAt" to (snapshot?.generatedAtMs ?: 0L),
        )
    }

    /**
     * 桌面上放着的每一个实例。
     *
     * 尺寸走 [WidgetRenderer.sizeOf]（和渲染时同一处取法），所以设置页里显示的
     * 「2×1」和卡片实际被当成什么档位渲染，用的是同一个数 —— 两处各取一次的话，
     * 用户会看到「设置页说是大尺寸，画出来却是小尺寸的布局」。
     */
    private fun instances(): List<Map<String, Any?>> =
        ClasscalWidgetProvider.placedIds(context).map { id ->
            val (w, h) = WidgetRenderer.sizeOf(context, id)
            mapOf(
                "id" to id,
                "widthDp" to w,
                "heightDp" to h,
                "content" to WidgetStore.content(context, id),
                // 键名 `setKey` 和 Dart 侧那个字段同名（那边叫 `setKey` 而不是
                // `scope`）—— 契约测试扫的是这几个字面量，两边对不上就会**永远
                // 落到缺省**，也就是「配置页怎么改都显示总览」，而那不会报错。
                "setKey" to WidgetStore.scope(context, id),
                "showSetName" to WidgetStore.showSetName(context, id),
            )
        }

    companion object {
        /** 通道名和 Dart 侧 `MethodChannelHomeWidgetBridge.channelName` 必须一致。 */
        const val CHANNEL = "com.jingjunyu.classcal/widget"

        private const val TAG = "WidgetBridge"
    }
}
