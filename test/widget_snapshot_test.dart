import 'package:classcal/core/theme/course_colors.dart';
import 'package:classcal/core/widget/widget_snapshot.dart';
import 'package:classcal/data/model/resolve.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 小组件快照的边界。
///
/// 这一层错了**桌面上看不出来**：一张过期的、或者漏了一节课的课表，和一张对的
/// 课表长得一模一样，都只是几个彩色方块。所以窗口边界、停课过滤、绝对时刻、
/// 颜色符号这几件事全部在这里钉死，不靠人眼盯桌面。
///
/// v2 多了一整类要钉的东西：**按日程分块**。块错了同样看不出来 ——
/// 一个被钉在「辅修」上的实例画出主修那一套的课，用户只会觉得「这个日程的课
/// 怎么怪怪的」，而没有任何东西会报错。
///
/// v3（本轮）多的是**逐日时间轴**：窗口从「今天起 9 天」变成「本周一起 5 整周」，
/// 于是「今天」从一个日期变成了一个**下标**。这一层同样看不见 —— 下标错一格，
/// 桌面上的卡片就整天地画着昨天或者明天的课，而那张卡片看起来一如既往地正常。

/// 2026-10-10 是周六，落在第 5 周（第 1 周周一 = 2026-09-07）。
/// 这一周的周一是 10/05，所以窗口是 10/05 起 35 天：到 11/08（第 35 天），
/// 零点表排到 11/09（排他上界）。今天在窗口里的下标是 **5**（周六）。
final _now = DateTime(2026, 10, 10, 14, 30);
final _theme = ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4));

/// 主修照：第 1 周周一 = 2026-09-07，今天是它的第 5 周。
final _setA = WidgetSetInfo(
  id: 1,
  name: '2026-2027-1',
  week1Monday: DateTime(2026, 9, 7),
);

/// 另一个日程，**第 1 周周一比 A 晚一周**。
///
/// 这个「晚一周」不是随手编的：它正是本轮所有麻烦的来源 —— 同一个 2026-10-06，
/// 在 A 里是第 5 周的周二，在 B 里是第 4 周的周二。任何按**周号**筛的做法在
/// 这两个日程合起来看时必然错位。
final _setB = WidgetSetInfo(
  id: 2,
  name: '辅修',
  week1Monday: DateTime(2026, 9, 14),
);

ResolvedSession _s({
  required DateTime date,
  int startMinute = 8 * 60,
  int endMinute = 9 * 60 + 40,
  String title = '高等数学A(1)',
  String location = '第一教学楼303',
  int week = 5,
  bool cancelled = false,
  int? startPeriod = 1,
  int? endPeriod = 2,
  String? colorHex,
  int setId = 1,
}) =>
    ResolvedSession(
      date: date,
      startMinute: startMinute,
      endMinute: endMinute,
      title: title,
      location: location,
      weekday: date.weekday,
      week: week,
      cancelled: cancelled,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      colorHex: colorHex,
      setId: setId,
    );

WidgetSnapshot _build(
  List<ResolvedSession> sessions, {
  List<WidgetSetInfo>? sets,
  int activeSetId = 1,
}) =>
    buildWidgetSnapshot(
      sessions: sessions,
      theme: _theme,
      now: _now,
      sets: sets ?? [_setA],
      activeSetId: activeSetId,
    );

/// 按 id 找一块。找不到就抛 —— 一条静默返回 null 的查找会把「块没了」写成
/// 「断言通过」。
WidgetSetBlock _blockOf(WidgetSnapshot snap, int id) => snap.blocks
    .firstWhere((b) => b.id == id, orElse: () => throw StateError('没有 id=$id 的块'));

WidgetSetBlock _overviewOf(WidgetSnapshot snap) => _blockOf(snap, kOverviewBlockId);

/// [WidgetSnapshot.dayIndexOf] 在测试里的等价物：now 落在窗口的第几格。
int _windowIndex(WidgetSnapshot snap) {
  final now = _now.millisecondsSinceEpoch;
  for (var i = snap.dayStartsMs.length - 1; i >= 0; i--) {
    if (now >= snap.dayStartsMs[i]) return i;
  }
  return -1;
}

/// 这一块这一次该画的那一周的**八个**零点（最后一个是排他上界）。
///
/// **Kotlin 侧 `gridFor` 在测试里的等价物。** 刻意照抄那一段的形状：先把 now
/// 翻成窗口下标（除 7 就是第几周 —— 窗口锚在周一，所以那个除法成立），再看这一块
/// 那一周的标题是不是空串：空串说明今天不在这个日程的学期里，退回块上那份兜底周。
///
/// 这里要**自己**算下标，而正因为如此这条测才是有效的：它证明「Dart 把整条时间轴
/// 摊平之后，查的那一侧只需要区间比较和查表」。日历运算在这份快照生成时就已经
/// 做完了，不在读它的那一侧。
List<int> _gridWeek(WidgetSnapshot snap, WidgetSetBlock block) {
  final weekIdx = _windowIndex(snap) ~/ 7;
  if (block.weekTitles[weekIdx].isNotEmpty) {
    final from = weekIdx * 7;
    return snap.dayStartsMs.sublist(from, from + 8);
  }
  // 兜底周只有七个零点，没有第八格 —— 右端补一天，和 Kotlin 侧同一条写法。
  return [
    ...block.fallbackWeekMs,
    block.fallbackWeekMs.last + const Duration(days: 1).inMilliseconds,
  ];
}

/// **Kotlin 侧 `sessionsBetween(block, grid.from, grid.end)` 在测试里的等价物。**
///
/// 两件事合起来才筛得对：日程对得上（`accepts`），日期落在**这一块要画的那一周**
/// 里。后者是这一段的关键 —— 每一块画的是哪一周由窗口的下标决定，不再挂在块上。
List<WidgetSession> _inWeek(WidgetSnapshot snap, WidgetSetBlock block) {
  final week = _gridWeek(snap, block);
  return [
    for (final s in snap.sessions)
      if ((block.id == kOverviewBlockId || s.setId == block.id) &&
          s.startAtMs >= week.first &&
          s.startAtMs < week.last)
        s,
  ];
}

/// 和 `_argb` 同一条换算，用来在测试里表达期望值。
int _signed(int v) => v > 0x7FFFFFFF ? v - 0x100000000 : v;

void main() {
  group('窗口边界', () {
    test('窗口 = 本周一起 5 整周，两边都封口', () {
      final lastDay = DateTime(2026, 10, 5).add(const Duration(days: 34));
      final snap = _build([
        // 上周日：在窗口之前（窗口从 10/05 周一开始）
        _s(date: DateTime(2026, 10, 4)),
        // 本周一：窗口第一天，要收
        _s(date: DateTime(2026, 10, 5), title: '第一天'),
        // 明天（周日）：要收
        _s(date: DateTime(2026, 10, 11), title: '明天'),
        // 窗口内最后一天（第 35 天，11/08 周日）：要收
        _s(date: lastDay, title: '最后一天'),
        // 再往后一天：正好是 windowEnd，**不收**
        _s(date: lastDay.add(const Duration(days: 1)), title: '刚好出界'),
      ]);

      final titles = snap.sessions.map((s) => s.title).toList();
      expect(titles, ['第一天', '明天', '最后一天']);
    });

    test('窗口锚在周一而不是今天 —— 周网格要画整周，左边不能缺半张', () {
      // 今天周六，但如果窗口从今天起算，周一到周五就没数据可画了。
      final snap = _build([_s(date: DateTime(2026, 10, 5), title: '周一那节')]);
      expect(snap.sessions, hasLength(1));
    });

    test('停课的条目被滤掉 —— 解析结果里它们是保留的', () {
      // 不滤的话，桌面上会给一节已经停掉的课留一个彩色块，
      // 而用户明明在 App 里把它停掉了，只会觉得「小组件没更新」。
      final snap = _build([
        _s(date: DateTime(2026, 10, 12), title: '照上'),
        _s(date: DateTime(2026, 10, 12), title: '停课', cancelled: true),
      ]);
      expect(snap.sessions.map((s) => s.title), ['照上']);
    });

    test('结果按开始时刻升序 —— 原生侧靠这个顺序直接取「下一节」', () {
      final snap = _build([
        _s(date: DateTime(2026, 10, 13), startMinute: 14 * 60, title: '下午'),
        _s(date: DateTime(2026, 10, 12), startMinute: 8 * 60, title: '周一早'),
        _s(date: DateTime(2026, 10, 12), startMinute: 10 * 60, title: '周一晚'),
      ]);
      expect(snap.sessions.map((s) => s.title), ['周一早', '周一晚', '下午']);
    });

    test('同一时刻的两条要有确定先后 —— 按日程、再按标题', () {
      // Dart 的 `List.sort` 不是稳定排序，而「谁在前」决定了小尺寸卡片上画的是
      // 哪一节。不加这两级 tiebreak，两个日程里撞在同一时间的课会让卡片每次
      // 刷新翻一次面 —— 而那看起来完全正常。
      ResolvedSession at(String title, int setId) => _s(
            date: DateTime(2026, 10, 12),
            startMinute: 8 * 60,
            title: title,
            setId: setId,
          );
      final input = [at('乙', 2), at('甲', 1), at('丙', 2)];
      final forward = _build(input).sessions.map((s) => s.title).toList();
      final backward =
          _build(input.reversed.toList()).sessions.map((s) => s.title).toList();
      expect(forward, backward);
      // 先按日程（甲是 1 号日程，排在 2 号的丙乙前面），再按标题的字面序。
      expect(forward, ['甲', '丙', '乙']);
    });

    test('一条课都没有时不崩，窗口和边界照样成立', () {
      final snap = _build(const []);
      expect(snap.sessions, isEmpty);
      expect(snap.boundariesMs, isNotEmpty, reason: '零点边界还在，小组件仍要翻页');
    });
  });

  group('绝对时刻与现成的标签', () {
    test('startAtMs 是本地墙上时刻，和日期+分钟数算出来的一致', () {
      final snap = _build([_s(date: DateTime(2026, 10, 12))]);
      final s = snap.sessions.single;
      expect(s.startAtMs, DateTime(2026, 10, 12, 8).millisecondsSinceEpoch);
      expect(s.endAtMs, DateTime(2026, 10, 12, 9, 40).millisecondsSinceEpoch);
    });

    test('时间、星期、日期、节次都是格式化好的字符串', () {
      final snap = _build([_s(date: DateTime(2026, 10, 12))]);
      final s = snap.sessions.single;
      expect(s.startLabel, '08:00');
      expect(s.endLabel, '09:40');
      expect(s.dayLabel, '周一');
      expect(s.dateLabel, '10/12');
      expect(s.periodLabel, '第一二节');
    });

    test('单次事件没有节次，periodLabel 为空串而不是 null', () {
      // 空串让布局侧少画一行；null 会让 Kotlin 的 setTextViewText 拿到 null。
      final snap = _build([
        _s(date: DateTime(2026, 10, 12), startPeriod: null, endPeriod: null),
      ]);
      expect(snap.sessions.single.periodLabel, '');
    });

    test('每条事件都带着它属于哪个日程', () {
      final snap = _build([
        _s(date: DateTime(2026, 10, 12), title: '主修课', setId: 1),
        _s(date: DateTime(2026, 10, 12), startMinute: 10 * 60, title: '辅修课', setId: 2),
      ]);
      final byTitle = {for (final s in snap.sessions) s.title: s};
      expect(byTitle['主修课']!.setId, 1);
      expect(byTitle['辅修课']!.setId, 2);
    });
  });

  group('逐日时间轴：今天是一个下标', () {
    test('零点表是本周一起连续 36 格，最后一格是排他上界', () {
      // **这一条是本轮的核心契约。** 原生侧判「今天 / 明天」全靠这张表：
      // 拿 now 从后往前比出下标 t，t 就是今天、t+1 就是明天。所以
      // 1) 必须是**本地零点**（Dart 算好，原生不做日历运算），
      // 2) 必须**连续**（少一天，它后面每一天的下标都会错 1），
      // 3) 最后一格必须是「再下一天的零点」而不是某一天本身 ——
      //    它是第 35 天的排他上界，也是最后一周网格精确的右端。
      final snap = _build(const []);
      expect(snap.dayStartsMs, hasLength(kWidgetHorizonDays + 1));
      expect(snap.dayStartsMs.first, DateTime(2026, 10, 5).millisecondsSinceEpoch);
      expect(
        snap.dayStartsMs.last,
        DateTime(2026, 10, 5).add(const Duration(days: 35)).millisecondsSinceEpoch,
      );
      for (var i = 1; i < snap.dayStartsMs.length; i++) {
        expect(
          snap.dayStartsMs[i] - snap.dayStartsMs[i - 1],
          const Duration(days: 1).inMilliseconds,
          reason: '第 $i 格和前一格之间的间隔不是一天 —— 后面每一天的下标都会错',
        );
      }
    });

    test('dayLabels 和零点表的前 35 项一一对应，是**绝对**星期', () {
      // 「今天 · 周三」里那个「周三」就是从这里取的。刻意不是「今天」这种相对
      // 措辞：相对措辞是由**取哪一项**表达的，写在字符串里就跟着下标一起错。
      final snap = _build(const []);
      expect(snap.dayLabels, hasLength(kWidgetHorizonDays));
      expect(snap.dayLabels.first, '周一', reason: '窗口从周一起');
      expect(snap.dayLabels[5], '周六', reason: '今天（10/10 周六）在窗口第 6 天');
      expect(snap.dayLabels[6], '周日');
      expect(snap.dayLabels[7], '周一', reason: '下一周重新从周一数');
    });

    test('窗口锚在周一、不跟着 now 平移 —— 今天在窗口里的位置才是变的那个', () {
      // 改之前窗口是从今天起的 9 天，所以「今天」恒是下标 0。现在锚在周一起，
      // 于是**不同的一天有不同的下标，而同一天生成的两份快照下标相同**。
      final lateNight = buildWidgetSnapshot(
        sessions: const [],
        theme: _theme,
        now: DateTime(2026, 10, 10, 23, 55),
      );
      final earlyMorning = buildWidgetSnapshot(
        sessions: const [],
        theme: _theme,
        now: DateTime(2026, 10, 11, 0, 5),
      );
      // 差 10 分钟、跨了一天，但**窗口一格都没动**（它们在同一周里）。
      expect(earlyMorning.dayStartsMs, lateNight.dayStartsMs);
      expect(earlyMorning.dayLabels, lateNight.dayLabels);
      // 挪的是「今天」：跨越零点之后 t 从 5 变成 6，而那张表还是同一张。
      // 这正是「过了零点卡片自己翻页」的全部机制。
      expect(lateNight.dayStartsMs[5], DateTime(2026, 10, 10).millisecondsSinceEpoch);
      expect(earlyMorning.dayStartsMs[6], DateTime(2026, 10, 11).millisecondsSinceEpoch);
    });

    test('发一个生成时的本地 UTC 偏移 —— 换时区要靠它判过期', () {
      // 窗口要 35 天才用完，不补这一条的话，飞到另一个时区之后「哪节课算今天」
      // 会偏几个小时，而那看起来完全正常。两边都只是读一次当前偏移。
      final snap = _build(const []);
      expect(snap.tzOffsetMinutes, _now.timeZoneOffset.inMinutes);
    });
  });

  group('块：每周标题和兜底周', () {
    test('每个日程一块，末尾永远是总览块', () {
      final snap = _build(const [], sets: [_setA, _setB]);
      expect(snap.blocks.map((b) => b.id), [1, 2, kOverviewBlockId]);
    });

    test('一个日程都没有时也有一块，就是总览 —— 空课表该说「今天没有课」', () {
      // 少了这一块，原生侧就要写「没有块」那条支路，而它只有一句可画：
      // 「打开 ClassCal 更新」。用户刚装上 App 看到那句话会以为坏了。
      final snap = _build(const [], sets: const []);
      expect(snap.blocks.map((b) => b.id), [kOverviewBlockId]);
      expect(_overviewOf(snap).fallbackWeekMs, hasLength(7));
    });

    test('weekTitles 和窗口的 5 周一一对应，周号各算各的', () {
      // 同一个今天在 A 是第 5 周、在 B 是第 4 周；而窗口是同一个，所以第 k 格
      // 指向的是**同一个日历周**，变的只有编号。这两个事实必须同时成立。
      final snap = _build(const [], sets: [_setA, _setB]);
      final a = _blockOf(snap, 1);
      final b = _blockOf(snap, 2);
      expect(a.weekTitles, hasLength(kWidgetHorizonDays ~/ 7));
      expect(a.weekTitles[0], '第 5 周 · 10/5–10/11');
      expect(b.weekTitles[0], '第 4 周 · 10/5–10/11');
      expect(a.weekTitles[1], '第 6 周 · 10/12–10/18');
      expect(b.weekTitles[1], '第 5 周 · 10/12–10/18');
    });

    test('总览块的标题只有日期区间，**没有「第 N 周」**', () {
      // 它不是某个日程，没有自己的周号。硬写一个就是编的。
      final snap = _build(const [], sets: [_setA, _setB], activeSetId: 1);
      final ov = _overviewOf(snap);
      expect(ov.weekTitles[0], '10/5–10/11');
      expect(ov.weekTitles[0], isNot(contains('周')));
      expect(ov.weekTitles, hasLength(kWidgetHorizonDays ~/ 7));
    });

    test('总览块的标题和「当前是谁」无关 —— 窗口对每一块都是同一份', () {
      // 改之前这里断言的是「总览借当前那套的周号」。v3 之后**没有周号可借了**：
      // 窗口只有一份（锚在本周一），总览的标题一直是日期区间。所以这条改成钉住
      // 「换 activeSetId 不影响总览画出来的周」—— 那正是「按日期筛、不按周号筛」
      // 那条老性质在新结构里的样子。
      for (final active in [1, 2]) {
        final snap = _build(const [], sets: [_setA, _setB], activeSetId: active);
        expect(_overviewOf(snap).weekTitles[0], '10/5–10/11');
      }
    });

    test('总览块借当前那套的**锚点** —— 只有兜底周用得上它', () {
      // 总览自己不构成一个学期，所以「今天不在学期里」对它无从判断（它的标题
      // 永远是日期区间）。它那份兜底周于是按「全部日程里最早的那一节课」算；
      // **一条课都没有**时才落到当前这一套的第 1 周 —— 这就是 `activeSetId`
      // 还能影响到总览的**唯一一处**，也正是 `_focusSet` 那条「退到第一个」
      // 兜底唯一能被观察到的地方。
      final a = WidgetSetInfo(id: 1, name: 'A', week1Monday: DateTime(2026, 9, 7));
      final b = WidgetSetInfo(id: 2, name: 'B', week1Monday: DateTime(2026, 9, 14));

      expect(_overviewOf(_build(const [], sets: [a, b], activeSetId: 1))
          .fallbackWeekMs.first, DateTime(2026, 9, 7).millisecondsSinceEpoch);
      expect(_overviewOf(_build(const [], sets: [a, b], activeSetId: 2))
          .fallbackWeekMs.first, DateTime(2026, 9, 14).millisecondsSinceEpoch);
      // 指向一个不存在的日程时退到第一个 —— 不崩、不空。
      expect(_overviewOf(_build(const [], sets: [a, b], activeSetId: 99))
          .fallbackWeekMs.first, DateTime(2026, 9, 7).millisecondsSinceEpoch);
    });

    test('每块的 name 非空，总览块叫「总览」', () {
      // 小组件上那条日程名信息条直接读它 —— name 为空等于那一栏凭空消失，
      // 而用户看到的只是「我打开的那个开关好像没用」。
      final snap = _build(const [], sets: [_setA, _setB]);
      for (final b in snap.blocks) {
        expect(b.name, isNotEmpty, reason: 'id=${b.id} 的块没有名字');
      }
      expect(_overviewOf(snap).name, '总览');
      expect(_blockOf(snap, 2).name, '辅修');
    });

    test('网格的行数来自作息表，和事件的 gridRow 是同一张表', () {
      final snap = _build(const []);
      expect(_blockOf(snap, 1).gridRows, 5, reason: '一天五个大节');
    });

    test('今天不在学期内时标题是空串，兜底周指向第一节课那一周', () {
      // 一张空格子比「往前翻几周的真课」难看得多 —— 这正是 fallback 的意义。
      // 空串不是「没算出来」而是一个**有含义的值**：Kotlin 侧 `gridFor` 拿它
      // 当判据决定退回兜底周，`weekView` 拿它当「退回『本周课表』」的判据。
      // 所以这里钉的是「空」本身，不是某一句话。
      //
      // 用第 3 周而不是第 1 周，是为了让这条断言**真的**在测 fallback：
      // 写第 1 周的话，它和「没有 fallback 时的兜底值 1」分不出来。
      final future = WidgetSetInfo(
        id: 3,
        name: '下学期',
        week1Monday: DateTime(2026, 11, 2),
      );
      final snap = _build(
        [_s(date: DateTime(2026, 11, 17), week: 3, setId: 3, title: '第三周那节')],
        sets: [future],
        activeSetId: 3,
      );
      final b = _blockOf(snap, 3);
      // 今天在第 0 周那一格，而那一格算不出周号（今天早于第 1 周）—— 这就是
      // Kotlin 侧 `gridFor` 采用的那条判据。
      expect(b.weekTitles[0], '');
      // 但窗口有 5 周，尾巴上那一格（11/02）**落在**这个日程的第 1 周里，
      // 所以后面几格是有标题的。这不矛盾：判据只看今天所在的那一格。
      expect(b.weekTitles[4], startsWith('第 1 周 · '));
      expect(b.fallbackWeekMs.first, DateTime(2026, 11, 16).millisecondsSinceEpoch,
          reason: '但网格该画那节课所在的周');
      expect(b.fallbackWeekMs, hasLength(7));
    });

    test('一个日程一节课都没有时兜底周退到第 1 周，不崩', () {
      final snap = _build(const [], sets: [_setA, _setB]);
      // B 一条课都没有、但今天在它的学期里（第 4 周），所以走的是窗口那一支，
      // 兜底周根本不会被读到 —— 它照样要是良构的七个零点。
      expect(_blockOf(snap, 2).weekTitles[0], startsWith('第 4 周'));
      expect(_blockOf(snap, 2).fallbackWeekMs, hasLength(7));

      final blank = _build(
        const [],
        sets: [WidgetSetInfo(id: 9, name: '空的', week1Monday: DateTime(2026, 11, 2))],
        activeSetId: 9,
      );
      expect(
        _blockOf(blank, 9).fallbackWeekMs.first,
        DateTime(2026, 11, 2).millisecondsSinceEpoch,
        reason: '一处可退的都没有时退到第 1 周那个周一',
      );
    });
  });

  group('块：按日期筛，不按周号筛', () {
    test('同一个日期区间在起点不同的两个日程里各自筛出自己那些事件', () {
      // **这是本轮的核心回归测试。** 2026-10-06 在 A 里是第 5 周的周二，
      // 在 B 里是第 4 周的周二。按周号筛的话，B 那节课永远不会出现在总览里
      // （或者更糟：A 的课被当成 B 的）。
      final snap = _build(
        [
          _s(date: DateTime(2026, 10, 6), title: 'A 的周二', week: 5, setId: 1),
          _s(date: DateTime(2026, 10, 6), title: 'B 的周二', week: 4, setId: 2),
        ],
        sets: [_setA, _setB],
        activeSetId: 1,
      );

      final ov = _inWeek(snap, _overviewOf(snap));
      expect(ov.map((s) => s.title), containsAll(['A 的周二', 'B 的周二']));

      // 各自的块只收自己那些 —— 这一条靠的是 `setId`，不是日期。
      expect(_inWeek(snap, _blockOf(snap, 1)).map((s) => s.title), ['A 的周二']);
      expect(_inWeek(snap, _blockOf(snap, 2)).map((s) => s.title), ['B 的周二']);
    });

    test('总览块借的是 A 那一周的日期，B 在别的日期的课不进来', () {
      // 总览不是「所有事件的集合」，是「当前这一周的合并视图」。B 那条 10/20
      // 的课在它自己的第 6 周，但不在总览借来的 10/5–10/11 里。
      final snap = _build(
        [
          _s(date: DateTime(2026, 10, 6), title: '本周', setId: 1),
          _s(date: DateTime(2026, 10, 20), title: '两周后', week: 6, setId: 2),
        ],
        sets: [_setA, _setB],
        activeSetId: 1,
      );
      expect(_inWeek(snap, _overviewOf(snap)).map((s) => s.title), ['本周']);
    });

    test('画的那一周的七个零点足以定出「落在哪一列」，不需要事件的 weekday', () {
      // 列号 = 拿 startAtMs 跟这一周的七个零点从后往前比出来的。总览那一块里
      // 混着几个日程的事件，它们的周号各不相同 —— 只有绝对日期是共有的。
      final snap = _build(
        [_s(date: DateTime(2026, 10, 8), title: '周四那节', setId: 2)],
        sets: [_setA, _setB],
        activeSetId: 1,
      );
      final ov = _overviewOf(snap);
      final s = _inWeek(snap, ov).single;
      final days = _gridWeek(snap, ov);
      var col = -1;
      for (var i = days.length - 2; i >= 0; i--) {
        if (s.startAtMs >= days[i]) {
          col = i;
          break;
        }
      }
      expect(col, 3, reason: '周四 = 第 4 列（0-based 3）');
    });
  });

  group('颜色', () {
    test('发的是已经解析好的有符号 32 位 ARGB', () {
      final snap = _build([_s(date: DateTime(2026, 10, 12))]);
      final s = snap.sessions.single;
      final expected = _signed(courseColor('高等数学A(1)').toARGB32());
      expect(s.color, expected);
      // 调色板全是不透明的深色，最高位一定是 1 —— 所以有符号之后必然是负数。
      // 不减那个 2^32 的话，Kotlin 的 Int 会拿到一个溢出的值，颜色直接错掉。
      expect(s.color, lessThan(0));
      expect(s.color, greaterThanOrEqualTo(-0x80000000));
    });

    test('手动指定的颜色优先，和 App 里一致', () {
      final snap = _build([
        _s(date: DateTime(2026, 10, 12), colorHex: '#123456'),
      ]);
      expect(snap.sessions.single.color, _signed(0xFF123456));
    });

    test('主题色也由这一侧解析好，原生不碰 Material 角色表', () {
      final snap = _build(const []);
      expect(snap.theme.surface, _signed(_theme.surface.toARGB32()));
      expect(snap.theme.accent, _signed(_theme.primary.toARGB32()));
      expect(snap.theme.secondary, _signed(_theme.onSurfaceVariant.toARGB32()));
    });
  });

  group('边界表', () {
    test('含每节课的开始、结束，和窗口内每个本地零点', () {
      final snap = _build([_s(date: DateTime(2026, 10, 12))]);
      final bounds = snap.boundariesMs.toSet();
      expect(bounds, contains(DateTime(2026, 10, 12, 8).millisecondsSinceEpoch));
      expect(bounds, contains(DateTime(2026, 10, 12, 9, 40).millisecondsSinceEpoch));
      // 窗口 = 10/05 起 35 天，零点从 10/05 排到 11/09（含最后一个，它是排他上界）。
      expect(bounds, contains(DateTime(2026, 10, 5).millisecondsSinceEpoch));
      expect(bounds, contains(DateTime(2026, 11, 9).millisecondsSinceEpoch));
    });

    test('升序且去重 —— 原生只做 firstOrNull { it > now }', () {
      final snap = _build([
        _s(date: DateTime(2026, 10, 12)),
        // 同一时刻的另一节课：不能出现两个相同的边界值。
        _s(date: DateTime(2026, 10, 12), title: '另一节'),
      ]);
      final list = snap.boundariesMs;
      expect(list.toSet(), hasLength(list.length), reason: '有重复项');
      for (var i = 1; i < list.length; i++) {
        expect(list[i], greaterThan(list[i - 1]), reason: '不是严格升序');
      }
    });

    test('列表为空时仍有零点边界 —— 否则小组件永远停在旧的一天', () {
      final snap = _build(const []);
      // **窗口里每一个零点都要在**（36 个）。少一个，那一段跨零点的时刻就没有
      // 闹钟叫醒原生侧 —— 而表现只是「卡片偶尔不翻页」，撞不上就发现不了。
      expect(snap.boundariesMs.length, greaterThanOrEqualTo(kWidgetHorizonDays + 1));
    });
  });

  group('缩写', () {
    test('每节课都带一个缩写，快照发的是算好的那个', () {
      // 原生侧不认「标题 → 缩写」这套规则，它只画快照里那个串。所以这一侧
      // 漏算或者算错，桌面上的格子就会写别的字，而没有任何东西会报错。
      final snap = _build([
        _s(date: DateTime(2026, 10, 12), title: '高等数学A(1)'),
        _s(date: DateTime(2026, 10, 12), startMinute: 14 * 60, title: '离散数学(1)'),
      ]);
      final byTitle = {for (final s in snap.sessions) s.title: s};
      expect(byTitle['高等数学A(1)']!.abbr, '高数');
      expect(byTitle['离散数学(1)']!.abbr, '离散');
    });

    test('用户自定义的缩写盖过预置的', () {
      final snap = buildWidgetSnapshot(
        sessions: [_s(date: DateTime(2026, 10, 12), title: '高等数学A(1)')],
        theme: _theme,
        now: _now,
        abbrOverrides: const {'高等数学A(1)': '数分'},
      );
      expect(snap.sessions.single.abbr, '数分');
    });

    test('改了缩写的人不会因为「没改的课」而丢掉预置更新', () {
      // 覆盖表里只有用户真改过的那几门。要是建表时把预置值抄一份进来，
      // 预置表以后给某门课换了个更好的叫法，用户永远拿不到。
      final snap = buildWidgetSnapshot(
        sessions: [
          _s(date: DateTime(2026, 10, 12), title: '高等数学A(1)'),
          _s(date: DateTime(2026, 10, 12), startMinute: 14 * 60, title: '离散数学(1)'),
        ],
        theme: _theme,
        now: _now,
        abbrOverrides: const {'高等数学A(1)': '数分'},
      );
      final byTitle = {for (final s in snap.sessions) s.title: s};
      expect(byTitle['高等数学A(1)']!.abbr, '数分');
      expect(byTitle['离散数学(1)']!.abbr, '离散', reason: '没改过的课也要有缩写');
    });

    test('缩写也进了 JSON —— 原生侧读的就是这个键', () {
      final snap = _build([_s(date: DateTime(2026, 10, 12), title: '高等数学A(1)')]);
      final session = (snap.toJson()['sessions']! as List).single as Map;
      expect(session['abbr'], '高数');
    });
  });

  group('周网格的行号', () {
    test('行号按作息表查，和 App 里的网格一致', () {
      // 「第一二节」= 第 0 行，「第五六节」= 第 2 行。原生侧照抄这两个数字画，
      // 自己算的话就要在 Kotlin 里再抄一份作息表。
      final snap = _build([
        _s(date: DateTime(2026, 10, 12), startPeriod: 5, endPeriod: 6, title: '下午'),
        _s(date: DateTime(2026, 10, 13), startPeriod: 1, endPeriod: 2, title: '早上'),
      ]);
      final byTitle = {for (final s in snap.sessions) s.title: s};
      expect(byTitle['早上']!.gridRow, 0);
      expect(byTitle['下午']!.gridRow, 2);
    });

    test('1-4 节连堂跨两行 —— 不跨的话网格上会缺一块', () {
      final snap = _build([
        _s(date: DateTime(2026, 10, 12), startPeriod: 1, endPeriod: 4),
      ]);
      final s = snap.sessions.single;
      expect(s.gridRow, 0);
      expect(s.gridRowSpan, 2);
    });

    test('单次事件按钟点落到最近的大节', () {
      // 没有节次，但 14:30 明确落在第五六节里。
      final snap = _build([
        _s(
          date: DateTime(2026, 10, 12),
          startMinute: 14 * 60 + 30,
          endMinute: 16 * 60,
          startPeriod: null,
          endPeriod: null,
        ),
      ]);
      expect(snap.sessions.single.gridRow, 2);
      expect(snap.sessions.single.gridRowSpan, 1);
    });

    test('作息时间之外的单次事件行号是 -1，而不是硬塞进第一行', () {
      // 硬塞的话，一节 06:00 的补课会画在「第一二节」的位置上，看起来就像
      // 早上 8 点有课。列表里照常有它，只是网格里没有它的位置。
      final snap = _build([
        _s(
          date: DateTime(2026, 10, 12),
          startMinute: 6 * 60,
          endMinute: 7 * 60,
          startPeriod: null,
          endPeriod: null,
        ),
      ]);
      expect(snap.sessions.single.gridRow, -1);
    });

    test('今天星期几**不再发一个数** —— 网格那一列由逐日表的下标决定', () {
      // 改之前这里断言的是 `todayWeekday == 6`，而网格拿它减一当列号。那条路
      // 有个隐形的假设：画的**就是**今天所在的那一周。开学前画的是兜底周，
      // 假设就不成立 —— 那时候会在一块不是本周的网格上标出一列「今天」。
      // 现在列号是「今天这一刻落在这七个零点里的哪一格」，画的是别的一周时
      // 它自己会返回 -1（Kotlin 侧 `GridWeek.columnOf`）。
      final snap = _build(const []);
      expect(snap.dayLabels[5], '周六', reason: '今天在窗口第 6 格，那一格是周六');
      expect(snap.toJson().keys, isNot(contains('todayWeekday')));
    });
  });

  group('序列化', () {
    test('键名和结构固定 —— 原生侧按这些名字读', () {
      final snap = _build([_s(date: DateTime(2026, 10, 12))], sets: [_setA, _setB]);
      final json = snap.toJson();
      expect(json['version'], kWidgetSnapshotVersion);
      expect((json['dayStartsMs']! as List), hasLength(kWidgetHorizonDays + 1));
      expect((json['dayLabels']! as List), hasLength(kWidgetHorizonDays));
      expect(json['tzOffsetMinutes'], _now.timeZoneOffset.inMinutes);
      expect(json['activeSetId'], 1);
      expect(json.keys, containsAll([
        'theme', 'layout', 'sessions', 'boundariesMs', 'dayStartsMs',
        'dayLabels', 'tzOffsetMinutes', 'blocks', 'activeSetId',
      ]));

      // 「今天」从一个**日期**（`today: {y,m,d}`）换成了一条**时间轴**。
      // 留着那几个整数就是留着「快照只在这一天有效」那个结论 —— 而它正是
      // 本轮要拆掉的东西。所以这里反过来钉住它们**不在**。
      expect(json.keys, isNot(contains('today')));
      expect(json.keys, isNot(contains('todayTitle')));
      expect(json.keys, isNot(contains('tomorrowTitle')));
      expect(json.keys, isNot(contains('todayWeekday')));

      final session = (json['sessions']! as List).single as Map<String, Object?>;
      expect(session.keys, {
        'startAtMs', 'endAtMs', 'setId', 'weekday', 'title', 'location',
        'startLabel', 'endLabel', 'dayLabel', 'dateLabel', 'periodLabel',
        'color', 'onColor', 'abbr', 'gridRow', 'gridRowSpan',
      });

      // 周次 / 标题 / 网格坐标**不再在顶层** —— 它们搬进了块里。留在顶层就等于
      // 留一个「哪一套的周次」说不清的全局值，而它必然对其中一套是错的。
      expect(json.keys, isNot(contains('gridWeek')));
      expect(json.keys, isNot(contains('gridRows')));
    });

    test('块的键名和结构固定', () {
      final snap = _build(const [], sets: [_setA]);
      final block =
          (snap.toJson()['blocks']! as List).first as Map<String, Object?>;
      expect(block.keys, {
        'id', 'name', 'weekTitles', 'gridRows', 'fallbackWeekMs',
      });
      expect((block['weekTitles']! as List), hasLength(kWidgetHorizonDays ~/ 7));
      expect((block['fallbackWeekMs']! as List), hasLength(7));
    });

    test('总览块的 id 是 -2，不是 -1', () {
      // -1 已经被 `CalendarSetData.unsavedId` 占用表示「还没落库」，
      // 两个概念共用一个哨兵迟早出事。Kotlin 侧的常量由契约测试对着。
      expect(kOverviewBlockId, -2);
    });

    test('layout 的档位阈值进了快照 —— 「多大算大」只有这一处定义', () {
      final snap = _build(const []);
      expect(snap.layout.toJson(), {
        'smallMaxHeightDp': 110,
        'largeMinWidthDp': 250,
        'largeMinHeightDp': 180,
        'maxListRows': 8,
      });
    });

    test('阈值必须落在真实尺寸的缝里', () {
      // 这一条是这张表**存在的原因**。启动器报回来的尺寸是「格数 × 格子尺寸」，
      // 不是 `appwidget-provider` 里写的 `minWidth/minHeight` ——
      // 一个 2×1 拿到的大约是 190×84dp，一个 4×2 大约 380×170dp。
      // 阈值写在这些实测值**中间的空档**里才分得对；写在某一档的值上，
      // 那一档就永远命中不了（原来 `smallMaxWidthDp = 180` 就是这么坏的：
      // 190 > 180，4 列网格上的 2×1 从来就没被当成过「小」）。
      const l = WidgetLayout();

      // 1 格高 ≈ 84dp，2 格高 ≈ 170dp
      expect(l.smallMaxHeightDp, greaterThan(90));
      expect(l.smallMaxHeightDp, lessThan(150));

      // 2 格宽 ≈ 190dp，4 格宽 ≈ 380dp
      expect(l.largeMinWidthDp, greaterThan(195));
      expect(l.largeMinWidthDp, lessThan(370));

      // 2 格高 ≈ 170dp，4 格高 ≈ 380dp
      expect(l.largeMinHeightDp, greaterThan(175));
      expect(l.largeMinHeightDp, lessThan(350));
    });
  });
}
