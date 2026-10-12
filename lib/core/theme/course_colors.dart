/// 课程配色。
///
/// 默认按课程标题哈希从一张预设调色板里取色 —— 同一门课无论出现在星期几、
/// 第几节，颜色都一致，整个网格读起来才有意义（人眼靠颜色追踪一门课，
/// 而不是靠读文字）。用户手动指定的颜色优先。
library;

import 'package:flutter/material.dart';

/// 给课程用的候选色。刻意选了饱和度中等偏高的深色：网格块上要压白字，
/// 太浅会看不清。全部落在 Material 500/600 一档。
const List<Color> kCoursePalette = <Color>[
  Color(0xFF5C6BC0), // indigo
  Color(0xFF26A69A), // teal
  Color(0xFFEF5350), // red
  Color(0xFF7E57C2), // deep purple
  Color(0xFF42A5F5), // blue
  Color(0xFF66BB6A), // green
  Color(0xFFFFA726), // orange
  Color(0xFFEC407A), // pink
  Color(0xFF8D6E63), // brown
  Color(0xFF29B6F6), // light blue
  Color(0xFF9CCC65), // light green
  Color(0xFFAB47BC), // purple
];

/// 主题色的备选。
///
/// 和 [kCoursePalette] 刻意不同：那一张是给**课程块**用的，要压白字所以偏深；
/// 这一张是给**主题种子**用的，交给 `ColorScheme.fromSeed` 展开成整套色阶，
/// 太深反而会把整套压暗。所以挑的是中等明度、彼此色相拉得开的几个。
const List<Color> kSeedSwatches = <Color>[
  Color(0xFF6750A4), // 紫，Material 默认
  Color(0xFF0061A4), // 蓝
  Color(0xFF00696D), // 青
  Color(0xFF3F6B2C), // 绿
  Color(0xFF8B5000), // 橙棕
  Color(0xFF9A4057), // 玫红
  Color(0xFF6B4E9B), // 蓝紫
  Color(0xFF4A6267), // 灰蓝
];

/// 解析 `#RRGGBB` / `#AARRGGBB`（也接受不带 `#`）。失败返回 null。
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(v);
}

/// `Color` → `#RRGGBB`，供落库。
String toHexColor(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
}

/// 哈希取值而不是随机 —— 随机的话每次重建颜色都在跳，而且同一门课在不同
/// 日期会不一致。用稳定的字符串哈希保证「同标题同色」。
int _stableHash(String s) {
  var h = 0x811C9DC5; // FNV-1a 32 位
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// 课程的最终颜色：[overrideHex] 优先，否则按 [title] 从调色板取。
Color courseColor(String title, {String? overrideHex}) {
  final custom = parseHexColor(overrideHex);
  if (custom != null) return custom;
  if (title.isEmpty) return kCoursePalette.first;
  return kCoursePalette[_stableHash(title) % kCoursePalette.length];
}

/// 与课程色相配的前景色（文字/图标）。
Color onCourseColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
