import 'package:classcal/core/reminder/reminder_plan.dart';
import 'package:classcal/core/settings/app_settings.dart';
import 'package:classcal/data/model/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// 提醒时刻的计算。
///
/// 这一层错起来是**静默**的：不响、或者响错时间，两者都只在真实的一节课前
/// 几分钟才暴露。所以这里把边界一次钉死 —— 提前量、跨日、停课、窗口、
/// 门控点的匹配。

/// 2026-10-13 是周二。
final _now = DateTime(2026, 10, 13, 7, 0);

ResolvedSession sess({
  String title = '高等数学A(1)',
  DateTime? date,
  int startMinute = 8 * 60,
  int endMinute = 9 * 60 + 40,
  String location = '',
  String teacher = '',
  int? ruleId = 1,
  int? oneOffId,
  bool cancelled = false,
  bool remindersEnabled = true,
  int? leadMinutes,
  int setId = kNoSetId,
}) => ResolvedSession(
  date: date ?? DateTime(2026, 10, 13),
  startMinute: startMinute,
  endMinute: endMinute,
  title: title,
  location: location,
  teacher: teacher,
  ruleId: ruleId,
  oneOffId: oneOffId,
  cancelled: cancelled,
  remindersEnabled: remindersEnabled,
  leadMinutes: leadMinutes,
  setId: setId,
);

/// 一份日程提醒覆盖。没提到的字段从 [from]（默认就是出厂全局值）取 ——
/// 所以测出来的差异一定是点名改的那一项造成的。
SetReminderSettings block({
  AppSettings from = const AppSettings(),
  bool? remindersEnabled,
  int? defaultLeadMinutes,
  NearbyMode? nearbyMode,
  int? gateRadiusMeters,
  int? notificationTimeoutMinutes,
  bool? repeatReminders,
  int? repeatIntervalMinutes,
}) => SetReminderSettings.fromGlobal(from).copyWith(
  remindersEnabled: remindersEnabled,
  defaultLeadMinutes: defaultLeadMinutes,
  nearbyMode: nearbyMode,
  gateRadiusMeters: gateRadiusMeters,
  notificationTimeoutMinutes: notificationTimeoutMinutes,
  repeatReminders: repeatReminders,
  repeatIntervalMinutes: repeatIntervalMinutes,
);

ReminderPlan plan(
  List<ResolvedSession> sessions, {
  AppSettings settings = const AppSettings(),
  DateTime? now,
  Duration horizon = kReminderHorizon,
  int maxCount = kMaxReminders,
}) => buildReminderPlan(
  sessions: sessions,
  settings: settings,
  now: now ?? _now,
  horizon: horizon,
  maxCount: maxCount,
);

void main() {
  group('什么时候排', () {
    test('默认提前量：08:00 的课提前 15 分钟 → 07:45', () {
      final p = plan([sess()]);
      expect(p.specs, hasLength(1));
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 7, 45));
    });

    test('单课覆盖优先于全局默认', () {
      final p = plan([sess(leadMinutes: 45)]);
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 7, 15));
    });

    test('提前 0 分钟就是上课那一刻', () {
      final p = plan([sess(leadMinutes: 0)]);
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 8, 0));
    });

    test('提前量跨到前一天也照常算', () {
      // 00:05 的课提前 30 分钟 → 前一天 23:35，不是「今天 23:35」。
      final p = plan([
        sess(date: DateTime(2026, 10, 14), startMinute: 5, leadMinutes: 30),
      ]);
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 23, 35));
    });

    test('时间用的是平移之后的 startMinute，不是课表上的钟点', () {
      // 解析结果里 3-4 节被整体后移了 10 分钟（10:00 → 10:10）。
      final p = plan([sess(startMinute: 10 * 60 + 10)]);
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 9, 55));
    });

    test('按时刻排序，不按传入顺序', () {
      final p = plan([
        sess(title: '晚课', startMinute: 19 * 60, ruleId: 2),
        sess(title: '早课', startMinute: 8 * 60, ruleId: 1),
      ]);
      expect(p.specs.map((s) => s.title), ['早课', '晚课']);
    });
  });

  group('什么时候不排', () {
    test('总开关关掉就一条都不排', () {
      final p = plan([
        sess(),
      ], settings: const AppSettings(remindersEnabled: false));
      expect(p.specs, isEmpty);
      expect(p.totalInWindow, 0);
    });

    test('停课的那一次不排 —— 但条目仍在解析结果里', () {
      final s = sess(cancelled: true);
      expect(s.cancelled, isTrue, reason: '解析层刻意保留停课条目');
      expect(plan([s]).specs, isEmpty);
    });

    test('单课关掉提醒就不排', () {
      expect(plan([sess(remindersEnabled: false)]).specs, isEmpty);
    });

    test('已经过去的时刻不补排', () {
      // 现在 07:00，08:00 的课提前 15 分钟 = 07:45，还没到；改成提前 120 分钟
      // 就是 06:00，已经过去了。
      expect(plan([sess(leadMinutes: 120)]).specs, isEmpty);
    });

    test('刚好等于「现在」的那一条也不排', () {
      // 07:00 的闹钟在 07:00 整同步进来，排了就是立刻炸一条，纯噪音。
      final p = plan([sess(startMinute: 8 * 60, leadMinutes: 60)], now: _now);
      expect(p.specs, isEmpty);
    });

    test('窗口外的课不排', () {
      final far = sess(date: DateTime(2026, 12, 1), ruleId: 9);
      expect(plan([far]).specs, isEmpty);
      // 把窗口放大到覆盖得到，就排上了 —— 证明拒绝的原因是窗口而不是别的。
      expect(
        plan([far], horizon: const Duration(days: 90)).specs,
        hasLength(1),
      );
    });

    test('超过上限时截断，并留下「被截断了」的痕迹', () {
      final many = [
        for (var i = 0; i < 8; i++)
          sess(date: DateTime(2026, 10, 13 + i), ruleId: 100 + i),
      ];
      final p = plan(many, maxCount: 3);
      expect(p.specs, hasLength(3));
      expect(p.totalInWindow, 8);
      expect(p.truncated, isTrue);
      // 留下的是最靠前的那三条，不是随便三条。
      expect(p.specs.last.fireAt, DateTime(2026, 10, 15, 7, 45));
    });
  });

  group('正文', () {
    test('钟点 + 地点 + 老师', () {
      final p = plan([sess(location: '第一教学楼303', teacher: '张老师')]);
      expect(p.specs.single.body, '08:00 开始 · 第一教学楼303 · 张老师');
    });

    test('没有地点和老师时不留下孤零零的分隔符', () {
      expect(plan([sess()]).specs.single.body, '08:00 开始');
    });
  });

  group('定位门控', () {
    const xiaomi = SavedPlace(name: '第一教学楼', lat: 27.8912, lng: 112.9212);

    test('「照常提醒」不带门控点，哪怕地点配好了', () {
      final p = plan([
        sess(location: '第一教学楼303'),
      ], settings: const AppSettings(places: [xiaomi]));
      expect(p.specs.single.gated, isFalse);
      expect(p.specs.single.nearby, isNull);
      expect(p.gatedCount, 0);
    });

    test('地点匹配得上，就带上坐标、半径和模式', () {
      final p = plan(
        [sess(location: '第一教学楼303')],
        settings: const AppSettings(
          nearbyMode: NearbyMode.skip,
          gateRadiusMeters: 250,
          places: [xiaomi],
        ),
      );
      final s = p.specs.single;
      expect(s.gated, isTrue);
      expect(s.gateLat, 27.8912);
      expect(s.gateLng, 112.9212);
      expect(s.gateRadiusMeters, 250);
      expect(p.gatedCount, 1);
    });

    test('静音模式的门控和「不提醒」一样要带坐标', () {
      // 这两态在原生侧的唯一区别就是 `nearby` 这个字符串。少写一次坐标，
      // 静音就会退化成「不做门控、照常响」—— 正好是用户想避免的那个。
      final p = plan(
        [sess(location: '第一教学楼303')],
        settings: const AppSettings(
          nearbyMode: NearbyMode.silent,
          places: [xiaomi],
        ),
      );
      final s = p.specs.single;
      expect(s.gated, isTrue);
      expect(s.nearby, NearbyMode.silent);
      expect(p.gatedCount, 1);
    });

    test('「不提醒」模式带的是 skip', () {
      final p = plan(
        [sess(location: '第一教学楼303')],
        settings: const AppSettings(
          nearbyMode: NearbyMode.skip,
          places: [xiaomi],
        ),
      );
      expect(p.specs.single.nearby, NearbyMode.skip);
    });

    test('地点对不上就不门控 —— 拿不准就提醒，不是拿不准就闭嘴', () {
      // 这条很重要：漏一次提醒用户会错过课，多响一次只是吵一下。
      final p = plan(
        [sess(location: '十教附楼-302')],
        settings: const AppSettings(
          nearbyMode: NearbyMode.skip,
          places: [xiaomi],
        ),
      );
      expect(p.specs.single.gated, isFalse);
      expect(
        p.specs.single.nearby,
        isNull,
        reason: '没有门控点时模式也该是 null，别让原生侧以为门控还在',
      );
      expect(p.specs, hasLength(1), reason: '仍然要提醒');
    });

    test('课程没有地点时不门控', () {
      final p = plan(
        [sess()],
        settings: const AppSettings(
          nearbyMode: NearbyMode.skip,
          places: [xiaomi],
        ),
      );
      expect(p.specs.single.gated, isFalse);
    });

    test('两个地点都命中时取名字长的那个', () {
      const vague = SavedPlace(name: '教学楼', lat: 1, lng: 1);
      const exact = SavedPlace(name: '第一教学楼', lat: 2, lng: 2);
      final p = plan(
        [sess(location: '第一教学楼303')],
        settings: const AppSettings(
          nearbyMode: NearbyMode.skip,
          places: [vague, exact],
        ),
      );
      // 声明顺序也故意反着来一次，确认不是「先到先得」。
      expect(p.specs.single.gateLat, 2);
    });
  });

  group('通知自动清除', () {
    test('默认不自动清除', () {
      expect(plan([sess()]).specs.single.timeoutMs, 0);
    });

    test('分钟换算成毫秒', () {
      final p = plan([
        sess(),
      ], settings: const AppSettings(notificationTimeoutMinutes: 30));
      expect(p.specs.single.timeoutMs, 30 * 60 * 1000);
    });

    test('不门控的提醒也带自动清除时间', () {
      // 自动清除和门控是两件无关的事。要是把它挂在门控那条分支里，
      // 关了门控的人会发现通知永远不消失，而且想不出跟门控有什么关系。
      final p = plan([
        sess(location: '没有配过的楼'),
      ], settings: const AppSettings(notificationTimeoutMinutes: 15));
      expect(p.specs.single.gated, isFalse);
      expect(p.specs.single.timeoutMs, 15 * 60 * 1000);
    });
  });

  group('重复提醒', () {
    const on = AppSettings(repeatReminders: true);

    test('默认不重复', () {
      expect(plan([sess()]).specs.single.repeatIntervalMs, 0);
      expect(plan([sess()]).specs.single.repeats, isFalse);
    });

    test('打开之后按设定的间隔重复', () {
      final p = plan([
        sess(),
      ], settings: const AppSettings(repeatReminders: true, repeatIntervalMinutes: 5));
      expect(p.specs.single.repeatIntervalMs, 5 * 60 * 1000);
    });

    test('终止时刻是上课那一刻，不是提醒那一刻', () {
      // 写成提醒时刻（07:45）的话，重复链在上课**之前**就断了 ——
      // 而 07:45 到 08:00 这段恰恰是「人正走在路上、最需要再催一次」的窗口。
      final s = plan([sess()], settings: on).specs.single;
      expect(s.classStartMs, DateTime(2026, 10, 13, 8, 0).millisecondsSinceEpoch);
      expect(
        s.classStartMs,
        greaterThan(s.fireAt.millisecondsSinceEpoch),
        reason: '终止时刻必须晚于提醒时刻，否则这条链一次都不会重复',
      );
    });

    test('提前 0 分钟时，终止时刻和提醒时刻重合', () {
      // 这条链会立刻结束 —— 是对的：上课那一刻才提醒，也没什么可重复的了。
      // 但两个值必须还是分开算出来的，不能靠「提醒时刻 + 提前量」反推。
      final s = plan([sess(leadMinutes: 0, remindersEnabled: true)], settings: on)
          .specs
          .single;
      expect(s.fireAt, DateTime(2026, 10, 13, 8, 0));
      expect(s.classStartMs, s.fireAt.millisecondsSinceEpoch);
    });

    test('平移过的课用平移后的上课时刻', () {
      // 解析结果里 3-4 节被整体后移 10 分钟。终止时刻要是取自课表上的原始钟点，
      // 重复链就会在真实上课时间之后还继续响 10 分钟。
      final s = plan([
        sess(startMinute: 10 * 60 + 10),
      ], settings: on).specs.single;
      expect(s.classStartMs, DateTime(2026, 10, 13, 10, 10).millisecondsSinceEpoch);
      expect(s.fireAt, DateTime(2026, 10, 13, 9, 55));
    });

    test('和自动清除是两件无关的事', () {
      final s = plan([
        sess(),
      ], settings: const AppSettings(
        repeatReminders: true,
        repeatIntervalMinutes: 2,
        notificationTimeoutMinutes: 1,
      )).specs.single;
      expect(s.timeoutMs, 60 * 1000);
      expect(s.repeatIntervalMs, 2 * 60 * 1000);
    });
  });

  group('三层优先级：单课 → 日程 → 全局', () {
    const xiaomi = SavedPlace(name: '第一教学楼', lat: 27.8912, lng: 112.9212);

    test('日程层没覆盖（表里根本没有这个 setId）就完全走全局', () {
      final p = plan([sess(setId: 7)], settings: const AppSettings());
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 7, 45));
    });

    test('日程层覆盖压过全局', () {
      final p = plan(
        [sess(setId: 7)],
        settings: AppSettings(
          defaultLeadMinutes: 15,
          setReminders: {7: block(defaultLeadMinutes: 10)},
        ),
      );
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 7, 50));
    });

    test('单课覆盖压过日程层', () {
      final p = plan(
        [sess(setId: 7, leadMinutes: 5)],
        settings: AppSettings(setReminders: {7: block(defaultLeadMinutes: 10)}),
      );
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 7, 55));
    });

    test('同一个 setId 之外的日程不受这份覆盖影响', () {
      // 这是「按日程」三个字的字面检验：9 号日程没有块，就该走全局。
      final p = plan(
        [
          sess(setId: 7, ruleId: 1),
          sess(setId: 9, ruleId: 2, title: '另一门'),
        ],
        settings: AppSettings(
          defaultLeadMinutes: 15,
          setReminders: {7: block(defaultLeadMinutes: 10)},
        ),
      );
      // 按 key 取而不是按下标：排出来的表是按 `fireAt` 排的，而这两条
      // **正好就是要验的那两个不同时刻** —— 拿下标去取，验的就成了排序。
      final byKey = {for (final s in p.specs) s.key: s};
      expect(
        byKey['rule:1@2026-10-13']!.fireAt,
        DateTime(2026, 10, 13, 7, 50),
        reason: '7 号有覆盖：提前 10 分钟',
      );
      expect(
        byKey['rule:2@2026-10-13']!.fireAt,
        DateTime(2026, 10, 13, 7, 45),
        reason: '9 号没有覆盖：照全局的 15 分钟',
      );
    });

    test('日程层关掉提醒，压过全局的打开', () {
      final p = plan(
        [sess(setId: 7)],
        settings: AppSettings(
          remindersEnabled: true,
          setReminders: {7: block(remindersEnabled: false)},
        ),
      );
      expect(p.specs, isEmpty);
    });

    test('打开日程层的开关，救不回被全局总闸关掉的提醒', () {
      // 全局是「这个功能还开不开」，不随日程变。日程里的那个开关管的是
      // 「这个日程要不要」，管不了总闸。
      final p = plan(
        [sess(setId: 7)],
        settings: AppSettings(
          remindersEnabled: false,
          setReminders: {7: block(remindersEnabled: true)},
        ),
      );
      expect(p.specs, isEmpty);
    });

    test('单课关掉提醒，压过日程层的打开', () {
      final p = plan(
        [sess(setId: 7, remindersEnabled: false)],
        settings: AppSettings(setReminders: {7: block(remindersEnabled: true)}),
      );
      expect(p.specs, isEmpty);
    });

    test('门控模式、半径、自动清除、重复都跟着日程层走', () {
      final p = plan(
        [sess(setId: 7, location: '第一教学楼303')],
        settings: AppSettings(
          // 全局这几项**故意设成相反的值**：只测日程层能被读到，还证明不了
          // 全局那份没有被误当成生效值。
          nearbyMode: NearbyMode.remind,
          gateRadiusMeters: 999,
          notificationTimeoutMinutes: 0,
          repeatReminders: false,
          places: const [xiaomi],
          setReminders: {
            7: block(
              nearbyMode: NearbyMode.silent,
              gateRadiusMeters: 250,
              notificationTimeoutMinutes: 30,
              repeatReminders: true,
              repeatIntervalMinutes: 3,
            ),
          },
        ),
      );
      final s = p.specs.single;
      expect(s.gated, isTrue, reason: '全局是不门控，日程层要门控 —— 门控得生效');
      expect(s.nearby, NearbyMode.silent);
      expect(s.gateRadiusMeters, 250);
      expect(s.timeoutMs, 30 * 60 * 1000);
      expect(s.repeatIntervalMs, 3 * 60 * 1000);
    });

    test('地点永远是全局的 —— 日程层带不了自己的地点表', () {
      // 日程层把模式设成 skip，但地点表是全局那份、里面根本没有这节课的楼，
      // 于是算不出门控点，退回「照常提醒」。这条钉的是「地点没跟着日程走」。
      final p = plan(
        [sess(setId: 7, location: '十教附楼-302')],
        settings: AppSettings(
          places: const [xiaomi],
          setReminders: {7: block(nearbyMode: NearbyMode.skip)},
        ),
      );
      expect(p.specs.single.gated, isFalse);
      expect(p.specs.single.nearby, isNull);
    });

    test('setId 为 0（不属于任何日程）时只能落到全局', () {
      // 生产路径上不该出现，但测试夹具和「还没落库的临时会话」会。
      // 这条钉的是 `setReminders` 里不会有一个 0 号块被它悄悄认领。
      final p = plan(
        [sess()],
        settings: AppSettings(
          defaultLeadMinutes: 15,
          setReminders: {0: block(defaultLeadMinutes: 1)},
        ),
      );
      expect(p.specs.single.fireAt, DateTime(2026, 10, 13, 7, 45));
    });
  });

  group('id 与 key', () {
    test('同一次排课永远算出同一个 id，且不是 0', () {
      final a = plan([sess()]).specs.single;
      final b = plan([sess()]).specs.single;
      expect(a.id, b.id);
      expect(a.id, isNot(0));
      expect(a.id, greaterThan(0), reason: 'requestCode 必须落在正的 int 里');
      expect(a.key, 'rule:1@2026-10-13');
    });

    test('不同的课算出不同的 id', () {
      final p = plan([
        sess(ruleId: 1, startMinute: 8 * 60),
        sess(ruleId: 2, startMinute: 10 * 60),
      ]);
      expect(p.specs[0].id, isNot(p.specs[1].id));
    });

    test('规则和单次事件不共用 id 空间', () {
      // 两者的主键各自自增，不区分来源的话「规则 3」和「单次事件 3」
      // 会撞成同一条，其中一节课就永远没有提醒。
      final a = plan([sess(ruleId: 3, oneOffId: null)]).specs.single;
      final b = plan([sess(title: '班会', ruleId: null, oneOffId: 3)])
          .specs
          .single;
      expect(a.id, isNot(b.id));
      expect(a.key, startsWith('rule:'));
      expect(b.key, startsWith('one:'));
    });

    test('id 不随标题和地点变化 —— 它只认「哪一次排课」', () {
      final a = plan([sess(title: '高数')]).specs.single;
      final b = plan([sess(title: '高等数学A(1)', location: '一教303')]).specs.single;
      expect(a.id, b.id, reason: '改了名字不该让旧闹钟变成取消不掉的幽灵');
    });
  });
}
