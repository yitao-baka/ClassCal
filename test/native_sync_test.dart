/// 原生同步的**接线**测试。
///
/// `reminder_plan_test.dart` / `widget_snapshot_test.dart` 管的是「计划算得对不对」，
/// 这一份管的是「算好的东西有没有真的送到系统手里」—— 也就是 provider 之间那几根线。
///
/// 这几根线有个共同的坏脾气：**断了不报错**。课表没排上、改了设置没重排、
/// 第二套课表被漏掉、小组件快照压根没推，表现全都是「安安静静地什么都不发生」，
/// 跟「功能没做」长得一模一样。所以只能靠测试把它们钉住。
library;

import 'dart:typed_data';

import 'package:classcal/app/native_sync.dart';
import 'package:classcal/app/providers.dart';
import 'package:classcal/app/settings_providers.dart';
import 'package:classcal/core/platform/home_widget.dart';
import 'package:classcal/core/platform/reminder_scheduler.dart';
import 'package:classcal/core/reminder/reminder_plan.dart';
import 'package:classcal/core/settings/app_settings.dart';
import 'package:classcal/core/widget/widget_snapshot.dart';
import 'package:classcal/data/db/database.dart';
import 'package:classcal/data/model/domain.dart';
import 'package:classcal/data/repository/calendar_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'temp_dir.dart';

/// 记下每一次推给原生的小组件快照。
///
/// 这一份盯的是一条**完全没有报错**的失败：小组件那边什么都对（XML 写好、
/// provider 注册好、模板排好），就是从来没人往里推过数据 —— 桌面上永远画着
/// 「打开 ClassCal 更新」。跨文件读代码是看不出来的，因为「谁调了谁」不在
/// 任何一个文件里。
class _FakeHomeWidget implements HomeWidgetBridge {
  final List<Map<String, Object?>> pushes = [];

  Map<String, Object?> get last => pushes.last;

  @override
  Future<void> sync(Map<String, Object?> snapshot) async =>
      pushes.add(snapshot);

  @override
  Future<HomeWidgetStatus> status() async =>
      HomeWidgetStatus(supported: true, count: pushes.length);

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
}

/// 记下每一次推送。判「有没有同步」靠它就是够了 —— 同步的**结果**对不对
/// 是 `reminder_plan_test.dart` 的事。
class _FakeScheduler implements ReminderScheduler {
  final List<List<ReminderSpec>> pushes = [];

  List<ReminderSpec> get last => pushes.last;

  @override
  Future<void> sync(List<ReminderSpec> specs) async => pushes.add(List.of(specs));

  @override
  Future<ReminderCapabilities> capabilities() async =>
      const ReminderCapabilities(supported: true);

  @override
  Future<void> cancelAll() async {}

  @override
  Future<NotificationPermission> requestNotification() async =>
      NotificationPermission.granted;

  @override
  Future<LocationPermission> requestLocation() async =>
      LocationPermission.always;

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

/// 搭一套能跑的后台：内存库 + 假原生口 + 临时设置文件。
class _Harness {
  _Harness._(this.db, this.repo, this.scheduler, this.homeWidget, this.container);

  final AppDatabase db;
  final CalendarRepository repo;
  final _FakeScheduler scheduler;
  final _FakeHomeWidget homeWidget;
  final ProviderContainer container;

  /// [watchSync] 对应 `_NativeSyncHost.build` 里那句 `ref.watch`。
  /// 设成 false 就还原出「只 read」的写法，用来验证那句 watch 到底有没有用。
  static _Harness start({bool watchSync = true}) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final scheduler = _FakeScheduler();
    final homeWidget = _FakeHomeWidget();
    final dir = tempDirForTest('classcal_sync');
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        homeWidgetBridgeProvider.overrideWithValue(homeWidget),
        settingsStoreProvider
            .overrideWithValue(SettingsStore.atPath('${dir.path}/settings.json')),
      ],
    );

    final sub = watchSync ? container.listen(nativeSyncProvider, (_, _) {}) : null;
    if (!watchSync) {
      // 只读一次，不建立监听 —— 这正是修好之前 `_NativeSyncHost` 的写法。
      container.read(nativeSyncProvider);
    }

    // **收尾顺序是功能性的。** drift 的 `close()` 会等所有活着的查询流结束，
    // 而容器里的 `allSetsDataProvider` 正挂着一条 drift 的 stream —— 先关库就是
    // 死等，表现为「测试体跑完了，然后超时 30 秒」，而堆栈里只有
    // `_RawReceivePort._handleMessage`，看不出跟数据库有关。
    //
    // 临时目录的删除不在这里 —— 它由 `tempDirForTest` 登记，是**最先**登记的那个，
    // LIFO 之下排在最后，也就是「先把容器拆了、把库关了，再删目录」，正是要的顺序。
    addTearDown(() async {
      sub?.close();
      container.dispose();
      await db.close();
    });

    return _Harness._(
      db,
      CalendarRepository(db),
      scheduler,
      homeWidget,
      container,
    );
  }

  /// 等到同步落定。同步本身是 800ms 防抖 + 一次异步读库，给足余量。
  Future<List<ReminderSpec>> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    return scheduler.pushes.isEmpty ? const <ReminderSpec>[] : scheduler.last;
  }
}

/// 造一套「一定还有课没上」的课表：7 个星期各一条，周次覆盖前后几周。
///
/// 这样无论测试在一天里的什么时候跑，都至少有几条提醒还没到点 ——
/// 写死某个日期的话，这个测试过了今天就红。
Future<int> _seedSet(
  CalendarRepository repo,
  String name, {
  bool enabled = true,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final mondayThisWeek = today.subtract(Duration(days: today.weekday - 1));
  final week1Monday = mondayThisWeek.subtract(const Duration(days: 14));

  return repo.createSet(
    CalendarSetData(
      id: CalendarSetData.unsavedId,
      name: name,
      shifts: SetShifts(week1Monday: week1Monday),
      templates: [
        for (var wd = 1; wd <= 7; wd++)
          CourseTemplate(
            id: wd,
            title: '$name-$wd',
            weekday: wd,
            startPeriod: 1,
            endPeriod: 2,
            weeks: const [1, 2, 3, 4, 5, 6, 7, 8],
            remindersEnabled: enabled,
          ),
      ],
    ),
  );
}

void main() {
  test('课表从盘里读出来之后，计划会被推给系统', () async {
    final h = _Harness.start();
    await _seedSet(h.repo, 'A');

    final specs = await h.settle();

    expect(specs, isNotEmpty, reason: '课表有了，一条提醒都没排出去');
    // 已经过去的课不该排 —— 排了会在装上当场响一堆。
    expect(
      specs.where((s) => !s.fireAt.isAfter(DateTime.now())),
      isEmpty,
      reason: '排出了已经过期的提醒',
    );
  });

  test('两套课表的提醒都会排上，后一套不会把前一套盖掉', () async {
    final h = _Harness.start();
    await _seedSet(h.repo, 'A');
    await _seedSet(h.repo, 'B');

    final specs = await h.settle();

    // 这一条盯的是 `allSessionsProvider` 是不是真的把**所有**标签页合起来了。
    // 只看当前那一套也能让网格画得好好的，但辅修的课就不会响。
    expect(specs.any((s) => s.title.startsWith('A-')), isTrue);
    expect(specs.any((s) => s.title.startsWith('B-')), isTrue);
  });

  test('改提前量会重排，而且时间真的挪了', () async {
    final h = _Harness.start();
    await _seedSet(h.repo, 'A');
    final before = await h.settle();
    expect(before, isNotEmpty);
    final sample = before.first;

    h.container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(defaultLeadMinutes: 45));
    final after = await h.settle();

    final same = after.firstWhere((s) => s.key == sample.key);
    expect(same.fireAt, sample.fireAt.subtract(const Duration(minutes: 30)),
        reason: '提前量从 15 改成 45 分钟，触发时刻该提前 30 分钟');
  });

  test('关掉总开关会把已排的提醒全部撤掉', () async {
    final h = _Harness.start();
    await _seedSet(h.repo, 'A');
    expect(await h.settle(), isNotEmpty);

    h.container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(remindersEnabled: false));
    final after = await h.settle();

    // 空表不是「什么都没做」，而是「把系统里排着的全撤了」——原生侧拿到的
    // 就是一次空推送。这一条同时保证「总开关」真的连着系统。
    expect(after, isEmpty);
  });

  test('哪天课表被清空，提醒也会跟着清空', () async {
    final h = _Harness.start();
    final setId = await _seedSet(h.repo, 'A');
    expect(await h.settle(), isNotEmpty);

    await h.repo.deleteSet(setId);
    expect(await h.settle(), isEmpty);
  });

  test('只 read 不订阅的话，整条链会被 Riverpod 3 暂停 —— 这就是必须 watch 的原因',
      () async {
    // 这条是**探针**：它钉住的是 Riverpod 的暂停语义，而不是我们自己的逻辑
    // （`nativeSyncProvider` 的注释里有完整解释）。
    //
    // 如果哪天它红了 —— 也就是「只 read」也开始有推送了 —— 说明 Riverpod 改了
    // 暂停规则，那么 `_NativeSyncHost.build` 里那句 watch 的必要性要重新评估。
    // 这正是值得被告知的一件事，所以宁可让它红，也不要让它悄悄失效。
    final h = _Harness.start(watchSync: false);
    await _seedSet(h.repo, 'A');

    await Future<void>.delayed(const Duration(milliseconds: 2000));
    expect(h.scheduler.pushes, isEmpty);
  });

  test('每条事件都知道自己属于哪个日程 —— 探针', () async {
    // `resolveSessions(setId:)` 是**可选**参数（它有二十多处调用点，其中绝大多数
    // 不关心归属，逼它们各写一个 `setId: 0` 只会训练人无脑粘魔数）。
    // 代价是「新加一条喂提醒的 resolve 忘了盖 setId」要到运行期才暴露，
    // 而它的表现是**静默的**：每日程提醒会全部退回全局默认，界面上一片正常。
    //
    // 这条探针就是抵这个代价的。它红了意味着有人漏盖了 setId，
    // 或者走了「把几个日程拼成一个假日程再 resolve 一次」那条路 ——
    // 后者会让**所有**事件都带上同一个 setId。
    final h = _Harness.start();
    final a = await _seedSet(h.repo, 'A');
    final b = await _seedSet(h.repo, 'B');
    await h.settle();

    final sessions = h.container.read(allSessionsProvider);
    expect(sessions, isNotEmpty);

    expect(
      sessions.where((s) => s.setId < 1),
      isEmpty,
      reason: '有事件没带上真实日程 —— drift 的 id 从 1 开始，'
          '留下 kNoSetId(0) 就是漏盖了',
    );
    // 两个日程各自的事件都要在，且各自带自己的 id（不是被统一成一个）。
    expect(sessions.map((s) => s.setId).toSet(), containsAll({a, b}));
    expect(
      sessions.where((s) => s.title.startsWith('A-')).map((s) => s.setId).toSet(),
      {a},
      reason: 'A 的事件被盖上了别的 setId —— 十有八九是合成假日程那条路',
    );
  });

  group('小组件快照也走同一条线', () {
    /// 快照里那串 `sessions`。
    List<Map<String, Object?>> sessionsOf(Map<String, Object?> snapshot) => [
          for (final s in (snapshot['sessions']! as List)) s as Map<String, Object?>,
        ];

    test('课表读出来之后，快照也会推给原生', () async {
      final h = _Harness.start();
      await _seedSet(h.repo, 'A');
      await h.settle();

      expect(h.homeWidget.pushes, isNotEmpty, reason: '快照压根没推过 —— 桌面上永远是空的');
      final snap = h.homeWidget.last;
      expect(snap['version'], isNotNull);
      expect(snap['today'], isNotNull);
      // 造的那套课表 7 个星期各一条，窗口 9 天里一定有课。
      expect(sessionsOf(snap), isNotEmpty);
      expect(sessionsOf(snap).first.keys, contains('startAtMs'));
    });

    test('关掉提醒开关，快照照样推 —— 两个开关不该互相管', () async {
      // 「提醒关掉」只表示别再排闹钟，桌面上的那张课表还是要显示的。
      // 把快照推送塞进 `if (remindersEnabled)` 里，表现就是「一关提醒，
      // 桌面小组件跟着变成空白」，而用户只会以为小组件坏了。
      final h = _Harness.start();
      await _seedSet(h.repo, 'A');
      h.container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(remindersEnabled: false));
      await h.settle();

      expect(h.scheduler.last, isEmpty, reason: '提醒该清空');
      expect(sessionsOf(h.homeWidget.last), isNotEmpty, reason: '但快照不该跟着空');
    });

    test('两套课表的课都进快照，和提醒一样跨标签页', () async {
      final h = _Harness.start();
      await _seedSet(h.repo, 'A');
      await _seedSet(h.repo, 'B');
      await h.settle();

      final titles = sessionsOf(h.homeWidget.last)
          .map((s) => s['title']! as String)
          .toList();
      expect(titles.any((t) => t.startsWith('A-')), isTrue);
      expect(titles.any((t) => t.startsWith('B-')), isTrue);
    });

    test('快照按日程分块，且 activeSetId 真的指到当前那一套', () async {
      final h = _Harness.start();
      final idA = await _seedSet(h.repo, 'A');
      await h.settle();

      final blocks = (h.homeWidget.last['blocks']! as List)
          .cast<Map<String, Object?>>();
      expect(blocks.map((b) => b['id']),
          containsAll([idA, kOverviewBlockId]),
          reason: '每个日程一块，末尾永远跟一个总览块');

      // `_seedSet` 把 week1Monday 放在两周前，所以现在是第 3 周。
      final mine = blocks.firstWhere((b) => b['id'] == idA);
      expect(mine['currentWeek'], 3);
      expect(mine['weekTitle'], startsWith('第 3 周 · '));

      // 这一句钉的是**接线**，不是算得对不对：小组件上「跟随当前」那个 scope
      // 是照顶层这个 `activeSetId` 去挑块的，它要是没跟着 `effectiveSetIdProvider`
      // 走，桌面上那些实例会一直停在某一个日程上，而没有任何东西会报错。
      expect(h.homeWidget.last['activeSetId'], idA);
    });

    test('配色来自和界面同一个 ColorScheme', () async {
      final h = _Harness.start();
      await _seedSet(h.repo, 'A');
      await h.settle();

      final theme = h.homeWidget.last['theme']! as Map<String, Object?>;
      final scheme = h.container.read(colorSchemeProvider);
      int signed(int v) => v > 0x7FFFFFFF ? v - 0x100000000 : v;
      expect(theme['surface'], signed(scheme.surface.toARGB32()));
    });

    test('还在读盘时既不排提醒也不推快照 —— 护栏是共用的', () async {
      // 这一条盯的是「开机瞬间」：那时 `allSetsDataProvider` 还没值，
      // 空表的含义是「什么都没有」，推下去会把桌面上那张卡片清成空白。
      //
      // 内存库几乎立刻就发出空表，所以这里**必须**用一个永不发值的流来复现
      // 「还在读盘」—— 直接起个空库是复现不出来的（那真的是「一套课表都没有」，
      // 两者的含义正好相反）。
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final scheduler = _FakeScheduler();
      final homeWidget = _FakeHomeWidget();
      final dir = tempDirForTest('classcal_loading');

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          reminderSchedulerProvider.overrideWithValue(scheduler),
          homeWidgetBridgeProvider.overrideWithValue(homeWidget),
          settingsStoreProvider.overrideWithValue(
            SettingsStore.atPath('${dir.path}/settings.json'),
          ),
          allSetsDataProvider
              .overrideWith((ref) => const Stream<List<CalendarSetData>>.empty()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(nativeSyncProvider).flushNow();

      expect(homeWidget.pushes, isEmpty, reason: '读盘还没完就把快照推下去了');
      expect(scheduler.pushes, isEmpty);
    });
  });
}
