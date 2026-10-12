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

String _kotlinClassBody(String name) {
  final src = _read(_kotlinSnapshot);
  final start = src.indexOf('data class $name(');
  expect(start, isNonNegative, reason: 'Kotlin 侧没找到 data class $name');
  final next = RegExp(r'\n(data class |object |enum )')
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
      // 周次 / 标题 / 网格坐标从顶层搬到了这里。少一个键的表现是轻的
      // （Kotlin 用默认值兜），但 `gridDayStartsMs` 兜不住：它是那一块的
      // 全部坐标，缺了它整张网格会画成一堆叠在周一那一列的方块。
      expectSameKeys('WidgetSetBlock', {
        'id', 'name', 'currentWeek', 'weekTitle', 'gridWeek', 'gridRows',
        'gridDayStartsMs',
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
      // `y` / `m` / `d` 是 `today` 那个嵌套对象里的三个键。
      // `currentWeek` / `weekTitle` / `gridWeek` / `gridRows` **不在这一层了** ——
      // 它们搬进了 `blocks`。留在顶层就等于留一个「这是哪一套的周次」说不清的
      // 全局值，而它必然对其中一个日程是错的。
      expectSameKeys('WidgetSnapshot', {
        'version', 'generatedAtMs', 'today', 'todayTitle', 'tomorrowTitle',
        'dayStartsMs', 'todayWeekday', 'theme', 'layout', 'sessions',
        'boundariesMs', 'activeSetId', 'blocks', 'y', 'm', 'd',
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
      // 本轮从 1 提到 2。两个都停在 1 的话，这条测试照旧是绿的，
      // 而桌面上会拿新版 Dart 写出的快照去喂一个不认识 `blocks` 的旧 Kotlin。
      expect(dart, kWidgetSnapshotVersion.toString());
      expect(dart, '2');
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
      // 扫出来的键集合里含着 `today` 那个嵌套对象里的 `y`/`m`/`d`，
      // 所以顶层要减掉它们 —— 减掉之后两边必须**一模一样**，多一个少一个都算。
      expect(json.keys.toSet(),
          _dartKeys(_dartClassBody('WidgetSnapshot')).difference({'y', 'm', 'd'}));
      expect((json['today']! as Map).keys.toSet(), {'y', 'm', 'd'});
      // 三个零点必须是**整数毫秒**：Kotlin 用 `getLong` 读，写成字符串或者
      // 精度不够的浮点会让那边拿到 0，然后「今天」永远是错的。
      expect(json['dayStartsMs'], everyElement(isA<int>()));
      expect((json['dayStartsMs']! as List<int>).first,
          DateTime(2026, 10, 10).millisecondsSinceEpoch);

      // 块那一份也要真的写出来：`gridDayStartsMs` 同样是 `getLong` 读的
      // **整数毫秒的七个值**，而它是那一块的全部坐标 —— 少一个、
      // 或者写成浮点，桌面上整张网格会叠在周一那一列。
      final blocks = json['blocks']! as List;
      expect(blocks, hasLength(2), reason: '一个日程 + 一块总览');
      final block = blocks.first as Map<String, Object?>;
      expect(block['name'], '2026-2027-1');
      expect(block['gridDayStartsMs'], everyElement(isA<int>()));
      expect(block['gridDayStartsMs'], hasLength(7));
      expect((block['gridDayStartsMs']! as List<int>).first,
          DateTime(2026, 10, 5).millisecondsSinceEpoch,
          reason: '第 5 周的周一');
      expect((blocks.last as Map)['id'], kOverviewBlockId);
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

    test('快照过期时不许照画', () {
      // 用户一周没开 App，快照会照样说「今天是周三」，然后自信地画出**上周三**
      // 的课。这是整个小组件唯一一种会安静地错的失败形态。
      final renderer = _read(_kotlinRenderer);
      expect(
        RegExp(r'if \(snapshot == null \|\| snapshot\.isStale\(nowMs\)\)')
            .hasMatch(renderer),
        isTrue,
        reason: '渲染入口没有把「没有快照」和「快照过期」放在同一条兜底路径上',
      );
      final snapshot = _read(_kotlinSnapshot);
      for (final field in ['Calendar.YEAR', 'Calendar.MONTH', 'Calendar.DAY_OF_MONTH']) {
        expect(snapshot, contains(field),
            reason: 'isStale 没有真的和本机的年月日比 —— 少了 $field');
      }
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

    test('「下一节课」问的是那节课在哪一天，不是「今天是不是第 0 天」', () {
      // `dayIndexOf(nowMs)` 恒等于 0（now 一定落在今天那个区间里），所以
      // 拿它当条件的那一支永远命中，带星期的那一支成了死代码。表现是周六
      // 的卡片上写着「第一二节 · 08:00–09:40」指着一节周一的课 ——
      // 读起来就是「我今天一二节有课」，而且没有任何东西看起来不对。
      final renderer = _read(_kotlinRenderer);
      expect(RegExp(r'dayIndexOf\(session\.startAtMs\)').hasMatch(renderer),
          isTrue,
          reason: '这一支问的不是「这节课在哪一天」');
      expect(RegExp(r'dayIndexOf\(nowMs\)').hasMatch(renderer), isFalse,
          reason: '还在拿 now 去查它在哪一天 —— 那个答案永远是 0');
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
      expect(RegExp(r'snapshot\.weekTitle').hasMatch(renderer), isFalse,
          reason: '还在从快照顶层读周次标题 —— 那是「当前日程」的，不是这个实例的');
      expect(renderer, contains('block.weekTitle'));

      final painter = _stripComments(_read(_kotlinPainter));
      expect(RegExp(r'snapshot\.gridRows|snapshot\.gridWeek').hasMatch(painter),
          isFalse,
          reason: '还在从快照顶层读网格坐标');
      expect(painter, contains('block.gridRows'),
          reason: '网格的行数不是从块上取的');
      // 列号必须按块的七天零点算，不能退回 `s.weekday` ——
      // 总览那一块里混着几个日程的事件，它们的周号各不相同，
      // 只有绝对日期是共有的。
      expect(painter, contains('block.dayIndexOf('),
          reason: '列号不是按块的零点算的');
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
