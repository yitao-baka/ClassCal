import 'dart:io';

import 'package:classcal/core/platform/wallpaper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 壁纸取色的 Dart 侧。
///
/// 这里最要紧的一条其实是最后一个 group —— 它读 Kotlin 源码做契约核对。
/// 因为这条通道的两端是两种语言，**键名对不上不会报任何错**：Kotlin 高高兴兴
/// 返回 `{accent1_500: ...}`，Dart 去取 `accent1` 得到 null，然后把 null 一路
/// 当成「本设备不支持壁纸取色」显示出去。这个 bug 真的发生过（Kotlin 那边
/// 原来是 `key.removePrefix("system_")`，留下的是 `accent1_500`），而且从界面
/// 上完全看不出是键名错了还是 ROM 不支持。mock 测不出跨语言的错位，所以那
/// 一个 group 直接去读文件。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.jingjunyu.classcal/theme');

  void mockHandler(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  // 传 null 摘掉 mock —— 不这么做，上一个用例的桩会漏给下一个。
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  group('MethodChannelWallpaperSource', () {
    test('读回系统调色板，并把有符号 int 还原成 ARGB', () async {
      // 这三个值是 API 36 模拟器上真实的回包 —— 负数，因为 Java 的
      // `ContextCompat.getColor` 返回的是有符号 int。
      mockHandler((call) async {
        if (call.method != 'wallpaperPalette') return null;
        return <String, int>{
          'accent1': -10455380,
          'accent2': -9406581,
          'accent3': -7574132,
        };
      });

      final palette = await const MethodChannelWallpaperSource().load();
      expect(palette, isNotNull);
      // 直接丢 `Color(-10455380)` 会断言失败，必须先按 32 位掩码还原。
      expect(palette!.accent1, 0xFF6076AC);
      expect(palette.accent2, 0xFF70778B);
      expect(palette.accent3, 0xFF8C6D8C);
      expect(palette.accent1, greaterThan(0));
    });

    test('原生返回 null（ROM 没这批资源）就是 null，不是错误', () async {
      mockHandler((call) async => null);
      expect(await const MethodChannelWallpaperSource().load(), isNull);
    });

    test('缺 accent1 就整体作废 —— 种子色是必填的', () async {
      mockHandler((call) async => <String, int>{'accent2': -9406581});
      expect(await const MethodChannelWallpaperSource().load(), isNull);
    });

    test('只有 accent1 时也能用，accent2/3 留空', () async {
      mockHandler((call) async => <String, int>{'accent1': -10455380});
      final palette = await const MethodChannelWallpaperSource().load();
      expect(palette!.accent1, 0xFF6076AC);
      expect(palette.accent2, isNull);
      expect(palette.accent3, isNull);
    });

    test('通道没接上（MissingPluginException）不抛，退回 null', () async {
      mockHandler((call) async => throw MissingPluginException('没有宿主'));
      expect(await const MethodChannelWallpaperSource().load(), isNull);
    });

    test('原生抛 PlatformException 也不抛，退回 null', () async {
      mockHandler((call) async => throw PlatformException(code: 'boom'));
      expect(await const MethodChannelWallpaperSource().load(), isNull);
    });
  });

  group('与原生侧的键名契约', () {
    test('ThemeBridge.kt 产出的键 = Dart 侧读取的键', () {
      final file = File(
        'android/app/src/main/kotlin/com/jingjunyu/classcal/ThemeBridge.kt',
      );
      expect(file.existsSync(), isTrue, reason: '找不到 ${file.path}');
      final source = file.readAsStringSync();

      // 只在这张映射表里找 `"x" to "system_y"` 形式的键值对。
      final block = RegExp(
        r'ACCENT_KEYS\s*=\s*mapOf\((.*?)\)',
        dotAll: true,
      ).firstMatch(source);
      expect(block, isNotNull, reason: 'ThemeBridge 里没有 ACCENT_KEYS 映射表');

      final keys = RegExp(r'"([^"]+)"\s*to\s*"([^"]+)"')
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();

      // 就这三个，且必须正好是 Dart 去取的名字。多一个少一个都是错位。
      expect(keys, ['accent1', 'accent2', 'accent3']);

      // 再核一遍资源名：键去掉了 `_500` 后缀，资源名不能跟着掉。
      final resources = RegExp(r'"([^"]+)"\s*to\s*"([^"]+)"')
          .allMatches(block.group(1)!)
          .map((m) => m.group(2)!)
          .toList();
      expect(resources, [
        'system_accent1_500',
        'system_accent2_500',
        'system_accent3_500',
      ]);
    });
  });
}
