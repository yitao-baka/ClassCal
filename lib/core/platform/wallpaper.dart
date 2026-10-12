/// 壁纸取色 —— 平台无关的抽象。
///
/// 平台能力全部藏在接口后面，是**为了 Windows 端**：`flutter build windows`
/// 必须能过，不能因为某个包只支持 Android 就卡住整个工程。Android 走
/// MethodChannel，Windows 先给一个返回 null 的桩，等阶段 6 用 `win32` 的
/// `IDesktopWallpaper` 补上真实现 —— 到那时只换工厂里的一个分支。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 系统按壁纸算出的主题色。
///
/// 只留种子色而不是整套色阶：Material 的「角色 → 第几档」映射表版本之间会变，
/// 自己抄一份必然跟系统实际观感走偏。种子对了，`ColorScheme.fromSeed`
/// 展开出来的整套就跟壁纸一个调。
@immutable
class WallpaperPalette {
  const WallpaperPalette({
    required this.accent1,
    this.accent2,
    this.accent3,
  });

  /// 主强调色 —— 实际用来当种子的就是它。
  final int accent1;

  /// 次强调色。目前不参与构色，留着是因为「让用户从壁纸给出的几个调子里挑」
  /// 是个自然的下一步，先把数据取到手比事后补通道便宜。
  final int? accent2;
  final int? accent3;

  @override
  bool operator ==(Object other) =>
      other is WallpaperPalette &&
      other.accent1 == accent1 &&
      other.accent2 == accent2 &&
      other.accent3 == accent3;

  @override
  int get hashCode => Object.hash(accent1, accent2, accent3);
}

/// 取色来源。取不到时一律返回 null，**不抛异常**。
abstract class WallpaperSource {
  /// 当前壁纸的调色板；系统不支持或读取失败时为 null。
  Future<WallpaperPalette?> load();
}

/// 按平台挑实现。
WallpaperSource createWallpaperSource() {
  if (!kIsWeb && Platform.isAndroid) return MethodChannelWallpaperSource();
  return const UnsupportedWallpaperSource();
}

/// 走 `ThemeBridge.kt` 读 `android.R.color.system_accent*`。
class MethodChannelWallpaperSource implements WallpaperSource {
  const MethodChannelWallpaperSource();

  static const MethodChannel _channel =
      MethodChannel('com.jingjunyu.classcal/theme');

  @override
  Future<WallpaperPalette?> load() async {
    try {
      final raw = await _channel.invokeMapMethod<String, int>('wallpaperPalette');
      if (raw == null) return null;
      final a1 = raw['accent1'];
      if (a1 == null) return null;
      return WallpaperPalette(
        accent1: _argb(a1),
        accent2: raw['accent2'] == null ? null : _argb(raw['accent2']!),
        accent3: raw['accent3'] == null ? null : _argb(raw['accent3']!),
      );
    } on PlatformException {
      // 通道没接上（比如跑在测试里、或是换了 ROM）不是错误，
      // 只是没这个能力 —— 上层会退回预设主题。
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Java 的 `getColor` 返回**有符号** Int：`0xFF5C6BC0` 过来是负数。
  /// 直接丢给 `Color()` 会断言失败，必须先按 32 位掩码还原。
  static int _argb(int signed) => signed & 0xFFFFFFFF;
}

/// Windows / 其它平台。等阶段 6 换成 `win32` 读桌面壁纸。
class UnsupportedWallpaperSource implements WallpaperSource {
  const UnsupportedWallpaperSource();

  @override
  Future<WallpaperPalette?> load() async => null;
}
