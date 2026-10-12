/// 节次 ↔ 时间、周次 ↔ 日期 的换算。
///
/// 纯 Dart，不 import Flutter —— 这层是课表渲染和提醒调度的共同地基，
/// 保持无依赖才能在 `dart test` 里直接跑，不必起 widget 测试环境。
library;

/// 一个「大节」的上课时段。
///
/// 教务课表按「第一二节 / 第三四节」这样成对排课，所以时段的最小单位是两节，
/// 而不是单节。跨节次的课程块高度就是由这里推出来的。
class PeriodSlot {
  const PeriodSlot({
    required this.startPeriod,
    required this.endPeriod,
    required this.startMinute,
    required this.endMinute,
  });

  /// 起始节次，1-based。「第一二节」为 1。
  final int startPeriod;

  /// 结束节次，含。「第一二节」为 2。
  final int endPeriod;

  /// 距当日 00:00 的分钟数。
  ///
  /// 用「分钟数」而不是 `TimeOfDay` 或 `DateTime`，是为了让这一层不碰 Flutter
  /// 的 UI 类型、也不引入时区语义 —— 上课时间永远是本地墙上时间。
  final int startMinute;
  final int endMinute;

  int get durationMinutes => endMinute - startMinute;
}

/// 湖南科技大学 45 分钟制作息时间表。
///
/// 依据：第一节 08:00-08:45、第二节 08:55-09:40，逐节推出整块区间。
/// 作息表可能改版，因此全部集中在这一张表里 —— 要改只动这里。
const List<PeriodSlot> kPeriodSlots = <PeriodSlot>[
  PeriodSlot(startPeriod: 1, endPeriod: 2, startMinute: 8 * 60, endMinute: 9 * 60 + 40),
  PeriodSlot(startPeriod: 3, endPeriod: 4, startMinute: 10 * 60, endMinute: 11 * 60 + 40),
  PeriodSlot(startPeriod: 5, endPeriod: 6, startMinute: 14 * 60, endMinute: 15 * 60 + 40),
  PeriodSlot(startPeriod: 7, endPeriod: 8, startMinute: 16 * 60, endMinute: 17 * 60 + 40),
  PeriodSlot(startPeriod: 9, endPeriod: 10, startMinute: 19 * 60, endMinute: 20 * 60 + 40),
];

/// 课表网格的行数 = 大节数量。
int get kPeriodRowCount => kPeriodSlots.length;

const List<String> _cnDigits = <String>['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// 1..99 的中文数字，用于拼「第一二节」这类标签。
String chineseNumeral(int n) {
  if (n < 0) return '';
  if (n < 10) return _cnDigits[n];
  if (n == 10) return '十';
  if (n < 20) return '十${_cnDigits[n % 10]}';
  // 注意 `$tens十` 不加花括号是安全的：`十` 不是合法的标识符字符，
  // Dart 的词法分析在这里就结束了 `$tens`。
  final tens = _cnDigits[n ~/ 10];
  final ones = n % 10;
  return ones == 0 ? '$tens十' : '$tens十${_cnDigits[ones]}';
}

/// 「第一二节」。
String periodLabel(int startPeriod, int endPeriod) =>
    '第${chineseNumeral(startPeriod)}${chineseNumeral(endPeriod)}节';

/// 找到以 [startPeriod] 开头的大节；课表里出现未知节次时返回 null。
///
/// 返回 null 而不是抛异常，是因为导入的 ICS 可能来自别的学校、用别的作息；
/// 这种条目应该被跳过并计入「无法识别」，而不是让整个导入失败。
PeriodSlot? slotForStartPeriod(int startPeriod) {
  for (final slot in kPeriodSlots) {
    if (slot.startPeriod == startPeriod) return slot;
  }
  return null;
}

/// 找到**包含**第 [period] 节的大节；不在作息表里返回 null。
///
/// 和 [slotForStartPeriod] 是两件事，混用会静默算错时间：
/// 结束节次通常是大节的第二节（2 / 4 / 6 / 8 / 10），拿它去问
/// `slotForStartPeriod` 一律得到 null —— 于是「1-4 节连堂」的课会被
/// 算成 08:00-09:40（第 1-2 节的时长）而不是 08:00-11:40。
PeriodSlot? slotForPeriod(int period) {
  for (final slot in kPeriodSlots) {
    if (period >= slot.startPeriod && period <= slot.endPeriod) return slot;
  }
  return null;
}

/// 按开始时间反推大节 —— 外部日历只给钟点、不给「第几节」，导入时要靠这个还原。
///
/// 容忍 [toleranceMinutes] 的偏差：别的学校（或别的版本作息表）上下课时间可能差几分钟，
/// 严格相等匹配会把整批事件判成「不在任何节次」。取最接近的一个；超出容差返回 null，
/// 由调用方决定是丢弃还是降级成单次事件。
PeriodSlot? slotForMinute(int minute, {int toleranceMinutes = 15}) {
  PeriodSlot? best;
  var bestDiff = 1 << 30;
  for (final slot in kPeriodSlots) {
    final diff = (slot.startMinute - minute).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = slot;
    }
  }
  return bestDiff <= toleranceMinutes ? best : null;
}

/// 该大节在网格中的行号，0-based；找不到返回 null。
int? rowForStartPeriod(int startPeriod) {
  for (var i = 0; i < kPeriodSlots.length; i++) {
    if (kPeriodSlots[i].startPeriod == startPeriod) return i;
  }
  return null;
}

/// 某个钟点落在网格的哪一行，0-based；超出网格画的范围则返回 null。
///
/// 和 [slotForMinute] 是两件事，别互相顶替：
///
/// * [slotForMinute] 给**导入**用 —— 外部日历只给钟点，要靠「离哪个大节的开始
///   时间最近」猜它想说第几节，容差之外就认输。
/// * 这里给**渲染**用 —— 已经知道一件事发生在 14:30，只要指出它落在哪一行。
///   所以先看**包含**关系（14:30 在 14:00–15:40 之内），而不是看谁离得近。
///
/// 落在两节之间的课间或午休（如 12:00）时取**最近的那一节**（按到整段区间的
/// 距离算）：那一段本来就没有对应的行，非挑一个的话「刚下课那节」比「两小时后
/// 才上的那节」更接近它要表达的事。
int? rowForMinute(int minute) {
  // 网格只画「第一节课开始」到「最后一节结束」这一段。清早和深夜的事件没有
  // 对应的行，硬塞进第一行或最后一行会让人以为它就发生在那一节课上。
  if (minute < kPeriodSlots.first.startMinute ||
      minute > kPeriodSlots.last.endMinute) {
    return null;
  }

  var nearest = 0;
  var nearestGap = 1 << 30;
  for (var i = 0; i < kPeriodSlots.length; i++) {
    final slot = kPeriodSlots[i];
    // 到这个大节**整段**的距离。落在区间内就是 0，而 0 是最小可能值，
    // 所以「就在这节课上」自然压过其它行，不必再单独判一次包含。
    final gap = minute < slot.startMinute
        ? slot.startMinute - minute
        : (minute > slot.endMinute ? minute - slot.endMinute : 0);
    if (gap < nearestGap) {
      nearestGap = gap;
      nearest = i;
    }
  }
  return nearest;
}

/// 课程块在网格里跨几行（大节）。
///
/// 教务系统偶尔排出 1-4 节连上的课；这种块要占满两行，否则网格上会缺一块。
/// 遇到不落在整大节上的区间（如 1-3），按覆盖到的完整行数算。
int rowsSpanned(int startPeriod, int endPeriod) {
  final s = rowForStartPeriod(startPeriod);
  if (s == null) return 1;
  for (var i = kPeriodSlots.length - 1; i >= s; i--) {
    if (kPeriodSlots[i].endPeriod <= endPeriod) return i - s + 1;
  }
  return 1;
}

/// 分钟数 → `08:00`。
String formatMinutes(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// `08:00` → 分钟数；解析失败返回 null。
int? parseMinutes(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

// ---------------------------------------------------------------------------
// 周次 ↔ 日期
// ---------------------------------------------------------------------------

/// [week] 周、星期 [weekday]（1=周一 … 7=周日）对应的日期。
///
/// [week1Monday] 必须是第 1 周的周一 —— 整个课表的日期锚点。
DateTime dateFor({
  required DateTime week1Monday,
  required int week,
  required int weekday,
}) {
  final base = DateTime(week1Monday.year, week1Monday.month, week1Monday.day);
  return base.add(Duration(days: (week - 1) * 7 + (weekday - 1)));
}

/// [date] 落在第几周（[week1Monday] 所在周为第 1 周）。
///
/// 早于第 1 周的日期返回 0 或负数 —— 调用方自行判断是否在学期内。
int weekOf({required DateTime week1Monday, required DateTime date}) {
  final base = DateTime(week1Monday.year, week1Monday.month, week1Monday.day);
  final d = DateTime(date.year, date.month, date.day);
  return d.difference(base).inDays ~/ 7 + 1;
}

/// DateTime 的星期，1=周一 … 7=周日（`DateTime.weekday` 已是这个约定，这里只是显式化）。
int isoWeekday(DateTime d) => d.weekday;

/// 只保留年月日，抹掉时间部分。
///
/// 平移、比较日期时必须先归一化 —— 带时分秒的 DateTime 做 `==` 或 `difference`
/// 会得到反直觉的结果（例如跨夏令时、或 3 天 23 小时被 ~/ 成 3）。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 两个日期是否同一天。
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
