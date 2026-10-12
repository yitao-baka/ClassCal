/// 提醒设置页的**界面层**测试。
///
/// 这个功能原来一条 UI 测试都没有：`ReminderScope` 完全没被覆盖，
/// 「按日程分别设置」那条路也只有真机上点过。而这个功能的失败方式**一直是安静的**
/// —— 设置写进去了但界面产不出来（`remindersEnabled` 就是这个例子：算法支持三层与，
/// 却没有任何控件能把它设成 false），或者界面写着「提前 30 分钟」实际一条都不排。
/// 两种都不会报错，只会让用户以为「提醒怎么不响」。
///
/// 所以这里钉的是三件事：作用域语义（global / 日程 两个方向都写对）、
/// 界面对「跟随 / 自定义 / 关掉」三态的呈现、以及从首页能不能走到这一页。
library;

import 'package:classcal/app/providers.dart';
import 'package:classcal/app/settings_providers.dart';
import 'package:classcal/core/settings/app_settings.dart';
import 'package:classcal/data/db/database.dart';
import 'package:classcal/data/model/domain.dart';
import 'package:classcal/data/repository/calendar_repository.dart';
import 'package:classcal/features/home_page.dart';
import 'package:classcal/features/settings/reminder_page.dart';
import 'package:classcal/features/settings/reminder_scope.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'temp_dir.dart';

// ---------------------------------------------------------------------------
// 起环境
// ---------------------------------------------------------------------------

/// 一套最简课表：本周周一有一节课。
///
/// 周次按「相对今天」算而不是写死数字，否则这个测试过了今天就红。
Future<int> _seed(CalendarRepository repo) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final week1Monday = monday.subtract(const Duration(days: 14));

  return repo.createSet(
    CalendarSetData(
      id: CalendarSetData.unsavedId,
      name: '测试课表',
      colorSeedHex: '#00696D',
      shifts: SetShifts(week1Monday: week1Monday),
      templates: [
        CourseTemplate(
          id: 1,
          title: '高等数学A(1)',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: List.generate(20, (i) => i + 1),
          location: '第一教学楼202',
        ),
      ],
    ),
  );
}

/// 推若干帧，让界面落定。
///
/// 刻意**不用 `pumpAndSettle`**：提醒页在能力快照还没回来时会画一屏「正在读取…」，
/// 而加载中的分支里有一直排帧的动画部件时 `pumpAndSettle` 永远等不到静止 ——
/// 表现是整个测试文件卡死，而且卡不卡取决于 provider 多快 resolve。
/// 详情见 `home_page_test.dart` 里同名函数的注释。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 装一个真的 [ReminderPage]（或者首页），把库、设置、课表流都换成假的。
///
/// 为什么要 `UncontrolledProviderScope` 而不是就地写 `ProviderScope`：
/// 断言要**回容器里读设置**（「写进去了没有」），而 `ProviderScope` 不把容器
/// 交出来。直接建容器、自己 dispose，比事后从 element 上摸容器干净。
///
/// `tabRowsProvider` / `setDataProvider` / `allSetsDataProvider` 三个流查询都换成
/// 一次性快照，理由和 `home_page_test.dart` 那段一样：drift 的流被取消时会排一个
/// 零延时定时器收尾，而树是在测试体之后才拆的，那时 fake clock 上还挂着它 ——
/// binding 会判「有定时器没跑完」直接失败，报的错和被测代码毫无关系。
Future<void> _withApp(
  WidgetTester tester,
  Future<void> Function(int setId, ProviderContainer container) body, {
  required Widget Function(int setId) app,
  AppSettings Function(int setId)? settings,
}) async {
  // **把测试画布拉高。**
  //
  // 提醒页是一条 `ListView`，而 `SliverMultiBoxAdaptorElement` 只给**视口内**的
  // 孩子建 element —— 默认 800 高的画布下，页面下半截那几节（重复提醒、
  // 按日程分别设置）根本没被挂上树，`find.text` 找的是 element 而不是
  // 「这份 children 列表里有没有」，于是会报「找不到」。
  //
  // 这和被测代码无关：真机上滚下去它们就在。所以这里改的是**观察窗**，
  // 而不是给每处断言都加一次滚动。
  tester.view.physicalSize = const Size(1200, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(() async {
    // 关库放在真实时钟的 tearDown 里（drift 的 `close()` 在假时钟下会死等）。
    await db.close();
  });

  final repo = CalendarRepository(db);
  final setId = await _seed(repo);
  final rows = await repo.allTabRows();
  final data = await repo.loadSetData(setId);
  final dir = tempDirForTest('classcal_reminder');

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      settingsStoreProvider.overrideWithValue(
        SettingsStore.atPath('${dir.path}/settings.json'),
      ),
      // 它是 30 秒一跳的周期流；不钉住的话每一跳都会让界面重建、排新帧。
      nowProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      if (settings != null)
        initialSettingsProvider.overrideWithValue(settings(setId)),
      tabRowsProvider.overrideWith((ref) => Stream.value(rows)),
      setDataProvider.overrideWith((ref, id) => Stream.value(data)),
      allSetsDataProvider.overrideWith(
        (ref) => Stream.value(<CalendarSetData>[?data]),
      ),
    ],
  );
  // 顺序是功能性的：先拆容器、再关库 —— 反过来会撞上「drift 的流还活着」，
  // 表现是测试体跑完后超时 30 秒（见 native_sync_test.dart 同一段注释）。
  // `addTearDown` 是后进先出，所以容器这一句写在关库那句**之后**才排得上。
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: app(setId)),
  );
  await _settle(tester);
  await body(setId, container);
}

/// 只为了拿到一个 [WidgetRef] 的最小外壳 —— [ReminderScope] 读写走的是它。
///
/// 不能让 `ProviderContainer` 顶替：那是 `Ref`，不是 `WidgetRef`，而作用域
/// 只有界面那一份。所以老老实实挂一个 `Consumer`，把 ref 记下来。
class _ScopeHarness {
  _ScopeHarness._(this.ref);

  final WidgetRef ref;

  AppSettings get settings => ref.read(settingsProvider);

  /// 每次都用**当下**的设置造一个新作用域 —— 页面也是这么干的
  /// （`ReminderPage.build` 每次重建都 new 一个）。抱着旧作用域再写，
  /// 算 `values` 用的是过期快照，写出来的块会少掉中间那一步的改动。
  ReminderScope scope(int? setId) =>
      ReminderScope(ref: ref, setId: setId, settings: settings);
}

Future<void> _withScope(
  WidgetTester tester,
  Future<void> Function(_ScopeHarness h) body, {
  AppSettings initial = const AppSettings(),
}) async {
  final dir = tempDirForTest('classcal_scope');
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          SettingsStore.atPath('${dir.path}/settings.json'),
        ),
        initialSettingsProvider.overrideWithValue(initial),
      ],
      child: Consumer(
        builder: (_, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  await body(_ScopeHarness._(captured));
}

/// 找一个 `SwitchListTile` 的开关状态。
///
/// 直接 `tester.tap(find.text(...))` 是能切换的（整块 tile 可点），但要**断言**
/// 开关本身是开是关就得拿到那个 widget —— 不能靠「点完之后哪几节不见了」反推，
/// 那样「开关画反了」这种错会被漏掉。
SwitchListTile _switchOf(WidgetTester tester, String title) => tester.widget(
      find.ancestor(
        of: find.text(title),
        matching: find.byType(SwitchListTile),
      ),
    );

void main() {
  // -------------------------------------------------------------------------
  // ReminderScope：两种作用域的语义
  // -------------------------------------------------------------------------

  group('ReminderScope', () {
    testWidgets('没有覆盖时 values 返回全局那一份，following 为真', (tester) async {
      await _withScope(
        tester,
        (h) async {
          expect(h.scope(7).following, isTrue);
          // 「跟随全局」的含义就是读完值 —— 所以这个 getter 在两种模式下都对，
          // 调用方不必先判一次。
          expect(h.scope(7).values.defaultLeadMinutes, 25);
          expect(h.scope(7).values.repeatReminders, isTrue);
        },
        initial: const AppSettings(defaultLeadMinutes: 25, repeatReminders: true),
      );
    });

    testWidgets('全局页自己永远不是「跟随」', (tester) async {
      await _withScope(tester, (h) async {
        // 它不是「可以跟随」的东西，它就是被跟随的那一份。
        expect(h.scope(null).following, isFalse);
        expect(h.scope(null).isGlobal, isTrue);
      });
    });

    testWidgets('setFollowing(false) 播的是**当下**的全局值，不是出厂默认', (tester) async {
      await _withScope(
        tester,
        (h) async {
          h.scope(7).setFollowing(false);

          final block = h.settings.setReminders[7];
          expect(block, isNotNull);
          expect(h.scope(7).following, isFalse);
          // 硬编码一套默认值的话，一个把提前量调成 25 的人点「不跟随」会看到
          // 它跳回 15，然后得重新调一遍 —— 而他要的只是改其中一项。
          expect(block!.defaultLeadMinutes, 25);
          expect(block.repeatReminders, isTrue);
          expect(block.remindersEnabled, isTrue);
        },
        initial: const AppSettings(defaultLeadMinutes: 25, repeatReminders: true),
      );
    });

    testWidgets('setFollowing(true) 把块删掉，回到跟随', (tester) async {
      await _withScope(
        tester,
        (h) async {
          h.scope(7).setFollowing(false);
          expect(h.settings.setReminders.containsKey(7), isTrue);

          h.scope(7).setFollowing(true);
          expect(h.settings.setReminders.containsKey(7), isFalse);
          expect(h.scope(7).following, isTrue);
        },
      );
    });

    testWidgets('日程作用域的写入不碰全局，全局写入也不碰日程', (tester) async {
      await _withScope(
        tester,
        (h) async {
          h.scope(7).write((s) => s.copyWith(defaultLeadMinutes: 5));

          // 块是在全局值基础上改一项来的，其余照旧。
          expect(h.settings.setReminders[7]!.defaultLeadMinutes, 5);
          expect(h.settings.setReminders[7]!.notificationTimeoutMinutes, 0);
          // 全局一动不动 —— 这一条是整个功能的立身之本：
          // 「辅修改 5 分钟」不该顺手把别的日程也改了。
          expect(h.settings.defaultLeadMinutes, 25);

          h.scope(null).write((s) => s.copyWith(defaultLeadMinutes: 40));
          expect(h.settings.defaultLeadMinutes, 40);
          expect(h.settings.setReminders[7]!.defaultLeadMinutes, 5);
        },
        initial: const AppSettings(defaultLeadMinutes: 25),
      );
    });

    testWidgets('可以只把一个日程整个关掉，全局仍然开着', (tester) async {
      // 这一档**算法一直支持、界面一直产不出来**：`remindersEnabled` 是三层与里
      // 日程那一层，但块的来源是 `fromGlobal`，而能走到日程页就说明全局总闸开着
      // —— 于是它事实上恒为 true。用户要的是「全局开着，但「辅修」这个日程一条都别响」。
      await _withScope(
        tester,
        (h) async {
          h.scope(7).write((s) => s.copyWith(remindersEnabled: false));

          expect(h.settings.setReminders[7]!.remindersEnabled, isFalse);
          expect(h.settings.remindersEnabled, isTrue);
        },
      );
    });
  });

  // -------------------------------------------------------------------------
  // 某一个日程的提醒页
  // -------------------------------------------------------------------------

  group('日程页', () {
    testWidgets('跟随时只有只读摘要，四节都不出现', (tester) async {
      await _withApp(
        tester,
        (setId, _) async {
          expect(find.text('跟随全局默认'), findsOneWidget);
          expect(find.textContaining('用全局设置：'), findsOneWidget);
          for (final s in const ['提前多久', '定位门控', '通知自动清除', '重复提醒']) {
            expect(find.text(s), findsNothing, reason: '跟随时不该出现「$s」');
          }
          // 关着的开关也还没出现 —— 跟随时压根没有块，`remindersEnabled` 无处可写。
          expect(find.text('开启这个日程的提醒'), findsNothing);
        },
        app: (setId) => MaterialApp(home: ReminderPage(setId: setId)),
      );
    });

    testWidgets('自定义时四节都在，但**没有**全局那三节', (tester) async {
      // 地点是「我到过哪些地方」这个事实，全局唯一一份；系统权限和检查与排查是
      // 设备级的，和日程无关。摆进日程页要么点不动，要么让用户以为
      // 「这个日程没权限、那个有」。
      await _withApp(
        tester,
        (setId, _) async {
          for (final s in const ['提前多久', '定位门控', '通知自动清除', '重复提醒']) {
            expect(find.text(s), findsOneWidget, reason: '自定义时该出现「$s」');
          }
          for (final s in const ['地点', '系统权限', '检查与排查']) {
            expect(find.text(s), findsNothing, reason: '日程页不该有「$s」');
          }
        },
        app: (setId) => MaterialApp(home: ReminderPage(setId: setId)),
        settings: (setId) => AppSettings(
          setReminders: {setId: SetReminderSettings.fromGlobal(const AppSettings())},
        ),
      );
    });

    testWidgets('关掉「跟随全局默认」→ 四节出现，日程开关是开的', (tester) async {
      await _withApp(
        tester,
        (setId, container) async {
          await tester.tap(find.text('跟随全局默认'));
          await _settle(tester);

          expect(find.text('提前多久'), findsOneWidget);
          // 块由全局值播种而来，而能走到这里就说明全局总闸开着 —— 所以它是开的。
          expect(_switchOf(tester, '开启这个日程的提醒').value, isTrue);
          expect(container.read(settingsProvider).setReminders[setId], isNotNull);
        },
        app: (setId) => MaterialApp(home: ReminderPage(setId: setId)),
      );
    });

    testWidgets('把日程开关关掉 → 四节消失，且真的写下去了', (tester) async {
      await _withApp(
        tester,
        (setId, container) async {
          await tester.tap(find.text('跟随全局默认'));
          await _settle(tester);
          expect(find.text('提前多久'), findsOneWidget);

          await tester.tap(find.text('开启这个日程的提醒'));
          await _settle(tester);

          // 一份改了不会生效的设置比看不到更糟 —— 所以是**藏起来**，不是置灰。
          expect(find.text('提前多久'), findsNothing);
          expect(find.text('定位门控'), findsNothing);
          // 开关自己还在（不然就再也开不回来了）。
          expect(_switchOf(tester, '开启这个日程的提醒').value, isFalse);
          expect(
            container.read(settingsProvider).setReminders[setId]!.remindersEnabled,
            isFalse,
          );
        },
        app: (setId) => MaterialApp(home: ReminderPage(setId: setId)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // 全局页里的「按日程分别设置」
  // -------------------------------------------------------------------------

  group('按日程分别设置', () {
    testWidgets('被关掉的日程不能继续写「提前 30 分钟」', (tester) async {
      // 这一行原来对有块的日程一律写 `reminderSummary(b)` —— 于是块被关掉之后
      // 它继续显示「提前 30 分钟 · 已在教室则静音」，看起来在正常提醒，
      // 实际一条都不排。这个功能的失败方式一直是安静的，所以这一行必须说实话。
      await _withApp(
        tester,
        (setId, _) async {
          expect(find.text('这个日程的提醒已关闭'), findsOneWidget);
          expect(find.textContaining('提前 30 分钟'), findsNothing);
        },
        app: (_) => const MaterialApp(home: ReminderPage()),
        settings: (setId) => AppSettings(
          setReminders: {
            setId: SetReminderSettings.fromGlobal(const AppSettings())
                .copyWith(remindersEnabled: false, defaultLeadMinutes: 30),
          },
        ),
      );
    });

    testWidgets('开着的日程照旧写实际会发生什么', (tester) async {
      await _withApp(
        tester,
        (setId, _) async {
          expect(find.text('这个日程的提醒已关闭'), findsNothing);
          expect(find.textContaining('提前 30 分钟'), findsOneWidget);
        },
        app: (_) => const MaterialApp(home: ReminderPage()),
        settings: (setId) => AppSettings(
          setReminders: {
            setId: SetReminderSettings.fromGlobal(const AppSettings())
                .copyWith(defaultLeadMinutes: 30),
          },
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // 入口
  // -------------------------------------------------------------------------

  group('首页入口', () {
    testWidgets('菜单里有「本日程的提醒」，点进去直接落在那个日程上', (tester) async {
      // 原来的入口有四层深（设置 → 课前提醒 → 按日程分别设置 → 点某个日程），
      // 而用户心里想的是一句「这个日程的提醒」—— 他正看着那个日程。
      await _withApp(
        tester,
        (setId, _) async {
          await tester.tap(find.byTooltip('更多'));
          await _settle(tester);
          expect(find.text('本日程的提醒'), findsOneWidget);

          await tester.tap(find.text('本日程的提醒'));
          await _settle(tester);

          // 落在**日程页**上：有「跟随全局默认」，没有全局那三节。
          expect(find.text('跟随全局默认'), findsOneWidget);
          expect(find.text('系统权限'), findsNothing);
          // 标题是这个日程的名字（`tabRowsProvider` 给的）。
          expect(find.text('测试课表'), findsWidgets);
        },
        app: (_) => const MaterialApp(home: HomePage()),
      );
    });
  });
}
