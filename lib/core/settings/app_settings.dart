/// 应用级设置。
///
/// 和课表数据分开存，理由不只是「类型不同」：课表走 drift 是因为它需要
/// 带索引的日期区间查询；这几项是**零散的开关**，为它加一张表就要动
/// schema 版本、写迁移、还得考虑旧装的用户 —— 收益却只是省一个文件。
///
/// 存 JSON 文件（而不是 `shared_preferences`）则是为了少一个依赖：读写的
/// 目录本来就靠 `path_provider` 拿到了，而这个依赖已经在了。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../text/course_abbr.dart';
import 'schedule_ref.dart';

/// 主题明暗。
enum AppThemeMode { system, light, dark }

/// 主题色的来源。
enum AppColorSource {
  /// 跟着系统壁纸走（Android 12+ 由系统算好的 Material You 调色板）。
  wallpaper,

  /// 用户手选的一个颜色。
  custom,
}

/// 人已经在教室附近时，这次提醒该怎么办。
///
/// **三态而不是一个开关**，是真机上跑出来的结论。原来只有「提醒 / 不提醒」，
/// 而第三态恰恰是最常见的那种心情 —— 人已经到教学楼了，却还想扫一眼确认今天
/// 这节是不是换了教室。只给「不提醒」的话，这些人就只能二选一：要么被打扰，
/// 要么什么也看不到。
///
/// 而且门控**静默生效时和坏掉长得一模一样**：用户没法区分「它判断我在教室所以
/// 没响」和「它压根没响」。真机上第一次跑就撞上了这个 —— 14:15 的闹钟按设计
/// 跳过了提醒，而人看到的是「没有闹钟响」。
enum NearbyMode {
  /// 不做门控：到点就正常提醒。
  remind,

  /// 就在教室里，不必再响 —— 直接不弹。
  skip,

  /// 照常弹出来，但不出声（没有铃声、没有振动）。
  silent,
}

/// 一个记下来的地点 —— 把课程表里的地点**字符串**换算成坐标。
///
/// 为什么是「记地点」而不是「给每门课打经纬度」：教务系统给的是
/// 「第一教学楼303」「十教附楼-302」这种自由文本，一学期二十几门课、
/// 十来个地点，逐个打点要打二十几次，而按楼记一次就够 —— 一栋楼的尺度
/// 远小于 200m 的门控半径，同楼不同教室根本区分不出来，也没必要区分。
@immutable
class SavedPlace {
  const SavedPlace({
    required this.name,
    required this.lat,
    required this.lng,
  });

  /// 楼名。和课程的 `location` 做**包含**匹配，重合时名字长的赢。
  final String name;
  final double lat;
  final double lng;

  Map<String, Object?> toJson() => {'name': name, 'lat': lat, 'lng': lng};

  /// 坐标越界的一律丢弃 —— 一个经纬度写反的条目（比如把 112.9 写成 91.2）
  /// 会让门控**永远判定为「不在教室」**，而那种失败看起来跟「定位没拿到」
  /// 一模一样，极难查。宁可当作没这个地点。
  static SavedPlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final lat = _num(raw['lat']);
    final lng = _num(raw['lng']);
    if (name is! String || name.trim().isEmpty) return null;
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return SavedPlace(name: name.trim(), lat: lat, lng: lng);
  }

  static double? _num(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  @override
  bool operator ==(Object other) =>
      other is SavedPlace &&
      other.name == name &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(name, lat, lng);

  @override
  String toString() => 'SavedPlace($name @ $lat,$lng)';
}

/// 某一个日程自己的提醒设置。
///
/// **整块可空**：`AppSettings.setReminders` 里没有这个 setId 的项，就是「跟随
/// 全局默认」。为什么是整块而不是逐字段的「跟随」哨兵 —— 界面上就是一个开关，
/// 语义就该是一个开关。逐字段哨兵要写七个「有没有设过」，也要在界面上表达七次
/// 「这一项是继承的还是自己的」，而用户心里想的是「这个日程的提醒我要单独配」。
///
/// 字段名**照抄全局那一套**，只有提前量例外：它叫 [defaultLeadMinutes] 而不是
/// `leadMinutes`，因为 `leadMinutes` 在本项目里已经被 `CourseTemplate.leadMinutes`
/// 占用，含义是「**这门课**的覆盖」。日程块里再用这个名字，正好会在最容易搞混的
/// 那一处（三层里谁的提前量赢）制造视觉撞车。叫 `defaultLeadMinutes` 之后解析链
/// 读起来是对称的：`block?.defaultLeadMinutes ?? settings.defaultLeadMinutes`。
///
/// **七个字段全部必填**，没有「留空就用默认」的构造：这个项目里关于「默认值是多少」
/// 只该有一个说法，就是 [AppSettings] 的构造参数。想要一份默认值，用
/// [SetReminderSettings.fromGlobal] 从一份设置里取，不要在这里再抄一遍数字 ——
/// 抄出来的第二份迟早会和第一份不一样，而症状是「关掉跟随之后提前量莫名从 15 变 20」。
@immutable
class SetReminderSettings {
  const SetReminderSettings({
    required this.remindersEnabled,
    required this.defaultLeadMinutes,
    required this.nearbyMode,
    required this.gateRadiusMeters,
    required this.notificationTimeoutMinutes,
    required this.repeatReminders,
    required this.repeatIntervalMinutes,
  });

  /// 拿全局的当下值当这份覆盖的初值。
  ///
  /// 用在两处：界面上关掉「跟随全局默认」那一刻（用户的意思是「在现在的基础上
  /// 改一点」，不是「重置成出厂设置」），以及 JSON 里某个块缺字段时的兜底。
  factory SetReminderSettings.fromGlobal(AppSettings s) => SetReminderSettings(
        remindersEnabled: s.remindersEnabled,
        defaultLeadMinutes: s.defaultLeadMinutes,
        nearbyMode: s.nearbyMode,
        gateRadiusMeters: s.gateRadiusMeters,
        notificationTimeoutMinutes: s.notificationTimeoutMinutes,
        repeatReminders: s.repeatReminders,
        repeatIntervalMinutes: s.repeatIntervalMinutes,
      );

  final bool remindersEnabled;
  final int defaultLeadMinutes;
  final NearbyMode nearbyMode;
  final int gateRadiusMeters;
  final int notificationTimeoutMinutes;
  final bool repeatReminders;
  final int repeatIntervalMinutes;

  SetReminderSettings copyWith({
    bool? remindersEnabled,
    int? defaultLeadMinutes,
    NearbyMode? nearbyMode,
    int? gateRadiusMeters,
    int? notificationTimeoutMinutes,
    bool? repeatReminders,
    int? repeatIntervalMinutes,
  }) =>
      SetReminderSettings(
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        defaultLeadMinutes: defaultLeadMinutes ?? this.defaultLeadMinutes,
        nearbyMode: nearbyMode ?? this.nearbyMode,
        gateRadiusMeters: gateRadiusMeters ?? this.gateRadiusMeters,
        notificationTimeoutMinutes:
            notificationTimeoutMinutes ?? this.notificationTimeoutMinutes,
        repeatReminders: repeatReminders ?? this.repeatReminders,
        repeatIntervalMinutes:
            repeatIntervalMinutes ?? this.repeatIntervalMinutes,
      );

  Map<String, Object?> toJson() => {
        'remindersEnabled': remindersEnabled,
        'defaultLeadMinutes': defaultLeadMinutes,
        'nearbyMode': nearbyMode.name,
        'gateRadiusMeters': gateRadiusMeters,
        'notificationTimeoutMinutes': notificationTimeoutMinutes,
        'repeatReminders': repeatReminders,
        'repeatIntervalMinutes': repeatIntervalMinutes,
      };

  /// 数值范围**照抄全局那一套常量**（别名而不是重写数字），夹到区间而不是丢弃
  /// —— 和 [AppSettings._int] 的既有策略一致。缺字段的那一项退回出厂默认。
  static SetReminderSettings? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final d = SetReminderSettings.fromGlobal(const AppSettings());
    return SetReminderSettings(
      remindersEnabled: AppSettings._bool(m['remindersEnabled']) ?? d.remindersEnabled,
      defaultLeadMinutes: AppSettings._int(
            m['defaultLeadMinutes'],
            min: 0,
            max: AppSettings.kMaxLeadMinutes,
          ) ??
          d.defaultLeadMinutes,
      nearbyMode:
          AppSettings._byName(NearbyMode.values, m['nearbyMode']) ?? d.nearbyMode,
      gateRadiusMeters: AppSettings._int(
            m['gateRadiusMeters'],
            min: AppSettings.kMinRadiusMeters,
            max: AppSettings.kMaxRadiusMeters,
          ) ??
          d.gateRadiusMeters,
      notificationTimeoutMinutes: AppSettings._int(
            m['notificationTimeoutMinutes'],
            min: 0,
            max: AppSettings.kMaxTimeoutMinutes,
          ) ??
          d.notificationTimeoutMinutes,
      repeatReminders:
          AppSettings._bool(m['repeatReminders']) ?? d.repeatReminders,
      repeatIntervalMinutes: AppSettings._int(
            m['repeatIntervalMinutes'],
            min: AppSettings.kMinRepeatMinutes,
            max: AppSettings.kMaxRepeatMinutes,
          ) ??
          d.repeatIntervalMinutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SetReminderSettings &&
      other.remindersEnabled == remindersEnabled &&
      other.defaultLeadMinutes == defaultLeadMinutes &&
      other.nearbyMode == nearbyMode &&
      other.gateRadiusMeters == gateRadiusMeters &&
      other.notificationTimeoutMinutes == notificationTimeoutMinutes &&
      other.repeatReminders == repeatReminders &&
      other.repeatIntervalMinutes == repeatIntervalMinutes;

  @override
  int get hashCode => Object.hash(
        remindersEnabled,
        defaultLeadMinutes,
        nearbyMode,
        gateRadiusMeters,
        notificationTimeoutMinutes,
        repeatReminders,
        repeatIntervalMinutes,
      );
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.colorSource = AppColorSource.wallpaper,
    this.customSeedHex = kDefaultSeedHex,
    this.remindersEnabled = true,
    this.defaultLeadMinutes = 15,
    this.nearbyMode = NearbyMode.remind,
    this.gateRadiusMeters = 200,
    this.notificationTimeoutMinutes = 0,
    this.repeatReminders = false,
    this.repeatIntervalMinutes = 5,
    this.setReminders = const {},
    this.places = const [],
    this.courseAbbrs = const {},
    this.tabOrder = const [],
    this.defaultTab = ScheduleRef.unset,
    this.overviewEnabled = true,
  });

  final AppThemeMode themeMode;
  final AppColorSource colorSource;

  /// `#RRGGBB`。取不到壁纸色时的兜底，也是用户手选的那个色。
  final String customSeedHex;

  // ---------------------------------------------------------------------------
  // 课前提醒
  // ---------------------------------------------------------------------------

  /// 提醒总开关。关掉之后不再往系统里排任何闹钟。
  final bool remindersEnabled;

  /// 默认提前几分钟。单门课可以在课程编辑里覆盖。
  final int defaultLeadMinutes;

  /// 已经在教室附近时怎么办。见 [NearbyMode]。
  ///
  /// **默认 [NearbyMode.remind]**，也就是不做门控：另外两态要的是「始终允许」
  /// 级别的位置权限，比通知权限更重的一步授权，不该在用户还没看见这个设置的时候
  /// 就替他做决定。选了之后设置页会说清代价。
  final NearbyMode nearbyMode;

  /// 门控半径（米）。所有地点共用 —— 教学楼的尺度就那么点，
  /// 给每栋楼单独配半径只是多几个要维护的数字。
  final int gateRadiusMeters;

  /// 提醒弹出后多久自动消失，单位分钟；**0 表示不自动清除**。
  ///
  /// 上课铃响之后，通知栏里那条「还有 15 分钟上课」就只是噪音了，而且会一直
  /// 待在那儿到下次清理 —— 尤其是上午的提醒堆到晚上还挂着，第二天看见会以为
  /// 是当天的课。
  final int notificationTimeoutMinutes;

  /// 同一条提醒反复弹，直到用户按「我已到教室」或者已经上课。
  ///
  /// 存在理由是「一条会被忽略的提醒等于没提醒」：上课前 15 分钟那条弹出来时，
  /// 人多半正走在路上、或者手上还压着一件事，扫一眼就划掉了 —— 而划掉之后
  /// 什么也不会再发生。开了这个之后它会按 [repeatIntervalMinutes] 一直追，
  /// 直到人真的到了教室（按下按钮）或者已经不需要提醒了（上课）。
  ///
  /// **默认关**：会重复响的东西必须由用户明确选择。默认开着的话，把所有课都
  /// 变成「每 5 分钟响一次」对没预期到的人是纯粹的骚扰。
  final bool repeatReminders;

  /// 重复提醒的间隔，分钟。
  final int repeatIntervalMinutes;

  /// 按日程覆盖的提醒设置：setId → 那一套值。
  ///
  /// **没有这个 setId 的项 = 跟随全局默认。** 所以老用户升级上来时这张表是空的，
  /// 每一个日程都走全局那一套，行为和升级前一模一样，不需要任何迁移。
  ///
  /// 放在 [AppSettings] 而不是给 `CalendarSets` 加列或新开一张表：那两样都要动
  /// schema 版本、写 `onUpgrade`、并在真机上把「老库能不能升上来」验一遍 ——
  /// 而收益只是「设置跟着日程走」。这里的 `fromJson` 本来就是逐字段容错的，
  /// 加一项的成本是一次 `toJson`/`fromJson` 的编辑。`places` / `courseAbbrs`
  /// 当初也是这个理由放在这里的。
  ///
  /// 代价有两条，都要说清楚：
  ///
  /// 1. **删掉一个日程会留下一份孤儿记录。** 它是永久无害的 ——
  ///    `CalendarSets.id` 是 `INTEGER PRIMARY KEY AUTOINCREMENT`，
  ///    已用过的 id 永不复用，那条记录再也不会被哪个新日程认领；按 id 查不到
  ///    就当作没设过。会在删日程那一处顺手清掉，但即便漏了也不影响行为。
  /// 2. **它不进 JSON 备份。** 那个备份只装日程本身，而提醒设置和主题、地点、
  ///    缩写一样是设备级的。换机器要靠重设。
  final Map<int, SetReminderSettings> setReminders;

  /// 查某个日程的提醒覆盖；没有就是「跟随全局」。
  ///
  /// **非正的 id 一律当作没有覆盖**，而不是去查那个键。`_setReminders` 在解析
  /// JSON 时已经挡掉了这些，但构造器是公开的 —— 内存里塞一个 0 号块照样可能，
  /// 而那时「不属于任何日程」（`kNoSetId == 0`）和「这个日程叫 0 号」会在同一次
  /// 查表上撞车，症状是**所有不属于任何日程的事件都套上了某个日程的设置**。
  /// 哨兵的判断落在查表这一侧，才是查得到的地方。
  ///
  /// 写 `<= 0` 而不是 `== kNoSetId`：`core/settings` 这层有意不 import
  /// `data/model`（[ScheduleRef.setIdOf] 用的是同一条判据），而正数 id 是
  /// drift 那张自增表的性质，在这里说出来比引一个常量更准。
  SetReminderSettings? remindersFor(int setId) =>
      setId <= 0 ? null : setReminders[setId];

  /// 这个日程**实际会用的默认提前量** —— 日程有覆盖就用覆盖的，否则用全局的。
  ///
  /// 写成方法而不是在调用点各写一遍 `setReminders[setId]?.defaultLeadMinutes
  /// ?? defaultLeadMinutes`：[course_editor.dart](lib/features/editor/course_editor.dart)
  /// 那个「跟随默认（N 分钟）」的 chip 显示的就是这个数，而它**必须**和
  /// `buildReminderPlan` 里日程层那一级的算法是同一份。两处各写一遍的话，
  /// 一个自定义过提前量的日程里，那门课会显示一个**不是它真正会用的**数字，
  /// 用户照着它调时间，提醒却在另一个时刻响。
  ///
  /// 注意它**不含单课那一层**：这个方法回答的是「这门课没自己设过的话会用几分」。
  int leadMinutesFor(int setId) =>
      remindersFor(setId)?.defaultLeadMinutes ?? defaultLeadMinutes;

  /// 记下来的地点。
  ///
  /// 存在这里而不是新开一张 drift 表：它是几条只读出来匹配一下的记录，
  /// 为它加一张表就要动 schema 版本、写迁移、照顾老库，收益只是省一个文件。
  final List<SavedPlace> places;

  /// 用户手写的课程缩写：课程标题 → 缩写。
  ///
  /// 只有**用户改过的**那些课在里面。没改过的课不进这张表 ——
  /// 那样预置表以后加了一门新课的叫法，用户不用做什么就能跟着更新；
  /// 而如果一开始就把预置值抄进来，那张表就永远停在用户装 App 那一天。
  ///
  /// 键是**标题**而不是模板 id：同一门课拆成星期一、星期五两条模板时，
  /// 它们共用一个缩写，和 `courseColor` 按标题取色是同一个约定。
  ///
  /// 存在这里而不是开一张 drift 表，理由和 [places] 完全一样：几十条
  /// 「读出来匹配一下」的记录，为它加一张表就要动 schema 版本、写迁移、
  /// 照顾老库 —— 收益只是省一个文件。而且设置一变 `NativeSync` 就会重推
  /// 快照，桌面上的小组件跟着更新，这条链子是现成的。
  final Map<String, String> courseAbbrs;

  // ---------------------------------------------------------------------------
  // 标签页
  // ---------------------------------------------------------------------------

  /// 标签栏的顺序，元素是 [ScheduleRef] 词汇表里的串。
  ///
  /// **列表里没出现的日程按数据库顺序接在后面。** 这一条规则同时解决了
  /// 「新导入一个日程」和「老用户第一次升级上来（这个列表是空的）」两件事 ——
  /// 两处都不需要写迁移代码。
  ///
  /// 为什么放在这里而不是数据库的 `CalendarSets.tabOrder` 列：**一行一个整数
  /// 表达不了「总览插在第二和第三个日程之间」**。总览没有 id，也就没有那一列。
  final List<String> tabOrder;

  /// 打开软件时停在哪一页。取值 `''`（第一个日程）/ `'overview'` / `'set:<id>'`。
  ///
  /// **默认空串**，也就是现在的行为（落在第一个日程）—— 老用户升级上来
  /// 打开的还是他昨天在看的那个位置。
  final String defaultTab;

  /// 标签栏里显不显示「总览」。
  ///
  /// **只有一个日程时总览不参与标签栏**，哪怕这里是 true ——
  /// 不给单日程用户凭空添一个和自己一模一样的页。这条和既有的
  /// 「少于 2 个日程就不显示整条标签栏」是同一条思路，不是新规矩，
  /// 但设置页里必须写出来，否则「我明明开了怎么没有」。
  final bool overviewEnabled;

  /// 提前量的上限。24 小时是防手滑把一条提醒排到几年后 —— 排出去容易，
  /// 用户找不到它是哪里来的。
  static const int kMaxLeadMinutes = 24 * 60;

  /// 半径下限 50m 是室内 GPS 的常态误差，比这更小只会让「明明在教室里却被
  /// 判定为不在」反复发生。
  static const int kMinRadiusMeters = 50;
  static const int kMaxRadiusMeters = 2000;

  /// 自动清除的上限。再长就等于没开 —— 一条提醒不该在通知栏里过夜。
  static const int kMaxTimeoutMinutes = 12 * 60;

  /// 重复间隔的下限是 1 分钟。再短就不像提醒而像卡住了 —— 而且每次重复都要
  /// 起一次广播接收器、探一次位置，密集重复的代价比响一声大得多。
  static const int kMinRepeatMinutes = 1;

  /// 重复间隔的上限。比 2 小时更长的重复在课间根本没有第二次机会 ——
  /// 一节课才 45 分钟，排到课后去的那些会被「已经上课」那条规则拦掉。
  static const int kMaxRepeatMinutes = 120;

  /// 预设主题色的默认值 —— Material 的紫，中性、不抢眼。
  static const String kDefaultSeedHex = '#6750A4';

  ThemeMode get materialThemeMode => switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppColorSource? colorSource,
    String? customSeedHex,
    bool? remindersEnabled,
    int? defaultLeadMinutes,
    NearbyMode? nearbyMode,
    int? gateRadiusMeters,
    int? notificationTimeoutMinutes,
    bool? repeatReminders,
    int? repeatIntervalMinutes,
    Map<int, SetReminderSettings>? setReminders,
    List<SavedPlace>? places,
    Map<String, String>? courseAbbrs,
    List<String>? tabOrder,
    String? defaultTab,
    bool? overviewEnabled,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        colorSource: colorSource ?? this.colorSource,
        customSeedHex: customSeedHex ?? this.customSeedHex,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        defaultLeadMinutes: defaultLeadMinutes ?? this.defaultLeadMinutes,
        nearbyMode: nearbyMode ?? this.nearbyMode,
        gateRadiusMeters: gateRadiusMeters ?? this.gateRadiusMeters,
        notificationTimeoutMinutes:
            notificationTimeoutMinutes ?? this.notificationTimeoutMinutes,
        repeatReminders: repeatReminders ?? this.repeatReminders,
        repeatIntervalMinutes: repeatIntervalMinutes ?? this.repeatIntervalMinutes,
        setReminders: setReminders ?? this.setReminders,
        places: places ?? this.places,
        courseAbbrs: courseAbbrs ?? this.courseAbbrs,
        tabOrder: tabOrder ?? this.tabOrder,
        defaultTab: defaultTab ?? this.defaultTab,
        overviewEnabled: overviewEnabled ?? this.overviewEnabled,
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'colorSource': colorSource.name,
        'customSeedHex': customSeedHex,
        'remindersEnabled': remindersEnabled,
        'defaultLeadMinutes': defaultLeadMinutes,
        'nearbyMode': nearbyMode.name,
        'gateRadiusMeters': gateRadiusMeters,
        'notificationTimeoutMinutes': notificationTimeoutMinutes,
        'repeatReminders': repeatReminders,
        'repeatIntervalMinutes': repeatIntervalMinutes,
        // 键必须是字符串 —— JSON 对象的键只能是字符串，而 `jsonEncode`
        // 遇到 `Map<int, _>` 会直接抛「不是可编码对象」。
        'setReminders': {
          for (final e in setReminders.entries) '${e.key}': e.value.toJson(),
        },
        'places': [for (final p in places) p.toJson()],
        'courseAbbrs': courseAbbrs,
        'tabOrder': tabOrder,
        'defaultTab': defaultTab,
        'overviewEnabled': overviewEnabled,
      };

  /// 从 JSON 还原。
  ///
  /// **每一项都单独容错**：配置文件是可以被手改、被同步工具搞坏、被旧版本
  /// 写坏的。一个不认识的 `themeMode` 不该让整份设置连同课表一起进不去 ——
  /// 认不出来的那项退回默认值就好。
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const fallback = AppSettings();
    return AppSettings(
      themeMode: _byName(AppThemeMode.values, json['themeMode']) ??
          fallback.themeMode,
      colorSource:
          _byName(AppColorSource.values, json['colorSource']) ?? fallback.colorSource,
      customSeedHex: _hex(json['customSeedHex']) ?? fallback.customSeedHex,
      remindersEnabled: _bool(json['remindersEnabled']) ?? fallback.remindersEnabled,
      defaultLeadMinutes: _int(
            json['defaultLeadMinutes'],
            min: 0,
            max: kMaxLeadMinutes,
          ) ??
          fallback.defaultLeadMinutes,
      nearbyMode: _nearbyMode(json) ?? fallback.nearbyMode,
      gateRadiusMeters: _int(
            json['gateRadiusMeters'],
            min: kMinRadiusMeters,
            max: kMaxRadiusMeters,
          ) ??
          fallback.gateRadiusMeters,
      notificationTimeoutMinutes: _int(
            json['notificationTimeoutMinutes'],
            min: 0,
            max: kMaxTimeoutMinutes,
          ) ??
          fallback.notificationTimeoutMinutes,
      repeatReminders: _bool(json['repeatReminders']) ?? fallback.repeatReminders,
      repeatIntervalMinutes: _int(
            json['repeatIntervalMinutes'],
            min: kMinRepeatMinutes,
            max: kMaxRepeatMinutes,
          ) ??
          fallback.repeatIntervalMinutes,
      setReminders: _setReminders(json['setReminders']),
      places: _places(json['places']),
      courseAbbrs: _abbrs(json['courseAbbrs']),
      tabOrder: _tabOrder(json['tabOrder']),
      defaultTab: _tabKey(json['defaultTab']) ?? fallback.defaultTab,
      overviewEnabled: _bool(json['overviewEnabled']) ?? fallback.overviewEnabled,
    );
  }

  /// 标签顺序表。
  ///
  /// 和 [_places] / [_abbrs] 一样**逐项容错**：认不出的那一项（比如某个日程
  /// 已经被删掉了，或者手改文件时写坏了）单独丢掉，其余照收。
  ///
  /// **丢掉的项不会让顺序出错**：`tabOrder` 的语义本来就是「这里列出来的按这个
  /// 顺序排在前面，没列出来的按数据库顺序接在后面」，所以删掉一项等于把它
  /// 降级成「接在后面」，正是想要的结果。
  ///
  /// 重复项也去掉 —— 一个 key 在标签栏里出现两次，两处会指向同一页，
  /// 而用户点哪个都一样，看起来像卡住了。
  ///
  /// 用的是 [ScheduleRef.isTabKey] **而不是** [ScheduleRef.isValid]：
  /// 后者连 `follow` 也收，而 `follow`（跟随当前）当标签页顺序是句没有意义的话
  /// —— 「上一个停在哪就排在哪」。它在小组件那边是合法的，在这里不是。
  static List<String> _tabOrder(Object? raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final item in raw) {
      if (item is! String || !ScheduleRef.isTabKey(item)) continue;
      if (seen.add(item)) out.add(item);
    }
    return out;
  }

  /// 默认标签页的 key。
  ///
  /// 只接受 [ScheduleRef.isTabKey] 认的那些（总览，或某个 `set:<id>`）；
  /// `follow` 在这里没有意义 —— 「默认停在上次停的地方」不是个设置项。
  ///
  /// **空串是合法的**，含义是「第一个日程」，也就是老版本的行为；
  /// 认不出的值同样退回空串，而不是退回「总览」之类 —— 一个坏值不该
  /// 把用户的启动位置换到另一个页面上。
  static String? _tabKey(Object? raw) {
    if (raw is! String) return null;
    if (raw.isEmpty) return ScheduleRef.unset;
    return ScheduleRef.isTabKey(raw) ? raw : ScheduleRef.unset;
  }

  /// 按日程的提醒设置表。
  ///
  /// 和 [_places] / [_abbrs] / [_tabOrder] 一样**逐项容错**：认不出的那一项单独
  /// 丢掉，其余照收 —— 一个手改坏的块不该让用户别的日程的提醒设置一起消失。
  ///
  /// **键还必须 `> 0`。** drift 的 id 从 1 开始，`kNoSetId = 0` 是「这条事件不属于
  /// 任何日程」的哨兵；允许它当有效键，会让那两件事在 `setReminders[0]` 上撞车 ——
  /// 那种查表写起来毫无破绽，只有行为不对。负数同理（`unsavedId` 用负数）。
  static Map<int, SetReminderSettings> _setReminders(Object? raw) {
    if (raw is! Map) return const {};
    final out = <int, SetReminderSettings>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final id = int.tryParse(key);
      if (id == null || id <= 0) continue;
      final block = SetReminderSettings.fromJson(entry.value);
      if (block == null) continue;
      out[id] = block;
    }
    return out;
  }

  /// 缩写覆盖表。
  ///
  /// 和 [places] 一样**逐项容错**：坏掉的那一条丢掉，其余照收。键统一去空格
  /// （`abbrFor` 也会兜一层，但让表本身只存规范化的键，设置页里的「已自定义」
  /// 判断才准），值统一收进 [kMaxAbbrChars]。
  ///
  /// 空值**收进来而不是丢掉** —— 一个空的覆盖和「没有这条」在 `abbrFor` 里
  /// 是同一个意思，但设置页要靠它区分「用户清空了，用回预置」和「配过又被
  /// 删了」；两种都回落预置，留着这条更省事。
  static Map<String, String> _abbrs(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) continue;
      final name = key.trim();
      if (name.isEmpty) continue;
      out[name] = clampAbbr(value);
    }
    return out;
  }

  /// 新键优先，读不到再认老键 `gateByLocation`。
  ///
  /// 老键是个 bool，只表达得了「提醒 / 不提醒」两种，正好对上前两态。已经装在
  /// 手机上的那份 `settings.json` 里只有老键，不认它的话，用户明确打开过的门控
  /// 会在升级后被悄悄关掉 —— 而他只会觉得「这功能怎么自己没了」。
  static NearbyMode? _nearbyMode(Map<String, Object?> json) {
    final named = _byName(NearbyMode.values, json['nearbyMode']);
    if (named != null) return named;
    final legacy = _bool(json['gateByLocation']);
    if (legacy == null) return null;
    return legacy ? NearbyMode.skip : NearbyMode.remind;
  }

  static T? _byName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  static bool? _bool(Object? raw) => raw is bool ? raw : null;

  /// 夹到合法区间而不是丢弃：一个「提前 99999 分钟」的脏值应当变成 24 小时，
  /// 而不是让整项退回默认的 15 分钟 —— 后者看起来像用户自己改错了。
  static int? _int(Object? raw, {required int min, required int max}) {
    if (raw is! num) return null;
    return raw.round().clamp(min, max);
  }

  /// 列表里坏掉的项**单独丢掉**，不牵连其余 —— 一个手改坏的坐标不该让
  /// 用户别的九个地点一起消失。
  static List<SavedPlace> _places(Object? raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <SavedPlace>[];
    for (final item in raw) {
      final p = SavedPlace.fromJson(item);
      // 同名去重：匹配时是「长的赢」，两条同名只是徒增歧义。
      if (p == null || !seen.add(p.name)) continue;
      out.add(p);
    }
    return out;
  }

  /// 顺手校验一下格式 —— 坏掉的色值会让整个主题构建抛异常，
  /// 那时候 UI 是一片灰白，比退回默认色难查得多。
  static String? _hex(Object? raw) {
    if (raw is! String) return null;
    final s = raw.trim();
    return RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s) ? s.toUpperCase() : null;
  }
}

/// 设置的读写。整个应用只有一份。
class SettingsStore {
  SettingsStore(this._file);

  /// 测试用：指向一个临时文件。
  factory SettingsStore.atPath(String path) => SettingsStore(File(path));

  final File _file;

  Future<AppSettings> load() async {
    try {
      if (!await _file.exists()) return const AppSettings();
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map) return const AppSettings();
      return AppSettings.fromJson(raw.cast<String, Object?>());
    } on FormatException {
      // 文件被写坏了：用默认值继续跑，不要因为一个设置文件让 App 打不开。
      return const AppSettings();
    } on FileSystemException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    // 先写临时文件再改名：直接覆写的话，中途断电/被杀进程会留下半截 JSON，
    // 下次启动读到的是坏文件。改名是原子的。
    final tmp = File('${_file.path}.tmp');
    await tmp.create(recursive: true);
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }
}
