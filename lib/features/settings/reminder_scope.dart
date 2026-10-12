/// 提醒设置页的读写目标：全局默认，或某一个日程。
///
/// 存在的唯一理由是**别把整页 UI 抄两遍**。所有设置控件都只通过它读写，于是
/// 「每个日程独立管理」不需要复制任何一个 `_LeadPicker` / `_GateTile` /
/// `_TimeoutPicker` / `_RepeatTile`。
///
/// **刻意没有 `following` 这个字段。**「跟随」= `setReminders` 里**没有**这个
/// setId 的项，也就是作用域本身不存在 —— 所以一个日程 scope 只会在「自定义」
/// 模式下被造出来。「跟不跟随」这件事交给 `settings.setReminders.containsKey(setId)`
/// **一个地方**表达。多加一个布尔就必然出现「开关说着跟随、对象里却还带着一份
/// 旧值」这种自相矛盾的状态，而它没有第二种正确读法。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings_providers.dart';
import '../../core/settings/app_settings.dart';

/// 一份提醒设置的一行摘要。
///
/// 三处共用：设置页那一行的副标题、日程页「跟随全局」时的只读说明、
/// 「按日程分别设置」列表里每行的状态。三处分开写的话，同一套设置会长出
/// 三种说法，而用户是靠「数字对不对得上」来判断改没改成功的。
String reminderSummary(SetReminderSettings v) {
  final buffer = StringBuffer('提前 ${v.defaultLeadMinutes} 分钟');
  switch (v.nearbyMode) {
    // 门控三态各说各的：只说「已在教室则不提醒」的话，选了静音的人在这一行
    // 看到的是**别的**设置，会以为自己没改成功。
    case NearbyMode.remind:
      break;
    case NearbyMode.skip:
      buffer.write(' · 已在教室则不再提醒');
    case NearbyMode.silent:
      buffer.write(' · 已在教室则静音');
  }
  final t = v.notificationTimeoutMinutes;
  if (t > 0) {
    buffer.write(t % 60 == 0 ? ' · ${t ~/ 60} 小时后自动清除' : ' · $t 分钟后自动清除');
  }
  if (v.repeatReminders) {
    buffer.write(' · 每 ${v.repeatIntervalMinutes} 分钟重复到教室');
  }
  return buffer.toString();
}

/// 一个提醒设置的读写目标。
class ReminderScope {
  ReminderScope({
    required this.ref,
    required this.setId,
    required this.settings,
  });

  final WidgetRef ref;

  /// 全局默认页为 null。
  final int? setId;

  /// 当前设置的一份快照。写走 [write]，所以这里不需要是响应式的 ——
  /// 页面每次重建都会重新造一个 scope。
  final AppSettings settings;

  bool get isGlobal => setId == null;

  /// 当前生效值。
  ///
  /// 没有覆盖时**返回全局值**而不是抛异常：那正好就是「跟随全局」的含义，
  /// 于是这个 getter 在两种模式下都是对的，调用方不必先判一次。
  SetReminderSettings get values {
    final id = setId;
    if (id == null) return SetReminderSettings.fromGlobal(settings);
    return settings.remindersFor(id) ?? SetReminderSettings.fromGlobal(settings);
  }

  /// 这个日程现在是不是跟着全局走。
  ///
  /// 全局页恒为 false —— 它不是一个「可以跟随」的东西，它就是被跟随的那一份。
  bool get following => setId != null && !settings.setReminders.containsKey(setId);

  /// 改一项。全局写 `settingsProvider`，日程写 `setReminders[setId]`。
  void write(SetReminderSettings Function(SetReminderSettings) change) {
    final id = setId;
    final next = change(values);
    ref.read(settingsProvider.notifier).update((s) {
      if (id == null) {
        return s.copyWith(
          remindersEnabled: next.remindersEnabled,
          defaultLeadMinutes: next.defaultLeadMinutes,
          nearbyMode: next.nearbyMode,
          gateRadiusMeters: next.gateRadiusMeters,
          notificationTimeoutMinutes: next.notificationTimeoutMinutes,
          repeatReminders: next.repeatReminders,
          repeatIntervalMinutes: next.repeatIntervalMinutes,
        );
      }
      return s.copyWith(setReminders: {...s.setReminders, id: next});
    });
  }

  /// 开/关「跟随全局默认」。
  ///
  /// **关掉（开始自定义）时用当下的全局值当初始覆盖**，而不是硬编码一套默认值：
  /// 用户点「不跟随」的意思是「在现在的基础上改一点」，不是「重置成出厂设置」。
  /// 用硬编码的话，一个把提前量调成 30 分钟的人会看到它突然跳回 15，然后得
  /// 重新调一遍 —— 而他要的只是改其中一项。
  void setFollowing(bool follow) {
    final id = setId;
    if (id == null) return;
    ref.read(settingsProvider.notifier).update((s) {
      final next = Map<int, SetReminderSettings>.from(s.setReminders);
      if (follow) {
        next.remove(id);
      } else {
        next[id] = SetReminderSettings.fromGlobal(s);
      }
      return s.copyWith(setReminders: next);
    });
  }
}
