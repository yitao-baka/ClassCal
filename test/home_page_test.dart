/// 首页的**接线**测试。
///
/// 起因是一个具体的、已经发生过的漏接：单次事件的表单、仓库方法、编辑入口
/// 全都在，唯独**没有一条路能新建它** —— `addOneOff` 一个调用者都没有。
/// 这种缺口在单元测试里是隐形的（每一块单独测都绿），在界面上也很难看出来
/// （「是不是这个功能本来就没做？」），只能靠「把界面点一遍」来钉住。
///
/// 所以这里断言的是**从界面能不能走到那个功能**，而不是功能本身对不对。
library;

import 'package:classcal/app/providers.dart';
import 'package:classcal/app/settings_providers.dart';
import 'package:classcal/core/settings/app_settings.dart';
import 'package:classcal/data/db/database.dart';
import 'package:classcal/data/model/domain.dart';
import 'package:classcal/data/repository/calendar_repository.dart';
import 'package:classcal/features/home_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'temp_dir.dart';

typedef _Ctx = ({int setId, CalendarRepository repo});

/// 一套最简课表：本周周一有一节课，周次覆盖前后几周。
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

/// 从库里把这一套的单次事件读回来。
Future<List<OneOffData>> _oneOffs(CalendarRepository repo, int setId) async =>
    (await repo.loadSetData(setId))?.oneOffs ?? const <OneOffData>[];

/// 起一个装好假依赖的首页，跑 [body]。
///
/// 这几个 override 都是必需的，不是图省事：
/// * `databaseProvider` —— 测试不能碰真库。
/// * `settingsStoreProvider` —— 同理，设置会写盘。
/// * `nowProvider` —— 它是个 30 秒一跳的周期流。不钉住的话每一跳都会让
///   provider 变化、界面重建、排新帧。
/// * `tabRowsProvider` / `setDataProvider` —— 把 drift 的**查询流**换成一次性
///   快照。这不是省事，是这一类测试的硬约束：drift 在查询流被取消时会排一个
///   零延时定时器做收尾，而树是在测试体之后才拆的，那时 fake clock 上还挂着
///   这个定时器，binding 会判「有定时器没跑完」直接失败 —— 报的错跟被测代码
///   毫无关系。在测试体里拆树也没用：`db.close()` 在假时钟里会卡死（流已经
///   开过之后它等的那件事永远不来）。
///
///   流式语义本身由 `reminder_sync_test.dart` 用真流测；这里只管界面接线。
///   界面因此不会自动刷新，所以断言一律回库里读，不看屏幕。
/// [settings] 拿到 setId 之后才造得出来（里面要按 setId 挂日程级的设置），
/// 所以是个回调而不是一份值。
Future<void> _withHome(
  WidgetTester tester,
  Future<void> Function(_Ctx ctx) body, {
  AppSettings Function(int setId)? settings,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  // 临时目录的删除由 `tempDirForTest` 登记，排在下面这个收尾块之后
  // —— 也就是「先关库，再删目录」。
  final dir = tempDirForTest('classcal_home');
  addTearDown(() async {
    // 关库放在这里而不是测试体里：tearDown 跑在真实时钟下，能正常收尾。
    await db.close();
  });

  final repo = CalendarRepository(db);
  final setId = await _seed(repo);
  final rows = await repo.allTabRows();
  final data = await repo.loadSetData(setId);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(
          SettingsStore.atPath('${dir.path}/settings.json'),
        ),
        nowProvider.overrideWith((ref) => Stream.value(DateTime.now())),
        if (settings != null)
          initialSettingsProvider.overrideWithValue(settings(setId)),
        tabRowsProvider.overrideWith((ref) => Stream.value(rows)),
        setDataProvider.overrideWith((ref, id) => Stream.value(data)),
      ],
      child: const MaterialApp(home: HomePage()),
    ),
  );
  await _settle(tester);

  await body((setId: setId, repo: repo));
}

/// 推若干帧，让界面落定。
///
/// 刻意**不用 `pumpAndSettle`**：加载时那圈 `CircularProgressIndicator` 是一直
/// 排帧的动画，只要它还没被数据替掉，`pumpAndSettle` 就永远等不到静止。表现出来
/// 是整个测试文件卡死，而且卡不卡还取决于数据库多快返回 —— 同一份代码有时过
/// 有时不过。这里改成有上限地推帧：够让同步的 sqlite 查询和微任务跑完，
/// 但不会因为一个动画而空转。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 打开「新增」那一层。
Future<void> _openAddSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FloatingActionButton, '新增'));
  await _settle(tester);
}

void main() {
  testWidgets('课表读出来之后才画网格，不会一直转圈', (tester) async {
    await _withHome(tester, (_) async {
      expect(find.text('高等数学A(1)'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('「新增」里三条路都在：单次事件、课程、导入', (tester) async {
    await _withHome(tester, (_) async {
      // 这颗按钮原来写着「导入」。导入一学期只做一次，新增才是常做的事，
      // 所以换成了「新增」—— 这两条断言就是防止它被改回去。
      await _openAddSheet(tester);

      expect(find.text('新增单次事件'), findsOneWidget);
      expect(find.text('新增课程'), findsOneWidget);
      expect(find.text('导入课表'), findsOneWidget);
    });
  });

  testWidgets('新增单次事件真的能建出来 —— 这就是当初漏掉的那条路', (tester) async {
    await _withHome(tester, (ctx) async {
      expect(await _oneOffs(ctx.repo, ctx.setId), isEmpty);

      await _openAddSheet(tester);
      await tester.tap(find.text('新增单次事件'));
      await _settle(tester);

      // 表单确实被打开了，而不是弹了个空壳。
      expect(find.text('新增事件'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '讲座');
      await tester.tap(find.text('保存'));
      await _settle(tester);

      final saved = await _oneOffs(ctx.repo, ctx.setId);
      expect(saved, hasLength(1));
      expect(saved.single.title, '讲座');
    });
  });

  testWidgets('「跟随默认」写的是这个日程的提前量，不是全局那个数', (tester) async {
    // 这条钉的是一个**只在多日程下才暴露**的错：一直拿全局的
    // `defaultLeadMinutes` 去填那个 chip 的话，一个自定义过提前量的日程里，
    // 这门课会显示一个**不是它真正会用的**数字 —— 用户照着它调时间，
    // 提醒却在另一个时刻响。单元测试测不到它（`leadMinutesFor` 单独测是绿的），
    // 只有真把界面点开才看得见。
    await _withHome(
      tester,
      (ctx) async {
        await _openAddSheet(tester);
        await tester.tap(find.text('新增课程'));
        await _settle(tester);

        expect(find.text('跟随默认（10 分钟）'), findsOneWidget);
        expect(find.text('跟随默认（15 分钟）'), findsNothing);
      },
      settings: (setId) => AppSettings(
        defaultLeadMinutes: 15,
        setReminders: {
          setId: SetReminderSettings.fromGlobal(const AppSettings())
              .copyWith(defaultLeadMinutes: 10),
        },
      ),
    );
  });

  testWidgets('没有日程级覆盖时，「跟随默认」回到全局那个数', (tester) async {
    // 上一条的反面。两条一起才说明白：显示的是「三层解析之后那个数」，
    // 而不是「永远读日程那一层」。
    await _withHome(
      tester,
      (_) async {
        await _openAddSheet(tester);
        await tester.tap(find.text('新增课程'));
        await _settle(tester);

        expect(find.text('跟随默认（20 分钟）'), findsOneWidget);
      },
      settings: (_) => const AppSettings(defaultLeadMinutes: 20),
    );
  });

  testWidgets('只填了标题也能存：其余字段都有默认值', (tester) async {
    await _withHome(tester, (ctx) async {
      await _openAddSheet(tester);
      await tester.tap(find.text('新增单次事件'));
      await _settle(tester);
      await tester.enterText(find.byType(TextFormField).first, '临时会议');
      await tester.tap(find.text('保存'));
      await _settle(tester);

      final saved = (await _oneOffs(ctx.repo, ctx.setId)).single;
      expect(saved.title, '临时会议');
      // 默认 08:00–09:40，和表单里显示的初始值对得上。
      expect(saved.startMinute, 8 * 60);
      expect(saved.endMinute, 9 * 60 + 40);
    });
  });

  testWidgets('标题空着不让存，错误停在表单里而不是悄悄丢一条', (tester) async {
    await _withHome(tester, (ctx) async {
      await _openAddSheet(tester);
      await tester.tap(find.text('新增单次事件'));
      await _settle(tester);
      await tester.tap(find.text('保存'));
      await _settle(tester);

      expect(find.text('标题不能为空'), findsOneWidget);
      expect(find.text('新增事件'), findsOneWidget, reason: '校验没过不该关掉表单');
      expect(await _oneOffs(ctx.repo, ctx.setId), isEmpty);
    });
  });
}
