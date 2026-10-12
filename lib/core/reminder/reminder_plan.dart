/// 「下次该在什么时刻弹哪条提醒」—— 纯计算，不碰平台、不碰 Flutter。
///
/// 单独成一层，是因为这一层错了**看不见**：提醒要么不响，要么响错时间，
/// 而这两件事都只在真实的一节课前几分钟才暴露，没法靠点点界面发现。写成纯函数
/// 就能用 `dart test` 把边界（提前量、跨日、停课、超出窗口）一次钉死。
///
/// 平台侧的职责被压到最小：拿到一张「(时刻, 标题, 正文, 可选门控点)」的表格，
/// 到点弹窗、按需做一次定位判断。**算「该不该提醒」在这里，算「在哪」在原生**。
library;

import '../settings/app_settings.dart';
import '../time/periods.dart';
import '../../data/model/resolve.dart';

/// 一条排给系统的提醒。
///
/// 刻意是**扁平的纯数据**（没有 SavedPlace、没有 ResolvedSession）：它要跨进程
/// 边界传给原生侧并落盘成 JSON，能少一个类型依赖就少一个。
class ReminderSpec {
  const ReminderSpec({
    required this.id,
    required this.key,
    required this.fireAt,
    required this.title,
    required this.body,
    this.gateLat,
    this.gateLng,
    this.gateRadiusMeters = 0,
    this.nearby,
    this.timeoutMs = 0,
    this.repeatIntervalMs = 0,
    this.classStartMs = 0,
  });

  /// 给 `AlarmManager` 用的 requestCode，稳定且非 0。
  final int id;

  /// 可读的稳定标识（`rule:12@2026-10-13`）。调试时看日志用；
  /// 幂等去重也靠它 —— 同一个 key 永远算出同一个 [id]。
  final String key;

  /// 触发时刻，**本地墙上时间**。
  final DateTime fireAt;

  final String title;
  final String body;

  /// 门控点；两个都为 null 表示这条不门控。
  final double? gateLat;
  final double? gateLng;
  final int gateRadiusMeters;

  /// 判定为「就在教室里」之后怎么办：[NearbyMode.skip] 不弹，
  /// [NearbyMode.silent] 弹但不出声。没有门控时为 null。
  ///
  /// **判断「在不在教室」在原生侧**（那时候 App 是死的，起不了 Dart），但
  /// **判断「在教室附近该怎么办」在这里** —— 它是用户的设置，和定位本身无关，
  /// 而且这样调整行为不需要动 Kotlin。
  final NearbyMode? nearby;

  /// 弹出后多久自动消失，毫秒；0 表示不自动清除。
  final int timeoutMs;

  /// 每隔多久再弹一次，毫秒；0 表示只弹一次。
  final int repeatIntervalMs;

  /// 这节课的**开始时刻**（epoch 毫秒），重复提醒到这一刻必须停。
  ///
  /// 单独传一个绝对时刻而不是传「还有多少分钟」：原生侧要靠它判断「现在还该
  /// 不该响」，而那个判断发生在闹钟响的时候 —— 传相对值的话，每重复一次都得
  /// 重新算一遍剩余时间，算错一次就是下课后还追着人响。
  final int classStartMs;

  bool get gated => gateLat != null && gateLng != null;

  /// 要不要反复提醒。两个值都要有才成立：只有间隔没有终止时刻，这条链就停不下来。
  bool get repeats => repeatIntervalMs > 0 && classStartMs > 0;

  Map<String, Object?> toJson() => {
        'id': id,
        'key': key,
        'fireAtMs': fireAt.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        if (gateLat != null) 'gateLat': gateLat,
        if (gateLng != null) 'gateLng': gateLng,
        'gateRadiusMeters': gateRadiusMeters,
        if (nearby != null) 'nearby': nearby!.name,
        'timeoutMs': timeoutMs,
        'repeatIntervalMs': repeatIntervalMs,
        'classStartMs': classStartMs,
      };

  @override
  String toString() => 'ReminderSpec($key @ $fireAt'
      '${gated ? ' 门控 ${gateRadiusMeters}m/${nearby?.name}' : ''}'
      '${timeoutMs > 0 ? ' ${timeoutMs ~/ 60000} 分钟后自动清除' : ''}'
      '${repeats ? ' 每 ${repeatIntervalMs ~/ 60000} 分钟重复到上课' : ''})';
}

/// 算出来的提醒表 + 几个给界面看的数字。
class ReminderPlan {
  const ReminderPlan({
    required this.specs,
    required this.totalInWindow,
    required this.gatedCount,
  });

  static const ReminderPlan empty =
      ReminderPlan(specs: [], totalInWindow: 0, gatedCount: 0);

  final List<ReminderSpec> specs;

  /// 窗口内本应有几条（去掉被 [buildReminderPlan] 丢弃的重复后）。
  /// 和 `specs.length` 不等只可能是撞了 [kMaxReminders] 上限。
  final int totalInWindow;

  final int gatedCount;

  DateTime? get firstAt => specs.isEmpty ? null : specs.first.fireAt;

  bool get truncated => totalInWindow > specs.length;
}

/// 一次最多排多少条。
///
/// 每条一个 `AlarmManager` 闹钟，几百条不但没必要（系统对每个 app 的闹钟数量
/// 有软上限），而且每次同步都要重排一遍。两周的课约 40-60 条，120 条已经覆盖
/// 大半个月 —— 而 App 只要被打开就会重新排一次。
const int kMaxReminders = 120;

/// 往后排多远。
///
/// 超出这个窗口的课不排：**窗口是「多久没打开过 App」的容忍度**。用户一学期
/// 不开 App 也不会漏掉两周内的提醒；而多排的每一条都要占用一个系统闹钟位。
const Duration kReminderHorizon = Duration(days: 30);

/// 把解析后的上课时刻折成提醒表。
///
/// [now] 由调用方传入而不是内部取 —— 时间是这个函数唯一的隐含输入，
/// 让它显式化才能在测试里把「刚好差 1 分钟」「已经过去了」这些边界钉死。
///
/// **每一节课的参数都按它所属的日程（`ResolvedSession.setId`）三层解析**：
/// 单课覆盖 → 日程 → 全局。三层怎么合成见函数体里那一段注释。
ReminderPlan buildReminderPlan({
  required List<ResolvedSession> sessions,
  required AppSettings settings,
  required DateTime now,
  Duration horizon = kReminderHorizon,
  int maxCount = kMaxReminders,
}) {
  // 全局总开关是这个**功能**的总闸，不随日程变；所以有效开关是三层与。
  if (!settings.remindersEnabled) return ReminderPlan.empty;

  final end = now.add(horizon);
  final byKey = <String, ReminderSpec>{};

  for (final s in sessions) {
    // 停课的条目在解析结果里是**保留**的（为了能点开撤销），所以这里必须显式
    // 滤掉 —— 不然「停课一次」之后提醒照响，是这套设计里最容易漏的一处。
    if (s.cancelled) continue;
    if (!s.remindersEnabled) continue;

    // 三层解析。**每一层「没设」的表达方式都不一样**，所以这里不能改成统一写法：
    //
    // * **开关是「与」而不是「就近优先」**（所以是 `continue` 而不是往下取一个值）：
    //   `CourseTemplate.remindersEnabled` 是普通 bool 且默认 true，**它表达不了
    //   「没设过」**，只在用户明确关掉某一门课时才有信息量。让它参与「就近优先」，
    //   会把日程层那个开关整个吃掉。
    // * 其余各项都是**就近优先**：日程层没有这块（整块 null = 跟随全局）就落到全局。
    // * **地点 [AppSettings.places] 永远是全局的**：它是「我到过哪些地方」这个事实，
    //   不是某个日程的偏好；每个日程各存一份，用户就得在每个日程里重录同一栋楼。
    final block = settings.remindersFor(s.setId);
    if (block != null && !block.remindersEnabled) continue;

    final lead = block?.defaultLeadMinutes ?? settings.defaultLeadMinutes;
    final nearbyMode = block?.nearbyMode ?? settings.nearbyMode;
    final radiusMeters = block?.gateRadiusMeters ?? settings.gateRadiusMeters;
    final timeoutMinutes =
        block?.notificationTimeoutMinutes ?? settings.notificationTimeoutMinutes;
    final repeats = block?.repeatReminders ?? settings.repeatReminders;
    final repeatMinutes =
        block?.repeatIntervalMinutes ?? settings.repeatIntervalMinutes;

    final fireAt = _fireAtFor(s, lead);
    if (!fireAt.isAfter(now)) continue; // 已经过去了，别补一条迟到的
    if (fireAt.isAfter(end)) continue;

    // 只在需要门控时才去配地点：`remind` 那条路压根不看位置，这里算出来的
    // 任何东西都会是死数据，而且「没配地点」和「配了但不用」在原生侧是两回事。
    final place = nearbyMode == NearbyMode.remind
        ? null
        : matchPlace(s.location, settings.places);
    final key = _keyFor(s);
    byKey[key] = ReminderSpec(
      id: reminderIdFor(key),
      key: key,
      fireAt: fireAt,
      title: s.title,
      body: _bodyFor(s),
      gateLat: place?.lat,
      gateLng: place?.lng,
      gateRadiusMeters: place == null ? 0 : radiusMeters,
      nearby: place == null ? null : nearbyMode,
      timeoutMs: timeoutMinutes * 60 * 1000,
      repeatIntervalMs: repeats ? repeatMinutes * 60 * 1000 : 0,
      // 用的是**平移之后**的上课时刻，和 `fireAt` 同一套坐标 —— 两者要是
      // 取自不同的地方（一个平移过一个没平移），重复提醒就会在上课后接着响。
      classStartMs: _startAtFor(s).millisecondsSinceEpoch,
    );
  }

  final specs = byKey.values.toList()..sort((a, b) {
      final d = a.fireAt.compareTo(b.fireAt);
      // 同一时刻的按 id 排，保证同步给原生的顺序是确定的 —— 顺序不定会让
      // 「每次同步都重排一遍」的原生侧每次收到不同的列表。
      return d != 0 ? d : a.id.compareTo(b.id);
    });

  return ReminderPlan(
    specs: specs.length > maxCount ? specs.sublist(0, maxCount) : specs,
    totalInWindow: specs.length,
    gatedCount: specs.where((s) => s.gated).length,
  );
}

/// 提醒时刻 = 开始时刻 − 提前量。
///
/// 减出来跨天（比如 00:05 的课提前 30 分钟）不作特殊处理：`DateTime` 自己会
/// 走到前一天，而闹钟本来就该在那时候响。
DateTime _fireAtFor(ResolvedSession s, int defaultLeadMinutes) {
  // 单课覆盖优先；脏数据夹到 [0, 24h]，负数会让提醒落在下课后。
  final lead = (s.leadMinutes ?? defaultLeadMinutes)
      .clamp(0, AppSettings.kMaxLeadMinutes);
  return _startAtFor(s).subtract(Duration(minutes: lead));
}

/// 这节课的开始时刻。
///
/// 单独提出来是因为重复提醒要它 [ReminderSpec.classStartMs]：提醒时刻和上课
/// 时刻必须是同一次算出来的**两个视图**，各算各的就会在上课之后继续追着人响。
DateTime _startAtFor(ResolvedSession s) =>
    DateTime(s.date.year, s.date.month, s.date.day)
        .add(Duration(minutes: s.startMinute));

String _bodyFor(ResolvedSession s) {
  final buffer = StringBuffer('${formatMinutes(s.startMinute)} 开始');
  if (s.location.trim().isNotEmpty) buffer.write(' · ${s.location.trim()}');
  if (s.teacher.trim().isNotEmpty) buffer.write(' · ${s.teacher.trim()}');
  return buffer.toString();
}

/// 一次排课的稳定标识。
///
/// 单次事件和规律课程共用同一个 key 空间：两者的 id 各自独立自增，
/// 不区分来源的话「规则 3」和「单次事件 3」会撞成同一条，其中一节课
/// 就永远不会有提醒。
String _keyFor(ResolvedSession s) {
  final day = '${s.date.year}-${s.date.month}-${s.date.day}';
  if (s.ruleId != null) return 'rule:${s.ruleId}@$day';
  if (s.oneOffId != null) return 'one:${s.oneOffId}@$day';
  // 既不是规则也不是单次事件 —— 只有构造出来的测试数据会这样。
  return 'raw:${s.title}@$day';
}

/// key → 稳定的 32 位正整数 id（`AlarmManager` 的 requestCode 不能为 0）。
///
/// 用 FNV-1a 而不是 `String.hashCode`：后者只保证在**同一次运行内**一致，
/// 换个 Dart 版本就可能变，而这里的 id 要和已排好的系统闹钟对上，
/// 一旦对不上就是「取消不掉的幽灵闹钟」。
int reminderIdFor(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  // 收进 31 位（正的 Int）并避开 0。
  return (hash & 0x7FFFFFFF) | 1;
}

/// 课程地点落在哪个记下来的地点上；没有匹配返回 null。
///
/// 用**包含**匹配且**名字长的赢**：「第一教学楼」和「教学楼」同时命中
/// 「第一教学楼303」时，取前者 —— 它更具体，坐标也更可能是对的那一个。
SavedPlace? matchPlace(String location, List<SavedPlace> places) {
  final loc = location.trim();
  if (loc.isEmpty) return null;

  SavedPlace? best;
  var bestLen = 0;
  for (final p in places) {
    final name = p.name.trim();
    if (name.isEmpty || name.length <= bestLen) continue;
    if (!loc.contains(name)) continue;
    best = p;
    bestLen = name.length;
  }
  return best;
}
