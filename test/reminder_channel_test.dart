import 'dart:io';

import 'package:classcal/core/reminder/reminder_plan.dart';
import 'package:classcal/core/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart 与 Kotlin 之间的契约。
///
/// 提醒这条路有一半在 Kotlin 里，而**跨语言的不一致一条也不会报错**：
/// 名字对不上就是方法永远返回 null、字段对不上就是提醒永远不响。这两个失败
/// 都长得像「这个功能没做」，而不是像 bug，靠人眼审代码是审不出来的。
///
/// 所以这里直接读 Kotlin 源码来核对。它很笨，但笨得恰到好处 —— 改了一边的
/// 名字而忘了另一边，测试立刻红。
const _dartChannelFile = 'lib/core/platform/reminder_scheduler.dart';
const _kotlinBridgeFile =
    'android/app/src/main/kotlin/com/jingjunyu/classcal/ReminderBridge.kt';
const _kotlinStoreFile =
    'android/app/src/main/kotlin/com/jingjunyu/classcal/ReminderStore.kt';
const _kotlinReceiverFile =
    'android/app/src/main/kotlin/com/jingjunyu/classcal/ReminderReceiver.kt';
const _kotlinProbeFile =
    'android/app/src/main/kotlin/com/jingjunyu/classcal/LocationProbe.kt';
const _kotlinAlarmsFile =
    'android/app/src/main/kotlin/com/jingjunyu/classcal/ReminderAlarms.kt';
const _kotlinActionFile =
    'android/app/src/main/kotlin/com/jingjunyu/classcal/ReminderActionReceiver.kt';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '找不到 $path');
  return file.readAsStringSync();
}

/// 去掉源码里的注释 —— 和 `widget_channel_test.dart` 里那个同源。
///
/// **凡是要「断言某个写法不存在」的扫描，都得先剥注释**：注释里会*提到*被禁的
/// 写法（为的是解释为什么不用它），不剥的话测试会把说明文字判成违规，而那种
/// 失败指向完全错误的方向。`bannersState` 的注释正好提到了 `nm.importance`。
///
/// 简单粗暴地按 `//` 和 `/* */` 切，不区分字符串字面量 —— 这个文件里没有
/// 含 `//` 的字符串，真出现了再换成正经的扫描。
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('通道契约', () {
    test('通道名两边一致', () {
      final dart = _read(_dartChannelFile);
      final kotlin = _read(_kotlinBridgeFile);

      final dartName = RegExp(r"channelName\s*=\s*'([^']+)'").firstMatch(dart);
      expect(dartName, isNotNull, reason: 'Dart 侧没找到 channelName');
      final kotlinName = RegExp(r'CHANNEL\s*=\s*"([^"]+)"').firstMatch(kotlin);
      expect(kotlinName, isNotNull, reason: 'Kotlin 侧没找到 CHANNEL');

      expect(dartName!.group(1), kotlinName!.group(1));
      expect(dartName.group(1), 'com.jingjunyu.classcal/reminders');
    });

    test('Dart 调的方法名，Kotlin 全都实现了', () {
      final dart = _read(_dartChannelFile);
      final kotlin = _read(_kotlinBridgeFile);

      // Dart: `_invoke<void>('sync', ...)` 这种方法名（`_invoke` 内部那次
      // 带变量的调用不会匹配上，因为不是字面量）。
      //
      // `.*?` 而不是 `[^>]*`：泛型参数里还套着泛型
      // （`_invoke<Map<Object?, Object?>>`），一个 `[^>]*` 会在第一个 `>` 处
      // 停下，于是这几个方法被漏掉 —— 而漏掉的表现是「Kotlin 实现了但 Dart
      // 不调」，指向完全错误的方向。
      final dartMethods = RegExp(r"_invoke<.*?>\(\s*'([A-Za-z]+)'")
          .allMatches(dart)
          .map((m) => m.group(1)!)
          .toSet();

      // Kotlin: `when (call.method) { "sync" -> ... }` 的各个分支。
      // 到 `else ->` 为止 —— 那之后没有分支了。缩进不写死：这类正则一旦
      // 假定缩进，某次重排就会让它静默失配，而失配的表现是「一个方法都没扫到」，
      // 看起来像测试错了而不是代码错了。
      final handler = RegExp(
        r'when \(call\.method\)\s*\{(.*?)\n\s*else ->',
        dotAll: true,
      ).firstMatch(kotlin);
      expect(handler, isNotNull, reason: 'Kotlin 侧没找到 when (call.method) 分支');
      final kotlinMethods = RegExp(r'"([A-Za-z]+)"\s*->')
          .allMatches(handler!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      expect(dartMethods, isNotEmpty, reason: 'Dart 侧一个方法都没扫到，正则多半失效了');
      expect(kotlinMethods, isNotEmpty, reason: 'Kotlin 侧一个分支都没扫到');
      expect(
        dartMethods.difference(kotlinMethods),
        isEmpty,
        reason: 'Dart 在调这些方法，Kotlin 没实现 —— 调用会静默返回 null',
      );
      expect(
        kotlinMethods.difference(dartMethods),
        isEmpty,
        reason: 'Kotlin 实现了这些方法，Dart 从来不调',
      );
    });

    test('参数名两边一致', () {
      final dart = _read(_dartChannelFile);
      final kotlin = _read(_kotlinBridgeFile);

      final dartArgs = RegExp(r"'(specs|seconds)':")
          .allMatches(dart)
          .map((m) => m.group(1)!)
          .toSet();
      final kotlinArgs = RegExp(r'call\.argument<.*?>\("([A-Za-z]+)"\)')
          .allMatches(kotlin)
          .map((m) => m.group(1)!)
          .toSet();

      expect(dartArgs, isNotEmpty);
      expect(
        dartArgs.difference(kotlinArgs),
        isEmpty,
        reason: 'Dart 传了参数，Kotlin 按别的名字读 —— 读到的是 null',
      );
    });
  });

  group('提醒数据的 JSON 契约', () {
    /// 从 Dart 的 `toJson` 里抠出所有键名。
    Set<String> dartKeys() {
      final source = _read('lib/core/reminder/reminder_plan.dart');
      final block = RegExp(
        r'Map<String, Object\?> toJson\(\) => \{(.*?)\n      \};',
        dotAll: true,
      ).firstMatch(source);
      expect(block, isNotNull, reason: 'Dart 侧没找到 ReminderSpec.toJson');
      return RegExp(r"'([A-Za-z]+)':")
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
    }

    /// 从 Kotlin 的 `toJson` / `fromJson` 里各自抠出键名。两边都要看 ——
    /// 只看 `fromJson` 的话，Kotlin 写出去而自己读不回来的字段（不该有，
    /// 但 `toJson` 漏一个字段正好会造成这个）就查不出来。
    Set<String> kotlinKeys(String which) {
      final source = _read(_kotlinStoreFile);
      // 终结符是「换行 + 若干空白 + `}`」，**不写死缩进**。
      //
      // 这里原本写的是 `\n        }`（八格）。`fromJson` 的体在 `try { ... }`
      // 里，收尾那个 `}` 正好是八格，所以它一直是对的；`toJson` 的体是
      // `JSONObject().apply { ... }`，收尾是四格，于是这个懒惰匹配一路吃到了
      // **再下一个八格的 `}`** —— 也就是 `fromJson` 的 `} catch` 那一行。
      // 那之前正好是 companion object，于是 `NEARBY_SKIP = "skip"` 这类常量和
      // `fromJson` 的整个函数体都被算成了 `toJson` 写出去的键。
      //
      // 这个 bug 一直存在，只是以前那两个函数之间没有小写开头的字符串字面量，
      // 多吞进去的东西碰巧是空的。加一对常量就露出来了。写死缩进的匹配就是
      // 这样：改对了是运气，改错了不报错。
      final block = RegExp(
        'fun ${which == 'write' ? 'toJson' : 'fromJson'}\\([^)]*\\)[^{]*\\{(.*?)\\n[ \\t]*\\}',
        dotAll: true,
      ).firstMatch(source);
      expect(block, isNotNull, reason: 'Kotlin 侧没找到 $which');
      return RegExp(r'"([A-Za-z]+)"')
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          // `color`、`android` 这类非字段的字面量在这两个函数里不会出现，
          // 但 `Double`/`Long` 之类的大写开头要排除掉。
          .where((k) => k[0] == k[0].toLowerCase())
          .toSet();
    }

    test('Dart 写出去的字段，Kotlin 全都读得到', () {
      final expected = {
        'id',
        'key',
        'fireAtMs',
        'title',
        'body',
        'gateLat',
        'gateLng',
        'gateRadiusMeters',
        'nearby',
        'timeoutMs',
        'repeatIntervalMs',
        'classStartMs',
      };
      expect(dartKeys(), expected);
      expect(kotlinKeys('read'), expected);
      expect(kotlinKeys('write'), expected);
    });

    test('真的能往返：toJson 出来的每个键，fromJson 都认得', () {
      // 上一条是扫源码，这一条是跑一遍 Dart 侧的实际输出 —— 源码扫对了但
      // 序列化写错了（比如键名拼错在 toJson 里）时，只有这条会红。
      final spec = ReminderSpec(
        id: 42,
        key: 'rule:1@2026-10-13',
        fireAt: DateTime(2026, 10, 13, 7, 45),
        title: '高等数学A(1)',
        body: '08:00 开始 · 第一教学楼303',
        gateLat: 27.8912,
        gateLng: 112.9212,
        gateRadiusMeters: 200,
        nearby: NearbyMode.silent,
        timeoutMs: 30 * 60 * 1000,
        repeatIntervalMs: 5 * 60 * 1000,
        classStartMs: DateTime(2026, 10, 13, 8).millisecondsSinceEpoch,
      );
      final json = spec.toJson();
      expect(json.keys.toSet(), dartKeys());
      expect(json['id'], 42);
      expect(
        json['fireAtMs'],
        DateTime(2026, 10, 13, 7, 45).millisecondsSinceEpoch,
      );
      // Kotlin 侧 `nearby` 是**字符串**不是枚举名 —— `NearbyMode.silent` 的
      // `toString()` 是 "NearbyMode.silent"，写进去那边一个也认不出来。
      expect(json['nearby'], 'silent');
      expect(json['timeoutMs'], 1800000);
      expect(json['repeatIntervalMs'], 300000);
      expect(json['classStartMs'], DateTime(2026, 10, 13, 8).millisecondsSinceEpoch);
      // 门控点缺失时**不要**写 null：Kotlin 那边用 `has()` 判断有没有门控，
      // 写一个 null 进去会让 `getDouble` 抛异常，整条提醒被丢弃。
      //
      // `nearby` 同理，虽然 Kotlin 那边判的是 `gated` 而不是 `has("nearby")`：
      // `optString` 读到 JSON 里的 `null` 会返回字符串 `"null"`，
      // 那既不是 skip 也不是 silent，落进「认不出来就当作 skip」的兜底里 ——
      // 结果是碰巧对的，但靠的是巧合。
      final noGate = ReminderSpec(
        id: 1,
        key: 'k',
        fireAt: DateTime(2026, 10, 13, 7, 45),
        title: 't',
        body: 'b',
      );
      expect(noGate.toJson().containsKey('gateLat'), isFalse);
      expect(noGate.toJson().containsKey('gateLng'), isFalse);
      expect(noGate.toJson().containsKey('nearby'), isFalse);
      // `timeoutMs` 反而是**无条件**写的：它和门控无关，没门控的提醒一样
      // 该自动清除，漏掉它等于「这条不门控的提醒永远赖在通知栏里」。
      expect(noGate.toJson()['timeoutMs'], 0);
      // 同理，重复的两项也无条件写：Kotlin 那边是拿 `repeatIntervalMs > 0`
      // 判断要不要重复的，漏写这个键就等于「这条不重复」—— 碰巧是对的，
      // 但 `classStartMs` 漏掉会让 `repeats` 永远算不出 true。
      expect(noGate.toJson()['repeatIntervalMs'], 0);
      expect(noGate.toJson()['classStartMs'], 0);
      expect(noGate.repeats, isFalse);
    });
  });

  group('重复提醒停得下来', () {
    // 这一组盯的是一条**看起来完全正常**的失败：重复链一旦少了终点，
    // 提醒会一直弹下去。用户按下「我已到教室」、看到通知消失，一切正常 ——
    // 然后 N 分钟后它又回来了。这不是「有点烦」，是那个按钮根本没实现。
    //
    // 全都发生在 Kotlin 里，Dart 测不到，所以扫源码。

    test('上课之后不再弹，而且要把还挂着的那条撤掉', () {
      final receiver = _read(_kotlinReceiverFile);
      final guard_ = RegExp(r'if \((.+?)\) \{\s*\n\s*Log\.i\(TAG, "\$\{spec\.key\} 已经上课')
          .firstMatch(receiver)
          ?.group(1);
      expect(guard_, isNotNull, reason: 'ReminderReceiver 里没找到「上课就停」的判断');
      expect(
        guard_!,
        contains('classStartMs'),
        reason: '停止条件没有和上课时刻挂钩 —— 这条链就没有终点了',
      );
      // **只拦补发的那几跳**。提前量设成 0 的人（提醒时刻正好等于上课时刻）
      // 第一次响时已经到上课时间了，不加这个条件他一条提醒都收不到 ——
      // 而且设置页只会说「已开启」，什么都看不出来。
      expect(
        guard_,
        contains('force'),
        reason: '这条判断把第一次提醒也拦掉了：提前量 0 的人会一条都收不到',
      );
      expect(
        receiver,
        contains('cancelPending'),
        reason: '上课那一刻只停下不撤通知的话，它会一直留在通知栏里',
      );
    });

    test('最后一跳正好落在上课那一刻，不会再弹一条', () {
      final receiver = _read(_kotlinReceiverFile);
      // `minOf(now + repeatIntervalMs, classStartMs)` —— 夹到上课时刻。
      // 不夹的话最后一次重复会排在课后，而那时候弹出来只是在说「上课了」。
      expect(
        RegExp(r'minOf\([^)]*repeatIntervalMs[^)]*classStartMs').hasMatch(receiver),
        isTrue,
        reason: '下一跳没有夹到上课时刻，最后一次重复会排到课后去',
      );
      // 反过来，已经在课上就一跳都不要排：夹出来的下一跳会是「立刻」，
      // 于是刚弹出来的通知会被紧跟的收尾跳撤掉，用户看到一条一闪而过的横幅。
      expect(
        RegExp(r'fun repeatNext[\s\S]*?if \(now >= spec\.classStartMs\) return')
            .hasMatch(receiver),
        isTrue,
        reason: '提前量为 0 时还会排下一跳，通知会被立刻撤掉',
      );
    });

    test('「我已到教室」必须撤掉还没响的下一跳', () {
      final action = _read(_kotlinActionFile);
      final branch = RegExp(
        r'ACTION_ARRIVED\s*->\s*\{(.*?)\n            \}',
        dotAll: true,
      ).firstMatch(action)?.group(1);
      expect(branch, isNotNull, reason: '没找到 ACTION_ARRIVED 分支');
      expect(
        branch,
        contains('cancelPending'),
        reason: '按钮只 cancel 了通知、没撤闹钟 —— 按下去 N 分钟后提醒又弹回来，'
            '而用户会以为这个按钮坏了',
      );
    });

    test('重复提醒的下一跳也记进「要撤的闹钟」里', () {
      // 不记的话，改一次设置（触发全量重排）撤不掉还挂着的那一跳，
      // 它过几分钟会按**旧的**时刻弹一条出来。
      final alarms = _read(_kotlinAlarmsFile);
      expect(
        alarms,
        contains('pendingIds'),
        reason: '响过之后追加上去的闹钟没有被记下来，全量重排撤不掉它们',
      );
      expect(
        RegExp(r'fun cancelAll[\s\S]*?pendingIds').hasMatch(alarms),
        isTrue,
        reason: 'cancelAll 没有一并撤掉 pending 的那些闹钟',
      );
      expect(
        RegExp(r'fun snooze[\s\S]*?savePendingIds').hasMatch(alarms),
        isTrue,
        reason: 'snooze 排完闹钟没把它记下来',
      );
    });

    test('Dart 侧的 repeats 要求两个值都有', () {
      // 只有间隔没有终止时刻 = 一条停不下来的链。原生侧判的是同一件事
      // （`ReminderStore.kt` 的 `repeats`），两边都得挡住 —— 只挡一边的话，
      // 另一边就成了那条链唯一的防线，而它恰好是跨语言的那一半。
      ReminderSpec withBoth({int interval = 300000, int start = 1000}) =>
          ReminderSpec(
            id: 1,
            key: 'k',
            fireAt: DateTime(2026, 10, 13, 7, 45),
            title: 't',
            body: 'b',
            repeatIntervalMs: interval,
            classStartMs: start,
          );
      expect(withBoth().repeats, isTrue);
      expect(withBoth(start: 0).repeats, isFalse, reason: '没有终止时刻就不该重复');
      expect(withBoth(interval: 0).repeats, isFalse);
    });
  });

  group('定位门控的安全底线', () {
    // 这一组盯的是**一条具体的、安静的、后果很坏的失败**：用几小时前的
    // 缓存位置判定「你已经到教室了」，于是把该响的提醒吞掉。用户不会去查
    // 为什么，只会觉得「这个提醒时灵时不灵」。
    //
    // 它没法用 Dart 单元测试覆盖（整段逻辑在 Kotlin 里），所以只能扫源码。
    // 扫源码很笨，但比「等用户漏掉一节课才发现」好得多。

    test('判「在教室里」必须要求位置是新的', () {
      final receiver = _read(_kotlinReceiverFile);
      final inside = RegExp(r'val inside\s*=\s*(.+)')
          .firstMatch(receiver)
          ?.group(1);
      expect(inside, isNotNull, reason: 'ReminderReceiver 里没找到 inside 判定');

      expect(
        inside!,
        contains('contains('),
        reason: 'inside 判定里丢了「在不在范围内」这个条件',
      );
      expect(
        inside,
        contains('fresh'),
        reason: 'inside 判定没有要求位置是新的 —— 过期缓存会让提醒被静默吞掉',
      );
      // `fix != null` 的前置也不能丢，否则 `fix!!` 会崩。
      expect(inside, contains('!= null'));
    });

    test('探测结果分「新」和「旧」两态，而不是裸的 Location?', () {
      final probe = _read(_kotlinProbeFile);
      expect(
        probe,
        contains('class Fix('),
        reason: 'Fix 类型没了 —— 调用方就没法区分「拿到位置」和「位置够不够新」',
      );
      expect(
        probe,
        contains('MAX_CACHE_AGE_MS'),
        reason: '缓存位置的有效期上限没了，旧位置会被当成新位置用',
      );

      // 主动定位拿到的一定是新的，缓存位置按年龄判。两条写反了会立刻出事：
      // 前者写错成 false 就是「门控永远不生效」，后者写错成 true 就是本组要防的。
      expect(
        RegExp(r'Fix\(fresh,\s*fresh\s*=\s*true\)').hasMatch(probe),
        isTrue,
        reason: '主动拿到的位置没有被标成新的',
      );
      expect(
        RegExp(r'Fix\(cached,\s*fresh\s*=\s*recent\)').hasMatch(probe),
        isTrue,
        reason: '缓存位置没有按年龄判新旧',
      );
    });

    test('「用当前位置」只接受新位置，不拿旧缓存顶上', () {
      // 这个按钮记下的坐标会被长期当成「教室在哪」。塞一个几小时前的缓存进去，
      // 等于把地点记到昨天待过的地方，而且界面上完全看不出来。
      final bridge = _read(_kotlinBridgeFile);
      final block = RegExp(
        r'"currentLocation"\s*->\s*\{(.*?)\n            \}',
        dotAll: true,
      ).firstMatch(bridge)?.group(1);
      expect(
        block,
        isNotNull,
        reason: 'ReminderBridge 里没找到 currentLocation 分支',
      );
      expect(block, contains('fresh'), reason: '「用当前位置」没有过滤旧位置，会把错误的地点记下来');
    });
  });

  group('「横幅会不会弹」的判据', () {
    // 这一条在真机上**错了一次**，而且错得完全看不出来：判据用的是应用级的
    // 重要程度，而它对任何一个没被整个屏蔽的应用都返回 DEFAULT（AOSP 只在
    // 通知被完全挡掉时才让它变 NONE），于是「横幅被关掉了」这句警告**永远为真**，
    // 用户照它去系统设置里找一个本来就是开的开关。
    //
    // 表现是「其它一切都对，只有那句话是错的」—— 没有一条测试钉住判据，
    // 下次重写还会再犯。
    String bridge() => _stripComments(_read(_kotlinBridgeFile));

    test('读的是渠道的重要程度，不是应用级的', () {
      final src = bridge();
      expect(RegExp(r'getNotificationChannel\(').hasMatch(src), isTrue,
          reason: '没有读渠道 —— 横幅的判据只能是渠道的重要程度');
      expect(
        RegExp(r'channel\.importance\s*>=\s*NotificationManager\.IMPORTANCE_HIGH')
            .hasMatch(src),
        isTrue,
        reason: '读了渠道，却没拿它的 importance 和 IMPORTANCE_HIGH 比',
      );
      expect(RegExp(r'nm\.importance').hasMatch(src), isFalse,
          reason: '又回去读应用级的重要程度了 —— 那个值永远是 DEFAULT，'
              '拿它当判据会让这句警告永远为真');
    });

    test('读的是平常那条渠道，不是「已在教室」时才用的静音渠道', () {
      final src = bridge();
      expect(src, contains('NotificationHelper.CHANNEL_ID'),
          reason: '没指名读哪条渠道');
      expect(
        RegExp(r'getNotificationChannel\(\s*NotificationHelper\.SILENT_CHANNEL_ID')
            .hasMatch(src),
        isFalse,
        reason: '「提醒会不会弹横幅」问的不该是静音那条',
      );
    });

    test('Dart 侧缺字段时当作「会弹」，老原生侧不会凭空多出一句警告', () {
      // 兜底方向反了的话，一个还没实现这个方法的旧原生侧会立刻显示
      // 「横幅被关掉了」，而且用户毫无办法 —— 因为它其实没被关掉。
      final dart = _read(_dartChannelFile);
      expect(
        RegExp(r"banners:\s*raw\['banners'\]\s*!=\s*false").hasMatch(dart),
        isTrue,
        reason: '缺字段时的兜底方向变了 —— 应当当作「会弹」',
      );
    });
  });

  group('设置里的地点', () {
    test('坏坐标在入口就被挡住，不会进配置文件', () {
      // 经纬度写反（把 112.9 写成 91.2 还看得见，写成 191.2 就无声无息）会让
      // 门控永远判定「不在教室」，而那看起来跟「定位没拿到」一模一样。
      expect(
        SavedPlace.fromJson({'name': '楼', 'lat': 91.2, 'lng': 112.9}),
        isNull,
      );
      expect(
        SavedPlace.fromJson({'name': '楼', 'lat': 27.9, 'lng': 191.2}),
        isNull,
      );
      expect(
        SavedPlace.fromJson({'name': '  ', 'lat': 27.9, 'lng': 112.9}),
        isNull,
      );
      expect(
        SavedPlace.fromJson({'name': '楼', 'lat': 'x', 'lng': 112.9}),
        isNull,
      );
      expect(
        SavedPlace.fromJson({'name': '楼', 'lat': 27.9, 'lng': 112.9}),
        isNotNull,
      );
      // 字符串形式也认：手工改配置文件时很自然会写成带引号的数字。
      expect(
        SavedPlace.fromJson({'name': '楼', 'lat': '27.9', 'lng': '112.9'}),
        isNotNull,
      );
    });

    test('一份设置写出再读回来，提醒相关的项不丢', () {
      const original = AppSettings(
        remindersEnabled: true,
        defaultLeadMinutes: 25,
        nearbyMode: NearbyMode.silent,
        gateRadiusMeters: 300,
        notificationTimeoutMinutes: 30,
        repeatReminders: true,
        repeatIntervalMinutes: 3,
        places: [SavedPlace(name: '第一教学楼', lat: 27.8912, lng: 112.9212)],
      );
      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.defaultLeadMinutes, 25);
      expect(restored.nearbyMode, NearbyMode.silent);
      expect(restored.gateRadiusMeters, 300);
      expect(restored.notificationTimeoutMinutes, 30);
      expect(restored.repeatReminders, isTrue);
      expect(restored.repeatIntervalMinutes, 3);
      expect(restored.places, original.places);
    });

    test('重复间隔超范围被夹回来，1 仍然是合法值', () {
      expect(
        AppSettings.fromJson({'repeatIntervalMinutes': 99999})
            .repeatIntervalMinutes,
        AppSettings.kMaxRepeatMinutes,
      );
      expect(
        AppSettings.fromJson({'repeatIntervalMinutes': 0}).repeatIntervalMinutes,
        AppSettings.kMinRepeatMinutes,
        reason: '0 不是「不重复」的写法 —— 那件事由 repeatReminders 开关表达，'
            '间隔 0 只会让下一跳排在和这一跳同一时刻',
      );
    });

    test('默认不重复 —— 会主动打扰的选项必须由用户打开', () {
      expect(const AppSettings().repeatReminders, isFalse);
      // 老版本写的配置文件里没有这两个键，读出来也该是关着的。
      expect(AppSettings.fromJson({}).repeatReminders, isFalse);
    });

    test('老版本写的 gateByLocation 还能读出来，不会把门控悄悄关掉', () {
      // 手机上那份 settings.json 是**上一个版本**的 App 写的，里面只有
      // `gateByLocation`。不认它的话，用户明确打开过的门控会在升级后失灵，
      // 而他只会觉得「这功能怎么自己没了」—— 没有任何报错可查。
      final on = AppSettings.fromJson({'gateByLocation': true});
      final off = AppSettings.fromJson({'gateByLocation': false});
      expect(on.nearbyMode, NearbyMode.skip, reason: '老键 true 对应老行为「不提醒」');
      expect(off.nearbyMode, NearbyMode.remind);
      // 老键不在时不能用 false 顶上 —— 那会让默认值从「照常提醒」变成别的。
      expect(const AppSettings().nearbyMode, NearbyMode.remind);
    });

    test('新键优先：两个键都在时以 nearbyMode 为准', () {
      // 用户升级后改成「静音」，之后若某个同步工具把老键又写回来（老版本 App
      // 的备份、另一台没升级的设备），认老键就等于把他的改动吃掉。
      final s = AppSettings.fromJson({
        'nearbyMode': 'silent',
        'gateByLocation': true,
      });
      expect(s.nearbyMode, NearbyMode.silent);
    });

    test('认不出来的模式名当作「照常提醒」，不是当作静音也不是不提醒', () {
      // 脏值来自手改配置文件或者未来版本写的名字。退回**默认**那一态，
      // 也就是老行为：多响一次的代价远小于漏掉一次。
      final s = AppSettings.fromJson({'nearbyMode': 'whisper'});
      expect(s.nearbyMode, NearbyMode.remind);
    });

    test('自动清除时间超范围被夹回来，0 仍然是合法值', () {
      expect(
        AppSettings.fromJson({'notificationTimeoutMinutes': 99999})
            .notificationTimeoutMinutes,
        AppSettings.kMaxTimeoutMinutes,
      );
      expect(
        AppSettings.fromJson({'notificationTimeoutMinutes': -5})
            .notificationTimeoutMinutes,
        0,
      );
      expect(
        AppSettings.fromJson({'notificationTimeoutMinutes': 0})
            .notificationTimeoutMinutes,
        0,
        reason: '0 是「不自动清除」，不能被当成缺省值丢掉',
      );
    });

    test('超范围的提前量和半径被夹回来，而不是让整份设置退回默认', () {
      final restored = AppSettings.fromJson({
        'defaultLeadMinutes': 99999,
        'gateRadiusMeters': 1,
      });
      expect(restored.defaultLeadMinutes, AppSettings.kMaxLeadMinutes);
      expect(restored.gateRadiusMeters, AppSettings.kMinRadiusMeters);
    });

    test('同名地点去重 —— 留两条只会让匹配结果取决于列表顺序', () {
      final restored = AppSettings.fromJson({
        'places': [
          {'name': '第一教学楼', 'lat': 1.0, 'lng': 1.0},
          {'name': '第一教学楼', 'lat': 2.0, 'lng': 2.0},
        ],
      });
      expect(restored.places, hasLength(1));
      expect(restored.places.single.lat, 1.0);
    });
  });
}
