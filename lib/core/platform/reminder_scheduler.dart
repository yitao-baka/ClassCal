/// 课前提醒 —— 平台无关的抽象。
///
/// 和 `wallpaper.dart` 一样，平台能力藏在接口后面，为的是 Windows 端能构建通过。
/// 但这里多一条**设计上的**理由：判断「要不要提醒」需要两件原生才做得到的事 ——
/// 在 App 没运行时被唤醒，以及那一刻取一次定位。把这两件事留在 Kotlin 侧，
/// 我们就不必为了几秒钟的定位检查去起一个 Dart 后台 isolate，
/// 也省掉一个「后台 isolate 里能不能用 MethodChannel」的问题。
///
/// 所以分工是：**Dart 算出「什么时候、提醒什么、要不要门控」，原生负责
/// 「到点弹窗、顺带看一眼在不在教室」。**
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../reminder/reminder_plan.dart';

/// 通知权限的状态。
enum NotificationPermission { granted, denied, unsupported }

/// 位置权限的状态。
///
/// 分三档而不是布尔，是因为「只有前台权限」对我们**没用**：提醒触发时 App
/// 在后台，前台权限下取位置会静默失败。界面必须能把这一档说清楚，
/// 否则用户会以为「权限已给」却始终看到降级按钮。
enum LocationPermission {
  /// 「始终允许」。
  always,

  /// 只给了「使用应用时」。
  foregroundOnly,

  /// 没给，或者系统压根没有定位开关。
  denied,

  /// 这个平台没有定位能力（Windows）。
  unsupported,
}

/// 当前平台侧的能力快照。设置页拿它决定显示哪些提示。
@immutable
class ReminderCapabilities {
  const ReminderCapabilities({
    this.supported = false,
    this.notifications = NotificationPermission.unsupported,
    this.location = LocationPermission.unsupported,
    this.exactAlarms = false,
    this.scheduledCount = 0,
    this.manufacturer = '',
    this.banners = true,
  });

  static const ReminderCapabilities unsupported = ReminderCapabilities();

  /// 这个平台有没有提醒能力（Windows 目前没有）。
  final bool supported;

  final NotificationPermission notifications;
  final LocationPermission location;

  /// 能不能排**精确**闹钟。
  ///
  /// false 时我们退到「大致到点」（系统可能推迟几分钟）。这是必须告诉用户的：
  /// 「提醒晚了 3 分钟」和「提醒没响」是两回事，但用户分不出来。
  final bool exactAlarms;

  /// 原生侧当前排着的提醒条数。
  final int scheduledCount;

  /// 厂商名，用于挑 OEM 白名单引导页该显示哪一段。
  final String manufacturer;

  /// 提醒会不会以横幅（从屏幕顶部滑下来的那条）弹出来。
  ///
  /// **通知开着不等于看得见。** 应用级的通知重要程度会给自己所有渠道封顶，
  /// 被压到「默认」之后横幅就不弹了，只在通知栏里多一行 —— 而这件事在 App
  /// 里面查不出来（`areNotificationsEnabled()` 照样是 true，渠道属性也还是
  /// 最高级），只能去问应用级的那个值。
  ///
  /// 上课前 15 分钟那条提醒的价值全在「不用掏手机就看见」上，只进通知栏等于
  /// 没提醒，所以这一项要报给用户，并给一条去系统设置开的路径。
  final bool banners;

  bool get notificationsGranted => notifications == NotificationPermission.granted;

  @override
  bool operator ==(Object other) =>
      other is ReminderCapabilities &&
      other.supported == supported &&
      other.notifications == notifications &&
      other.location == location &&
      other.exactAlarms == exactAlarms &&
      other.scheduledCount == scheduledCount &&
      other.manufacturer == manufacturer &&
      other.banners == banners;

  @override
  int get hashCode => Object.hash(supported, notifications, location, exactAlarms,
      scheduledCount, manufacturer, banners);
}

/// 一个经纬度。
@immutable
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  String toString() => 'LatLng($lat, $lng)';
}

/// 提醒的排程口。所有方法都**不抛异常** —— 提醒失败不该让 App 崩，
/// 顶多是这条提醒没排上，而设置页会把状态显式画出来。
abstract class ReminderScheduler {
  /// 查一遍当前能力。设置页每次进入都该调一次：权限是用户随时能在系统设置里改的。
  Future<ReminderCapabilities> capabilities();

  /// 用 [specs] **整体替换**已排的提醒。
  ///
  /// 全量替换而不是增量：课表改一处（整体平移一节课、删一门课）会影响很多条，
  /// 算差量本身就是一类容易错的逻辑，而全部重排一遍的代价只是几十次
  /// `AlarmManager` 调用。
  Future<void> sync(List<ReminderSpec> specs);

  /// 清空所有已排提醒。
  Future<void> cancelAll();

  /// 弹系统的通知权限请求。返回用户选完之后的状态。
  Future<NotificationPermission> requestNotification();

  /// 弹前台位置权限请求。
  Future<LocationPermission> requestLocation();

  /// 跳到系统的「位置信息」权限页，让用户把这一项改成「始终允许」。
  ///
  /// Android 11 起没有别的办法：`requestPermissions` 请求后台定位不会弹框，
  /// 直接返回拒绝，只能引导用户自己去开。
  Future<void> openLocationSettings();

  /// 跳厂商的自启动 / 后台运行白名单设置。
  Future<void> openAutoStartSettings();

  /// 跳本应用的通知设置页 —— 横幅开关在那里。
  Future<void> openNotificationSettings();

  /// 跳系统的「闹钟和提醒」页，让用户把精确闹钟开关打开。
  Future<void> openExactAlarmSettings();

  /// 取一次当前位置（前台用，给「用当前位置记一个地点」按钮）。
  Future<LatLng?> currentLocation();

  /// 立刻弹一条演示通知，验证「通知能不能弹出来」这条链路。
  Future<void> testNotify({Duration after = const Duration(seconds: 5)});
}

/// 按平台挑实现。
ReminderScheduler createReminderScheduler() {
  if (!kIsWeb && Platform.isAndroid) return MethodChannelReminderScheduler();
  return const UnsupportedReminderScheduler();
}

/// 走 `ReminderBridge.kt`。
class MethodChannelReminderScheduler implements ReminderScheduler {
  const MethodChannelReminderScheduler();

  /// 通道名和原生侧 `ReminderBridge.CHANNEL` 必须一致。
  /// `test/reminder_channel_test.dart` 里有一条直接读 Kotlin 源码核对的契约测试。
  static const String channelName = 'com.jingjunyu.classcal/reminders';

  static const MethodChannel _channel = MethodChannel(channelName);

  @override
  Future<ReminderCapabilities> capabilities() async {
    final raw = await _invoke<Map<Object?, Object?>>('status');
    if (raw == null) return ReminderCapabilities.unsupported;
    return ReminderCapabilities(
      supported: true,
      notifications: _notification(raw['notifications']),
      location: _location(raw['location']),
      exactAlarms: raw['exactAlarms'] == true,
      scheduledCount: raw['scheduledCount'] is int ? raw['scheduledCount']! as int : 0,
      manufacturer: raw['manufacturer'] is String ? raw['manufacturer']! as String : '',
      // 读不到就当作「有横幅」：宁可漏报一次，也不要在正常的设备上凭空多出
      // 一行红字，让用户去改一个本来就对的设置。
      banners: raw['banners'] != false,
    );
  }

  @override
  Future<void> sync(List<ReminderSpec> specs) async {
    await _invoke<void>('sync', {
      'specs': [for (final s in specs) s.toJson()],
    });
  }

  @override
  Future<void> cancelAll() => _invoke<void>('cancelAll');

  @override
  Future<NotificationPermission> requestNotification() async {
    final granted = await _invoke<bool>('requestNotification');
    return granted == true
        ? NotificationPermission.granted
        : NotificationPermission.denied;
  }

  @override
  Future<LocationPermission> requestLocation() async {
    final raw = await _invoke<String>('requestLocation');
    return _location(raw);
  }

  @override
  Future<void> openLocationSettings() => _invoke<void>('openLocationSettings');

  @override
  Future<void> openAutoStartSettings() => _invoke<void>('openAutoStartSettings');

  @override
  Future<void> openNotificationSettings() =>
      _invoke<void>('openNotificationSettings');

  @override
  Future<void> openExactAlarmSettings() => _invoke<void>('openExactAlarmSettings');

  @override
  Future<LatLng?> currentLocation() async {
    final raw = await _invoke<Map<Object?, Object?>>('currentLocation');
    if (raw == null) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  @override
  Future<void> testNotify({Duration after = const Duration(seconds: 5)}) async {
    await _invoke<void>('testNotify', {'seconds': after.inSeconds});
  }

  /// 通道调用统一走这里，把两类「没接上」都收敛成 null。
  ///
  /// `MissingPluginException` 在真机上意味着原生侧忘了注册通道，但在
  /// `flutter test` 里是常态。两者都当作「这个平台没有这个能力」处理，
  /// 而不是让提醒基础设施把整个 App 拖崩。
  static Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static NotificationPermission _notification(Object? raw) {
    if (raw == 'granted') return NotificationPermission.granted;
    if (raw == 'denied') return NotificationPermission.denied;
    return NotificationPermission.unsupported;
  }

  static LocationPermission _location(Object? raw) => switch (raw) {
        'always' => LocationPermission.always,
        'foregroundOnly' => LocationPermission.foregroundOnly,
        'denied' => LocationPermission.denied,
        _ => LocationPermission.unsupported,
      };
}

/// Windows / 其它平台。等阶段 6 换成任务计划程序或托盘提示。
class UnsupportedReminderScheduler implements ReminderScheduler {
  const UnsupportedReminderScheduler();

  @override
  Future<ReminderCapabilities> capabilities() async =>
      ReminderCapabilities.unsupported;

  @override
  Future<void> sync(List<ReminderSpec> specs) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<NotificationPermission> requestNotification() async =>
      NotificationPermission.unsupported;

  @override
  Future<LocationPermission> requestLocation() async =>
      LocationPermission.unsupported;

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<void> openAutoStartSettings() async {}

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<LatLng?> currentLocation() async => null;

  @override
  Future<void> testNotify({Duration after = const Duration(seconds: 5)}) async {}
}
