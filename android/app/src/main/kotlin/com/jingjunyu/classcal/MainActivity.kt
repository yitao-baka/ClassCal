package com.jingjunyu.classcal

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var reminderBridge: ReminderBridge? = null
    private var widgetBridge: WidgetBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // **冷启动时先记下「这次启动是为了配置哪个实例」**，再挂通道。
        // Dart 那边首帧就会 `consumeLaunch()`，所以 id 必须在引擎可用**之前**
        // 就落到盘里 —— 放在 `onCreate` 里也行，但放这里离用它的地方更近，
        // 也顺带覆盖了「引擎重建」这条路径。
        rememberLaunchTarget(intent)

        // 传 applicationContext 而不是 this(Activity)：取色只读资源，
        // 没有任何理由让通道对象握住一个 Activity，那样还会泄漏。
        ThemeBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        // 提醒的桥必须握住 Activity —— 权限对话框只有 Activity 能弹，
        // 结果也只回到它的 onRequestPermissionsResult。生命周期和 engine 一致，
        // 所以在这里建、在 cleanUpFlutterEngine 里拆。
        reminderBridge = ReminderBridge(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.attach() }

        // 小组件的桥只读写落盘的快照和几张卡片，没有一件需要 Activity 的事，
        // 所以它和 ThemeBridge 一样拿 applicationContext。
        widgetBridge = WidgetBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.attach() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // 不拆的话，热重载之后旧桥还挂在通道上，Dart 那边发的请求会石沉大海。
        reminderBridge?.detach()
        reminderBridge = null
        widgetBridge?.detach()
        widgetBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * App 已经在跑的时候，小组件上的齿轮被点了一下。
     *
     * `MainActivity` 是 `launchMode="singleTop"`，所以这种时候走的是
     * `onNewIntent` 而不是重新 `onCreate` —— 不在这里接住，用户点齿轮会只是
     * 「切回 App 刚才那页」，什么都不发生。
     *
     * **只存不推**：把它记进 `WidgetStore`，Dart 那边在启动首帧和每次回到前台时
     * 主动 `consumeLaunch()`。反过来在这里往通道里推，会在 Dart 还没挂上监听时
     * 把这次调用丢掉 —— 而表现是「点了齿轮，App 开了，但没落到配置页」。
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        rememberLaunchTarget(intent)
    }

    private fun rememberLaunchTarget(intent: Intent?) {
        if (intent == null) return
        if (intent.action != WidgetRenderer.ACTION_CONFIGURE) return
        val id = intent.getIntExtra(WidgetRenderer.EXTRA_WIDGET_ID, 0)
        if (id != 0) WidgetStore.savePendingLaunch(applicationContext, id)
    }

    /** 权限对话框的异步结果转交给桥。 */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        reminderBridge?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
