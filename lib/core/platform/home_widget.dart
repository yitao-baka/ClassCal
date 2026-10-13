/// 桌面小组件 —— 平台无关的抽象。
///
/// 形状和 `wallpaper.dart` / `reminder_scheduler.dart` 一样：抽象类 + 按平台
/// 挑实现的工厂 + 一个「取不到就是没有」的空桩。**所有方法都不抛异常** ——
/// 小组件放不上去不该让 App 崩，顶多桌面上少一张卡片。
///
/// 但这里比那两份多一层克制：**Dart 侧只负责算和推，不负责画**。
/// 桌面上的那张卡片由启动器进程 inflate，App 死掉的时候它照样得是对的 ——
/// 所以画图那一半必须在原生侧，而这里能做的就是给它一份算好的快照
/// （`core/widget/widget_snapshot.dart`）。
///
/// Windows 端走 [UnsupportedHomeWidgetBridge]：`home_widget` 这类包只支持
/// Android/iOS，而 Win11 的 Widgets Board 对第三方不开放，阶段 6 的形态会是
/// 无边框置顶小窗。留这个桩是为了 `flutter build windows` 一直能过。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../settings/schedule_ref.dart';

/// 一个小组件实例要显示什么。
///
/// 刻意是**用户在每个实例上单独选**的（用户明确要求「具体显示什么由用户决定」），
/// 所以它存在实例配置里，而不是一个全局设置。
enum WidgetContent {
  /// 跟随尺寸：小 → 下一节课、中 → 今日课程、大 → 本周缩略。
  auto,

  /// 只画下一节课（大字）。
  next,

  /// 今天一天的课。
  today,

  /// 今天 + 明天两组。
  todayTomorrow,

  /// 本周的彩色缩略网格。
  week,
}

/// 原生侧的字符串 ↔ 枚举。名字对不上时退回 [WidgetContent.auto] ——
/// 一个认不出来的配置值不该让小组件什么都不画。
WidgetContent widgetContentFromName(Object? raw) {
  for (final v in WidgetContent.values) {
    if (v.name == raw) return v;
  }
  return WidgetContent.auto;
}

/// 桌面上已经放置的一个小组件实例。
@immutable
class HomeWidgetInstance {
  const HomeWidgetInstance({
    required this.id,
    required this.widthDp,
    required this.heightDp,
    required this.content,
    this.setKey = ScheduleRef.overview,
    this.showSetName = true,
  });

  /// 系统给的 appWidgetId，配置页拿它回写。
  final int id;

  /// 启动器报给我们的当前尺寸（dp）。用户拖着缩放时会变。
  final int widthDp;
  final int heightDp;

  /// 用户为这个实例选的内容。
  final WidgetContent content;

  /// 这个实例显示**哪个日程**，取值是 [ScheduleRef] 那套词表：
  /// `overview`（总览）/ `follow`（跟随当前）/ `set:<id>`。
  ///
  /// **默认「总览」**，和原生侧 `WidgetStore.scope()` 的缺省一致 —— 升级之前
  /// 小组件本来就是把所有日程**合并**显示的，所以只有「总览」是那个行为不变的
  /// 默认值。默认成「跟随当前」会让升级瞬间桌面上那几个实例悄悄换掉内容，
  /// 而那种回归没有任何东西会报错。
  ///
  /// 这个默认值只在**原生没给出这个键**时兜底（老版本原生、或者 `instances()`
  /// 解析失败）；正常路径上缺省由原生那一侧给。
  final String setKey;

  /// 要不要在卡片上留一条信息条写这是哪个日程。
  ///
  /// **默认显示。** 这一条和另外两个「默认值保行为不变」的决定方向相反，
  /// 理由不同：那两个（小组件选日程默认总览、提醒默认跟随全局）一改就会
  /// 悄悄换掉内容，而这一条是用户**明确要求新增**的显示项，没有「原来的
  /// 行为」可保 —— 小组件此前根本没有日程这个概念。
  ///
  /// 小尺寸（2×1）那一档结构上放不下这一栏，但那不是「关掉了」：
  /// 配置页的开关照旧持久化，用户改成中/大尺寸时它就会回来。
  final bool showSetName;

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetInstance &&
      other.id == id &&
      other.widthDp == widthDp &&
      other.heightDp == heightDp &&
      other.content == content &&
      other.setKey == setKey &&
      other.showSetName == showSetName;

  @override
  int get hashCode =>
      Object.hash(id, widthDp, heightDp, content, setKey, showSetName);
}

/// 小组件在原生侧的当前状态。
@immutable
class HomeWidgetStatus {
  const HomeWidgetStatus({
    this.supported = false,
    this.count = 0,
    this.hasSnapshot = false,
    this.snapshotAt = 0,
  });

  /// Android 上是 true，Windows 上是 false。设置页据此决定显不显示那一块。
  final bool supported;

  /// 桌面上放着几个。
  final int count;

  /// 快照有没有落盘 —— 没落盘时原生画的是「打开 App 更新」。
  final bool hasSnapshot;

  /// 快照的生成时刻（epoch 毫秒）；没有快照时为 0。
  final int snapshotAt;

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetStatus &&
      other.supported == supported &&
      other.count == count &&
      other.hasSnapshot == hasSnapshot &&
      other.snapshotAt == snapshotAt;

  @override
  int get hashCode => Object.hash(supported, count, hasSnapshot, snapshotAt);
}

/// 小组件的原生口。
abstract class HomeWidgetBridge {
  /// 把一份算好的快照推给原生并落盘，顺带重画所有实例、重新武装刷新闹钟。
  ///
  /// **全量替换**，和 `ReminderScheduler.sync` 同一个理由：算差量本身是一类
  /// 容易错的逻辑，而重画一张卡片的代价可以忽略。
  Future<void> sync(Map<String, Object?> snapshot);

  /// 查一遍原生侧的状态。
  Future<HomeWidgetStatus> status();

  /// 桌面上放着的全部实例（含各自的尺寸和配置）。
  Future<List<HomeWidgetInstance>> instances();

  /// 改某个实例的配置：画什么、画哪个日程、要不要写日程名。改完立刻重画那一个。
  ///
  /// **三项一起写，不拆成三个方法**：配置页手上本来就同时有这三个值，
  /// 拆开只会多出「写了一半」的中间态 —— 用户把内容改成「本周课表」的那一瞬间，
  /// 卡片会用旧日程重画一次。
  Future<void> setConfig(
    int id,
    WidgetContent content, {
    required String setKey,
    required bool showSetName,
  });

  /// 忘记某个实例的配置 —— 它被从桌面上删掉时调。
  Future<void> clearConfig(int id);

  /// 让原生重新画一遍全部实例（配置改完、或回到前台时）。
  Future<void> refreshAll();

  /// 把指定内容按指定尺寸渲染成 PNG，给配置页做**实时预览**。
  ///
  /// 这不是临时脚手架：它同时是本阶段的关键验证手段 ——
  /// `adb shell cmd appwidget` 在这台 ROM 上不可用，没法用命令行往桌面上放
  /// 小组件，而这条路让布局、配色、数据正确性全部能在**没有桌面小组件的情况下**
  /// 用截图验证。
  ///
  /// [setKey] / [showSetName] 也要传：预览必须走和桌面**同一个**「选哪一块、
  /// 画不画日程名」的判定，否则配置页上那个预览会指着一个用户在桌面上看不到的
  /// 样子，比没有预览更坏。
  Future<Uint8List?> preview({
    required WidgetContent content,
    required String setKey,
    required bool showSetName,
    required int widthDp,
    required int heightDp,
  });

  /// 取出「打开 App 是为了配置某个实例」的那一次启动。
  ///
  /// **拉而不是推**：原生把待处理的 appWidgetId 存着，Dart 起来之后主动问。
  /// 反过来让原生在 Dart 还没挂上监听时推，那次调用会丢掉 ——
  /// 和 `capabilities()` 是同一个道理。
  ///
  /// 取一次就清掉，避免每次冷启动都弹配置页。返回 null 表示这次是正常启动。
  Future<int?> consumeLaunch();

  /// 取出「打开 App 是为了看某个实例显示的那个日程」的那一次点击。
  ///
  /// 和 [consumeLaunch] 是**两条独立的路**，各自记各自的待处理 id：点卡片主体
  /// 是「打开 App 看课表」，点齿轮是「打开 App 改这张卡片的配置」，用户可能
  /// 连着点两下不同位置，混成一个槽位就会丢掉其中一次。
  ///
  /// 同样是**拉而不是推**，同样取一次就清。返回 null 表示这一次不是从卡片
  /// 进来的。
  Future<int?> consumeOpen();
}

/// 按平台挑实现。
HomeWidgetBridge createHomeWidgetBridge() {
  if (!kIsWeb && Platform.isAndroid) return MethodChannelHomeWidgetBridge();
  return const UnsupportedHomeWidgetBridge();
}

/// 走 `WidgetBridge.kt`。
class MethodChannelHomeWidgetBridge implements HomeWidgetBridge {
  const MethodChannelHomeWidgetBridge();

  /// 通道名和原生侧 `WidgetBridge.CHANNEL` 必须一致。
  /// `test/widget_channel_test.dart` 里有一条直接读 Kotlin 源码核对的契约测试。
  static const String channelName = 'com.jingjunyu.classcal/widget';

  static const MethodChannel _channel = MethodChannel(channelName);

  @override
  Future<void> sync(Map<String, Object?> snapshot) async {
    await _invoke<void>('sync', {'snapshot': snapshot});
  }

  @override
  Future<HomeWidgetStatus> status() async {
    final raw = await _invoke<Map<Object?, Object?>>('status');
    if (raw == null) return const HomeWidgetStatus();
    return HomeWidgetStatus(
      supported: true,
      count: raw['count'] is int ? raw['count']! as int : 0,
      hasSnapshot: raw['hasSnapshot'] == true,
      snapshotAt: raw['snapshotAt'] is int ? raw['snapshotAt']! as int : 0,
    );
  }

  @override
  Future<List<HomeWidgetInstance>> instances() async {
    final raw = await _invoke<List<Object?>>('instances');
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          HomeWidgetInstance(
            id: item['id'] is int ? item['id']! as int : 0,
            widthDp: item['widthDp'] is int ? item['widthDp']! as int : 0,
            heightDp: item['heightDp'] is int ? item['heightDp']! as int : 0,
            content: widgetContentFromName(item['content']),
            // 认不出来的 key 照样原样收下，**不在这里放宽** —— 退回哪一块需要
            // 快照里的 `activeSetId`，而那个只有原生手上有。缺键（老版本原生）
            // 时才落到 `overview`：那正是它当时在画的东西（所有日程合并）。
            setKey: item['setKey'] is String
                ? item['setKey']! as String
                : ScheduleRef.overview,
            showSetName: item['showSetName'] != false,
          ),
    ];
  }

  @override
  Future<void> setConfig(
    int id,
    WidgetContent content, {
    required String setKey,
    required bool showSetName,
  }) =>
      _invoke<void>('setConfig', {
        'id': id,
        'content': content.name,
        'setKey': setKey,
        'showSetName': showSetName,
      });

  @override
  Future<void> clearConfig(int id) => _invoke<void>('clearConfig', {'id': id});

  @override
  Future<void> refreshAll() => _invoke<void>('refreshAll');

  @override
  Future<Uint8List?> preview({
    required WidgetContent content,
    required String setKey,
    required bool showSetName,
    required int widthDp,
    required int heightDp,
  }) =>
      _invoke<Uint8List>('preview', {
        'content': content.name,
        'setKey': setKey,
        'showSetName': showSetName,
        'widthDp': widthDp,
        'heightDp': heightDp,
      });

  @override
  Future<int?> consumeLaunch() async {
    final id = await _invoke<int>('consumeLaunch');
    // 原生侧不该给 0，但真给了也当作「没有」—— 0 不是合法的 appWidgetId。
    return (id == null || id == 0) ? null : id;
  }

  @override
  Future<int?> consumeOpen() async {
    final id = await _invoke<int>('consumeOpen');
    return (id == null || id == 0) ? null : id;
  }

  /// 通道调用统一走这里，把两类「没接上」都收敛成 null。
  ///
  /// `MissingPluginException` 在真机上意味着原生侧忘了注册通道，但在
  /// `flutter test` 里是常态。两者都当作「这个平台没有这个能力」处理。
  static Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Windows / 其它平台。等阶段 6 换成无边框置顶小窗。
class UnsupportedHomeWidgetBridge implements HomeWidgetBridge {
  const UnsupportedHomeWidgetBridge();

  @override
  Future<void> sync(Map<String, Object?> snapshot) async {}

  @override
  Future<HomeWidgetStatus> status() async => const HomeWidgetStatus();

  @override
  Future<List<HomeWidgetInstance>> instances() async => const [];

  @override
  Future<void> setConfig(
    int id,
    WidgetContent content, {
    required String setKey,
    required bool showSetName,
  }) async {}

  @override
  Future<void> clearConfig(int id) async {}

  @override
  Future<void> refreshAll() async {}

  @override
  Future<Uint8List?> preview({
    required WidgetContent content,
    required String setKey,
    required bool showSetName,
    required int widthDp,
    required int heightDp,
  }) async =>
      null;

  @override
  Future<int?> consumeLaunch() async => null;

  @override
  Future<int?> consumeOpen() async => null;
}
