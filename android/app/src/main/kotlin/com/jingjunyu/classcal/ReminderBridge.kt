package com.jingjunyu.classcal

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart ↔ 原生的提醒通道。
 *
 * 权限这一块必须经过 Activity：`requestPermissions` 只有 Activity 能发，
 * 结果也只会回到 Activity 的 `onRequestPermissionsResult`。所以这个桥握着
 * 一个 Activity 引用而不是 applicationContext —— 和 `ThemeBridge` 正好相反，
 * 那边只读资源，这边要弹系统对话框。
 */
class ReminderBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    /** 权限对话框是异步的，结果回来之前先把通道这边的 Result 存着。 */
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingLocationResult: MethodChannel.Result? = null

    fun attach() {
        channel.setMethodCallHandler(this)
        NotificationHelper.ensureChannel(activity.applicationContext)
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        // 结果悬着不还，Dart 那边的 Future 就永远不完成 —— 热重载之后
        // 设置页会卡在「正在请求权限」。
        pendingNotificationResult?.success(notificationState())
        pendingLocationResult?.success(locationState())
        pendingNotificationResult = null
        pendingLocationResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = activity.applicationContext
        when (call.method) {
            "status" -> result.success(status())

            "sync" -> {
                val raw = call.argument<List<Map<String, Any?>>>("specs").orEmpty()
                val specs = raw.mapNotNull { ReminderSpec.fromJson(org.json.JSONObject(it)) }
                ReminderAlarms.sync(context, specs)
                result.success(null)
            }

            "cancelAll" -> {
                ReminderAlarms.cancelAll(context)
                result.success(null)
            }

            "requestNotification" -> requestNotification(result)

            "requestLocation" -> requestLocation(result)

            "openLocationSettings" -> {
                openAppDetails()
                result.success(null)
            }

            "openAutoStartSettings" -> {
                result.success(openAutoStartSettings())
            }

            "openNotificationSettings" -> {
                result.success(openNotificationSettings())
            }

            "openExactAlarmSettings" -> {
                // 31 之前没有「精确闹钟」这个开关，跳过去也没有这一页。
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.fromParts("package", activity.packageName, null),
                    ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                    startOrIgnore(intent)
                }
                result.success(null)
            }

            "currentLocation" -> {
                // 定位要好几秒，不能占着平台线程不放 —— 那会把整个界面冻住。
                Thread {
                    val fix = LocationProbe.bestBlocking(context, LocationProbe.DEFAULT_TIMEOUT_MS)
                    Handler(Looper.getMainLooper()).post {
                        // **只要新位置**。这是用户在教室里按「用当前位置」记一个地点，
                        // 而这个坐标会被当成「教室在哪」，之后长期用来决定要不要提醒。
                        // 塞一个几小时前的缓存进去，等于把地点记到了昨天待过的地方，
                        // 而且从界面上完全看不出来。宁可返回 null，让对话框说
                        // 「没能取到位置」，用户知道要重试或手填。
                        result.success(
                            if (fix != null && fix.fresh) {
                                mapOf("lat" to fix.location.latitude, "lng" to fix.location.longitude)
                            } else {
                                null
                            }
                        )
                    }
                }.start()
            }

            "testNotify" -> {
                val seconds = (call.argument<Int>("seconds") ?: 5).coerceIn(1, 300).toLong()
                ReminderAlarms.armTest(context, System.currentTimeMillis() + seconds * 1000, seconds)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // 状态
    // -------------------------------------------------------------------------

    private fun status(): Map<String, Any?> {
        val context = activity.applicationContext
        return mapOf(
            "notifications" to notificationState(),
            "location" to locationState(),
            "exactAlarms" to ReminderAlarms.canExact(context),
            "scheduledCount" to ReminderStore.armedIds(context).size,
            "manufacturer" to Build.MANUFACTURER.orEmpty(),
            "banners" to bannersState(),
        )
    }

    /**
     * 提醒会不会以**横幅**（从屏幕顶部滑下来的那条）的形式弹出来。
     *
     * 判据是**渠道**的重要程度，不是应用级的。这一点写错过一次，代价是这条
     * 永远返回 false、界面上永远挂着一句「横幅被关掉了」—— 哪怕横幅弹得
     * 好好的，用户被支使去系统设置里找一个本来就是开的开关。
     *
     * 为什么会写错：`NotificationManager.getImportance()`（应用级）听起来正是
     * 「这个应用的通知重要程度」，但它对**任何一个没被整个屏蔽的应用都返回
     * DEFAULT** —— AOSP 只在那条通知被完全挡掉时才让它是 NONE，从来不反映
     * 渠道的 HIGH。真正决定一条通知重要程度的是渠道，
     * `NotificationRecord.calculateInitialImportance()` 第一句就是
     * `int importance = getChannel().getImportance();`；应用级那个值只对
     * **没有渠道**的旧式通知（`targetSdk < O`）生效，而我们建了真渠道。
     *
     * 读出来是 HIGH 也不等于**保证**会弹：有的 ROM（本机这台 vivo）在渠道之外
     * 另有一个按应用的「悬浮通知」开关，`dumpsys` 里叫 `isShowHeadsUp`，
     * **App 读不到** —— 它不在任何可读的 Settings 命名空间里，只在
     * NotificationManagerService 的内存里。所以这里只能回答「按 Android 的规则
     * 该弹」，界面上的措辞要跟着这个置信度走，不能断言。
     *
     * 通知整个被关掉时返回 false：那种情况界面上「通知」那一行已经报了，
     * 再报一次横幅只是同一件事说两遍。
     */
    private fun bannersState(): Boolean {
        val context = activity.applicationContext
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // 读主渠道而不是 SILENT_CHANNEL_ID：静音那条只在「已在教室」时用，
        // 问「提醒会不会弹横幅」问的是平常那条。
        val channel = nm.getNotificationChannel(NotificationHelper.CHANNEL_ID) ?: return false
        return channel.importance >= NotificationManager.IMPORTANCE_HIGH
    }

    /**
     * 用 `areNotificationsEnabled()` 而不是只看权限位。
     *
     * Android 13 起有运行时权限，13 之前没有 —— 但两种情况用户都能在系统设置里
     * 把通知整个关掉，那时候权限位仍然是「已授予」。用户看到的「通知关了」是
     * 后一种，所以必须问通知管理器本身。
     */
    private fun notificationState(): String =
        if (NotificationManagerCompat.from(activity.applicationContext)
                .areNotificationsEnabled()
        ) {
            "granted"
        } else {
            "denied"
        }

    private fun locationState(): String {
        val context = activity.applicationContext
        if (!hasLocationFeature(context)) return "unsupported"
        val fine = granted(context, Manifest.permission.ACCESS_FINE_LOCATION) ||
            granted(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (!fine) return "denied"
        // Android 10 起才区分「仅前台」和「始终」；9 及以下给了就是给了。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "always"
        return if (granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)) {
            "always"
        } else {
            "foregroundOnly"
        }
    }

    // -------------------------------------------------------------------------
    // 权限
    // -------------------------------------------------------------------------

    private fun requestNotification(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // 13 之前没有这个权限，弹不出对话框，直接报当前状态。
            result.success(notificationState())
            return
        }
        if (pendingNotificationResult != null) {
            result.success(notificationState())
            return
        }
        pendingNotificationResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION,
        )
    }

    private fun requestLocation(result: MethodChannel.Result) {
        val context = activity.applicationContext
        if (granted(context, Manifest.permission.ACCESS_FINE_LOCATION)) {
            // 前台权限已经有了 —— 剩下的「始终允许」只能去系统设置里开，
            // 这里报当前状态，由界面引导用户。
            result.success(locationState())
            return
        }
        if (pendingLocationResult != null) {
            result.success(locationState())
            return
        }
        pendingLocationResult = result

        val wanted = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
        // Android 10 上请求后台定位会弹「始终允许」，可以一并要；11 起不会弹，
        // 只会静默拒绝，所以那时候不放进这次请求里。
        if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
            wanted.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }
        activity.requestPermissions(wanted.toTypedArray(), REQUEST_LOCATION)
    }

    /** 由 `MainActivity` 转交。 */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        when (requestCode) {
            REQUEST_NOTIFICATION -> {
                val result = pendingNotificationResult ?: return
                pendingNotificationResult = null
                result.success(notificationState())
            }

            REQUEST_LOCATION -> {
                val result = pendingLocationResult ?: return
                pendingLocationResult = null
                result.success(locationState())
            }
        }
    }

    // -------------------------------------------------------------------------
    // 跳系统设置
    // -------------------------------------------------------------------------

    /**
     * 跳到本应用的位置权限页。
     *
     * Android 11 起只能这么走：后台定位不再有对话框，`requestPermissions`
     * 直接返回拒绝。所以界面上必须把「权限 → 位置信息 → 始终允许」这条路径
     * 写出来，光给个按钮用户会在设置里迷路。
     */
    private fun openAppDetails() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
        startOrIgnore(intent)
    }

    /**
     * 跳厂商的自启动 / 后台运行白名单页。
     *
     * 每家 ROM 的类名都不一样，而且都不公开、随版本改。所以是一张**尽力而为**
     * 的表：逐个 `resolveActivity`，能用哪个用哪个，实在找不到就退到应用详情页
     * （用户至少能在那里找到「电池」「权限」）。
     */
    private fun openAutoStartSettings(): Boolean {
        for ((pkg, cls) in AUTO_START_TARGETS) {
            val intent = Intent().apply {
                component = ComponentName(pkg, cls)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            if (activity.packageManager.resolveActivity(intent, 0) != null) {
                if (startOrIgnore(intent)) return true
            }
        }
        openAppDetails()
        return false
    }

    /**
     * 跳本应用的通知设置页。
     *
     * 横幅的开关就藏在这一页里，而**各家 ROM 对它的叫法不一样**（「横幅通知」
     * 「悬浮通知」「弹出通知」），路径也不一样，所以界面上要给出这句提示，
     * 光给个按钮用户会在设置里迷路 —— 和位置那项是同一个道理。
     *
     * 打不开就退到应用详情页（那里至少还有「通知」入口）。返回是否真的落到了
     * 通知页本身。
     */
    private fun openNotificationSettings(): Boolean {
        // API 26 起才有这一页；更老的版本只有应用详情里那个笼统的开关。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
            if (startOrIgnore(intent)) return true
        }
        openAppDetails()
        return false
    }

    private fun startOrIgnore(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: Exception) {
        Log.w(TAG, "打不开 ${intent.component ?: intent.action}", e)
        false
    }

    private fun granted(context: Context, permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun hasLocationFeature(context: Context) =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION)

    companion object {
        /** 通道名和 Dart 侧 `MethodChannelReminderScheduler.channelName` 必须一致。 */
        const val CHANNEL = "com.jingjunyu.classcal/reminders"

        private const val TAG = "ReminderBridge"
        private const val REQUEST_NOTIFICATION = 4001
        private const val REQUEST_LOCATION = 4002

        private val AUTO_START_TARGETS = listOf(
            // 小米 / HyperOS
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            // 华为
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            // 荣耀（分家之后是另一套包名）
            "com.hihonor.systemmanager" to
                "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            // OPPO / 一加（coloros 与 oplus 两代包名都留着）
            "com.coloros.safecenter" to
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.oplus.safecenter" to
                "com.oplus.safecenter.permission.startup.StartupAppListActivity",
            // vivo
            "com.vivo.permissionmanager" to
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            // 三星
            "com.samsung.android.lool" to
                "com.samsung.android.sm.ui.battery.BatteryActivity",
            // 魅族
            "com.meizu.safe" to "com.meizu.safe.permission.SmartBGActivity",
        )
    }
}
