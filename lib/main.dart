import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/localization.dart';
import 'app/native_sync.dart';
import 'app/settings_providers.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'features/home_page.dart';
import 'features/settings/widget_page.dart';

/// 全局的导航器。
///
/// 小组件上的齿轮要能在**没有 `BuildContext` 的地方**推一页出来
/// （`_NativeSyncHost` 里 `consumeLaunch()` 拿回一个 appWidgetId 时），
/// 所以得有这么一把钥匙。
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // 下面要用 path_provider 拿目录，得先把绑定初始化好
  WidgetsFlutterBinding.ensureInitialized();

  // 设置在**跑起来之前**读盘。改成在 `MaterialApp` 里用 FutureBuilder 等，
  // 换来的只是一帧默认主题的闪回 —— 而主题闪一下特别显眼。
  final store = SettingsStore(
    File('${(await getApplicationSupportDirectory()).path}/settings.json'),
  );
  final settings = await store.load();

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const _NativeSyncHost(child: ClassCalApp()),
    ),
  );
}

/// 让原生同步活起来，并在回到前台时补跑一次。
///
/// 为什么需要这样一个「什么都不画」的组件：同步是**副作用**，它挂在
/// `nativeSyncProvider` 上，而 Riverpod 的 provider 是懒的 —— 没有任何东西读它，
/// 副作用就永远不会挂上去。表现是「设置页里一切都对，就是一条提醒都不响、
/// 桌面小组件一直是空的」，而且从代码上完全看不出来。
///
/// 回到前台要再同步一遍：离开的这段时间可能已经跨过好几条提醒（或者整个
/// 学期的课表都被改了），而 Android 端的定时刷新最快也要 15 分钟。
class _NativeSyncHost extends ConsumerStatefulWidget {
  const _NativeSyncHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_NativeSyncHost> createState() => _NativeSyncHostState();
}

class _NativeSyncHostState extends ConsumerState<_NativeSyncHost> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(nativeSyncProvider).flushNow();
        // 齿轮那条路在**冷启动**和**App 已经在跑**两种情况下都会落到这里：
        // 前者由 `MainActivity.configureFlutterEngine` 把 id 存好，后者由
        // `onNewIntent` 存。所以「首帧」和「每次回到前台」都问一次，
        // 那两种路径就都覆盖到了（原生侧取一次就清，重复问是安全的）。
        _consumeLaunchTarget();
      },
    );
    // 首帧之后再问：`navigatorKey.currentState` 要等第一帧才非空。
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeLaunchTarget());
  }

  /// 「这次启动是为了配置某个小组件」的那一次。
  ///
  /// **拉而不是等原生推**：`MethodChannel` 是双向的，但 Dart 这边挂上监听之前
  /// 原生发的调用会直接丢掉 —— 而那时 AppWidgetProvider 早就被系统叫起来过了。
  /// 让原生只把 id 存着、我们主动问，就没有这个时间窗。
  Future<void> _consumeLaunchTarget() async {
    final id = await ref.read(homeWidgetBridgeProvider).consumeLaunch();
    if (!mounted || id == null) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    pushWidgetConfig(navigator, id);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 这个 watch 是**功能性的**，不是风格问题：Riverpod 3 会把「没人监听」的
    // provider 连同它的订阅递归地暂停掉，而暂停的 `StreamProvider` 连底层流都
    // 收不到消息。写成 `ref.read` 的话提醒和小组件会一起静默失效。
    // 完整来龙去脉见 `nativeSyncProvider` 的注释。
    ref.watch(nativeSyncProvider);
    return widget.child;
  }
}

class ClassCalApp extends ConsumerWidget {
  const ClassCalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **只订这一个字段，不订整份 `AppSettings`。**
    //
    // 这里原来写的是 `ref.watch(settingsProvider)`，而下面只用到
    // `materialThemeMode`。代价是每写一次设置都要重建 `MaterialApp`，而
    // `theme` / `darkTheme` 两行会各跑一次 `ColorScheme.fromSeed`
    // （`app_theme.dart`）—— 那是重算整套 Material 色调表，两次。
    //
    // 于是「在设置页点一个 radio / 开一个开关 / 拖一下滑块」都会顺带重算
    // 两套调色板。`.select` 把这一层收窄到「明暗真的换了」，其余写入不再
    // 波及整个 App。
    final materialThemeMode = ref.watch(
      settingsProvider.select((s) => s.materialThemeMode),
    );
    final seed = ref.watch(themeSeedProvider);

    return MaterialApp(
      title: 'ClassCal',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      // 少了这两行不会报错，只会让选时间、选日期这些自带弹窗按**设备语言**
      // 渲染 —— 中文界面上弹出 "Select time / Cancel / OK"。配置本身在
      // `app/localization.dart`，那边的注释写了为什么不跟随系统语言。
      localizationsDelegates: kLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      theme: buildTheme(brightness: Brightness.light, seed: seed),
      darkTheme: buildTheme(brightness: Brightness.dark, seed: seed),
      themeMode: materialThemeMode,
      home: const HomePage(),
    );
  }
}
