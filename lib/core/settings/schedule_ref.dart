/// 「指向哪个日程」的统一写法。
///
/// 有三处要表达「总览 / 某一个日程」：标签页顺序、默认标签页、桌面小组件实例。
/// 其中后两处的值**要到运行期才知道**（日程 id 是自增的），所以用字符串而不是枚举 ——
/// 枚举的成员必须在编译期写死，而 `set:<id>` 里的 id 是用户导入课表时才产生的。
///
/// 词汇表只有三个：
///
/// ```
/// 'overview'   把所有日程合起来看的那个虚拟页
/// 'follow'     跟随当前打开的那个日程（只有小组件用）
/// 'set:<id>'   某一个具体的日程
/// ```
///
/// **`'overview'` 不是一个 `CalendarSet`。** 它没有 id、不能持久化、不参与导入合并、
/// 不进 JSON 备份、也没有自己的提醒设置 —— 它只是同一批事件的另一个视图。
/// 把这条记牢，下面每个 `int?` 的含义才不会含混。
library;

import 'package:flutter/foundation.dart';

abstract final class ScheduleRef {
  /// 把所有日程合起来看的那个虚拟页。
  static const String overview = 'overview';

  /// 跟随当前打开的那个日程。只有小组件用 —— 标签页顺序和默认标签页里
  /// 出现它是没有意义的（那样等于「上一秒停在哪就停在哪」）。
  static const String follow = 'follow';

  /// 还没有人设过。用它而不是 `null`，是因为这两处最终都要落到 JSON 里，
  /// 而 JSON 的 null 和「键不存在」在容错读取时是一回事，一个空串更直白。
  static const String unset = '';

  static String ofSet(int id) => 'set:$id';

  /// 这个 key 是不是「总览」。空串和坏串都返回 false。
  static bool isOverview(String? key) => key == overview;

  /// `set:<id>` → id。**总览、`follow`、空串、坏串一律返回 null** ——
  /// 想区分「是总览」和「认不出来」请另外用 [isOverview] 和 [isValid]，
  /// 不要从一个 `int?` 里读出三件事。
  static int? setIdOf(String? key) {
    if (key == null || !key.startsWith(_setPrefix)) return null;
    final id = int.tryParse(key.substring(_setPrefix.length));
    // id 必须为正：0 是 `kNoSetId` 那个「不属于任何日程」的哨兵，
    // 让它成为一个合法的日程引用，会让「没归属」和「第 0 号日程」撞车。
    return (id == null || id <= 0) ? null : id;
  }

  /// 认得出的 key（含总览）。空串和坏串返回 false。
  static bool isValid(String? key) =>
      key == overview || key == follow || setIdOf(key) != null;

  /// 能不能当**标签页**的 key。`follow` 不行 —— 见 [follow] 的注释。
  static bool isTabKey(String? key) => key == overview || setIdOf(key) != null;
}

const String _setPrefix = 'set:';

/// 标签栏里的一个条目：总览，或者某一个日程。
///
/// 存在的理由：标签栏要渲染的东西已经不只是数据库里那张表了，多了一个虚拟页；
/// 让 widget 拿着 `List<CalendarSet>` 再到处特判「总览」会把这个特判撒到
/// 每一处消费标签的地方。
@immutable
class TabEntry {
  const TabEntry({
    required this.key,
    required this.setId,
    required this.name,
    this.colorSeedHex,
  });

  /// [ScheduleRef] 词汇表里的串。它是这个条目的**身份** ——
  /// 比较、持久化、小组件的 `scope_<id>` 都用它。
  final String key;

  /// 总览条目为 null。**不是 `kNoSetId`** —— 那会把「总览」和「坏数据」
  /// 混成一个值，而这两者要走的回退路径完全不同。
  final int? setId;

  final String name;

  /// 总览条目为 null：它不是某个日程，不该借用某个日程的颜色。
  final String? colorSeedHex;

  bool get isOverview => setId == null;

  @override
  bool operator ==(Object other) =>
      other is TabEntry &&
      other.key == key &&
      other.setId == setId &&
      other.name == name &&
      other.colorSeedHex == colorSeedHex;

  @override
  int get hashCode => Object.hash(key, setId, name, colorSeedHex);

  @override
  String toString() => 'TabEntry($key, $name)';
}
