import 'dart:io';

import 'package:classcal/core/widget/widget_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart 与 Kotlin 之间关于桌面小组件的契约。
///
/// 和 `reminder_channel_test.dart` 同一个道理：**跨语言的不一致一条也不会报错**。
///
/// - 通道名打错 → 方法永远返回 null；
/// - 字段名对不上 → 桌面上那张卡片画的是兜底值（白底、`-1` 行号）；
/// - 方法少实现一个 → Dart 收到 `MissingPluginException`，然后被
///   `MethodChannelHomeWidgetBridge._invoke` **静默收敛成「这个平台没有这个能力」**。
///
/// 三者的表现都跟「功能没做」一模一样，靠人眼审代码审不出来。所以这里直接读
/// 两边的源码来核对 —— 笨，但笨得恰到好处。
const _k = 'android/app/src/main/kotlin/com/jingjunyu/classcal/';

const _dartBridge = 'lib/core/platform/home_widget.dart';
const _dartSnapshot = 'lib/core/widget/widget_snapshot.dart';
const _kotlinBridge = '${_k}WidgetBridge.kt';
const _kotlinSnapshot = '${_k}WidgetSnapshot.kt';
const _kotlinStore = '${_k}WidgetStore.kt';
const _kotlinRenderer = '${_k}WidgetRenderer.kt';
const _kotlinAlarms = '${_k}WidgetAlarms.kt';
const _kotlinPainter = '${_k}WidgetPainter.kt';
const _manifest = 'android/app/src/main/AndroidManifest.xml';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '找不到 $path');
  return file.readAsStringSync();
}

/// 抠出一个类的**类体**（含类头，不含前面的文档注释）。
///
/// 用「从类头到下一个顶格的类/对象」来切，而不是靠缩进或括号配对：那两种写法
/// 在某次重排之后都会静默失配，而失配的表现是「一个键都没扫到」，看起来像
/// 测试自己错了 —— `reminder_channel_test.dart` 里那条注释记的就是这个坑。
String _dartClassBody(String name) {
  final src = _read(_dartSnapshot);
  final start = src.indexOf('class $name {');
  expect(start, isNonNegative, reason: 'Dart 侧没找到 class $name');
  // Dart 侧的类体以顶格的 `}` 收尾；嵌套的那些收尾都带缩进。
  final end = src.indexOf('\n}\n', start);
  expect(end, isNonNegative, reason: 'class $name 没有顶格的收尾大括号');
  return src.substring(start, end);
}

/// `class` 也在边界里，不只是 `data class` —— 文件里有一个普通的
/// `class GridWeek`，而它的七个零点**不是** JSON 键。漏掉这一条的话，
/// `WidgetSetBlock` 那段会一路吞到下一个 `data class`，把 GridWeek 圈进去 ——
/// 表现是「扫出来的键集合里多了几个」，指向完全错误的方向。
String _kotlinClassBody(String name) {
  final src = _read(_kotlinSnapshot);
  final start = src.indexOf('data class $name(');
  expect(start, isNonNegative, reason: 'Kotlin 侧没找到 data class $name');
  final next = RegExp(r'\n(data class |class |object |enum )')
      .firstMatch(src.substring(start + 1));
  return src.substring(start, next == null ? src.length : start + 1 + next.start);
}

/// 一段源码里所有 `'name':` 形式的键名（Dart 的 map 字面量）。
Set<String> _dartKeys(String body) => RegExp(r"'([A-Za-z]+)':")
    .allMatches(body)
    .map((m) => m.group(1)!)
    .toSet();

/// 一段源码里所有 `"name"` 形式的键名（Kotlin 的 `optInt("…")` / `put("…")`）。
/// 去掉大写开头的（那是 `JSONObject`、`RGB_565` 这类类型名和常量）。
Set<String> _kotlinKeys(String body) => RegExp(r'"([A-Za-z]+)"')
    .allMatches(body)
    .map((m) => m.group(1)!)
    .where((k) => k[0] == k[0].toLowerCase())
    .toSet();

/// 去掉源码里的注释。
///
/// **凡是要「断言某个写法不存在」的扫描，都得先剥注释**：注释里会*提到*被禁的
/// 写法（为的是解释为什么不用它），不剥的话测试会把说明文字判成违规，
/// 而那种失败指向完全错误的方向。布局白名单那条已经因为这个红过一次，
/// 缩写这一版撞的是同一堵墙（注释里写了 `MAX_SIDE_PX = 500` 的来历）。
///
/// 简单粗暴地按 `//` 和 `/* */` 切，不区分字符串字面量 —— 这两个文件里
/// 没有含 `//` 的字符串，真出现了再换成正经的扫描。
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('通道契约', () {
    test('通道名两边一致', () {
      final dart = RegExp(r"channelName\s*=\s*'([^']+)'")
          .firstMatch(_read(_dartBridge))
          ?.group(1);
      final kotlin = RegExp(r'CHANNEL\s*=\s*"([^"]+)"')
          .firstMatch(_read(_kotlinBridge))
          ?.group(1);

      expect(dart, isNotNull, reason: 'Dart 侧没找到 channelName');
      expect(kotlin, isNotNull, reason: 'Kotlin 侧没找到 CHANNEL');
      expect(dart, kotlin);
      expect(dart, 'com.jingjunyu.classcal/widget');
    });

    test('Dart 调的方法，Kotlin 全都实现了（反过来也一样）', () {
      // `.*?` 而不是 `[^>]*`：泛型参数里还套着泛型
      // （`_invoke<Map<Object?, Object?>>`），一个 `[^>]*` 会在第一个 `>` 处停下，
      // 于是那些方法被漏掉 —— 而漏掉的表现是「Kotlin 实现了但 Dart 不调」，
      // 指向完全错误的方向。
      final dart = RegExp(r"_invoke<.*?>\(\s*'([A-Za-z]+)'")
          .allMatches(_read(_dartBridge))
          .map((m) => m.group(1)!)
          .toSet();

      final handler = RegExp(r'when \(call\.method\)\s*\{(.*?)\n\s*else ->',
              dotAll: true)
          .firstMatch(_read(_kotlinBridge));
      expect(handler, isNotNull, reason: 'Kotlin 侧没找到 when (call.method) 分支');
      final kotlin = RegExp(r'"([A-Za-z]+)"\s*->')
          .allMatches(handler!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      expect(dart, isNotEmpty, reason: 'Dart 侧一个方法都没扫到，正则多半失效了');
      expect(kotlin, isNotEmpty, reason: 'Kotlin 侧一个分支都没扫到');
      expect(dart.difference(kotlin), isEmpty,
          reason: 'Dart 在调这些方法，Kotlin 没实现 —— 会静默返回 null，'
              '表现和「这个平台不支持」一模一样');
      expect(kotlin.difference(dart), isEmpty,
          reason: 'Kotlin 实现了这些方法，Dart 从来不调');
    });

    test('参数名两边一致', () {
      // **加新参数时必须加进这个 alternation** —— 不加的话它根本扫不到那个名字，
      // 于是「Dart 发 `setKey`、Kotlin 读 `scope`」这种错永远不会红，
      // 只会表现为「配置页怎么改，桌面上都是总览」。
      final dartArgs =
          RegExp(r"'(snapshot|id|content|setKey|showSetName|widthDp|heightDp)':")
          .allMatches(_read(_dartBridge))
          .map((m) => m.group(1)!)
          .toSet();
      final kotlinArgs = RegExp(r'call\.argument<.*?>\("([A-Za-z]+)"\)')
          .allMatches(_read(_kotlinBridge))
          .map((m) => m.group(1)!)
          .toSet();

      expect(dartArgs, isNotEmpty);
      expect(dartArgs, kotlinArgs,
          reason: 'Dart 传的参数和 Kotlin 读的名字对不上 —— 读到的是 null');
    });

    test('内容枚举名两边逐字一致', () {
      // 不只是「通道参数」的问题：`WidgetStore.config_<id>` 里存的就是这些名字，
      // 所以错一个字，那个实例的配置就永远落回默认值 —— 用户选了「今天 + 明天」,
      // 桌面上画的是下一节课。
      final enumBody = RegExp(r'enum WidgetContent \{(.*?)\n\}', dotAll: true)
          .firstMatch(_read(_dartBridge))!
          .group(1)!;
      final dartNames = RegExp(r'^  ([a-zA-Z]+),', multiLine: true)
          .allMatches(enumBody)
          .map((m) => m.group(1)!)
          .toSet();

      final kotlinNames = RegExp(r'CONTENT_[A-Z_]+\s*=\s*"([A-Za-z]+)"')
          .allMatches(_read(_kotlinRenderer))
          .map((m) => m.group(1)!)
          .toSet();

      expect(dartNames, {'auto', 'next', 'today', 'todayTomorrow', 'week'});
      expect(kotlinNames, dartNames);
    });
  });

  group('快照的 JSON 契约', () {
    // 这一组是**双向**的：Dart 写出去的键，Kotlin 要能读到（`fromJson`），
    // 也要能写回来（`toJson` —— 快照会被原样落盘再读回，漏一个键会让
    // 「读回来之后那个字段没了」）。
    void expectSameKeys(String name, Set<String> expected) {
      expect(_dartKeys(_dartClassBody(name)), expected,
          reason: '$name：Dart 侧写出去的键变了');
      final kotlin = _kotlinClassBody(name);
      expect(_kotlinKeys(kotlin), expected,
          reason: '$name：Kotlin 侧读/写的键和 Dart 对不上');
    }

    test('一节课', () {
      // v2 用 `setId` 换掉了 `week`：原生侧改按**日期区间**筛之后，
      // 「这条在第几周」在那边一个读者都没有了，而留着一个没人读的字段
      // 迟早会被谁当成「筛选依据」用起来 —— 那正是本轮要杜绝的错法。
      expectSameKeys('WidgetSession', {
        'startAtMs', 'endAtMs', 'setId', 'weekday', 'title', 'location',
        'startLabel', 'endLabel', 'dayLabel', 'dateLabel', 'periodLabel',
        'color', 'onColor', 'abbr', 'gridRow', 'gridRowSpan',
      });
    });

    test('一块日程', () {
      // v3 换掉了这一块的三个键：`currentWeek` / `gridWeek` 删了（周号在原生侧
      // 一个读者都没有），`weekTitle` 变成 `weekTitles`（5 周各一条），
      // `gridDayStartsMs` 收窄成 `fallbackWeekMs`（今天不在学期里时才画的那一周）。
      //
      // 少一个键的表现是轻的（Kotlin 那里是空表，退回兜底），但
      // `fallbackWeekMs` 兜不住的是**语义**：它从「画的那一周」变成了
      // 「没有别的可画时才画的那一周」。留着旧名字就会有人拿它当默认的网格周 ——
      // 而学期中那样画出来的是别的一周，只在开学前才看得出来。
      expectSameKeys('WidgetSetBlock', {
        'id', 'name', 'weekTitles', 'gridRows', 'fallbackWeekMs',
      });
    });

    test('主题', () {
      expectSameKeys('WidgetTheme', {
        'surface', 'onSurface', 'secondary', 'accent', 'onAccent',
      });
    });

    test('档位阈值', () {
      expectSameKeys('WidgetLayout', {
        'smallMaxHeightDp', 'largeMinWidthDp', 'largeMinHeightDp', 'maxListRows',
      });
    });

    test('档位阈值的**默认值**两边也一致', () {
      // 上面那条只比键名。默认值也要对上：快照里没有 `layout` 这一块时
      // （老版本 App 写下的快照、或者手工塞进去的），Kotlin 用的是**自己的**
      // 默认值 —— 两边不一致的话行为会随「快照是新的还是旧的」而变，
      // 而这两种情况在其他任何地方都看不出来。
      final dartDefaults = Map.fromEntries(
        RegExp(r'this\.(\w+) = (\d+),')
            .allMatches(_dartClassBody('WidgetLayout'))
            .map((m) => MapEntry(m.group(1)!, int.parse(m.group(2)!)),
        ),
      );
      final kotlinDefaults = Map.fromEntries(
        RegExp(r'val (\w+): Int = (\d+),')
            .allMatches(_kotlinClassBody('WidgetLayout'))
            .map((m) => MapEntry(m.group(1)!, int.parse(m.group(2)!)),
        ),
      );
      expect(dartDefaults, isNotEmpty, reason: 'Dart 侧一个默认值都没扫到');
      expect(kotlinDefaults, dartDefaults);
    });

    test('快照顶层', () {
      // `currentWeek` / `weekTitle` / `gridWeek` / `gridRows` **不在这一层** ——
      // 它们搬进了 `blocks`。留在顶层就等于留一个「这是哪一套的周次」说不清的
      // 全局值，而它必然对其中一个日程是错的。
      //
      // v3 又删掉了五个键：`today`（嵌套的 `y`/`m`/`d`）和 `todayTitle` /
      // `tomorrowTitle` / `todayWeekday`。它们五个合起来表达的是**生成那一刻的
      // 今天**，而本轮要拆的正是这个结论 —— 只要「今天」还是一个钉死的日期，
      // 过了零点那份快照就只能是错的。取而代之的是 `dayStartsMs`（36 格逐日表）
      // 和 `dayLabels`（35 个绝对星期），于是「今天」变成一个**算出来的下标**。
      expectSameKeys('WidgetSnapshot', {
        'version', 'generatedAtMs', 'dayStartsMs', 'dayLabels',
        'tzOffsetMinutes', 'theme', 'layout', 'sessions', 'boundariesMs',
        'activeSetId', 'blocks',
      });
    });

    test('结构版本号两边一致 —— 不一致会让桌面永远画「打开 ClassCal 更新」', () {
      final dart = RegExp(r'kWidgetSnapshotVersion = (\d+)')
          .firstMatch(_read(_dartSnapshot))
          ?.group(1);
      final kotlin = RegExp(r'SUPPORTED_VERSION = (\d+)')
          .firstMatch(_read(_kotlinStore))
          ?.group(1);
      expect(dart, isNotNull, reason: 'Dart 侧没找到 kWidgetSnapshotVersion');
      expect(dart, kotlin);
      // v2 从 1 提到 2（块），v3 从 2 提到 3（逐日时间轴）。两个数字停在上一版
      // 的话，这条测试照旧是绿的，而桌面上会拿新 Dart 写出的快照去喂一个不认识
      // 新结构的旧 Kotlin —— 读出来的是「今天是 0 年 0 月 0 日」那种东西。
      expect(dart, kWidgetSnapshotVersion.toString());
      expect(dart, '3');
    });

    test('总览块的哨兵 id 两边一致', () {
      // 对不上时 Kotlin 会去找一个**不存在**的块，然后退到 `activeSetId`
      // 那一块 —— 表现是「配成总览的实例画的是某一个日程」，而且不报错。
      final dart = RegExp(r'kOverviewBlockId = (-?\d+)')
          .firstMatch(_read(_dartSnapshot))
          ?.group(1);
      final kotlin = RegExp(r'OVERVIEW_ID = (-?\d+)')
          .firstMatch(_read(_kotlinSnapshot))
          ?.group(1);
      expect(dart, isNotNull, reason: 'Dart 侧没找到 kOverviewBlockId');
      expect(kotlin, isNotNull, reason: 'Kotlin 侧没找到 OVERVIEW_ID');
      expect(dart, kotlin);
      expect(dart, '-2');
    });

    test('`set:<id>` 前缀和那两个关键字两边一致', () {
      // 这一串过的是 shared_preferences：Dart 写、Kotlin 读。错一个字符的
      // 表现是「配置页选好日程，桌面上没反应」，而且它**永远不会**报错。
      final ref = _read('lib/core/settings/schedule_ref.dart');
      final store = _read(_kotlinStore);
      for (final key in ['overview', 'follow']) {
        final dart = RegExp("$key = '([^']+)'").firstMatch(ref)?.group(1);
        final kotlin =
            RegExp('SCOPE_${key.toUpperCase()} = "([^"]+)"').firstMatch(store)?.group(1);
        expect(dart, isNotNull, reason: 'Dart 侧没找到 ScheduleRef.$key');
        expect(kotlin, isNotNull, reason: 'Kotlin 侧没找到 SCOPE_${key.toUpperCase()}');
        expect(dart, kotlin);
      }
      expect(RegExp(r"ofSet\(int id\) => 'set:\$id'").hasMatch(ref), isTrue,
          reason: 'ScheduleRef.ofSet 的形状变了');
      expect(RegExp(r'SCOPE_SET_PREFIX = "set:"').hasMatch(store), isTrue,
          reason: 'Kotlin 侧的 set: 前缀变了');
    });

    test('真的能往返：Dart 实际写出来的每个键，契约里都列了', () {
      // 上一条是扫源码，这一条跑一遍 Dart 侧的实际输出。源码扫对了但序列化
      // 写错了（比如 `toJson` 里漏了一行）时，只有这条会红。
      final snap = buildWidgetSnapshot(
        sessions: const [],
        theme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        now: DateTime(2026, 10, 10, 14, 30),
        sets: [
          WidgetSetInfo(
            id: 1,
            name: '2026-2027-1',
            week1Monday: DateTime(2026, 9, 7),
          ),
        ],
        activeSetId: 1,
      );
      final json = snap.toJson();
      // 顶层不再有嵌套的日期对象（v2 的 `today: {y,m,d}`），所以两边必须
      // **一模一样**，多一个少一个都算。
      expect(json.keys.toSet(), _dartKeys(_dartClassBody('WidgetSnapshot')));
      // 36 个零点必须是**整数毫秒**：Kotlin 用 `getLong` 读，写成字符串或者
      // 精度不够的浮点会让那边拿到 0 —— 于是整条时间轴报废，卡片永远停在
      // 「打开 ClassCal 更新」。
      expect(json['dayStartsMs'], everyElement(isA<int>()));
      expect((json['dayStartsMs']! as List<int>).length, kWidgetHorizonDays + 1);
      expect((json['dayStartsMs']! as List<int>).first,
          DateTime(2026, 10, 5).millisecondsSinceEpoch,
          reason: '窗口锚在**本周一**，不是今天');
      expect((json['dayStartsMs']! as List<int>).last,
          DateTime(2026, 11, 9).millisecondsSinceEpoch,
          reason: '最后一格是第 35 天的排他上界');
      // 星期标签和零点表**等长减一**：多一个少一个都会让「今天 · 周三」错位一格，
      // 而错位之后每一天都还长得正常。
      expect((json['dayLabels']! as List).length, kWidgetHorizonDays);
      expect((json['dayLabels']! as List).first, '周一');
      // 时区偏移是 `getOffset(now)/60000` 比的那个数（Kotlin 用 `optInt` 读）。
      expect(json['tzOffsetMinutes'], isA<int>());

      // 块那一份也要真的写出来：`fallbackWeekMs` 同样是 `getLong` 读的
      // **整数毫秒的七个值** —— 少一个、或者写成浮点，开学前那张网格会叠在
      // 周一那一列。
      final blocks = json['blocks']! as List;
      expect(blocks, hasLength(2), reason: '一个日程 + 一块总览');
      final block = blocks.first as Map<String, Object?>;
      expect(block['name'], '2026-2027-1');
      expect((block['weekTitles']! as List).length, kWidgetHorizonDays ~/ 7);
      expect((block['weekTitles']! as List).first, startsWith('第 5 周 · '));
      expect(block['fallbackWeekMs'], everyElement(isA<int>()));
      expect(block['fallbackWeekMs'], hasLength(7));
      expect((blocks.last as Map)['id'], kOverviewBlockId);
      expect((blocks.last as Map)['weekTitles'],
          everyElement(isA<String>()),
          reason: '总览块的标题只有日期区间，照样是五个字符串');
    });
  });

  group('注册', () {
    test('provider 和两个接收器都在 manifest 里', () {
      final manifest = _read(_manifest);
      for (final cls in [
        'ClasscalWidgetProvider',
        'WidgetTickReceiver',
        'WidgetBootReceiver',
      ]) {
        expect(manifest, contains('android:name=".$cls"'),
            reason: '$cls 没在 manifest 里注册 —— 系统根本不会叫它');
      }
      expect(manifest, contains('android:name="android.appwidget.provider"'),
          reason: '少了这份 meta-data，桌面「小组件」列表里找不到 ClassCal');
      expect(manifest, contains('@xml/classcal_widget_info'));
    });

    test('小组件的 action 和提醒的**不同** —— 否则会互相顶掉', () {
      // 两个模块的 request code 空间是重叠的（提醒那边是哈希出来的任意 31 位，
      // 这边是固定的 0）。`PendingIntent` 的相等性把 action 算在内，所以只要
      // action 不同就彻底隔开了 —— 而「一样」不会报错，只会让某一方静默失灵。
      final widget =
          RegExp(r'ACTION_TICK\s*=\s*"([^"]+)"').firstMatch(_read(_kotlinAlarms))?.group(1);
      final reminder = RegExp(r'ACTION_FIRE\s*=\s*"([^"]+)"')
          .firstMatch(_read('${_k}ReminderAlarms.kt'))
          ?.group(1);
      expect(widget, isNotNull);
      expect(reminder, isNotNull);
      expect(widget, isNot(reminder));
    });
  });

  group('渲染的三条底线', () {
    // 这三条各自对应一种**看起来完全正常但是错的**失败。全部发生在 Kotlin 里，
    // Dart 测不到，所以只能扫源码。

    test('快照盖不住 now 时不许照画 —— 但判据是**窗口**，不是「今天是几号」', () {
      // 这一条以前断言的是「`isStale` 必须和本机的年月日比」。**方向翻过来了**，
      // 因为它比的那个东西正是 bug 本身：拿「今天是几号」当判据，等于宣布
      // 「这份快照只在生成的那一天有效」，于是过了零点的每一次重画都被拦下来画
      // 一句「打开 ClassCal 更新」—— 闹钟一直有响，是这道闸门把卡片判死的。
      //
      // 现在判的是「now 在不在窗口里」，所以这里钉的是那两次区间比较。
      final renderer = _read(_kotlinRenderer);
      expect(
        RegExp(r'if \(snapshot == null \|\| snapshot\.isStale\(nowMs\)\)')
            .hasMatch(renderer),
        isTrue,
        reason: '渲染入口没有把「没有快照」和「快照过期」放在同一条兜底路径上',
      );
      final snapshot = _read(_kotlinSnapshot);
      for (final field in ['Calendar.YEAR', 'Calendar.MONTH', 'Calendar.DAY_OF_MONTH']) {
        expect(snapshot, isNot(contains(field)),
            reason: 'isStale 又回去比本机的年月日了 —— 那会把跨天判成「过期」，'
                '桌面上那张卡片就又要靠每天打开一次 App 才活');
      }
      expect(RegExp(r'val first = dayStartsMs\.firstOrNull\(\) \?: return true')
              .hasMatch(snapshot),
          isTrue,
          reason: '窗口的左端没有比较 —— 快照太旧时会被当成还能用');
      expect(RegExp(r'val last = dayStartsMs\.lastOrNull\(\) \?: return true')
              .hasMatch(snapshot),
          isTrue,
          reason: '**空表要当过期。** 用 `first()` / `last()` 的话，键缺失时它会抛，'
              '而渲染路径上的 catch 会把异常吞掉 —— 表现是卡片静默冻在上一帧，'
              '比画一句提示更难查');
      expect(RegExp(r'nowMs < first \|\| nowMs >= last').hasMatch(snapshot), isTrue,
          reason: '窗口边界不是这个比法。`>= last` 而不是 `> last`：最后一格是'
              '**排他上界**，写成 `> last` 会多算一天，而那天是真上课的日子');
      // 换了时区也要判过期：窗口里的零点是在旧时区算出来的，不纠正的话
      // 往后「哪节课算今天」会偏几个小时 —— 而那看起来完全正常。
      expect(RegExp(r'TimeZone\.getDefault\(\)\.getOffset\(nowMs\)').hasMatch(snapshot),
          isTrue,
          reason: 'isStale 没有比时区偏移 —— 跨时区之后要等 35 天窗口用尽才会纠正');
    });

    test('位图只有周网格一张，尺寸按字节封顶', () {
      // `RemoteViews` 的位图走 Binder 那条 1 MB 的共享事务缓冲区，而它是
      // **整个进程共享**的。多一张 4×4 的 ARGB_8888 就是 4.5 MB —— 直接炸。
      final bitmapCalls = RegExp(r'\.(setImageViewBitmap|setImageBitmap)\(')
          .allMatches(_read(_kotlinRenderer))
          .length;
      expect(bitmapCalls, 1,
          reason: '除了周网格之外还有别的地方在传位图，迟早撞上 TransactionTooLarge');

      final painter = _stripComments(_read(_kotlinPainter));
      expect(painter, contains('RGB_565'),
          reason: '周网格位图不是 565 —— 每像素多占一倍，正好卡在预算线上');
      // **按字节封顶，不按像素。** 按「长边 500 px」封顶是拿错了尺子：同一个
      // 像素数，扁宽的和接近正方形的放大倍数差得很远，而受约束的量是字节。
      expect(painter, contains('MAX_BITMAP_BYTES'),
          reason: '位图没有按字节封顶 —— 换成按像素封顶会在扁宽的卡片上浪费预算');
      expect(RegExp(r'MAX_SIDE_PX').hasMatch(painter), isFalse,
          reason: '按像素封顶的写法回来了');

      // 上限本身要真的落在 1 MB 那条线下面，留出余量给同一次事务里的其它 action。
      final bytes = int.parse(
        RegExp(r'MAX_BITMAP_BYTES = ([\d_]+)').firstMatch(painter)!
            .group(1)!
            .replaceAll('_', ''),
      );
      expect(bytes, lessThan(1024 * 1024),
          reason: '位图预算已经顶到 Binder 那条 1 MB 的线上了');
      expect(bytes, lessThanOrEqualTo(700 * 1024),
          reason: '留的余量不够 —— 那条缓冲区是整个进程共享的，卡着上限做会偶发地炸');
    });

    test('网格里的缩写会缩到放得下，缩不下就不画', () {
      // 加了缩写之后，位图里就**必须**有字 —— 前一版是刻意不画的，理由是
      // 「放大之后必糊」。那个理由还成立，只是结论换掉了：一张认不出课的
      // 课表等于没有。所以这里钉的不是「画不画」，而是**画得放不下怎么办**。
      final painter = _stripComments(_read(_kotlinPainter));
      expect(painter, contains('drawText'), reason: '网格里不画缩写了');
      expect(painter, contains('session.abbr'),
          reason: '画的不是快照里那个缩写 —— 缩写要么来自别处，要么根本没读');
      expect(painter, contains('session.onColor'),
          reason: '文字没用课程色配套的前景色，深色块上会看不见');
      expect(painter, contains('measureText'),
          reason: '字号没有实测宽度 —— 中英文混排（`C语言`）按字数估会溢出格子');
      // 缩到底还放不下时**不画**：一个字被压成一条糊线，比一个干净的色块更糟，
      // 而且会让人以为渲染坏了。
      expect(painter, contains('MIN_TEXT_PX'),
          reason: '没有字号下限 —— 极端尺寸下会把字压成一条线');
      expect(
        RegExp(r'if \(size < MIN_TEXT_PX\) continue').hasMatch(painter),
        isTrue,
        reason: '算出了字号下限却没有据此跳过，那个下限就是白写的',
      );
    });

    test('「下一节课」问的是那节课在哪一天，**两边都问同一个下标**', () {
      // 这条断言的方向也翻过来了。
      //
      // 它以前禁止渲染器里出现 `dayIndexOf(nowMs)`，理由是「那个答案永远是 0，
      // 所以拿它当条件的那一支恒真、带星期的那一支是死代码」。那在当时是对的：
      // 「今天是第 0 天」在旧结构里是定义出来的，不是算出来的。
      //
      // 现在窗口锚在周一起，「今天是第几格」是**真的算出来的**（今天可能是 0..34
      // 里任何一格），所以它恰恰是这一支该用的那个数。所以现在钉的是两句话：
      // 两边的下标都得问出来，而且**是同一个来源**。
      final renderer = _read(_kotlinRenderer);
      expect(RegExp(r'dayIndexOf\(nowMs\)').hasMatch(renderer), isTrue,
          reason: '没有算「今天是窗口里的第几格」—— 那「这节是不是今天的」就无从判起');
      expect(RegExp(r'dayIndexOf\(session\.startAtMs\)').hasMatch(renderer),
          isTrue,
          reason: '这一支问的不是「这节课在哪一天」');
      expect(RegExp(r'dayIndex == t').hasMatch(renderer), isTrue,
          reason: '比的两个下标不是同一个来源（该是 `t` 和这条自己的 dayIndex）');
      // 更远的那一支必须带上日期：窗口有 5 周，光写「周三」无从判断是哪个周三。
      expect(renderer, contains('session.dateLabel'),
          reason: '比明天更远的课没有带上日期 —— 一个无从定位的「周三」比不写更坏');
      // 搜索范围要夹在一周之内，否则 2×1 那张卡片会在放假时报一节三周后的课。
      expect(RegExp(r'currentOrNext\(block, nowMs, untilMs = weekEnd\)').hasMatch(renderer),
          isTrue,
          reason: '「下一节课」的搜索范围没有上界 —— 35 天窗口里会报出很远的课');
    });

    test('「小」这一档按高度判，不按宽度', () {
      // 这条挡的是一个**只会安静地错**的设计错误：判据用了宽度，而
      // `Width() < 180` 在 4 列网格上永远不会成立（2×1 报回来约 190dp）。
      // 表现是「小尺寸的小组件画成了今天的课单，挤成一团」——
      // 没有人会去查阈值，只会觉得这个小组件做得糙。
      final renderer = _read(_kotlinRenderer);
      expect(
        RegExp(r'heightDp < layout\.smallMaxHeightDp').hasMatch(renderer),
        isTrue,
        reason: '「小」这一档不是按高度判的',
      );
      expect(RegExp(r'smallMaxWidthDp').hasMatch(renderer), isFalse,
          reason: '按宽度判「小」的那个写法回来了 —— 它在 4 列网格上永不命中');
    });

    test('列表行数按高度算，不是一个固定的行数', () {
      // 写死行数的后果是「今天 + 明天」多出一个分组标题就把最后一行连同
      // 「还有 N 节」一起顶出卡片 —— 而那句话正是为了不让用户以为课就
      // 这几节才写的。填不满的后果是多出来的行露一半，看起来像渲染坏了。
      final renderer = _read(_kotlinRenderer);
      expect(renderer, contains('rowsThatFit'),
          reason: '列表不再按高度算行数了');
      expect(RegExp(r'heightDp - chrome').hasMatch(renderer), isTrue,
          reason: '算行数时没有把卡片高度减掉标题占的那块');
      // 每一组都要分到行，否则「今天 + 明天」里第二组连标题都不出现。
      expect(renderer, contains('allowance'),
          reason: '预算又变成第一组吃光了');
    });

    test('布局里只许用 RemoteViews 放行的控件', () {
      // `RemoteViews.apply()` 在 inflate 之前会装一个 `LayoutInflater.Filter`，
      // 只放行带 `@RemoteView` 标注的类。`android.view.View` **没有**这个标注，
      // 所以 `<View android:id="@+id/bar" .../>` 这种看起来最无辜的写法会在
      // **运行期**抛 `InflateException: Class not allowed to be inflated`。
      //
      // 这个坑已经踩过一次（两条课程色竖线），而且它编译通过、`dart test` 也不报，
      // 只有在真机上才炸 —— 更坏的情况是只在预览里炸，桌面上那张卡片同时是坏的
      // 而你以为只是预览的问题。所以在这里钉死。
      const allowed = {
        'FrameLayout', 'GridLayout', 'LinearLayout', 'RelativeLayout',
        'StackView', 'AdapterViewFlipper', 'ViewFlipper', 'GridView',
        'ListView', 'AnalogClock', 'Button', 'Chronometer', 'ImageButton',
        'ImageView', 'ProgressBar', 'TextView', 'ViewStub',
      };
      // `merge` / `include` / `requestFocus` 不是控件，是 inflate 指令。
      const directives = {'merge', 'include', 'requestFocus'};

      final layouts = Directory('android/app/src/main/res/layout')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.xml'))
          .toList();
      expect(layouts, isNotEmpty, reason: '一个布局文件都没找到');

      final offenders = <String>[];
      for (final f in layouts) {
        final name = f.path.split(RegExp(r'[\\/]')).last;
        // 先剥掉注释：注释里会**提到**被禁的标签名（解释为什么不能用），
        // 不剥的话测试会把说明文字当成违规，而那种失败指向完全错误的方向。
        final src = f
            .readAsStringSync()
            .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
        for (final m in RegExp(r'<([A-Za-z][\w.]*)').allMatches(src)) {
          final tag = m.group(1)!;
          if (directives.contains(tag)) continue;
          // 带包的写全名（`android.widget.TextView`），取最后一段比
          if (allowed.contains(tag.split('.').last)) continue;
          offenders.add('$name → <$tag>');
        }
      }
      expect(offenders, isEmpty,
          reason: '这些控件不在 RemoteViews 的白名单里，桌面上会 inflate 失败：'
              '${offenders.join('、')}');
    });

    test('块的坐标是唯一来源 —— 布局不再从快照顶层读周次和网格行数', () {
      // v2 把 `weekTitle` / `gridWeek` / `gridRows` 从顶层搬进了块。
      // 如果哪里还留着读顶层那份的代码，它就是**错的**：顶层那份用的是
      // 「当前日程」的周次，而这个实例配的可能是别的日程。
      //
      // 表现是「被钉在辅修上的实例，标题写着主修的『第 5 周』」——
      // 日期和课对不上，但看起来完全正常。
      final renderer = _stripComments(_read(_kotlinRenderer));
      // `(?!Of)`：要禁的是**顶层那个字段**，而 `snapshot.weekTitleOf(block, …)`
      // 恰恰是从块上取的那一个（它名字里带着 `weekTitle`，所以不加这一条会误报）。
      expect(RegExp(r'snapshot\.weekTitle(?!Of)').hasMatch(renderer), isFalse,
          reason: '还在从快照顶层读周次标题 —— 那是「当前日程」的，不是这个实例的');
      // v3 起标题是**五条**，按今天在窗口里的第几周去取 —— 取哪一条也得先算下标，
      // 所以这里同时钉住「从块上取」和「用算出来的下标取」。
      expect(RegExp(r'weekTitleOf\(block, weekIdx\)').hasMatch(renderer), isTrue,
          reason: '周次标题不是从块上、按算出来的周下标取的');
      expect(RegExp(r'weekIndexOf\(nowMs\)').hasMatch(renderer), isTrue,
          reason: '没有算今天在窗口里属于第几周');

      final painter = _stripComments(_read(_kotlinPainter));
      expect(RegExp(r'snapshot\.gridRows|snapshot\.gridWeek').hasMatch(painter),
          isFalse,
          reason: '还在从快照顶层读网格坐标');
      expect(painter, contains('block.gridRows'),
          reason: '网格的行数不是从块上取的');
      // 列号必须按**这一周那七个零点**算，不能退回 `s.weekday` ——
      // 总览那一块里混着几个日程的事件，它们的周号各不相同，
      // 只有绝对日期是共有的。
      //
      // v3 改的是「那七个零点从哪来」：以前挂在块上（`block.dayIndexOf`），
      // 现在由 `gridFor` 从窗口里切出来（`grid.columnOf`）。**判据本身一个字
      // 没变**，变的是它的来源 —— 而 `columnOf` 比 `dayIndexOf` 多一条上界，
      // 因为兜底周整周都在今天之前时，「往前找最近的一天」会把周日当成今天。
      expect(painter, contains('grid.columnOf('),
          reason: '列号不是按这一周的零点算的');
      expect(RegExp(r'\.sessionsInWeek\(').hasMatch(painter), isFalse,
          reason: '还在用「块上那一周」取事件 —— 学期中那是别的一周');
      expect(painter, contains('block, grid.fromMs, grid.endMs'),
          reason: '画的不是「这一块在这一周里」的事件');
    });

    test('三种布局都收到同一块，没有一处自己去找日程', () {
      // 挑块只在 `remotes` 里做一次。散到各个布局里的话，「配了日程」这条
      // 规则会变成三份各自演化的复制品 —— 而它们不一致时没有任何东西会报错。
      final renderer = _stripComments(_read(_kotlinRenderer));
      for (final f in ['nextView', 'listView', 'weekView']) {
        final sig =
            RegExp('private fun $f\\(([^)]*)\\)', dotAll: true).firstMatch(renderer);
        expect(sig, isNotNull, reason: '没找到 private fun $f');
        expect(sig!.group(1), contains('block: WidgetSetBlock'),
            reason: '$f 没有收到块 —— 它要么自己找日程，要么不认日程');
      }
    });

    test('日程名那条的高度进了行数预算', () {
      // 这是本轮**唯一一条单元测试看不见的**契约：`LABEL_DP` 没加进 `chrome`
      // 的话，开着日程名时最后一行会被顶出卡片露出半个，而所有测试照旧全绿。
      // 这里只能钉住「它确实被减掉了」，真机截图才钉得住那个数字对不对。
      final renderer = _stripComments(_read(_kotlinRenderer));
      final chrome = RegExp(r'val chrome = [^\n]*').firstMatch(renderer)?.group(0);
      expect(chrome, isNotNull, reason: '没找到 chrome 那行');
      expect(chrome, contains('LABEL_DP'),
          reason: '日程名那条占的高度没有从行数预算里扣掉');
      expect(renderer, contains('LABEL_DP'), reason: '没找到 LABEL_DP 这个常量');
    });

    test('日程名那条只在放得下的两种布局里，且默认收着', () {
      // 小尺寸（2×1）那一档**结构上**没有这一栏：`widget_next.xml` 里四个控件
      // 已经排满，连齿轮都没有。那不是「用户关掉了」，所以配置页那个开关
      // 在小尺寸上不生效但也不置灰 —— 它要持久化。
      for (final f in ['widget_list.xml', 'widget_week.xml']) {
        final src = _read('android/app/src/main/res/layout/$f');
        expect(src, contains('@+id/set_label'), reason: '$f 少了日程名那条');
        expect(src, contains('android:visibility="gone"'),
            reason: '$f 里的日程名默认没有收起 —— 关掉开关不会真的省下一行');
      }
      expect(_read('android/app/src/main/res/layout/widget_next.xml'),
          isNot(contains('set_label')),
          reason: '小尺寸那一档凭空多了一条日程名');
    });

    test('明天没课时给一句话，而不是留一个孤零零的标题', () {
      // 原来什么都不画，看起来和「渲染坏了」一模一样。
      final renderer = _stripComments(_read(_kotlinRenderer));
      expect(renderer, contains('R.layout.widget_note'),
          reason: '「没有课」那句没有布局可用 —— RemoteViews 的子视图只能来自布局资源');
      expect(renderer, contains('noteView'),
          reason: '「没有课」那句没有被画出来');
      // 它吃的是**剩下的**预算：课程行先排。反过来把这句话排到前面，
      // 就会出现「显示着『明天没有课』、今天的课却被折成『还有 2 节』」——
      // 拿有内容的换没内容的。
      expect(RegExp(r'if \(total > 0\)').hasMatch(renderer), isTrue,
          reason: '「没有课」那句没有和「今天也没有课」那条页脚错开');
    });

    test('每次渲染都新建 RemoteViews，不存进字段复用', () {
      // 复用同一个实例会把每次 `setImageViewBitmap` 累积成一条条独立 action，
      // 改十次就是十份位图一起过 Binder。这是个不撞上就永远不知道的坑。
      final renderer = _read(_kotlinRenderer);
      expect(RegExp(r'(val|var)\s+\w+\s*:\s*RemoteViews\??').hasMatch(renderer),
          isFalse,
          reason: '有人把 RemoteViews 存进了字段 —— 那它就是在被复用');
      // 每个布局各建各的：widget_initial / next / list / row / group / week。
      final sites = RegExp(r'RemoteViews\(context\.packageName, R\.layout')
          .allMatches(renderer)
          .length;
      expect(sites, greaterThanOrEqualTo(6),
          reason: '有布局没有自己新建 RemoteViews');
    });
  });
}
