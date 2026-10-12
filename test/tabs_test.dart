/// 标签页的顺序、默认页、总览开关 —— 也就是 `tabEntriesProvider` 那一段纯逻辑。
///
/// 为什么值得单开一份：这几条规则**没有一处会报错**。顺序排错、默认页落到别处、
/// 总览该出现时没出现，看起来都只是「这页怎么是这样」，而它们同时又决定了
/// 「打开 App 停在哪」这个每天都会经历一次的事情。
///
/// 界面上怎么画是 `home_page_test.dart` 的事，这里只钉 provider 吐出来的列表。
library;

import 'package:classcal/app/providers.dart';
import 'package:classcal/app/settings_providers.dart';
import 'package:classcal/core/settings/app_settings.dart';
import 'package:classcal/core/settings/schedule_ref.dart';
import 'package:classcal/data/db/database.dart';
import 'package:classcal/data/model/domain.dart';
import 'package:classcal/data/repository/calendar_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'temp_dir.dart';

/// 一套最简日程 —— 标签页那一层只读 `CalendarSets` 这张表，
/// 课一条都不用造。
Future<int> _seed(CalendarRepository repo, String name) => repo.createSet(
      CalendarSetData(
        id: CalendarSetData.unsavedId,
        name: name,
        shifts: SetShifts(week1Monday: DateTime(2026, 9, 7)),
      ),
    );

/// 起一个容器，可选地注入一份**初始设置**（同步注入，不必等落盘）。
class _H {
  _H._(this.repo, this.container);

  final CalendarRepository repo;
  final ProviderContainer container;

  static _H start(AppSettings settings) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final dir = tempDirForTest('classcal_tabs');
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsStoreProvider
            .overrideWithValue(SettingsStore.atPath('${dir.path}/settings.json')),
        // 直接注入，绕过「从磁盘读」那一趟异步 —— `settingsProvider.build()`
        // 本来就是同步返回 `initialSettingsProvider`。
        initialSettingsProvider.overrideWithValue(settings),
      ],
    );
    // 订阅住，否则 `tabRowsProvider` 这条 drift 流会被 Riverpod 3 暂停。
    final sub = container.listen(tabEntriesProvider, (_, _) {});

    // 收尾顺序是功能性的：先撤订阅、再拆容器、最后关库（理由见
    // native_sync_test.dart 里同一段注释）。临时目录的删除由 `tempDirForTest`
    // 登记，因为它是**最先**登记的，LIFO 之下排在最后 —— 顺序刚好。
    addTearDown(() async {
      sub.close();
      container.dispose();
      await db.close();
    });

    return _H._(CalendarRepository(db), container);
  }

  /// 等 drift 的查询流发够了 [rows] 条日程。
  ///
  /// **不能只等「非空」**：drift 的 `watch` 是每写完一条就推一次的，插了两套
  /// 只等非空，读到的会是只插了第一套的那一帧 —— 而且它看起来完全正常
  /// （一张只有一项的列表），只是少了一整个日程。
  Future<void> waitRows(int rows) async {
    for (var i = 0; i < 200; i++) {
      final n = container.read(tabRowsProvider).value?.length;
      if (n != null && n == rows) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('等了 2 秒，日程数没到 $rows');
  }

  Future<List<TabEntry>> entries(int rows) async {
    await waitRows(rows);
    return container.read(tabEntriesProvider);
  }

  List<String> keys() => container.read(tabEntriesProvider).map((e) => e.key).toList();
}

void main() {
  test('没配过顺序时：按数据库顺序，总览排在最后', () async {
    final h = _H.start(const AppSettings());
    final a = await _seed(h.repo, 'A');
    final b = await _seed(h.repo, 'B');

    await h.entries(2);

    // 总览排最后是**刻意的**：老用户的 `tabOrder` 是空的，而「默认标签页」
    // 为空串时落在 entries.first 上 —— 总览要是排最前，升级瞬间所有人打开
    // App 看到的都换了一页。
    expect(h.keys(), [ScheduleRef.ofSet(a), ScheduleRef.ofSet(b), ScheduleRef.overview]);
    expect(h.container.read(effectiveTabProvider)!.setId, a);
  });

  test('配过的顺序生效；没被列进去的日程按数据库顺序接在后面', () async {
    final h = _H.start(const AppSettings());
    final a = await _seed(h.repo, 'A');
    final b = await _seed(h.repo, 'B');

    h.container.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            tabOrder: [ScheduleRef.overview, ScheduleRef.ofSet(b)],
          ),
        );
    await h.entries(2);

    // `a` 没被列进去 —— 它该接在后面，而不是消失。
    // 这一条同时就是「新导入一个日程」的情形：新日程必然不在 tabOrder 里。
    expect(h.keys(), [ScheduleRef.overview, ScheduleRef.ofSet(b), ScheduleRef.ofSet(a)]);
  });

  test('tabOrder 里留着已经删掉的日程时不炸，也不留空位', () async {
    final h = _H.start(const AppSettings());
    final a = await _seed(h.repo, 'A');

    h.container.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            tabOrder: [ScheduleRef.ofSet(999), ScheduleRef.ofSet(a)],
          ),
        );
    await h.entries(1);

    // 999 号日程不存在 —— 跳过它，后面的照常排。
    expect(h.keys(), [ScheduleRef.ofSet(a)]);
  });

  test('只有一个日程时总览不参与 —— 哪怕开关是开的', () async {
    final h = _H.start(const AppSettings());
    final a = await _seed(h.repo, 'A');

    await h.entries(1);

    // 不给单日程用户凭空添一个和自己一模一样的页。
    expect(h.container.read(settingsProvider).overviewEnabled, isTrue);
    expect(h.keys(), [ScheduleRef.ofSet(a)]);
  });

  test('关掉总览开关之后它就不在列表里了', () async {
    final h = _H.start(const AppSettings());
    final a = await _seed(h.repo, 'A');
    final b = await _seed(h.repo, 'B');

    h.container.read(settingsProvider.notifier).update(
          (s) => s.copyWith(overviewEnabled: false),
        );
    await h.entries(2);

    expect(h.keys(), [ScheduleRef.ofSet(a), ScheduleRef.ofSet(b)]);
  });

  test('手选的标签页指向已删日程时，回退到默认页而不是留在空页上', () async {
    final h = _H.start(const AppSettings());
    final a = await _seed(h.repo, 'A');
    final b = await _seed(h.repo, 'B');

    h.container.read(selectedTabProvider.notifier).select(ScheduleRef.ofSet(b));
    await h.entries(2);
    expect(h.container.read(effectiveTabProvider)!.setId, b);

    // 模拟「b 被删了」：列表里不再有它，但内存里那个手选值还指着它。
    // 三级回退里「手选」那一级查不到，自然落到默认页 —— 而不是留在一个
    // 指向已删日程的空 key 上，让界面一直转圈。
    await h.repo.deleteSet(b);
    await h.waitRows(1);

    expect(h.container.read(effectiveTabProvider)!.setId, a);
  });

  test('默认页设在总览：那一页是总览，但 setId 仍然回退到第一个日程', () async {
    final h = _H.start(const AppSettings(defaultTab: ScheduleRef.overview));
    final a = await _seed(h.repo, 'A');
    await _seed(h.repo, 'B');

    await h.entries(2);

    final tab = h.container.read(effectiveTabProvider)!;
    expect(tab.isOverview, isTrue);
    // 「当前是哪个标签页」和「周次锚点用哪个 setId」现在是**两个**问题：
    // 总览没有自己的周号，也没有 setId，所以锚点回退到第一个日程。
    expect(h.container.read(effectiveSetIdProvider), a);
  });

  test('默认页设在第二个日程', () async {
    final h = _H.start(const AppSettings());
    await _seed(h.repo, 'A');
    final b = await _seed(h.repo, 'B');

    h.container.read(settingsProvider.notifier).update(
          (s) => s.copyWith(defaultTab: ScheduleRef.ofSet(b)),
        );
    await h.entries(2);

    expect(h.container.read(effectiveTabProvider)!.setId, b);
    expect(h.container.read(effectiveSetIdProvider), b);
  });
}
