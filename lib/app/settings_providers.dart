/// 设置与主题相关的 provider。
///
/// 单独一份而不是塞进 `providers.dart`：那个文件讲的是「课表数据怎么流动」，
/// 这一份讲的是「外观怎么决定」，两者唯一的交点是都不碰 UI。
library;

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/wallpaper.dart';
import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';

/// 设置的读写口。**必须在 `ProviderScope` 里覆盖**（见 `main.dart`）——
/// 它需要 `path_provider` 给的目录，而那是个异步调用，没法在 provider 里
/// 优雅地同步拿到。默认实现直接抛，免得漏了覆盖之后变成「设置改了不保存」
/// 这种安静的失败。
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => throw UnimplementedError('settingsStoreProvider 必须在 main 里覆盖'),
);

/// 启动时从磁盘读到的那份设置。
///
/// 单独开一个 provider 而不是让 `SettingsNotifier.build()` 自己去读文件：
/// `build()` 是同步的，而读文件是异步的。在 `main()` 里读完再覆盖进来，
/// 既省掉「等待期间显示什么主题」这个没答案的问题，也不会有一帧闪回默认色。
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  /// 改一项就落一次盘。这几项都是用户在设置页点一下就要生效的东西，
  /// 攒着一起写只会让「改完立刻杀进程」丢掉改动。
  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    unawaited(_save(state));
  }

  Future<void> _save(AppSettings s) async {
    try {
      await ref.read(settingsStoreProvider).save(s);
    } on Object {
      // 磁盘满、目录被删这类问题不该在设置页弹错误框：设置在当前这次运行里
      // 已经生效了，只是下次启动会退回旧值。
    }
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// 系统壁纸给出的主强调色；取不到为 null。
///
/// 用 `FutureProvider` 而不是启动时算一次：取色是通道调用，可能失败也可能
/// 在换壁纸后变化，让它自己带 `AsyncValue` 的状态比手工维护一个
/// 「正在取 / 取到了 / 没取到」的三态变量省事。
final wallpaperAccentProvider = FutureProvider<Color?>((ref) async {
  final palette = await createWallpaperSource().load();
  return palette == null ? null : Color(palette.accent1);
});

/// 当前生效的种子色。
///
/// 壁纸还没取到时用预设色兜底 —— 不能返回 null 让上层去等，
/// 那样启动瞬间会是一屏没有主题的灰。
final themeSeedProvider = Provider<Color>((ref) {
  // 只订它真正用到的那两个字段。订整份设置的话，改任何一项（提前量、门控
  // 半径、缩写……）都会重算一次种子色，进而让 `colorSchemeProvider` 重建、
  // 整个 App 换一套主题 —— 而种子色根本没变。
  //
  // 具名记录（record）按值比较，所以「改的恰好是这两项」时下游仍会收到通知，
  // 「改的是别的」时不会。
  final (colorSource, customSeedHex) = ref.watch(
    settingsProvider.select((s) => (s.colorSource, s.customSeedHex)),
  );
  final wallpaper = ref.watch(wallpaperAccentProvider).value;
  return resolveSeedFrom(
    source: colorSource,
    customSeedHex: customSeedHex,
    wallpaperAccent: wallpaper,
  );
});

/// 当前生效的配色方案。
///
/// 走的是 `ClassCalApp` 里**同一个** `buildTheme`，保证桌面小组件拿到的颜色
/// 和 App 界面里的一模一样 —— 两边各调一次 `ColorScheme.fromSeed` 的话，
/// 哪天主题构建改了参数，桌面上的卡片就会悄悄留在旧配色上。
///
/// `system` 那一档用 `PlatformDispatcher` 读系统明暗：这里没有 `context`，
/// 而小组件的快照是在 widget 树之外算的。系统明暗切换**不会**让这个 provider
/// 重建，但它会在下次回到前台 `flushNow()` 时被读到。
final colorSchemeProvider = Provider<ColorScheme>((ref) {
  final settings = ref.watch(settingsProvider);
  final seed = ref.watch(themeSeedProvider);
  final brightness = switch (settings.materialThemeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => PlatformDispatcher.instance.platformBrightness,
  };
  return buildTheme(brightness: brightness, seed: seed).colorScheme;
});
