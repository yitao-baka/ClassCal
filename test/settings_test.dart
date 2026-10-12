import 'dart:convert';
import 'dart:io';

import 'package:classcal/core/settings/app_settings.dart';
import 'package:classcal/core/settings/schedule_ref.dart';
import 'package:classcal/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置的读写测试。
///
/// 重点不在「存进去能读出来」—— 那条几乎不会错。真正会咬人的是**读不到**
/// 的时候：配置文件是可以被手改、被云同步搞坏、被旧版本写坏的。一份坏掉的
/// 设置不该让 App 打不开，也不该把课表一起拖下水。

void main() {
  late Directory dir;
  late SettingsStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('classcal_settings');
    store = SettingsStore.atPath('${dir.path}/settings.json');
  });

  tearDown(() async {
    // Windows 上递归删目录偶发 errno 145「目录不是空的」—— 是文件系统
    // 的时序问题，跟被测代码无关。清理失败不该让测试红。
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // 交给系统临时目录自己去清
    }
  });

  group('往返', () {
    test('没存过时给出默认值，而不是报错', () async {
      final s = await store.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.colorSource, AppColorSource.wallpaper);
      expect(s.customSeedHex, AppSettings.kDefaultSeedHex);
    });

    test('改过的每一项都存得住', () async {
      await store.save(const AppSettings(
        themeMode: AppThemeMode.dark,
        colorSource: AppColorSource.custom,
        customSeedHex: '#123ABC',
      ));

      final back = await store.load();
      expect(back.themeMode, AppThemeMode.dark);
      expect(back.colorSource, AppColorSource.custom);
      expect(back.customSeedHex, '#123ABC');
    });

    test('写入是原子替换 —— 旧的 .tmp 不会留在原地', () async {
      await store.save(const AppSettings());
      await store.save(const AppSettings(themeMode: AppThemeMode.light));

      final names = dir.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last);
      expect(names.contains('settings.json.tmp'), isFalse);
      expect((await store.load()).themeMode, AppThemeMode.light);
    });
  });

  group('坏文件不能把 App 拦在门外', () {
    test('内容不是 JSON —— 用默认值继续', () async {
      File('${dir.path}/settings.json').writeAsStringSync('{ 这不是 json');
      final s = await store.load();
      expect(s.themeMode, AppThemeMode.system);
    });

    test('JSON 合法但类型不对 —— 用默认值继续', () async {
      File('${dir.path}/settings.json').writeAsStringSync('[1,2,3]');
      expect((await store.load()).colorSource, AppColorSource.wallpaper);
    });

    test('认不出的枚举名退回默认，其它项照常读出来', () async {
      // 这是「降级安装」的样子：新版本写了 themeMode 的新取值，
      // 用户又装回了旧版本。旧版本该认得的项要认得，不认得的退回默认，
      // 而不是整份设置作废。
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'themeMode': 'midnight',
        'colorSource': 'custom',
        'customSeedHex': '#00FF00',
      }));

      final s = await store.load();
      expect(s.themeMode, AppThemeMode.system); // 认不出 → 默认
      expect(s.colorSource, AppColorSource.custom); // 认得 → 保留
      expect(s.customSeedHex, '#00FF00');
    });

    test('色值格式不对就退回默认 —— 坏色值会让整棵树构不出主题', () async {
      for (final bad in ['红色', '#12', '#GGGGGG', '']) {
        File('${dir.path}/settings.json')
            .writeAsStringSync(jsonEncode({'customSeedHex': bad}));
        expect(
          (await store.load()).customSeedHex,
          AppSettings.kDefaultSeedHex,
          reason: '「$bad」应当被拒绝',
        );
      }
    });

    test('小写 hex 要接受并归一成大写', () async {
      File('${dir.path}/settings.json')
          .writeAsStringSync(jsonEncode({'customSeedHex': '#abcdef'}));
      expect((await store.load()).customSeedHex, '#ABCDEF');
    });
  });

  group('标签页：顺序 / 默认页 / 总览开关', () {
    test('往返', () async {
      await store.save(AppSettings(
        tabOrder: const [ScheduleRef.overview, 'set:3'],
        defaultTab: ScheduleRef.ofSet(3),
        overviewEnabled: false,
      ));

      final back = await store.load();
      expect(back.tabOrder, [ScheduleRef.overview, 'set:3']);
      expect(back.defaultTab, 'set:3');
      expect(back.overviewEnabled, isFalse);
    });

    test('老版本写下的文件里没有这三个键 —— 退回默认，且默认是「行为不变」', () async {
      // 这一条其实是**升级路径**：用户装的是上一版，文件里只有旧键。
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'themeMode': 'dark',
        'defaultLeadMinutes': 20,
      }));

      final s = await store.load();
      expect(s.tabOrder, isEmpty, reason: '空列表 = 按数据库顺序，正是老行为');
      // **空串**而不是 null：含义是「第一个日程」，也就是老版本打开时停的地方。
      expect(s.defaultTab, '');
      // 默认开着 —— 但只有一个日程时它仍然不参与标签栏，见 tabEntriesProvider。
      expect(s.overviewEnabled, isTrue);
      // 旧键照常读出来，别被新字段带崩。
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.defaultLeadMinutes, 20);
    });

    test('tabOrder 里坏掉的项单独丢，其余照收', () async {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'tabOrder': [
          'set:2',
          42, // 不是字符串
          'set:0', // 0 是 kNoSetId 那个哨兵，不是日程
          'set:-1',
          'follow', // 只有小组件能用，当标签页 key 没意义
          'set:2', // 重复
          'overview',
          'overview', // 重复
          '',
        ],
      }));

      final s = await store.load();
      // 顺序要保住：`set:2` 在前、`overview` 在后。
      expect(s.tabOrder, ['set:2', 'overview']);
    });

    test('defaultTab 认不出的值退回空串 —— 一个坏值不该把用户换到别的页上', () async {
      for (final raw in ['typo', 'set:0', 'follow', 42]) {
        File('${dir.path}/settings.json')
            .writeAsStringSync(jsonEncode({'defaultTab': raw}));
        expect((await store.load()).defaultTab, '',
            reason: '「$raw」应当被拒绝');
      }
    });

    test('set:<id> 的解析', () {
      expect(ScheduleRef.setIdOf('set:3'), 3);
      expect(ScheduleRef.setIdOf('set:0'), isNull, reason: '0 是「不属于任何日程」的哨兵');
      expect(ScheduleRef.setIdOf('set:-1'), isNull);
      // 总览、follow、空串、坏串一律 null —— 想区分「是总览」请另外判。
      for (final k in [ScheduleRef.overview, ScheduleRef.follow, '', 'set:', 'set:x']) {
        expect(ScheduleRef.setIdOf(k), isNull, reason: '「$k」不该被解析成某个 id');
      }
      expect(ScheduleRef.isOverview(ScheduleRef.overview), isTrue);
      expect(ScheduleRef.isOverview(ScheduleRef.ofSet(1)), isFalse);
      // follow 合法但不是个能当标签页的 key。
      expect(ScheduleRef.isValid(ScheduleRef.follow), isTrue);
      expect(ScheduleRef.isTabKey(ScheduleRef.follow), isFalse);
      expect(ScheduleRef.isTabKey(ScheduleRef.overview), isTrue);
      expect(ScheduleRef.isTabKey(''), isFalse);
    });
  });

  group('按日程的提醒设置', () {
    test('往返：整块存得住，且键是 setId 的字符串形式', () async {
      final b = SetReminderSettings.fromGlobal(const AppSettings()).copyWith(
        defaultLeadMinutes: 10,
        nearbyMode: NearbyMode.silent,
        gateRadiusMeters: 300,
        notificationTimeoutMinutes: 20,
        repeatReminders: true,
        repeatIntervalMinutes: 3,
      );
      await store.save(AppSettings(setReminders: {3: b, 8: b}));

      final raw = jsonDecode(File('${dir.path}/settings.json').readAsStringSync());
      expect((raw as Map)['setReminders'], isA<Map>());
      expect(raw['setReminders'].keys.toSet(), {'3', '8'});

      final back = await store.load();
      expect(back.setReminders.keys.toSet(), {3, 8});
      expect(back.setReminders[3], b, reason: '整块要一模一样地回来');
    });

    test('老版本写下的文件里没有 setReminders —— 每个日程都跟着全局走', () async {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'defaultLeadMinutes': 20,
        'nearbyMode': 'skip',
      }));

      final s = await store.load();
      expect(s.setReminders, isEmpty, reason: '空表 = 全部跟随全局，正是老行为');
      // 「跟随」的含义落在 leadMinutesFor 上，一起验掉。
      expect(s.leadMinutesFor(1), 20);
      expect(s.leadMinutesFor(999), 20, reason: '没设过的日程照样落到全局');
    });

    test('坏项单独丢，其余照收 —— 一个坏块不该带走别的日程', () async {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'setReminders': {
          '2': {'defaultLeadMinutes': 10},
          '0': {'defaultLeadMinutes': 1}, // 0 是「不属于任何日程」的哨兵
          '-1': {'defaultLeadMinutes': 1}, // 负数同理（unsavedId 用的就是负数）
          'x': {'defaultLeadMinutes': 1}, // 不是整数
          '4': '不是对象',
          '5': {}, // 空对象：全部字段退回出厂默认，仍然是一条有效的覆盖
        },
      }));

      final s = await store.load();
      expect(s.setReminders.keys.toSet(), {2, 5});
      expect(s.setReminders[2]!.defaultLeadMinutes, 10);
      expect(
        s.setReminders[5]!.defaultLeadMinutes,
        const AppSettings().defaultLeadMinutes,
        reason: '空块应当补上出厂默认，而不是变成 0 分钟',
      );
    });

    test('越界的数值被夹到区间，而不是整块丢弃', () async {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'setReminders': {
          '2': {
            'defaultLeadMinutes': 999999,
            'gateRadiusMeters': 1,
            'notificationTimeoutMinutes': -5,
            'repeatIntervalMinutes': 9999,
          },
        },
      }));

      final b = (await store.load()).setReminders[2]!;
      expect(b.defaultLeadMinutes, AppSettings.kMaxLeadMinutes);
      expect(b.gateRadiusMeters, AppSettings.kMinRadiusMeters);
      expect(b.notificationTimeoutMinutes, 0);
      expect(b.repeatIntervalMinutes, AppSettings.kMaxRepeatMinutes);
    });

    test('认不出的门控模式退回默认，其余项照常读出来', () async {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'setReminders': {
          '2': {'nearbyMode': 'whisper', 'defaultLeadMinutes': 7},
        },
      }));

      final b = (await store.load()).setReminders[2]!;
      expect(b.nearbyMode, const AppSettings().nearbyMode);
      expect(b.defaultLeadMinutes, 7);
    });

    test('leadMinutesFor 只认日程那一层，不含单课覆盖', () {
      // 这个方法回答的是「这门课没自己设过的话会用几分」——
      // 课程编辑器那个「跟随默认（N 分钟）」的 chip 直接显示它。
      final s = AppSettings(
        defaultLeadMinutes: 15,
        setReminders: {
          7: SetReminderSettings.fromGlobal(const AppSettings())
              .copyWith(defaultLeadMinutes: 10),
          8: SetReminderSettings.fromGlobal(const AppSettings())
              .copyWith(remindersEnabled: false),
        },
      );
      expect(s.leadMinutesFor(7), 10);
      expect(s.leadMinutesFor(9), 15, reason: '没设过的日程用全局');
      // 只关了开关的日程，提前量仍然是全局那个数 —— 两件事互不牵连。
      expect(s.leadMinutesFor(8), 15);
      // 非正 id 一律当作没设过，哪怕表里真有那个键。
      expect(s.remindersFor(0), isNull);
      expect(s.remindersFor(-1), isNull);
      expect(s.leadMinutesFor(0), 15);
    });
  });

  group('种子色的优先级', () {
    test('自定颜色压过壁纸 —— 用户明确选过的色不该被壁纸盖掉', () {
      const s = AppSettings(
        colorSource: AppColorSource.custom,
        customSeedHex: '#112233',
      );
      expect(resolveSeed(s, const Color(0xFFFF0000)), const Color(0xFF112233));
    });

    test('选了跟壁纸就往壁纸走', () {
      const s = AppSettings(colorSource: AppColorSource.wallpaper);
      expect(resolveSeed(s, const Color(0xFF00FF00)), const Color(0xFF00FF00));
    });

    test('取不到壁纸色时退回自定色，再退回预设 —— 不能返回 null', () {
      const s = AppSettings(
        colorSource: AppColorSource.wallpaper,
        customSeedHex: '#445566',
      );
      expect(resolveSeed(s, null), const Color(0xFF445566));

      const broken = AppSettings(
        colorSource: AppColorSource.wallpaper,
        customSeedHex: '不是颜色',
      );
      expect(resolveSeed(broken, null), const Color(0xFF6750A4));
    });

    test('自定色本身写坏了也不崩', () {
      const s = AppSettings(
        colorSource: AppColorSource.custom,
        customSeedHex: '  ',
      );
      expect(resolveSeed(s, const Color(0xFF00FF00)), const Color(0xFF6750A4));
    });
  });
}
