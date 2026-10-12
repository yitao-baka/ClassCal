/// 全局依赖与派生状态。
///
/// 用 Riverpod 而不是 `setState` + 传参，主要图两件事：一是数据库本来是流式的，
/// drift 的 `watch` 天然就是「数据变了自动重建」，硬接进 StatefulWidget 会写很多
/// 订阅样板；二是「当前周」「当前可见课表」这类派生量散在各处算，很容易出现
/// 两个 widget 对同一件事看法不一致。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/schedule_ref.dart';
import '../core/time/periods.dart';
import '../data/db/database.dart';
import '../data/model/resolve.dart';
import '../data/repository/calendar_repository.dart';
import 'settings_providers.dart';

// ---------------------------------------------------------------------------
// 基础设施
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // 不关掉的话热重载会攒下一堆指向同一个文件的连接
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepository(ref.watch(databaseProvider)),
);

// ---------------------------------------------------------------------------
// 课表套
// ---------------------------------------------------------------------------

/// 标签页列表（含元信息）。
final tabRowsProvider = StreamProvider<List<CalendarSet>>(
  (ref) => ref.watch(repositoryProvider).watchTabRows(),
);

/// 标签栏里的全部条目，**已经按用户设定的顺序排好**。
///
/// 顺序规则（**一处写清，三处消费**）：
///
/// 1. `settings.tabOrder` 里列出来的，按那个顺序排在最前；
/// 2. 没被列进去的日程，按数据库顺序接在后面；
/// 3. 总览排在最末尾。
///
/// 第 2 条同时解决了「刚导入一个新日程」和「老用户第一次升级上来（这个列表是
/// 空的）」两件事，所以两处都不需要写迁移。
///
/// 第 3 条是**刻意的**：老用户的 `tabOrder` 是空的，而「默认标签页」为空串时
/// 落在 `entries.first` 上 —— 总览要是排在最前，升级瞬间所有人打开 App 看到的
/// 都换了一页。排在末尾，`first` 仍然是他原来那个日程。
final tabEntriesProvider = Provider<List<TabEntry>>((ref) {
  final rows = ref.watch(tabRowsProvider).value ?? const <CalendarSet>[];
  if (rows.isEmpty) return const [];

  final byKey = <String, TabEntry>{
    for (final r in rows)
      ScheduleRef.ofSet(r.id): TabEntry(
        key: ScheduleRef.ofSet(r.id),
        setId: r.id,
        name: r.name,
        colorSeedHex: r.colorSeedHex,
      ),
  };

  // 只有一个日程时总览不参与 —— 那会是一个和唯一那个日程长得一模一样的页。
  // 设置页里那个开关照旧是开着的，只是在这里被这一条压住了。
  final showOverview =
      ref.watch(settingsProvider).overviewEnabled && rows.length >= 2;
  if (showOverview) {
    byKey[ScheduleRef.overview] = const TabEntry(
      key: ScheduleRef.overview,
      setId: null,
      name: '总览',
    );
  }

  final out = <TabEntry>[];
  final taken = <String>{};
  for (final key in ref.watch(settingsProvider).tabOrder) {
    final e = byKey[key];
    if (e != null && taken.add(key)) out.add(e);
  }
  for (final r in rows) {
    final key = ScheduleRef.ofSet(r.id);
    if (taken.add(key)) out.add(byKey[key]!);
  }
  if (showOverview && taken.add(ScheduleRef.overview)) {
    out.add(byKey[ScheduleRef.overview]!);
  }
  return out;
});

class SelectedTabNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? key) => state = key;
}

/// 用户手选的标签页（[ScheduleRef] 的 key）；null 表示「跟随默认页」。
///
/// 存的不是 `int?` 而是一个 key：标签栏里现在有总览这个**没有 id** 的条目，
/// 用一个可空的 setId 兼两职，就没法表达「用户明确选了总览」和「用户什么都没选」。
final selectedTabProvider =
    NotifierProvider<SelectedTabNotifier, String?>(SelectedTabNotifier.new);

/// 实际生效的标签条目。
///
/// 三级回退，每一级对应一种真实会发生的事：
///
/// 1. 用户手选的（在本次运行里点过标签栏）；
/// 2. 否则用 `settings.defaultTab` —— 那个日程被删掉了、或总览被关掉了时，
///    这里的 `for` 找不到就落到第 3 级，而不是留下一个空页；
/// 3. 否则第一个条目。
final effectiveTabProvider = Provider<TabEntry?>((ref) {
  final entries = ref.watch(tabEntriesProvider);
  if (entries.isEmpty) return null;

  TabEntry? lookup(String? key) {
    if (key == null) return null;
    for (final e in entries) {
      if (e.key == key) return e;
    }
    return null;
  }

  return lookup(ref.watch(selectedTabProvider)) ??
      lookup(ref.watch(settingsProvider).defaultTab) ??
      entries.first;
});

/// 「用哪一套来当周次的坐标系」。
///
/// **它和 [effectiveTabProvider] 从这一刻起是两个问题。** 标签栏可以停在总览上，
/// 但周次锚点、「共 X-Y 周」、周网格的行数、小组件快照里的 `activeSetId`
/// 都需要一个**具体的日程** —— 总览的 `setId` 是 null，这里就回退到第一个日程。
///
/// 这么分开写的原因：以前一个 `int?` 兼两职，读代码的人分不清某处的 null 是
/// 「一套课表都没有」还是「当前在总览上」，而这两者对调用方的含义正好相反。
final effectiveSetIdProvider = Provider<int?>((ref) {
  final tab = ref.watch(effectiveTabProvider);
  if (tab != null && tab.setId != null) return tab.setId;
  for (final e in ref.watch(tabEntriesProvider)) {
    if (e.setId != null) return e.setId;
  }
  return null;
});

/// 某一套的完整内容（课程 + 单次事件 + 覆盖记录）。
final setDataProvider = StreamProvider.family<CalendarSetData?, int>(
  (ref, id) => ref.watch(repositoryProvider).watchSetData(id),
);

/// 当前课表解析后的全部上课时刻 —— 网格、周次选择器都读它。
final resolvedSessionsProvider = Provider.family<List<ResolvedSession>, int>(
  (ref, id) {
    final data = ref.watch(setDataProvider(id)).value;
    if (data == null) return const <ResolvedSession>[];
    return resolveSessions(
      shifts: data.shifts,
      templates: data.templates,
      oneOffs: data.oneOffs,
      overrides: data.overrides,
      setId: id,
    ).sessions;
  },
);

/// 全部套的完整内容（异步）。提醒同步需要它 —— 光看 `AsyncValue` 的值分不出
/// 「还在读盘」和「用户一套课表都没有」，而这两者对提醒的含义正好相反：
/// 前者什么都不该做，后者要把已排的提醒全撤掉。所以要连状态一起拿。
final allSetsDataProvider = StreamProvider<List<CalendarSetData>>(
  (ref) => ref.watch(repositoryProvider).watchAllSets(),
);

/// **全部标签页**的上课时刻。
///
/// 提醒必须跨标签页：用户导入的第二套课表（比如辅修）也是要上的课。
/// 课表网格看的是其中一套，这里看的是全部 —— 两者的差别就这一处。
final allSessionsProvider = Provider<List<ResolvedSession>>((ref) {
  final sets = ref.watch(allSetsDataProvider).value ?? const <CalendarSetData>[];
  final out = <ResolvedSession>[];
  for (final s in sets) {
    out.addAll(
      // **逐个日程解析**，不是一个合成的大日程。合成的话每条事件都会被盖上
      // 同一个 setId，而且 week1Monday 只能挑一个 —— 另一个日程的覆盖记录
      // 会落到错误的日期上。这是这一段唯一能写对的方式。
      resolveSessions(
        shifts: s.shifts,
        templates: s.templates,
        oneOffs: s.oneOffs,
        overrides: s.overrides,
        setId: s.id,
      ).sessions,
    );
  }
  return out..sort(ResolvedSession.compare);
});

/// 当前课表的周次范围。
final weekRangeProvider = Provider.family<({int first, int last}), int>(
  (ref, id) => weekRange(ref.watch(resolvedSessionsProvider(id))),
);

// ---------------------------------------------------------------------------
// 当前周
// ---------------------------------------------------------------------------

/// 今天落在第几周。不在学期内（放假、或锚点还没设）时为 null。
final currentWeekProvider = Provider<int?>((ref) {
  final id = ref.watch(effectiveSetIdProvider);
  if (id == null) return null;
  final data = ref.watch(setDataProvider(id)).value;
  if (data == null) return null;
  final w = weekOf(week1Monday: data.shifts.week1Monday, date: DateTime.now());
  return w > 0 ? w : null;
});

class ViewedWeekNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void show(int week) => state = week;
  void reset() => state = null;
}

/// 用户手动翻到的周；null 表示「跟着当前周走」。
///
/// 刻意用「null = 跟随当前周」而不是在进入时算一个固定值：跨过周一零点时，
/// 没动过手的用户应当自动跟到新的一周，而不是停在旧周上。
final viewedWeekProvider =
    NotifierProvider<ViewedWeekNotifier, int?>(ViewedWeekNotifier.new);

final displayedWeekProvider = Provider<int>((ref) {
  final picked = ref.watch(viewedWeekProvider);
  if (picked != null) return picked;
  final current = ref.watch(currentWeekProvider);
  if (current != null) return current;
  final id = ref.watch(effectiveSetIdProvider);
  if (id == null) return 1;
  return ref.watch(weekRangeProvider(id)).first;
});

// ---------------------------------------------------------------------------
// 时钟
// ---------------------------------------------------------------------------

/// 每 30 秒跳一次 —— 够画「现在」那条指示线。秒级精度对课表没有意义，
/// 却会让整棵树每分钟重建两次。
final nowProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  controller.add(DateTime.now());
  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) => controller.add(DateTime.now()),
  );
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});
