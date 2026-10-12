/// 原生侧的同步宿主 —— 课前提醒 + 桌面小组件快照。
///
/// 原来叫 `ReminderSync`（文件 `reminder_providers.dart`），改名是因为现在它推的
/// 不只是提醒：**一个叫 `ReminderSync` 的类里推小组件快照，下一个人找不到它**。
/// 纯机械改名，零行为变化。
///
/// 两组东西**共用同一个防抖循环**，不各起一个。触发集完全相同
/// （`allSessionsProvider` + `settingsProvider`），而且那里有一条必须复用的护栏：
/// [NativeSync._syncOnce] 开头那句「还在读盘时绝对不能同步」。另起一个宿主就等于
/// 把那条护栏再写一遍，而漏写一次的表现是「开机后桌面小组件空白，直到用户去点
/// 一下 App」—— 和提醒那边漏写时是同一类安静的失败。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/home_widget.dart';
import '../core/platform/reminder_scheduler.dart';
import '../core/reminder/reminder_plan.dart';
import '../core/widget/widget_snapshot.dart';
import '../data/model/domain.dart';
import 'providers.dart';
import 'settings_providers.dart';

// ---------------------------------------------------------------------------
// 提醒侧的原生口
// ---------------------------------------------------------------------------

/// 平台侧的排程口。
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => createReminderScheduler(),
);

/// 当前平台的能力快照。设置页读它画状态；权限变了就 `invalidate` 它。
final reminderCapabilitiesProvider = FutureProvider<ReminderCapabilities>(
  (ref) => ref.watch(reminderSchedulerProvider).capabilities(),
);

// ---------------------------------------------------------------------------
// 小组件侧的原生口
// ---------------------------------------------------------------------------

/// 桌面小组件的原生口。Windows 上是返回「不支持」的空桩。
final homeWidgetBridgeProvider = Provider<HomeWidgetBridge>(
  (ref) => createHomeWidgetBridge(),
);

// ---------------------------------------------------------------------------
// 同步宿主
// ---------------------------------------------------------------------------

/// 把算好的提醒表和小组件快照推给原生。
///
/// 为什么是「监听 + 副作用」而不是让各个编辑入口自己调一遍：会改到课表的地方
/// 有导入、合并、整门删除、单次改期、整体平移、调作息……七八个入口，
/// 逐个去加调用必然会漏一个，而漏掉的表现是「改了课表但提醒还按老时间响」，
/// 极难发现。盯着数据本身，就不存在漏。
class NativeSync {
  NativeSync(this._ref) {
    // 课表、提醒设置、配色任何一处变了都重来一遍。
    _ref.listen(allSessionsProvider, (_, _) => schedule());
    _ref.listen(settingsProvider, (_, _) => schedule());
    // 主题跟着壁纸色走：取色是异步的，启动那次推送很可能还没拿到，
    // 这里补一次，免得桌面上那张卡片一直用兜底的紫色。
    _ref.listen(colorSchemeProvider, (_, _) => schedule());
    // 标签页切换也要重推：快照里的 `activeSetId` 和总览块借用的日期都跟着
    // 「当前停在哪一套」走，而切标签页**只动这一个** provider —— 不监听的话，
    // 桌面上一张配成「跟随当前」的卡片会一直停在切走之前那一套上，
    // 直到用户碰巧改了别的设置才跟着变。这是个已经存在过的暗病。
    _ref.listen(effectiveSetIdProvider, (_, _) => schedule());
    schedule();
  }

  final Ref _ref;

  Timer? _debounce;
  bool _running = false;
  bool _dirty = false;
  bool _disposed = false;

  /// 安排一次同步（合并短时间内的多次触发）。
  ///
  /// 合并是必要的而不是优化：启动时每一套课表是分几次读出来的，
  /// 改一个设置也会连带触发别的 provider 重建。每一次都全量重排系统闹钟
  /// 既浪费又会让「已排 N 条」这个数字来回跳。
  void schedule() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _run);
  }

  /// 立刻同步一遍。回到前台时用 —— 离开期间可能已经跨过好几条提醒了。
  Future<void> flushNow() async {
    if (_disposed) return;
    _debounce?.cancel();
    await _run();
  }

  Future<void> _run() async {
    if (_disposed) return;
    if (_running) {
      // 正在跑的时候又来了新数据：记下来，这一轮跑完再来一轮，
      // 用最新的值覆盖掉刚才那次的结果。
      _dirty = true;
      return;
    }
    _running = true;
    try {
      do {
        _dirty = false;
        await _syncOnce();
      } while (_dirty && !_disposed);
    } on Object {
      // 推送失败不能影响用 App。设置页会把状态画出来，数字对不上就是这里出了问题。
    } finally {
      _running = false;
    }
  }

  Future<void> _syncOnce() async {
    // 还在读盘时**绝对不能同步**：这时 allSessionsProvider 是空的，而空表
    // 的含义是「一条提醒都不该有」，排下去就是把上一次开机排好的闹钟全撤了。
    // 每次冷启动都会这么干一遍，用户看到的是「提醒时灵时不灵」。
    //
    // 小组件同理，而且更难看：桌面上的卡片会在开机后先空一下再回来。
    // 这条护栏是**两个用途共用一份**的原因。
    if (!_ref.read(allSetsDataProvider).hasValue) return;

    final settings = _ref.read(settingsProvider);
    final sessions = _ref.read(allSessionsProvider);
    final now = DateTime.now();

    final plan = buildReminderPlan(
      sessions: sessions,
      settings: settings,
      now: now,
    );
    await _ref.read(reminderSchedulerProvider).sync(plan.specs);

    // 快照**无条件推**，不看 `settings.remindersEnabled` —— 提醒关掉了，
    // 桌面上那张课表照样要显示。这是两件事，别让一个开关管到另一个。
    final snapshot = buildWidgetSnapshot(
      sessions: sessions,
      theme: _ref.read(colorSchemeProvider),
      now: now,
      sets: _setInfos(),
      activeSetId: _ref.read(effectiveSetIdProvider) ?? kNoSetId,
      abbrOverrides: settings.courseAbbrs,
    );
    await _ref.read(homeWidgetBridgeProvider).sync(snapshot.toJson());
  }

  /// 每个日程的坐标（id / 名字 / 周次锚点），**顺序即数据库顺序**。
  ///
  /// 从**已经读出来的那份**（`allSetsDataProvider`）里取，而不是去 `read`
  /// `setDataProvider(id)`：后者是个 family，这里第一次 `read` 会把它冷启动成
  /// `AsyncLoading`，`.value` 是 null —— 于是那个日程的周次永远是空的，
  /// 而它只会表现为桌面上少了一行标题、或者网格画错一周。
  /// `allSetsDataProvider` 本来就被监听，拿它不会有这个问题。
  ///
  /// 上面那道 `hasValue` 守卫保证这里拿得到值；真拿不到也返回空表 ——
  /// 空表在快照里的含义是「只有总览块」，比让整次同步失败好。
  List<WidgetSetInfo> _setInfos() {
    final sets = _ref.read(allSetsDataProvider).value ?? const <CalendarSetData>[];
    return [
      for (final s in sets)
        WidgetSetInfo(
          id: s.id,
          name: s.name,
          week1Monday: s.shifts.week1Monday,
        ),
    ];
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
  }
}

/// 让同步活起来。
///
/// **这个 provider 必须被 `watch`，不能只 `read`。** 这是整个原生同步里最容易
/// 踩、也最难查的一个坑，值得写清楚：
///
/// Riverpod 3 起，「一个 provider 如果没有未被暂停的监听者，它自己就算被暂停」
/// 这条规则是**递归**的。只 `read` 一次的 `nativeSyncProvider` 没有任何监听者
/// → 被暂停 → 它注册的 `ref.listen` 订阅一并暂停 → `allSessionsProvider` 失去
/// 唯一的监听者 → 暂停 → `allSetsDataProvider` 同理暂停。而
/// `StreamProvider` 被暂停时会**暂停底层的 `StreamSubscription`**，于是那个流
/// 一个值都不会发。
///
/// 表现是：设置页里每一项都对、权限都给了、「已排 0 条」，改课表毫无反应，
/// 而代码从上到下读起来完全正常 —— 因为每一步单独看都没错，错的是它们之间
/// 「谁还活着」的隐式状态。`test/native_sync_test.dart` 里有一条专门钉它。
///
/// 解药只有一句：`_NativeSyncHost.build` 里的 `ref.watch(nativeSyncProvider)`。
/// 删掉它，提醒和小组件会一起静默失效。
final nativeSyncProvider = Provider<NativeSync>((ref) {
  final sync = NativeSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});
