/// 主题构建。
///
/// 从 `main.dart` 里抽出来，是因为它现在要看设置（明暗、种子色）和平台
/// （壁纸调色板），已经不是一个纯常量了 —— 留在 `main.dart` 里会让那个文件
/// 同时负责「启动」和「配色」两件事。
library;

import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'course_colors.dart';

/// 由种子色构建亮/暗两套主题。
///
/// 只用 `accent1` 当种子、其余交给 `ColorScheme.fromSeed`：Material 的
/// 「角色 → 第几档」映射表版本之间会变，自己按表搬运系统色阶必然跟系统的
/// 实际观感走偏。种子对了，整套的调子就对了。
ThemeData buildTheme({
  required Brightness brightness,
  required Color seed,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    // 课表网格信息密度很高，紧凑一点能少滚动
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surfaceContainer,
      elevation: 0,
    ),
  );
}

/// 当前生效的种子色。
///
/// 三档优先级，顺序不能换：
///
/// 1. 用户手选的色 —— 他明确说过要什么，就不再猜；
/// 2. 壁纸调色板 —— 只有用户选了「跟着壁纸」才走这里；
/// 3. 预设的紫 —— 老系统、Windows、通道异常时兜底。
Color resolveSeed(AppSettings settings, Color? wallpaperAccent) => resolveSeedFrom(
      source: settings.colorSource,
      customSeedHex: settings.customSeedHex,
      wallpaperAccent: wallpaperAccent,
    );

/// 同 [resolveSeed]，但只认那两个真正决定种子的输入。
///
/// 拆出来是为了让 `themeSeedProvider` 能**只订这两个字段**：那个 provider
/// 订整份 `AppSettings` 的话，改任何一项（提前量、门控半径、缩写……）都会
/// 重算一次种子色，进而让整套主题跟着换，而种子色根本没变。
///
/// 保留 [resolveSeed] 这个收 `AppSettings` 的版本，是因为它已经是这一层
/// 对外的样子（`settings_test.dart` 里五条断言直接喂设置对象）。
Color resolveSeedFrom({
  required AppColorSource source,
  required String customSeedHex,
  required Color? wallpaperAccent,
}) {
  if (source == AppColorSource.custom) {
    return parseHexColor(customSeedHex) ?? const Color(0xFF6750A4);
  }
  return wallpaperAccent ?? parseHexColor(customSeedHex) ??
      const Color(0xFF6750A4);
}
